// =============================================================
// customer-photo-sign — ออก signed URL สำหรับรูปโปรไฟล์ลูกค้าใน Storage
// Stage 36A
//
// บทบาท: CRM frontend ขอ short-lived signed URL เพื่อแสดงรูปโปรไฟล์ลูกค้า
//   ที่เก็บใน private bucket customer-photos
//
// ความปลอดภัย (มิเรอร์ customer-doc-sign ทุกประการ):
//   * ทุก request ต้องส่ง { customer_id, user_id, username }
//   * ตรวจ session ด้วย app_verify_session (active staff/admin)
//   * ดึง photo_storage_path จาก DB ฝั่ง server เท่านั้น — ❌ ไม่รับ path จาก client
//   * SUPABASE_SERVICE_ROLE_KEY ใช้ฝั่ง server เท่านั้น — ❌ ไม่ส่งกลับ client
//   * signed URL อายุสั้น 30 นาที
//
// ❌ ไม่แตะ: line-webhook-router / line-doc-inbox / line-ai-excel-* / attendance
//           / customer-doc-* / delete approval / Meta Ads
// =============================================================

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SIGN_EXPIRES_SEC = 1800;             // 30 นาที — signed URL อายุสั้น
const DEFAULT_BUCKET   = 'customer-photos';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

function svcHeaders(key: string, extra: Record<string, string> = {}): Record<string, string> {
  return {
    'apikey':        key,
    'Authorization': `Bearer ${key}`,
    'Content-Type':  'application/json',
    ...extra,
  };
}

// ─── Session auth: app_verify_session (เหมือน customer-doc-sign) ───────────
async function verifyUser(
  url: string, key: string, userId: string, username: string,
): Promise<{ ok: boolean; code: string | null; name: string | null }> {
  if (!userId || !username) return { ok: false, code: null, name: null };
  const vr = await fetch(`${url}/rest/v1/rpc/app_verify_session`, {
    method:  'POST',
    headers: svcHeaders(key),
    body:    JSON.stringify({ p_user_id: userId, p_username: username }),
  });
  if (!vr.ok) return { ok: false, code: null, name: null };
  let data: unknown;
  try { data = await vr.json(); } catch { data = null; }
  const u = (data && typeof data === 'object' && !Array.isArray(data))
    ? data as { id?: unknown; username?: string; full_name?: string; role?: string }
    : null;
  if (!u || u.id == null) return { ok: false, code: null, name: null };
  return { ok: true, code: u.username || username, name: u.full_name || username };
}

// ─── Fetch customer photo row (server-side — ❌ ไม่รับ path จาก client) ────
interface CustPhotoRow {
  id:                   number;
  photo_storage_bucket: string | null;
  photo_storage_path:   string | null;
  photo_mime_type:      string | null;
}

async function getCustPhotoRow(url: string, key: string, custId: string): Promise<CustPhotoRow | null> {
  const res = await fetch(
    `${url}/rest/v1/customers?id=eq.${encodeURIComponent(custId)}` +
    `&select=id,photo_storage_bucket,photo_storage_path,photo_mime_type&limit=1`,
    { headers: svcHeaders(key) },
  );
  if (!res.ok) throw new Error(`customer select ${res.status}: ${await res.text()}`);
  const rows = await res.json();
  return Array.isArray(rows) && rows[0] ? rows[0] as CustPhotoRow : null;
}

// ─── Create signed URL (service role — ❌ key ไม่ส่งออกจากฟังก์ชันนี้) ───
async function createSignedUrl(
  url: string, key: string, bucket: string, path: string,
): Promise<string> {
  const res = await fetch(
    `${url}/storage/v1/object/sign/${bucket}/${path}`,
    {
      method:  'POST',
      headers: svcHeaders(key),
      body:    JSON.stringify({ expiresIn: SIGN_EXPIRES_SEC }),
    },
  );
  if (!res.ok) throw new Error(`sign ${res.status}: ${await res.text()}`);
  const data = await res.json();
  return `${url}/storage/v1${data.signedURL}`;
}

// ─── Main ────────────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST')   return json({ ok: false, error: 'method' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) {
    console.error('[customer-photo-sign] missing required secrets');
    return json({ ok: false, error: 'not_configured' });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: 'bad_request' }, 400);
  }

  const custId   = String(body.customer_id ?? '').trim();
  const userId   = String(body.user_id     ?? '').trim();
  const username = String(body.username    ?? '').trim();

  if (!custId || !userId || !username) {
    return json({ ok: false, error: 'bad_request' }, 400);
  }

  // ── ตรวจ session (active staff/admin) ─────────────────────────────────────
  const actor = await verifyUser(url, key, userId, username);
  if (!actor.ok) {
    console.warn('[customer-photo-sign] unauthorized');
    return json({ ok: false, error: 'unauthorized' }, 401);
  }

  try {
    // ── ดึง customer row จาก DB — path มาจาก server เท่านั้น ───────────────
    const row = await getCustPhotoRow(url, key, custId);
    if (!row)                    return json({ ok: false, error: 'not_found' }, 404);
    if (!row.photo_storage_path) return json({ ok: false, error: 'no_storage_photo' });

    const bucket = row.photo_storage_bucket || DEFAULT_BUCKET;
    const signed = await createSignedUrl(url, key, bucket, row.photo_storage_path);

    console.log(`[customer-photo-sign] signed customer=${custId} actor=${actor.code}`);
    return json({ ok: true, url: signed, expires_in: SIGN_EXPIRES_SEC, mime_type: row.photo_mime_type });
  } catch (e) {
    console.error('[customer-photo-sign] error:', e instanceof Error ? e.message : e);
    return json({ ok: false, error: 'server_error' }, 500);
  }
});
