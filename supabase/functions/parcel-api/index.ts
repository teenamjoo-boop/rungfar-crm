// ============================================================================
// STAGE PARCEL-001 — parcel-api
//
// ประตูเดียวของเว็บรายรับ-รายจ่ายขนส่งพัสดุ (parcel.html) และลิงก์ดูอย่างเดียว
//   เว็บ → POST (text/plain, ไม่มี preflight) → ฟังก์ชันนี้ → public.parcel_api(action, token, args)
//
// Security
//   * Verify JWT = OFF: หน้าเว็บไม่มีกุญแจ Supabase เลย — ตัวตนใช้ session token ของระบบขนส่งเอง
//     (สุ่ม 256 bit, ฐานข้อมูลเก็บแค่ SHA-256) ตรวจใน parcel_api ทุกคำสั่ง
//   * service-role key อยู่ใน Edge runtime เท่านั้น · parcel_api เข้าถึงได้เฉพาะ service_role
//   * action allowlist · body ≤ 256 KiB · ไม่ log ข้อมูลผู้ใช้/รหัสผ่าน/token
// ============================================================================

const ACTIONS = new Set([
  'login', 'logout', 'boot', 'summary', 'list', 'save', 'delete',
  'carrier_save', 'opening_save', 'users_list', 'user_save',
  'share_get', 'share_create', 'share_revoke', 'share_view',
  'import', 'import_check',   // Stage PARCEL-IMPORT
]);
const MAX_BODY = 256 * 1024;   // Stage PARCEL-IMPORT: นำเข้าครั้งละ ≤ 200 แถว
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type',
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method !== 'POST') return json(405, { ok: false, error: 'method_not_allowed' });

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return json(500, { ok: false, error: 'server_not_configured' });

  let body: { a?: unknown; t?: unknown; args?: unknown } = {};
  try {
    const raw = await req.text();
    if (raw.length > MAX_BODY) return json(413, { ok: false, error: 'body_too_large' });
    body = raw ? JSON.parse(raw) : {};
  } catch (_) {
    return json(400, { ok: false, error: 'invalid_json' });
  }

  const action = typeof body.a === 'string' ? body.a : '';
  if (!ACTIONS.has(action)) return json(400, { ok: false, error: 'unknown_action' });
  const token = typeof body.t === 'string' && /^[0-9a-f]{64}$/.test(body.t) ? body.t : null;
  const args = body.args && typeof body.args === 'object' && !Array.isArray(body.args) ? body.args : {};

  try {
    const r = await fetch(`${url}/rest/v1/rpc/parcel_api`, {
      method: 'POST',
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_action: action, p_token: token, p_args: args }),
    });
    if (!r.ok) {
      // ข้อผิดพลาดจากการตรวจข้อมูล (เช่น invalid_cost) → ส่งรหัสกลับ ไม่ส่งรายละเอียดภายใน
      const e = await r.json().catch(() => ({}));
      const msg = String((e && (e as { message?: string }).message) || '');
      const code = /^[a-z_]{3,40}$/.test(msg) ? msg : 'server_error';
      return json(200, { ok: false, error: code });
    }
    return json(200, await r.json());
  } catch (_) {
    return json(502, { ok: false, error: 'upstream_failed' });
  }
});
