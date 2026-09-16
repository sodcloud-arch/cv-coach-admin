import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import webpush from "npm:web-push@3.6.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function asObject(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function bool(value: unknown, fallback = false): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function localMinutes(timeZone: string): number | null {
  try {
    const parts = new Intl.DateTimeFormat("en-GB", {
      timeZone,
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    }).formatToParts(new Date());
    const hour = Number(parts.find((p) => p.type === "hour")?.value);
    const minute = Number(parts.find((p) => p.type === "minute")?.value);
    return Number.isFinite(hour) && Number.isFinite(minute) ? hour * 60 + minute : null;
  } catch {
    return null;
  }
}

function parseTime(value: unknown, fallback: number): number {
  const raw = String(value ?? "");
  const match = raw.match(/^(\d{1,2}):(\d{2})/);
  if (!match) return fallback;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  return Number.isFinite(hour) && Number.isFinite(minute) ? hour * 60 + minute : fallback;
}

function inQuietHours(nowMinutes: number, start: number, end: number): boolean {
  if (start === end) return true;
  return start < end
    ? nowMinutes >= start && nowMinutes < end
    : nowMinutes >= start || nowMinutes < end;
}

function safeActionUrl(value: unknown): string {
  const raw = typeof value === "string" ? value.trim() : "";
  const allowed = new Set(["/", "/routine", "/progress", "/progress/missions", "/progress/achievements"]);
  return allowed.has(raw) ? raw : "/";
}

async function config() {
  const { data, error } = await supabase.rpc("get_push_dispatch_config_v101");
  if (error) throw new Error(`PUSH_CONFIG_RPC: ${error.message}`);
  const cfg = asObject(data);
  if (!bool(cfg.configured)) throw new Error("PUSH_CONFIG_NOT_READY");
  return cfg;
}

async function authUser(req: Request) {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!token) return null;
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) return null;
  return data.user;
}

async function finish(queueId: string, outcome: string, results: unknown[], errorMessage: string | null = null) {
  const { error } = await supabase.rpc("finish_push_dispatch_v101", {
    p_queue_id: queueId,
    p_outcome: outcome,
    p_results: results,
    p_error: errorMessage,
  });
  if (error) console.error("finish_push_dispatch_v101", error.message);
}

async function defer(queueId: string, seconds: number, reason: string) {
  const { error } = await supabase.rpc("defer_push_dispatch_v101", {
    p_queue_id: queueId,
    p_seconds: seconds,
    p_reason: reason,
  });
  if (error) console.error("defer_push_dispatch_v101", error.message);
}

async function dispatchOne(itemRaw: unknown, cfg: Record<string, unknown>) {
  const item = asObject(itemRaw);
  const queueId = String(item.queue_id ?? "");
  const userId = String(item.user_id ?? "");
  const notificationId = String(item.notification_id ?? "");
  const category = String(item.category ?? "system_updates");
  const metadata = asObject(item.metadata);
  if (!queueId || !userId || !notificationId) return { queue_id: queueId || null, outcome: "invalid" };

  const [{ data: pref, error: prefError }, { data: subscriptions, error: subError }] = await Promise.all([
    supabase.from("push_preferences_v101").select("*").eq("user_id", userId).maybeSingle(),
    supabase.from("push_subscriptions_v101").select("id,endpoint,p256dh,auth_secret,enabled").eq("user_id", userId).eq("enabled", true),
  ]);
  if (prefError) {
    await finish(queueId, "failed", [], `PREFERENCE_LOOKUP_FAILED: ${prefError.message}`);
    return { queue_id: queueId, outcome: "failed" };
  }
  if (subError) {
    await finish(queueId, "failed", [], `SUBSCRIPTION_LOOKUP_FAILED: ${subError.message}`);
    return { queue_id: queueId, outcome: "failed" };
  }

  const preferences = pref ?? {
    enabled: true,
    training_reminders: true,
    program_updates: true,
    progress_updates: true,
    coach_updates: true,
    system_updates: true,
    quiet_hours_start: "21:00:00",
    quiet_hours_end: "08:00:00",
    timezone: "America/Santiago",
  };

  if (preferences.enabled === false) {
    await finish(queueId, "skipped", [], "PUSH_DISABLED");
    return { queue_id: queueId, outcome: "skipped", reason: "PUSH_DISABLED" };
  }
  if ((preferences as Record<string, unknown>)[category] === false) {
    await finish(queueId, "skipped", [], `CATEGORY_DISABLED:${category}`);
    return { queue_id: queueId, outcome: "skipped", reason: "CATEGORY_DISABLED" };
  }
  if (!subscriptions?.length) {
    await finish(queueId, "skipped", [], "NO_ACTIVE_SUBSCRIPTION");
    return { queue_id: queueId, outcome: "skipped", reason: "NO_ACTIVE_SUBSCRIPTION" };
  }

  const bypassQuiet = bool(metadata.bypass_quiet_hours, false);
  const zone = String(preferences.timezone || "America/Santiago");
  const minutes = localMinutes(zone);
  const quietStart = parseTime(preferences.quiet_hours_start, 21 * 60);
  const quietEnd = parseTime(preferences.quiet_hours_end, 8 * 60);
  if (!bypassQuiet && minutes !== null && inQuietHours(minutes, quietStart, quietEnd)) {
    await defer(queueId, 30 * 60, "QUIET_HOURS_ACTIVE");
    return { queue_id: queueId, outcome: "deferred", reason: "QUIET_HOURS_ACTIVE" };
  }

  webpush.setVapidDetails(
    String(cfg.subject),
    String(cfg.public_key),
    String(cfg.private_key),
  );

  const payload = JSON.stringify({
    version: "PUSH_NOTIFICATIONS_OS_V101",
    notification_id: notificationId,
    type: String(item.type ?? "notification"),
    category,
    title: String(item.title ?? "CV Coach"),
    body: String(item.body ?? ""),
    action_url: safeActionUrl(item.action_url),
    icon: "./icon.svg",
    tag: `cv-${notificationId}`,
  });

  const results: Record<string, unknown>[] = [];
  for (const sub of subscriptions) {
    try {
      const sent = await webpush.sendNotification({
        endpoint: sub.endpoint,
        keys: { p256dh: sub.p256dh, auth: sub.auth_secret },
      }, payload, { TTL: 60 * 60, urgency: category === "program_updates" ? "high" : "normal" });
      results.push({ subscription_id: sub.id, status: "sent", http_status: sent.statusCode ?? 201, error: null });
    } catch (error) {
      const e = error as { statusCode?: number; message?: string };
      results.push({ subscription_id: sub.id, status: "failed", http_status: e.statusCode ?? null, error: String(e.message ?? error).slice(0, 1500) });
    }
  }

  const sentCount = results.filter((x) => x.status === "sent").length;
  const failedCount = results.length - sentCount;
  const outcome = sentCount > 0 ? (failedCount > 0 ? "partial" : "sent") : "failed";
  await finish(queueId, outcome, results, failedCount ? `${failedCount}/${results.length} push deliveries failed` : null);
  return { queue_id: queueId, outcome, sent: sentCount, failed: failedCount };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return response({ error: "METHOD_NOT_ALLOWED" }, 405);
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return response({ error: "SERVER_CONFIG_MISSING" }, 500);

  let body: Record<string, unknown>;
  try { body = asObject(await req.json()); } catch { return response({ error: "INVALID_JSON" }, 400); }
  const action = String(body.action ?? "dispatch");

  try {
    const cfg = await config();

    if (action === "test") {
      const user = await authUser(req);
      if (!user) return response({ error: "AUTH_REQUIRED" }, 401);
      const notificationId = String(body.notification_id ?? "");
      if (!notificationId) return response({ error: "NOTIFICATION_ID_REQUIRED" }, 400);
      const { data: claimed, error } = await supabase.rpc("claim_push_notification_v101", {
        p_notification_id: notificationId,
        p_user_id: user.id,
      });
      if (error) throw new Error(`CLAIM_TEST_FAILED: ${error.message}`);
      if (!claimed) return response({ ok: true, idempotent: true, message: "Test notification already processed or unavailable." });
      const result = await dispatchOne(claimed, cfg);
      return response({ ok: true, test: true, result });
    }

    if (action !== "dispatch") return response({ error: "INVALID_ACTION" }, 400);
    if (String(body.dispatch_token ?? "") !== String(cfg.dispatch_token ?? "")) return response({ error: "DISPATCH_AUTH_FAILED" }, 401);

    const limit = Math.max(1, Math.min(Number(body.limit ?? 25) || 25, 100));
    const { data: claimed, error } = await supabase.rpc("claim_push_dispatch_v101", { p_limit: limit });
    if (error) throw new Error(`CLAIM_FAILED: ${error.message}`);
    const items = Array.isArray(claimed) ? claimed : [];
    const results = [];
    for (const item of items) results.push(await dispatchOne(item, cfg));
    return response({ ok: true, version: "PUSH_NOTIFICATIONS_OS_V101", claimed: items.length, results });
  } catch (error) {
    console.error(error);
    return response({ error: String((error as Error)?.message ?? error) }, 500);
  }
});
