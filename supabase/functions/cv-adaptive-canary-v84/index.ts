import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@5.9.6";

const REPOSITORY = "sodcloud-arch/cv-coach-admin";
const REF = "refs/heads/main";
const WORKFLOW_REF = `${REPOSITORY}/.github/workflows/production-canary-v76.yml@${REF}`;
const ISSUER = "https://token.actions.githubusercontent.com";
const AUDIENCE = "cv-coach-production-canary-v76";
const JWKS = createRemoteJWKSet(new URL(`${ISSUER}/.well-known/jwks`));
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function bearer(req: Request) {
  const value = req.headers.get("authorization") || "";
  if (!value.startsWith("Bearer ")) throw new Error("missing_bearer");
  return value.slice(7).trim();
}

async function authorize(req: Request) {
  const { payload } = await jwtVerify(bearer(req), JWKS, {
    issuer: ISSUER,
    audience: AUDIENCE,
    algorithms: ["RS256"],
  });
  if (payload.repository !== REPOSITORY) throw new Error("repository_not_allowed");
  if (payload.ref !== REF) throw new Error("ref_not_allowed");
  if (payload.workflow_ref !== WORKFLOW_REF) throw new Error("workflow_not_allowed");
}

async function rpc(name: string, args: Record<string, unknown>) {
  const { data, error } = await sb.rpc(name, args);
  if (error) throw new Error(`${name}:${error.message}`);
  return data;
}

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    await authorize(req);
    const body = await req.json().catch(() => ({}));
    const runId = String(body?.run_id || "");
    if (!/^[A-Za-z0-9._:-]{1,120}$/.test(runId)) throw new Error("invalid_run_id");

    const progression = await rpc("run_adaptive_programming_e2e_v84", { p_run_id: runId });
    if (!progression || progression.ok !== true || progression.contract !== "CV_V84_ADAPTIVE_PROGRAMMING_E2E_OK") {
      throw new Error("adaptive_progression_e2e_contract_failed");
    }

    const draft = await rpc("run_adaptive_draft_e2e_v84", { p_run_id: runId });
    if (!draft || draft.ok !== true || draft.contract !== "CV_V84_ADAPTIVE_DRAFT_E2E_OK") {
      throw new Error("adaptive_draft_e2e_contract_failed");
    }

    return json({
      ...progression,
      contract: "CV_V84_ADAPTIVE_PROGRAMMING_FULL_E2E_OK",
      progression_contract: progression.contract,
      draft_contract: draft.contract,
      draft,
    });
  } catch (error) {
    console.error("CV_ADAPTIVE_CANARY_V84_ERROR", String(error));
    return json({ error: String(error instanceof Error ? error.message : error) }, 401);
  }
});
