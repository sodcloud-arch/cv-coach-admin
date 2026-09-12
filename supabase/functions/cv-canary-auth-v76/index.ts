import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@5.9.6";

const REPOSITORY = "sodcloud-arch/cv-coach-admin";
const REF = "refs/heads/main";
const WORKFLOW_REF = `${REPOSITORY}/.github/workflows/production-canary-v76.yml@${REF}`;
const ISSUER = "https://token.actions.githubusercontent.com";
const AUDIENCE = "cv-coach-production-canary-v76";
const JWKS = createRemoteJWKSet(new URL(`${ISSUER}/.well-known/jwks`));
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const sb = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

function bearer(req: Request) {
  const value = req.headers.get("authorization") || "";
  if (!value.startsWith("Bearer ")) throw new Error("missing_bearer");
  return value.slice(7).trim();
}

async function authorize(req: Request) {
  const token = bearer(req);
  const { payload } = await jwtVerify(token, JWKS, {
    issuer: ISSUER,
    audience: AUDIENCE,
    algorithms: ["RS256"],
  });
  if (payload.repository !== REPOSITORY) throw new Error("repository_not_allowed");
  if (payload.ref !== REF) throw new Error("ref_not_allowed");
  if (payload.workflow_ref !== WORKFLOW_REF) throw new Error("workflow_not_allowed");
  return payload;
}

function stable<T>(rows: T[], key: (row: T) => string) {
  return [...rows].sort((a, b) => key(a).localeCompare(key(b)));
}

function must<T>(data: T | null, error: { message?: string } | null, label: string): T {
  if (error) throw new Error(`${label}:${error.message || "query_failed"}`);
  return data as T;
}

async function canaryClient() {
  const { data, error } = await sb
    .from("cv_canary_clients")
    .select("client_id,label,enabled")
    .eq("label", "production-v76")
    .eq("enabled", true)
    .maybeSingle();
  const row = must(data, error, "canary_client");
  if (!row?.client_id || !UUID_RE.test(row.client_id)) throw new Error("canary_not_configured");
  return row.client_id as string;
}

async function fingerprint(clientId: string) {
  const [xpR, creditR, stateR, missionsR, achievementsR, snapshotsR, progressionsR, levelsR, notificationsR] = await Promise.all([
    sb.from("xp_ledger").select("id,amount,reversed_at").eq("client_id", clientId),
    sb.from("credit_ledger").select("id,transaction_type,amount").eq("client_id", clientId),
    sb.from("client_cv_state").select("client_id,current_level,total_xp,credit_balance,current_cv_score,dynamic_state").eq("client_id", clientId).maybeSingle(),
    sb.from("client_missions").select("id,progress,target,status,completed_at").eq("client_id", clientId),
    sb.from("client_achievements").select("id,achievement_id").eq("client_id", clientId),
    sb.from("cv_score_snapshots").select("id").eq("client_id", clientId),
    sb.from("progression_suggestions").select("id,source_session_id,status,reviewed_by,reviewed_at").eq("client_id", clientId),
    sb.from("client_level_history").select("id,level_number,trigger_source").eq("client_id", clientId),
    sb.from("notifications").select("id").eq("user_id", clientId),
  ]);

  const xp = must(xpR.data, xpR.error, "xp_ledger") || [];
  const credits = must(creditR.data, creditR.error, "credit_ledger") || [];
  const state = must(stateR.data, stateR.error, "client_cv_state") || null;
  const missions = must(missionsR.data, missionsR.error, "client_missions") || [];
  const achievements = must(achievementsR.data, achievementsR.error, "client_achievements") || [];
  const snapshots = must(snapshotsR.data, snapshotsR.error, "cv_score_snapshots") || [];
  const progressions = must(progressionsR.data, progressionsR.error, "progression_suggestions") || [];
  const levels = must(levelsR.data, levelsR.error, "client_level_history") || [];
  const notifications = must(notificationsR.data, notificationsR.error, "notifications") || [];

  const xpTotal = xp.reduce((sum: number, row: any) => sum + (row.reversed_at ? 0 : Number(row.amount || 0)), 0);
  const creditTotal = credits.reduce((sum: number, row: any) => {
    const n = Number(row.amount || 0);
    if (row.transaction_type === "earned") return sum + Math.abs(n);
    if (row.transaction_type === "spent") return sum - Math.abs(n);
    return sum + n;
  }, 0);

  return {
    xp_total: xpTotal,
    credit_total: creditTotal,
    xp_ids: stable(xp as any[], (x: any) => x.id).map((x: any) => x.id),
    credit_ids: stable(credits as any[], (x: any) => x.id).map((x: any) => x.id),
    cv_state: state,
    missions: stable(missions as any[], (x: any) => x.id).map((x: any) => ({
      id: x.id, progress: x.progress, target: x.target, status: x.status, completed_at: x.completed_at,
    })),
    achievement_ids: stable(achievements as any[], (x: any) => x.id).map((x: any) => x.id),
    snapshot_ids: stable(snapshots as any[], (x: any) => x.id).map((x: any) => x.id),
    progressions: stable(progressions as any[], (x: any) => x.id).map((x: any) => ({
      id: x.id, source_session_id: x.source_session_id, status: x.status,
      reviewed_by: x.reviewed_by, reviewed_at: x.reviewed_at,
    })),
    level_ids: stable(levels as any[], (x: any) => x.id).map((x: any) => x.id),
    notification_ids: stable(notifications as any[], (x: any) => x.id).map((x: any) => x.id),
  };
}

function sameFingerprint(a: any, b: any) {
  return JSON.stringify(a) === JSON.stringify(b);
}

async function restoreBaseline(clientId: string, baseline: any, sessionId?: string | null) {
  if (sessionId && UUID_RE.test(sessionId)) {
    await sb.from("event_outbox").delete().eq("client_id", clientId).eq("aggregate_id", sessionId);
    await sb.from("progression_suggestions").delete().eq("client_id", clientId).eq("source_session_id", sessionId);
    await sb.from("xp_ledger").delete().eq("client_id", clientId).eq("source_id", sessionId);
    await sb.from("credit_ledger").delete().eq("client_id", clientId).eq("source_id", sessionId);
    await sb.from("workout_sessions").delete().eq("id", sessionId).eq("client_id", clientId);
  }

  const baselineMissionIds = new Set<string>((baseline?.missions || []).map((x: any) => x.id));
  const { data: currentMissions } = await sb.from("client_missions").select("id").eq("client_id", clientId);
  for (const row of currentMissions || []) {
    if (!baselineMissionIds.has(row.id)) await sb.from("client_missions").delete().eq("id", row.id).eq("client_id", clientId);
  }
  for (const row of baseline?.missions || []) {
    await sb.from("client_missions").update({
      progress: row.progress, status: row.status, completed_at: row.completed_at,
    }).eq("id", row.id).eq("client_id", clientId);
  }

  const baselineAchievementIds = new Set<string>(baseline?.achievement_ids || []);
  const { data: currentAchievements } = await sb.from("client_achievements").select("id").eq("client_id", clientId);
  for (const row of currentAchievements || []) {
    if (!baselineAchievementIds.has(row.id)) await sb.from("client_achievements").delete().eq("id", row.id).eq("client_id", clientId);
  }

  const baselineSnapshotIds = new Set<string>(baseline?.snapshot_ids || []);
  const { data: currentSnapshots } = await sb.from("cv_score_snapshots").select("id").eq("client_id", clientId);
  for (const row of currentSnapshots || []) {
    if (!baselineSnapshotIds.has(row.id)) await sb.from("cv_score_snapshots").delete().eq("id", row.id).eq("client_id", clientId);
  }

  const baselineProgressionMap = new Map<string, any>((baseline?.progressions || []).map((x: any) => [x.id, x]));
  const { data: currentProgressions } = await sb.from("progression_suggestions").select("id").eq("client_id", clientId);
  for (const row of currentProgressions || []) {
    const old = baselineProgressionMap.get(row.id);
    if (!old) {
      await sb.from("progression_suggestions").delete().eq("id", row.id).eq("client_id", clientId);
    } else {
      await sb.from("progression_suggestions").update({
        source_session_id: old.source_session_id,
        status: old.status,
        reviewed_by: old.reviewed_by,
        reviewed_at: old.reviewed_at,
      }).eq("id", row.id).eq("client_id", clientId);
    }
  }

  const baselineXpIds = new Set<string>(baseline?.xp_ids || []);
  const { data: currentXp } = await sb.from("xp_ledger").select("id").eq("client_id", clientId);
  for (const row of currentXp || []) if (!baselineXpIds.has(row.id)) await sb.from("xp_ledger").delete().eq("id", row.id).eq("client_id", clientId);

  const baselineCreditIds = new Set<string>(baseline?.credit_ids || []);
  const { data: currentCredits } = await sb.from("credit_ledger").select("id").eq("client_id", clientId);
  for (const row of currentCredits || []) if (!baselineCreditIds.has(row.id)) await sb.from("credit_ledger").delete().eq("id", row.id).eq("client_id", clientId);

  const baselineLevelIds = new Set<string>(baseline?.level_ids || []);
  const { data: currentLevels } = await sb.from("client_level_history").select("id").eq("client_id", clientId);
  for (const row of currentLevels || []) if (!baselineLevelIds.has(row.id)) await sb.from("client_level_history").delete().eq("id", row.id).eq("client_id", clientId);

  const baselineNotificationIds = new Set<string>(baseline?.notification_ids || []);
  const { data: currentNotifications } = await sb.from("notifications").select("id").eq("user_id", clientId);
  for (const row of currentNotifications || []) if (!baselineNotificationIds.has(row.id)) await sb.from("notifications").delete().eq("id", row.id).eq("user_id", clientId);

  if (baseline?.cv_state?.client_id) {
    const s = baseline.cv_state;
    await sb.from("client_cv_state").update({
      current_level: s.current_level,
      total_xp: s.total_xp,
      credit_balance: s.credit_balance,
      current_cv_score: s.current_cv_score,
      dynamic_state: s.dynamic_state,
    }).eq("client_id", clientId);
  }
}

async function cleanupStale(clientId: string) {
  const { data: stale } = await sb
    .from("cv_canary_runs")
    .select("run_id,session_id,status,baseline")
    .eq("client_id", clientId)
    .neq("status", "cleaned")
    .order("started_at", { ascending: true });
  for (const run of stale || []) {
    try {
      await restoreBaseline(clientId, run.baseline || {}, run.session_id);
      await sb.from("cv_canary_runs").update({
        status: "cleaned", cleaned_at: new Date().toISOString(), updated_at: new Date().toISOString(),
        result: { recovered_by_next_run: true },
      }).eq("run_id", run.run_id);
    } catch (error) {
      await sb.from("cv_canary_runs").update({
        status: "failed", error_text: `stale_cleanup:${String(error)}`, updated_at: new Date().toISOString(),
      }).eq("run_id", run.run_id);
      throw error;
    }
  }

  // A run can die between starting the workout and claiming its session id.
  // This account is dedicated to QA, so orphan in-progress sessions are safe to remove.
  await sb.from("workout_sessions").delete().eq("client_id", clientId).eq("status", "in_progress");

  const { data: terminalCanaries } = await sb
    .from("workout_sessions")
    .select("id")
    .eq("client_id", clientId)
    .like("session_notes", "CV_CANARY_V76 run=%");
  for (const row of terminalCanaries || []) await sb.from("workout_sessions").delete().eq("id", row.id).eq("client_id", clientId);
}

async function bootstrap(runId: string) {
  const clientId = await canaryClient();
  await cleanupStale(clientId);

  const { data: cp, error: cpError } = await sb.from("client_profiles").select("onboarding_status").eq("client_id", clientId).maybeSingle();
  must(cp, cpError, "client_profile");
  if (cp?.onboarding_status !== "approved") throw new Error("canary_onboarding_not_approved");

  const { data: programs, error: programError } = await sb.from("programs").select("id").eq("client_id", clientId).eq("status", "active").limit(2);
  must(programs, programError, "active_program");
  if ((programs || []).length !== 1) throw new Error(`canary_active_program_count_${(programs || []).length}`);

  const base = await fingerprint(clientId);
  const now = new Date().toISOString();
  const { error: receiptError } = await sb.from("cv_canary_runs").upsert({
    run_id: runId, client_id: clientId, status: "bootstrapped", baseline: base,
    result: {}, error_text: null, started_at: now, updated_at: now,
  }, { onConflict: "run_id" });
  if (receiptError) throw new Error(`receipt:${receiptError.message}`);

  const { data: userResult, error: userError } = await sb.auth.admin.getUserById(clientId);
  if (userError || !userResult?.user?.email) throw new Error(`auth_user:${userError?.message || "email_missing"}`);

  const { data: link, error: linkError } = await sb.auth.admin.generateLink({
    type: "magiclink",
    email: userResult.user.email,
    options: { redirectTo: "https://cv-coach-roan.vercel.app" },
  });
  if (linkError || !link?.properties?.hashed_token) throw new Error(`magic_link:${linkError?.message || "token_missing"}`);

  return {
    ok: true,
    run_id: runId,
    client_id: clientId,
    token_hash: link.properties.hashed_token,
    expected_program_id: programs![0].id,
  };
}

async function runReceipt(runId: string) {
  const { data, error } = await sb.from("cv_canary_runs").select("*").eq("run_id", runId).maybeSingle();
  const row = must(data, error, "run_receipt");
  if (!row?.client_id) throw new Error("run_not_found");
  return row;
}

async function claim(runId: string, sessionId: string) {
  if (!UUID_RE.test(sessionId)) throw new Error("invalid_session_id");
  const run = await runReceipt(runId);
  if (run.status !== "bootstrapped") throw new Error(`invalid_run_status_${run.status}`);
  const { data: session, error } = await sb.from("workout_sessions").select("id,client_id,status,started_at").eq("id", sessionId).maybeSingle();
  must(session, error, "claim_session");
  if (!session || session.client_id !== run.client_id || session.status !== "in_progress") throw new Error("session_not_claimable");
  await sb.from("cv_canary_runs").update({
    session_id: sessionId, status: "claimed", claimed_at: new Date().toISOString(), updated_at: new Date().toISOString(),
  }).eq("run_id", runId);
  return { ok: true, run_id: runId, session_id: sessionId };
}

async function verify(runId: string, expectedWeight: number, expectedReps: number) {
  const run = await runReceipt(runId);
  if (run.status !== "claimed" || !run.session_id) throw new Error(`invalid_run_status_${run.status}`);
  const sessionId = run.session_id;
  const { data: session, error } = await sb.from("workout_sessions")
    .select("id,client_id,program_id,program_day_id,status,completion_pct,duration_seconds,total_volume,client_effort,fatigue_score,pain_score,pain_notes,session_notes,started_at,finished_at")
    .eq("id", sessionId).maybeSingle();
  must(session, error, "verify_session");
  if (!session || session.client_id !== run.client_id) throw new Error("session_missing");
  if (session.status !== "abandoned") throw new Error(`unexpected_status_${session.status}`);
  const pct = Number(session.completion_pct);
  if (!(pct > 0 && pct < 50)) throw new Error(`unexpected_completion_${session.completion_pct}`);
  if (!(Number(session.duration_seconds) >= 0) || !session.finished_at) throw new Error("terminal_metrics_missing");
  if (Number(session.client_effort) !== 6 || Number(session.fatigue_score) !== 3 || Number(session.pain_score) !== 0) throw new Error("feedback_mismatch");
  if (session.session_notes !== `CV_CANARY_V76 run=${runId}`) throw new Error("canary_marker_missing");

  const { data: sesEx, error: sesExError } = await sb.from("session_exercises").select("id").eq("workout_session_id", sessionId);
  must(sesEx, sesExError, "session_exercises");
  const ids = (sesEx || []).map((x: any) => x.id);
  if (!ids.length) throw new Error("session_exercises_missing");
  const { data: sets, error: setError } = await sb.from("set_logs").select("id,weight_kg,reps,completed").in("session_exercise_id", ids).eq("completed", true);
  must(sets, setError, "completed_sets");
  const matching = (sets || []).filter((x: any) => Number(x.weight_kg) === expectedWeight && Number(x.reps) === expectedReps);
  if (matching.length !== 1) throw new Error(`expected_completed_set_count_${matching.length}`);

  const coachFields = "id,status,started_at,finished_at,completion_pct,total_volume,client_effort,fatigue_score,pain_score,pain_notes,session_notes";
  const [{ data: ficha, error: fichaError }, { data: report, error: reportError }] = await Promise.all([
    sb.from("workout_sessions").select(coachFields).eq("client_id", run.client_id).order("started_at", { ascending: false }).limit(10),
    sb.from("workout_sessions").select(coachFields).eq("client_id", run.client_id).order("started_at", { ascending: false }).limit(200),
  ]);
  must(ficha, fichaError, "coach_ficha_source");
  must(report, reportError, "coach_report_source");
  if (!(ficha || []).some((x: any) => x.id === sessionId)) throw new Error("coach_ficha_missing_session");
  if (!(report || []).some((x: any) => x.id === sessionId)) throw new Error("coach_report_missing_session");

  const { data: outbox, error: outboxError } = await sb.from("event_outbox").select("id").eq("client_id", run.client_id).eq("aggregate_id", sessionId);
  must(outbox, outboxError, "outbox_check");
  if ((outbox || []).length) throw new Error("canary_outbox_not_suppressed");

  const after = await fingerprint(run.client_id);
  if (!sameFingerprint(run.baseline, after)) throw new Error(`state_drift_before_cleanup:${JSON.stringify({ baseline: run.baseline, after })}`);

  const result = {
    athlete_terminal_ok: true,
    coach_ficha_visible: true,
    coach_report_visible: true,
    completed_set_ok: true,
    outbox_suppressed: true,
    state_unchanged: true,
    completion_pct: pct,
  };
  await sb.from("cv_canary_runs").update({
    status: "verified", verified_at: new Date().toISOString(), result, updated_at: new Date().toISOString(),
  }).eq("run_id", runId);
  return { ok: true, run_id: runId, session_id: sessionId, ...result };
}

async function cleanup(runId: string) {
  const run = await runReceipt(runId);
  try {
    await restoreBaseline(run.client_id, run.baseline || {}, run.session_id);
    const after = await fingerprint(run.client_id);
    if (!sameFingerprint(run.baseline, after)) throw new Error(`state_drift_after_cleanup:${JSON.stringify({ baseline: run.baseline, after })}`);
    if (run.session_id) {
      const { count, error } = await sb.from("workout_sessions").select("id", { count: "exact", head: true }).eq("id", run.session_id);
      if (error || Number(count || 0) !== 0) throw new Error("session_cleanup_failed");
    }
    const now = new Date().toISOString();
    await sb.from("cv_canary_runs").update({
      status: "cleaned", cleaned_at: now, updated_at: now,
      result: { ...(run.result || {}), cleanup_ok: true, baseline_restored: true },
      error_text: null,
    }).eq("run_id", runId);
    return { ok: true, run_id: runId, cleanup_ok: true, baseline_restored: true };
  } catch (error) {
    await sb.from("cv_canary_runs").update({
      status: "failed", error_text: String(error), updated_at: new Date().toISOString(),
    }).eq("run_id", runId);
    throw error;
  }
}

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    await authorize(req);
    const body = await req.json().catch(() => ({}));
    const action = String(body?.action || "");
    const runId = String(body?.run_id || "");
    if (!/^[A-Za-z0-9._:-]{1,120}$/.test(runId)) throw new Error("invalid_run_id");

    if (action === "bootstrap") return json(await bootstrap(runId));
    if (action === "claim") return json(await claim(runId, String(body?.session_id || "")));
    if (action === "verify") return json(await verify(runId, Number(body?.expected_weight), Number(body?.expected_reps)));
    if (action === "cleanup") return json(await cleanup(runId));
    return json({ error: "unknown_action" }, 400);
  } catch (error) {
    console.error("CV_CANARY_V76_ERROR", String(error));
    return json({ error: String(error instanceof Error ? error.message : error) }, 401);
  }
});
