// =============================================================
// Security Login Log — Supabase Edge Function
// เวอร์ชัน: 1.0.0  |  สร้าง: 2026-06-24  |  Stage 17B
//
// รับ POST { payload เดียวกับ logLoginActivity() ฝั่ง frontend }
// → อ่าน IP จริงของ client จาก request headers (frontend JS เชื่อถือ IP ไม่ได้)
// → INSERT แถวเข้า public.security_login_logs ด้วย service role
//     (ห้าม expose service role key ออก frontend — ใช้เฉพาะใน Edge runtime)
//
// Stage 17B = "สร้าง function เฉย ๆ" — ยังไม่ชี้ frontend มาใช้ (Stage C)
//   * is_new_device / is_suspicious → เขียน false ไปก่อน (จะ "คำนวณ" ใน Stage D/E)
//   * best-effort: login flow จริงต้องไม่พังเพราะ logging — แต่ function เอง
//     จะคืน status ที่ถูกต้อง (400 body พัง / 500 insert พัง / 200 สำเร็จ)
//
// ไม่แตะ (สำคัญ): RLS/policies, RPC, migration, anon key usage, login flow,
//   โครงสร้างตาราง — function นี้ "เพิ่มอย่างเดียว" และยังไม่ถูกเรียกใช้
// =============================================================

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const JSON_HEADERS = { ...CORS_HEADERS, 'Content-Type': 'application/json' };

const jsonRes = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });

// ─── IP extraction ─────────────────────────────────────────────────────────────
// ลำดับความสำคัญ: x-forwarded-for (IP แรก) → x-real-ip → cf-connecting-ip → null
// x-forwarded-for อาจเป็น "client, proxy1, proxy2" → เอาตัวแรก (client จริง) แล้ว trim
function extractClientIp(req: Request): string | null {
  const xff = req.headers.get('x-forwarded-for');
  if (xff) {
    const first = xff.split(',')[0]?.trim();
    if (first) return first;
  }
  const xRealIp = req.headers.get('x-real-ip');
  if (xRealIp && xRealIp.trim()) return xRealIp.trim();

  const cfIp = req.headers.get('cf-connecting-ip');
  if (cfIp && cfIp.trim()) return cfIp.trim();

  return null;
}

// ─── Payload whitelist ───────────────────────────────────────────────────────────
// รับเฉพาะ field ที่ logLoginActivity() ส่งจริง — กันการ inject คอลัมน์แปลกปลอม
// (PostgREST จะ error ถ้าเจอ key ที่ไม่มีในตาราง) ทุก field เป็น optional
const ALLOWED_FIELDS = [
  'user_agent',
  'device_type',
  'browser_name',
  'device_fingerprint',
  'login_status',
  'fail_reason',
  'user_id',
  'username',
  'full_name',
  'role',
  'branch_id',
] as const;

function pickAllowed(body: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const key of ALLOWED_FIELDS) {
    if (body[key] !== undefined) out[key] = body[key];
  }
  return out;
}

// ─── Main Handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  // ── CORS preflight ─────────────────────────────────────────────────
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') {
    return jsonRes({ ok: false, error: 'Method not allowed' }, 405);
  }

  // ── Parse body (malformed → 400) ───────────────────────────────────
  let body: Record<string, unknown>;
  try {
    const parsed = await req.json();
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return jsonRes({ ok: false, error: 'Invalid JSON body' }, 400);
    }
    body = parsed as Record<string, unknown>;
  } catch {
    return jsonRes({ ok: false, error: 'Invalid JSON body' }, 400);
  }

  // ── Read secrets (service role only — never returned to client) ────
  // SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY inject อัตโนมัติโดย Supabase
  const supabaseUrl    = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    console.error('[security-login-log] Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
    return jsonRes({ ok: false, error: 'Server not configured' }, 500);
  }

  // ── Build insert row ───────────────────────────────────────────────
  // payload ที่อนุญาต + IP จาก header + flags ที่ยังไม่คำนวณ (Stage D/E)
  const row: Record<string, unknown> = {
    ...pickAllowed(body),
    ip_address:    extractClientIp(req),
    is_new_device: false, // Stage D จะคำนวณจริง
    is_suspicious: false, // Stage E จะคำนวณจริง
  };

  // ── Insert ด้วย service role (REST PostgREST — ตามแนวทาง function เดิม) ──
  try {
    const dbRes = await fetch(`${supabaseUrl}/rest/v1/security_login_logs`, {
      method: 'POST',
      headers: {
        'apikey':        serviceRoleKey,
        'Authorization': `Bearer ${serviceRoleKey}`,
        'Content-Type':  'application/json',
        'Prefer':        'return=minimal',
      },
      body: JSON.stringify(row),
    });

    if (!dbRes.ok) {
      // log รายละเอียดจริงไว้ฝั่ง server เท่านั้น — client ได้ error กลาง ๆ
      const errText = await dbRes.text();
      console.error('[security-login-log] insert failed:', dbRes.status, errText);
      return jsonRes({ ok: false, error: 'Insert failed' }, 500);
    }

    return jsonRes({ ok: true }, 200);
  } catch (e) {
    console.error('[security-login-log] unexpected error:', e instanceof Error ? e.message : String(e));
    return jsonRes({ ok: false, error: 'Insert failed' }, 500);
  }
});
