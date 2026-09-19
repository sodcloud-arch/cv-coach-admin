import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@5";

const ISSUER = "https://token.actions.githubusercontent.com";
const AUDIENCE = "ascend-core";
const ALLOWED_REF = "refs/heads/main";
const JWKS = createRemoteJWKSet(
  new URL("https://token.actions.githubusercontent.com/.well-known/jwks"),
);

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "access-control-allow-origin": "*",
      "access-control-allow-headers": "authorization,content-type,x-ascend-bridge-token",
      "access-control-allow-methods": "POST,OPTIONS",
    },
  });
}

async function sha256Hex(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function verifyGithubOidc(req: Request) {
  const auth = req.headers.get("authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) throw new Error("missing bearer token");

  const { payload } = await jwtVerify(token, JWKS, {
    issuer: ISSUER,
    audience: AUDIENCE,
  });

  if (payload.ref !== ALLOWED_REF) {
    throw new Error("only main-branch ASCEND bridge is allowed");
  }
  if (!payload.repository || typeof payload.repository !== "string") {
    throw new Error("repository claim missing");
  }
  return payload;
}

async function verifyBridgeDevice(req: Request, supabase: any) {
  const raw = req.headers.get("x-ascend-bridge-token") ?? "";
  if (!raw) throw new Error("missing bridge token");
  const tokenHash = await sha256Hex(raw);

  const { data, error } = await supabase
    .from("ascend_chat_bridge_devices")
    .select("id,device_key,label,enabled")
    .eq("token_sha256", tokenHash)
    .eq("enabled", true)
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data) throw new Error("bridge device not authorized");

  await supabase
    .from("ascend_chat_bridge_devices")
    .update({ last_seen_at: new Date().toISOString() })
    .eq("id", data.id);

  return data;
}

function parseAscendResult(content: string) {
  const marker = "ASCEND_RESULT_V1";
  const idx = content.lastIndexOf(marker);
  if (idx < 0) return null;

  const tail = content.slice(idx + marker.length).trim();
  const fenced = tail.match(/^\s*```(?:json)?\s*([\s\S]*?)\s*```/i);
  const source = fenced ? fenced[1].trim() : tail;

  const first = source.indexOf("{");
  const last = source.lastIndexOf("}");
  if (first < 0 || last <= first) return null;

  try {
    return JSON.parse(source.slice(first, last + 1));
  } catch {
    return null;
  }
}

function compactJson(value: unknown, max = 12000) {
  const s = JSON.stringify(value ?? {});
  return s.length <= max ? s : s.slice(0, max) + "...[TRUNCATED]";
}

function buildReasoningPrompt(claim: any) {
  const requestId = String(claim?.request_id ?? "");
  const project = String(claim?.project_key ?? "unknown");
  const mission = String(claim?.mission_code ?? "sin_mision");
  const problem = String(claim?.problem_type ?? "unknown");
  const rationale = String(claim?.rationale ?? "");
  const continuationInstruction = String(claim?.continuation_instruction ?? "").trim();
  const previousSummary = String(claim?.previous_summary ?? "").trim();
  const requestContext = compactJson(claim?.request_context ?? {}, 8000);
  const projectContext = compactJson(claim?.project_context ?? {}, 8000);

  const continuationSection = continuationInstruction
    ? [
        "",
        "CONTINUACIÓN DEL CICLO ANTERIOR:",
        continuationInstruction,
        previousSummary ? `Resumen anterior: ${previousSummary}` : "",
      ].filter(Boolean)
    : [];

  return [
    "ASCEND AUTOPILOT · REASONING REQUEST",
    "",
    `Request ID: ${requestId}`,
    `Proyecto: ${project}`,
    `Misión: ${mission}`,
    `Problema: ${problem}`,
    `Motivo: ${rationale}`,
    "",
    "Contexto operativo del Reasoning Request:",
    requestContext,
    "",
    "Estado ACTUAL del proyecto en ASCEND CORE:",
    projectContext,
    ...continuationSection,
    "",
    "INSTRUCCIÓN:",
    "Procede autónomamente usando las herramientas conectadas disponibles. Verifica primero el estado real antes de modificar código. Distingue fallo de producto, test e infraestructura. Conserva funcionalidades existentes, usa ramas/PR/tests cuando corresponda y evita acciones destructivas o irreversibles sin autorización humana.",
    "",
    "Al terminar, añade EXACTAMENTE al final de tu respuesta este bloque:",
    "ASCEND_RESULT_V1",
    "```json",
    JSON.stringify({
      request_id: requestId,
      status: "RESOLVED|CONTINUE|BLOCKED",
      summary: "resumen breve del resultado",
      next_instruction: "solo si status=CONTINUE; qué debe hacer ASCEND/ChatGPT en el siguiente ciclo",
    }),
    "```",
    "",
    "Usa RESOLVED si el problema quedó solucionado, CONTINUE si requiere otro ciclo autónomo, o BLOCKED solo si depende realmente de una decisión humana.",
  ].join("\n");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return json({ ok: true });
  if (req.method !== "POST") return json({ error: "POST required" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    return json({ error: "server configuration missing" }, 500);
  }

  const supabase = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let body: any = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON" }, 400);
  }

  const op = String(body?.op ?? "health");

  if (op.startsWith("bridge_")) {
    let device: any;
    try {
      device = await verifyBridgeDevice(req, supabase);
    } catch (error) {
      return json({
        error: "unauthorized_bridge",
        detail: String((error as Error)?.message ?? error),
      }, 401);
    }

    if (op === "bridge_health") {
      return json({
        ok: true,
        version: "0.7.0",
        mode: "nexus-chat-bridge",
        device_key: device.device_key,
        openai_api: false,
      });
    }

    if (op === "bridge_activate_session") {
      const conversationId = String(body?.conversation_id ?? "").trim();
      if (!conversationId) return json({ error: "conversation_id required" }, 400);

      let projectId: string | null = null;
      let missionId: string | null = null;

      const projectKey = String(body?.project_key ?? "").trim();
      if (projectKey) {
        const { data } = await supabase
          .from("ascend_projects")
          .select("id")
          .eq("project_key", projectKey)
          .maybeSingle();
        projectId = data?.id ?? null;
      }

      const missionCode = String(body?.mission_code ?? "").trim();
      if (missionCode && projectId) {
        const { data } = await supabase
          .from("ascend_missions")
          .select("id")
          .eq("project_id", projectId)
          .eq("mission_code", missionCode)
          .maybeSingle();
        missionId = data?.id ?? null;
      }

      const row = {
        device_id: device.id,
        project_id: projectId,
        mission_id: missionId,
        conversation_id: conversationId,
        conversation_url: body?.conversation_url ?? null,
        tab_id: Number.isFinite(Number(body?.tab_id)) ? Number(body.tab_id) : null,
        status: "active",
        autopilot_enabled: true,
        last_heartbeat_at: new Date().toISOString(),
        metadata: {
          source: "ascend_nexus",
          project_label: body?.project_label ?? null,
          mission_label: body?.mission_label ?? null,
          ...(body?.metadata ?? {}),
        },
      };

      const { data, error } = await supabase
        .from("ascend_chat_sessions")
        .upsert(row, { onConflict: "device_id,conversation_id" })
        .select("*")
        .single();

      if (error) return json({ error: error.message }, 400);

      await supabase.rpc("ascend_autopilot_tick", { p_limit: 250 });

      return json({
        ok: true,
        kind: "BRIDGE_SESSION_ACTIVE",
        session: data,
      });
    }

    if (op === "bridge_pause_session") {
      const sessionId = String(body?.session_id ?? "");
      const { data: session, error: findError } = await supabase
        .from("ascend_chat_sessions")
        .select("*")
        .eq("id", sessionId)
        .eq("device_id", device.id)
        .maybeSingle();

      if (findError) return json({ error: findError.message }, 400);
      if (!session) return json({ error: "session not found" }, 404);

      if (session.current_reasoning_request_id) {
        const worker = `nexus:${device.device_key}:${session.id}`;
        await supabase.rpc("ascend_resolve_reasoning_request", {
          p_request_id: session.current_reasoning_request_id,
          p_worker: worker,
          p_resolution: "retry",
          p_summary: "NEXUS autopilot session paused.",
          p_decision_id: null,
          p_error: "Chat bridge paused",
          p_retry_after_seconds: 30,
        });
      }

      const { data, error } = await supabase
        .from("ascend_chat_sessions")
        .update({
          status: "paused",
          autopilot_enabled: false,
          current_reasoning_request_id: null,
          last_event_at: new Date().toISOString(),
        })
        .eq("id", session.id)
        .select("*")
        .single();

      if (error) return json({ error: error.message }, 400);
      return json({ ok: true, kind: "BRIDGE_SESSION_PAUSED", session: data });
    }

    if (op === "bridge_heartbeat") {
      const sessionId = String(body?.session_id ?? "");
      const now = new Date().toISOString();

      const { data: session, error } = await supabase
        .from("ascend_chat_sessions")
        .update({
          last_heartbeat_at: now,
          last_event_at: now,
          conversation_url: body?.conversation_url ?? undefined,
          tab_id: Number.isFinite(Number(body?.tab_id)) ? Number(body.tab_id) : undefined,
        })
        .eq("id", sessionId)
        .eq("device_id", device.id)
        .select("*")
        .maybeSingle();

      if (error) return json({ error: error.message }, 400);
      if (!session) return json({ error: "session not found" }, 404);

      const { data: tick } = await supabase.rpc("ascend_autopilot_tick", { p_limit: 250 });
      const worker = `nexus:${device.device_key}:${session.id}`;
      const { data: reconcile, error: reconcileError } = await supabase.rpc(
        "ascend_reconcile_chat_session",
        { p_session_id: session.id, p_worker: worker },
      );
      if (reconcileError) {
        return json({ error: "bridge_reconcile_failed", detail: reconcileError.message }, 409);
      }

      const { data: reconciledSession } = await supabase
        .from("ascend_chat_sessions")
        .select("*")
        .eq("id", session.id)
        .maybeSingle();

      return json({
        ok: true,
        kind: "BRIDGE_HEARTBEAT",
        session: reconciledSession ?? session,
        autopilot: tick,
        reconcile,
      });
    }

    if (op === "bridge_status") {
      const { data, error } = await supabase
        .from("ascend_chat_sessions")
        .select("*")
        .eq("device_id", device.id)
        .order("updated_at", { ascending: false })
        .limit(10);

      if (error) return json({ error: error.message }, 400);

      return json({
        ok: true,
        kind: "BRIDGE_STATUS",
        sessions: data ?? [],
      });
    }

    if (op === "bridge_project_context") {
      const projectKey = String(body?.project_key ?? "").trim();
      if (!projectKey) return json({ error: "project_key required" }, 400);

      const { data, error } = await supabase.rpc("ascend_project_context", {
        p_project_key: projectKey,
      });
      if (error) return json({ error: error.message }, 400);

      return json({
        ok: true,
        kind: "ASCEND_PROJECT_CONTEXT",
        project_key: projectKey,
        result: data,
      });
    }

    if (op === "bridge_jarvis_update_check") {
      const currentReleaseOrder = Math.max(0, Number(body?.current_release_order ?? 0));
      const { data, error } = await supabase
        .from("ascend_jarvis_updates")
        .select("id,version,release_order,summary,minimum_runtime_version,manifest,checksum_sha256,published_at")
        .eq("status", "ready")
        .gt("release_order", currentReleaseOrder)
        .order("release_order", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (error) return json({ error: error.message }, 400);
      if (!data) {
        return json({
          ok: true,
          kind: "JARVIS_UPDATE_NONE",
          current_release_order: currentReleaseOrder,
        });
      }

      return json({
        ok: true,
        kind: "JARVIS_UPDATE_AVAILABLE",
        update: data,
      });
    }

    if (op === "bridge_jarvis_update_download") {
      const updateId = String(body?.update_id ?? "").trim();
      if (!updateId) return json({ error: "update_id required" }, 400);

      const { data, error } = await supabase
        .from("ascend_jarvis_updates")
        .select("id,version,release_order,summary,minimum_runtime_version,manifest,checksum_sha256,package_json")
        .eq("id", updateId)
        .eq("status", "ready")
        .maybeSingle();

      if (error) return json({ error: error.message }, 400);
      if (!data) return json({ error: "update not found" }, 404);

      return json({
        ok: true,
        kind: "JARVIS_UPDATE_PACKAGE",
        update: data,
      });
    }

    if (op === "bridge_jarvis_update_report") {
      const updateId = String(body?.update_id ?? "").trim();
      const status = String(body?.status ?? "").trim();
      if (!updateId || !["started","installed","failed","rolled_back"].includes(status)) {
        return json({ error: "invalid update report" }, 400);
      }

      const { data, error } = await supabase
        .from("ascend_jarvis_update_receipts")
        .insert({
          update_id: updateId,
          device_id: device.id,
          status,
          from_version: body?.from_version ?? null,
          to_version: body?.to_version ?? null,
          details: body?.details ?? {},
        })
        .select("id,created_at")
        .single();

      if (error) return json({ error: error.message }, 400);
      return json({ ok: true, kind: "JARVIS_UPDATE_REPORTED", receipt: data });
    }

    if (op === "bridge_next_prompt") {
      const sessionId = String(body?.session_id ?? "");
      let { data: session, error: sessionError } = await supabase
        .from("ascend_chat_sessions")
        .select("*")
        .eq("id", sessionId)
        .eq("device_id", device.id)
        .maybeSingle();

      if (sessionError) return json({ error: sessionError.message }, 400);
      if (!session) return json({ error: "session not found" }, 404);
      if (!session.autopilot_enabled || session.status !== "active") {
        return json({ ok: true, kind: "BRIDGE_IDLE", reason: "session_not_active" });
      }

      const worker = `nexus:${device.device_key}:${session.id}`;
      const { data: reconcile, error: reconcileError } = await supabase.rpc(
        "ascend_reconcile_chat_session",
        { p_session_id: session.id, p_worker: worker },
      );
      if (reconcileError) {
        return json({ error: "bridge_reconcile_failed", detail: reconcileError.message }, 409);
      }

      const { data: refreshedSession, error: refreshedError } = await supabase
        .from("ascend_chat_sessions")
        .select("*")
        .eq("id", session.id)
        .maybeSingle();
      if (refreshedError) return json({ error: refreshedError.message }, 400);
      if (refreshedSession) session = refreshedSession;

      if (session.current_reasoning_request_id) {
        return json({
          ok: true,
          kind: "BRIDGE_WAITING_RESPONSE",
          request_id: session.current_reasoning_request_id,
        });
      }

      const { data: claim, error: claimError } = await supabase.rpc(
        "ascend_claim_reasoning_request_for_project",
        {
          p_worker: worker,
          p_project_id: session.project_id ?? null,
        },
      );

      if (claimError) return json({ error: claimError.message }, 400);
      if (!claim || claim.kind === "IDLE") {
        return json({ ok: true, kind: "BRIDGE_IDLE", reason: "no_reasoning_request" });
      }

      const prompt = buildReasoningPrompt(claim);
      const promptHash = await sha256Hex(prompt);

      await supabase
        .from("ascend_reasoning_requests")
        .update({ chat_session_id: session.id })
        .eq("id", claim.request_id);

      await supabase
        .from("ascend_chat_sessions")
        .update({
          current_reasoning_request_id: claim.request_id,
          mission_id: claim.mission_id ?? session.mission_id,
          cycle_count: Number(session.cycle_count ?? 0) + 1,
          last_event_at: new Date().toISOString(),
        })
        .eq("id", session.id);

      await supabase.rpc("ascend_bridge_append_message", {
        p_session_id: session.id,
        p_direction: "ascend_to_chatgpt",
        p_content_hash: promptHash,
        p_content: prompt,
        p_metadata: {
          request_id: claim.request_id,
          worker,
          priority: claim.priority,
        },
        p_reasoning_request_id: claim.request_id,
      });

      return json({
        ok: true,
        kind: "BRIDGE_PROMPT_READY",
        request_id: claim.request_id,
        prompt,
        prompt_hash: promptHash,
        priority: claim.priority,
        mission_code: claim.mission_code,
        project_key: claim.project_key,
      });
    }

    if (op === "bridge_message") {
      const sessionId = String(body?.session_id ?? "");
      const direction = String(body?.direction ?? "");
      const content = String(body?.content ?? "");
      const contentHash = String(body?.content_hash ?? "") || await sha256Hex(content);

      if (!content.trim()) return json({ error: "content required" }, 400);

      const { data: session, error: sessionError } = await supabase
        .from("ascend_chat_sessions")
        .select("*")
        .eq("id", sessionId)
        .eq("device_id", device.id)
        .maybeSingle();

      if (sessionError) return json({ error: sessionError.message }, 400);
      if (!session) return json({ error: "session not found" }, 404);

      const requestId = session.current_reasoning_request_id ?? null;

      const { data: appendResult, error: appendError } = await supabase.rpc(
        "ascend_bridge_append_message",
        {
          p_session_id: session.id,
          p_direction: direction,
          p_content_hash: contentHash,
          p_content: content,
          p_metadata: body?.metadata ?? {},
          p_reasoning_request_id: requestId,
        },
      );

      if (appendError) return json({ error: appendError.message }, 400);

      let resolution: any = null;
      let protocol: any = null;

      if (direction === "assistant_to_ascend" && requestId && appendResult?.duplicate !== true) {
        protocol = parseAscendResult(content);
        const worker = `nexus:${device.device_key}:${session.id}`;

        if (protocol && String(protocol.request_id ?? "") === String(requestId)) {
          const status = String(protocol.status ?? "").toUpperCase();
          const summary = String(protocol.summary ?? "").slice(0, 5000);
          const nextInstruction = String(protocol.next_instruction ?? "").slice(0, 10000);

          if (status === "RESOLVED") {
            const { data, error } = await supabase.rpc("ascend_resolve_reasoning_request", {
              p_request_id: requestId,
              p_worker: worker,
              p_resolution: "resolved",
              p_summary: summary || "Resolved by ChatGPT through ASCEND NEXUS.",
              p_decision_id: null,
              p_error: null,
              p_retry_after_seconds: 30,
            });
            if (error) return json({ error: error.message }, 400);
            resolution = data;
          } else if (status === "BLOCKED") {
            const { data, error } = await supabase.rpc("ascend_resolve_reasoning_request", {
              p_request_id: requestId,
              p_worker: worker,
              p_resolution: "blocked",
              p_summary: summary || "Blocked by ChatGPT through ASCEND NEXUS.",
              p_decision_id: null,
              p_error: nextInstruction || "Human decision required",
              p_retry_after_seconds: 30,
            });
            if (error) return json({ error: error.message }, 400);
            resolution = data;
          } else if (status === "CONTINUE") {
            const { data, error } = await supabase.rpc("ascend_continue_reasoning_request", {
              p_request_id: requestId,
              p_worker: worker,
              p_summary: summary || "Continue autonomous reasoning cycle.",
              p_next_instruction: nextInstruction || null,
            });
            if (error) {
              return json({
                error: "continuation_rollover_failed",
                detail: error.message,
                request_id: requestId,
              }, 409);
            }
            resolution = data;
          } else {
            const { data, error } = await supabase.rpc("ascend_resolve_reasoning_request", {
              p_request_id: requestId,
              p_worker: worker,
              p_resolution: "retry",
              p_summary: summary || "ChatGPT returned an unsupported ASCEND status.",
              p_decision_id: null,
              p_error: `Unsupported ASCEND status: ${status || "EMPTY"}`,
              p_retry_after_seconds: 30,
            });
            if (error) return json({ error: error.message }, 400);
            resolution = data;
          }
        } else {
          const { data, error } = await supabase.rpc("ascend_resolve_reasoning_request", {
            p_request_id: requestId,
            p_worker: worker,
            p_resolution: "retry",
            p_summary: "ChatGPT responded, but the ASCEND_RESULT_V1 contract was missing or mismatched.",
            p_decision_id: null,
            p_error: "Missing or invalid ASCEND_RESULT_V1",
            p_retry_after_seconds: 30,
          });
          if (error) {
            return json({
              error: "reasoning_resolution_failed",
              detail: error.message,
              request_id: requestId,
            }, 409);
          }
          resolution = data;
        }

        await supabase
          .from("ascend_chat_sessions")
          .update({
            current_reasoning_request_id: null,
            last_event_at: new Date().toISOString(),
          })
          .eq("id", session.id)
          .eq("current_reasoning_request_id", requestId);
      }

      return json({
        ok: true,
        kind: "BRIDGE_MESSAGE_RECORDED",
        append: appendResult,
        protocol,
        resolution,
        should_request_next: direction === "assistant_to_ascend" && !!requestId,
      });
    }

    return json({ error: "unsupported bridge op" }, 400);
  }

  let claims: any;
  try {
    claims = await verifyGithubOidc(req);
  } catch (error) {
    return json({
      error: "unauthorized",
      detail: String((error as Error)?.message ?? error),
    }, 401);
  }

  if (op === "health") {
    return json({
      ok: true,
      version: "0.7.0",
      mode: "zero-cost",
      repository: claims.repository,
      ref: claims.ref,
      run_id: claims.run_id ?? null,
      openai_api: false,
    });
  }

  if (op === "learning_tick") {
    const limit = Math.max(1, Math.min(Number(body?.limit ?? 100), 500));
    const { data, error } = await supabase.rpc("ascend_learning_tick", {
      p_limit: limit,
    });
    if (error) return json({ error: error.message }, 400);
    return json({ ok: true, kind: "ASCEND_LEARNING_TICK", result: data });
  }

  if (op === "autopilot_tick") {
    const limit = Math.max(1, Math.min(Number(body?.limit ?? 100), 500));
    const { data, error } = await supabase.rpc("ascend_autopilot_tick", {
      p_limit: limit,
    });
    if (error) return json({ error: error.message }, 400);
    return json({ ok: true, kind: "ASCEND_AUTOPILOT_TICK", result: data });
  }

  if (op === "project_context") {
    const projectKey = String(body?.project_key ?? "").trim();
    if (!projectKey) return json({ error: "project_key required" }, 400);
    const { data, error } = await supabase.rpc("ascend_project_context", {
      p_project_key: projectKey,
    });
    if (error) return json({ error: error.message }, 400);
    return json({ ok: true, kind: "ASCEND_PROJECT_CONTEXT", result: data });
  }

  if (op !== "github_workflow_completed") {
    return json({ error: "unsupported op" }, 400);
  }

  const runId = Number(body?.run_id);
  const runNumber = Number(body?.run_number ?? 0);
  if (!Number.isSafeInteger(runId) || runId <= 0) {
    return json({ error: "invalid run_id" }, 400);
  }

  const payload = {
    ...(body?.payload ?? {}),
    github_oidc: {
      repository: claims.repository,
      ref: claims.ref,
      sha: claims.sha ?? null,
      workflow: claims.workflow ?? null,
      job_workflow_ref: claims.job_workflow_ref ?? null,
      actor: claims.actor ?? null,
      run_id: claims.run_id ?? null,
    },
  };

  const { data, error } = await supabase.rpc("ascend_ingest_github_workflow", {
    p_repository: String(claims.repository),
    p_workflow_name: body?.workflow_name ?? null,
    p_run_id: runId,
    p_run_number: Number.isFinite(runNumber) ? runNumber : 0,
    p_conclusion: body?.conclusion ?? null,
    p_event: body?.event ?? null,
    p_head_branch: body?.head_branch ?? null,
    p_head_sha: body?.head_sha ?? null,
    p_html_url: body?.html_url ?? null,
    p_payload: payload,
  });

  if (error) return json({ error: error.message }, 400);

  const { data: rules, error: rulesError } = await supabase.rpc("ascend_rules_tick", {
    p_limit: 50,
  });

  if (rulesError) {
    return json({
      error: "workflow recorded but rules tick failed",
      detail: rulesError.message,
      ingest: data,
    }, 500);
  }

  return json({
    ok: true,
    kind: "ASCEND_GITHUB_WORKFLOW_RECORDED",
    result: data,
    rules,
  });
});
