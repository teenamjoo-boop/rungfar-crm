// ============================================================================
// N8N-001A — n8n-read-api  (READ-ONLY V1)
// Target: Supabase STAGING ONLY
//
// Machine-to-machine read API for an external automation client (n8n).
//
// Security model
//   * Custom machine authentication: opaque bearer token (>=256 bits) held only
//     by n8n. This function stores ONLY the SHA-256 verifier
//     (N8N_READ_API_TOKEN_SHA256). The raw token never appears in source.
//   * Because this is machine auth rather than a Supabase end-user JWT, the
//     function is deployed with verify_jwt=false ONLY because it implements this
//     mandatory custom authentication itself. Fail-closed on missing/invalid.
//   * The service-role credential stays server-side inside the Edge runtime and
//     is never returned, logged, or forwarded to the client.
//   * Machine identity is entirely separate from public.app_users. No human
//     session, username, or user_id is ever used or impersonated.
//
// Hard limits
//   * POST + application/json only.
//   * Request body capped at 8 KiB, enforced by a bounded stream reader BEFORE
//     any JSON parsing and without trusting Content-Length.
//   * Static action allowlist. No generic proxy, no dynamic RPC/table/SQL.
//   * Authoritative request_id is generated server-side (crypto.randomUUID()).
//   * Authoritative rate limiting and all timestamps live in the database.
//   * Overall request deadline 8s. No automatic retries.
// ============================================================================

const ACTIONS = ["health.v1", "management.summary.v1", "cases.readiness.v1"] as const;
type Action = (typeof ACTIONS)[number];

// Static dispatch table. The RPC name is a hard-coded constant per action and is
// never derived from request input.
const ACTION_RPC: Record<Action, string> = {
  "health.v1": "integration_n8n_health_v1",
  "management.summary.v1": "integration_n8n_management_summary_v1",
  "cases.readiness.v1": "integration_n8n_case_readiness_v1",
};

const CLIENT_CODE = "n8n-staging-readonly";
const ALLOWED_KEYS = new Set(["action", "client_request_id"]);
const MAX_BODY_BYTES = 8192;

const DEADLINE_MS = 8000;
const ADMIT_TIMEOUT_MS = 1500;
const READ_TIMEOUT_MS = 4000;
const FINISH_TIMEOUT_MS = 1500;

// Coarse pre-auth isolate guard. Not globally authoritative — it only blunts
// accidental rapid loops and reduces invalid-token CPU pressure. The
// authoritative limiter is the database admission RPC.
const ISOLATE_MAX = 20;
const ISOLATE_WINDOW_MS = 5000;
let isolateHits: number[] = [];

function isolateAllows(): boolean {
  const now = Date.now();
  isolateHits = isolateHits.filter((t) => now - t < ISOLATE_WINDOW_MS);
  if (isolateHits.length >= ISOLATE_MAX) return false;
  isolateHits.push(now);
  return true;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

function fail(status: number, code: string, requestId?: string): Response {
  const body: Record<string, unknown> = { ok: false, error: code };
  if (requestId) body.request_id = requestId;
  return json(status, body);
}

// --- token verification ------------------------------------------------------

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Constant-time comparison over fixed-length lowercase hex digests.
function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// --- bounded body reader -----------------------------------------------------

// Reads at most maxBytes. Stops and cancels the stream as soon as the limit is
// exceeded. Never consults Content-Length and never parses JSON before the
// byte-size check passes.
async function readBounded(
  req: Request,
  maxBytes: number,
): Promise<{ ok: true; text: string } | { ok: false }> {
  if (!req.body) return { ok: true, text: "" };

  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;
      total += value.byteLength;
      if (total > maxBytes) {
        try {
          await reader.cancel();
        } catch {
          // stream already torn down
        }
        return { ok: false };
      }
      chunks.push(value);
    }
  } catch {
    return { ok: false };
  }

  const merged = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    merged.set(c, offset);
    offset += c.byteLength;
  }
  return { ok: true, text: new TextDecoder().decode(merged) };
}

// --- client_request_id validation -------------------------------------------

const CLIENT_REQUEST_ID_RE = /^[A-Za-z0-9._:-]{1,80}$/;

// --- database call helper ----------------------------------------------------

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const TOKEN_SHA256 = (Deno.env.get("N8N_READ_API_TOKEN_SHA256") ?? "").trim().toLowerCase();

type RpcResult = { ok: true; data: unknown } | { ok: false; timedOut: boolean };

async function callRpc(fn: string, args: Record<string, unknown>, timeoutMs: number): Promise<RpcResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      },
      body: JSON.stringify(args),
      signal: controller.signal,
    });
    if (!res.ok) {
      // Body is intentionally discarded: database error text must never reach
      // the machine client.
      return { ok: false, timedOut: false };
    }
    return { ok: true, data: await res.json() };
  } catch (e) {
    const timedOut = e instanceof DOMException && e.name === "AbortError";
    return { ok: false, timedOut };
  } finally {
    clearTimeout(timer);
  }
}

// Best-effort row count for audit purposes only.
function rowCountOf(action: Action, data: unknown): number | null {
  if (action === "cases.readiness.v1" && data && typeof data === "object") {
    const rc = (data as Record<string, unknown>).returned_count;
    if (typeof rc === "number") return rc;
  }
  if (action === "management.summary.v1" || action === "health.v1") return 1;
  return null;
}

// --- handler -----------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  const startedAt = Date.now();
  const remaining = () => DEADLINE_MS - (Date.now() - startedAt);

  // 1. Method / transport hardening (pre-auth, cheap).
  if (req.method !== "POST") {
    return fail(405, "method_not_allowed");
  }

  const contentType = req.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().includes("application/json")) {
    return fail(415, "unsupported_media_type");
  }

  if (!isolateAllows()) {
    return fail(429, "too_many_requests");
  }

  // 2. Configuration sanity. Fail closed rather than degrade.
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY || TOKEN_SHA256.length !== 64) {
    return fail(503, "service_unconfigured");
  }

  // 3. Machine authentication. Fail closed BEFORE any database call.
  const authHeader = req.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(authHeader.trim());
  if (!match) {
    return fail(401, "unauthorized");
  }
  const presentedHash = await sha256Hex(match[1]);
  if (!timingSafeEqualHex(presentedHash, TOKEN_SHA256)) {
    return fail(401, "unauthorized");
  }

  // 4. Body size cap enforced before JSON parsing.
  const bounded = await readBounded(req, MAX_BODY_BYTES);
  if (!bounded.ok) {
    return fail(413, "payload_too_large");
  }

  // 5. Parse and validate the request shape.
  let parsed: unknown;
  try {
    parsed = JSON.parse(bounded.text);
  } catch {
    return fail(400, "invalid_json");
  }

  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    return fail(400, "invalid_body");
  }
  const body = parsed as Record<string, unknown>;

  for (const key of Object.keys(body)) {
    if (!ALLOWED_KEYS.has(key)) {
      return fail(400, "unknown_field");
    }
  }

  const action = body.action;
  if (typeof action !== "string" || !(ACTIONS as readonly string[]).includes(action)) {
    return fail(400, "invalid_action");
  }
  const typedAction = action as Action;

  let clientRequestId: string | null = null;
  if (body.client_request_id !== undefined && body.client_request_id !== null) {
    if (typeof body.client_request_id !== "string" || !CLIENT_REQUEST_ID_RE.test(body.client_request_id)) {
      return fail(400, "invalid_client_request_id");
    }
    clientRequestId = body.client_request_id;
  }

  // 6. Authoritative server-generated request id. A client-supplied
  //    client_request_id is informational only and never substitutes for this.
  const requestId = crypto.randomUUID();

  // 7. Database rate admission. No business read runs if admission is rejected.
  const admit = await callRpc(
    "integration_n8n_admit_request_v1",
    {
      p_request_id: requestId,
      p_client_code: CLIENT_CODE,
      p_action: typedAction,
      p_client_request_id: clientRequestId,
    },
    Math.min(ADMIT_TIMEOUT_MS, Math.max(remaining(), 1)),
  );

  if (!admit.ok) {
    return fail(admit.timedOut ? 504 : 503, admit.timedOut ? "integration_timeout" : "admission_unavailable");
  }

  const admitBody = (admit.data ?? {}) as Record<string, unknown>;
  if (admitBody.admitted !== true) {
    const code = typeof admitBody.error_code === "string" ? admitBody.error_code : "rejected";
    // No 'started' row was inserted, so there is nothing to finalize.
    if (code.startsWith("rate_limited")) return fail(429, "rate_limited");
    if (code === "invalid_action") return fail(400, "invalid_action");
    if (code === "invalid_client_request_id") return fail(400, "invalid_client_request_id");
    return fail(400, "rejected");
  }

  // 8. Business read.
  const read = await callRpc(
    ACTION_RPC[typedAction],
    {},
    Math.min(READ_TIMEOUT_MS, Math.max(remaining(), 1)),
  );

  // 9. Finalize the audit row from the database clock. Fail closed if the audit
  //    cannot be persisted — never return business data with an unpersisted audit.
  const outcome = read.ok ? "success" : read.timedOut ? "timeout" : "error";
  const errorCode = read.ok ? null : read.timedOut ? "integration_timeout" : "read_failed";

  const finish = await callRpc(
    "integration_n8n_finish_request_v1",
    {
      p_request_id: requestId,
      p_outcome: outcome,
      p_row_count: read.ok ? rowCountOf(typedAction, read.data) : null,
      p_error_code: errorCode,
    },
    Math.min(FINISH_TIMEOUT_MS, Math.max(remaining(), 1)),
  );

  const finishBody = (finish.ok ? finish.data ?? {} : {}) as Record<string, unknown>;
  if (!finish.ok || finishBody.finished !== true) {
    return fail(503, "audit_unavailable", requestId);
  }

  if (!read.ok) {
    return read.timedOut
      ? fail(504, "integration_timeout", requestId)
      : fail(502, "read_failed", requestId);
  }

  return json(200, {
    ok: true,
    request_id: requestId,
    client_request_id: clientRequestId,
    action: typedAction,
    data: read.data,
  });
});
