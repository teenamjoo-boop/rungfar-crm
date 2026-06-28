// =============================================================
// customer-photo-upload — อัปโหลดรูปโปรไฟล์ลูกค้าไปยัง Supabase Storage
// Stage 36A
//
// บทบาท: รับ data_url จาก CRM frontend → decode → upload ไปยัง private
//   bucket customer-photos → UPDATE row ใน public.customers
//   (photo_storage_* มีค่า, photo = null)
//
// ความปลอดภัย (มิเรอร์ customer-doc-upload):
//   * ทุก request ต้องส่ง { user_id, username } → ตรวจด้วย app_verify_session
//   * SUPABASE_SERVICE_ROLE_KEY ใช้ฝั่ง server เท่านั้น — ❌ ไม่ส่งกลับ client
//   * storage_path คำนวณฝั่ง server (ASCII เท่านั้น) — ❌ ไม่รับ path จาก client
//   * audit log บันทึก metadata เท่านั้น — ❌ ไม่ log photo/base64/bytes
//   * ถ้า DB update ล้มเหลวหลัง storage upload → พยายาม cleanup object ที่ upload แล้ว
//
// พฤติกรรม photo เดิม:
//   * ตั้ง photo = null เฉพาะหลัง upload + update สำเร็จเท่านั้น
//   * ถ้า upload/update ล้มเหลว → frontend จะ fallback เขียน base64 ลง customers.photo
//     (dual-write safety — รูปไม่หาย)
//
// ❌ ไม่แตะ: line-webhook-router / line-doc-inbox / line-ai-excel-* / attendance
//           / customer-doc-* / delete approval / Meta Ads / import
// =============================================================

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const BUCKET = 'customer-photos';

const ALLOWED_MIME_TYPES = new Set([
  'image/jpeg', 'image/png',
]);

const IMG_MAX_BYTES = Math.round(1.5 * 1024 * 1024); // 1.5MB — ตรงกับ DOC_MAX_BYTES ใน frontend

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

// ─── Session auth: app_verify_session (เหมือน customer-doc-upload) ──────────
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

// ─── ตรวจ customer_id มีอยู่ใน DB ────────────────────────────────────────────
async function customerExists(url: string, key: string, customerId: number): Promise<boolean> {
  const res = await fetch(
    `${url}/rest/v1/customers?id=eq.${customerId}&select=id&limit=1`,
    { headers: svcHeaders(key) },
  );
  if (!res.ok) return false;
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0;
}

// ─── Decode data URL → bytes ──────────────────────────────────────────────────
function dataUrlToBytes(dataUrl: string): Uint8Array | null {
  const commaIdx = dataUrl.indexOf(',');
  if (commaIdx < 0) return null;
  const b64 = dataUrl.slice(commaIdx + 1);
  try {
    const binaryStr = atob(b64);
    const bytes = new Uint8Array(binaryStr.length);
    for (let i = 0; i < binaryStr.length; i++) bytes[i] = binaryStr.charCodeAt(i);
    return bytes;
  } catch {
    return null;
  }
}

// ─── สร้าง storage path ที่ปลอดภัย (ASCII เท่านั้น) ─────────────────────────
// ❌ ไม่ใช้ชื่อไฟล์เดิม (อาจมี Thai/space/emoji) — ใช้ timestamp + random เท่านั้น
function buildStoragePath(customerId: number, fileType: string): string {
  const now  = new Date();
  const yyyy = now.getUTCFullYear();
  const mm   = String(now.getUTCMonth() + 1).padStart(2, '0');
  const ts   = Date.now();
  const rand = Math.random().toString(36).slice(2, 8); // 6 random alphanumeric chars
  const ext  = fileType === 'image/png' ? 'png' : 'jpg';
  return `customers/${customerId}/${yyyy}/${mm}/${ts}_${rand}.${ext}`;
}

// ─── Upload bytes ไปยัง Supabase Storage (service role) ─────────────────────
async function uploadToStorage(
  url: string, key: string, path: string, bytes: Uint8Array, contentType: string,
): Promise<void> {
  const res = await fetch(`${url}/storage/v1/object/${BUCKET}/${path}`, {
    method:  'POST',
    headers: {
      'apikey':        key,
      'Authorization': `Bearer ${key}`,
      'Content-Type':  contentType,
      'x-upsert':      'false',
    },
    body: bytes,
  });
  if (!res.ok) throw new Error(`storage upload ${res.status}: ${await res.text()}`);
}

// ─── Cleanup: ลบ object ที่ upload แล้ว (best-effort — เรียกเมื่อ DB update ล้ม) ──
async function deleteFromStorage(url: string, key: string, path: string): Promise<void> {
  await fetch(`${url}/storage/v1/object/${BUCKET}`, {
    method:  'DELETE',
    headers: svcHeaders(key),
    body:    JSON.stringify({ prefixes: [path] }),
  }).catch(() => { /* best-effort */ });
}

// ─── UPDATE row ใน public.customers (photo = null) ──────────────────────────
async function updateCustomerPhoto(
  url: string, key: string, customerId: number,
  storagePath: string, fileSize: number, mimeType: string,
): Promise<void> {
  const res = await fetch(`${url}/rest/v1/customers?id=eq.${customerId}`, {
    method:  'PATCH',
    headers: svcHeaders(key, { 'Prefer': 'return=minimal' }),
    body:    JSON.stringify({
      photo_storage_bucket: BUCKET,
      photo_storage_path:   storagePath,
      photo_file_size:      fileSize,
      photo_mime_type:      mimeType,
      photo:                null,        // ❌ ล้าง base64 หลังย้ายเข้า Storage สำเร็จ
    }),
  });
  if (!res.ok) throw new Error(`customers update ${res.status}: ${await res.text()}`);
}

// ─── Main ────────────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST')   return json({ ok: false, error: 'method' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) {
    console.error('[customer-photo-upload] missing required secrets');
    return json({ ok: false, error: 'not_configured' });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: 'bad_request' }, 400);
  }

  const userId        = String(body.user_id    ?? '').trim();
  const username      = String(body.username   ?? '').trim();
  const customerIdRaw = body.customer_id;
  const fileType      = String(body.file_type  ?? '').trim();
  const dataUrl       = String(body.data_url   ?? '').trim();

  if (!userId || !username || customerIdRaw == null || !fileType || !dataUrl) {
    return json({ ok: false, error: 'bad_request' }, 400);
  }

  const customerId = Number(customerIdRaw);
  if (!Number.isInteger(customerId) || customerId <= 0) {
    return json({ ok: false, error: 'invalid_customer_id' }, 400);
  }

  // ── ตรวจ session (active staff/admin) ─────────────────────────────────────
  const actor = await verifyUser(url, key, userId, username);
  if (!actor.ok) {
    console.warn('[customer-photo-upload] unauthorized user_id=%s', userId);
    return json({ ok: false, error: 'unauthorized' }, 401);
  }

  // ── ตรวจ file_type (รูปภาพเท่านั้น) ───────────────────────────────────────
  if (!ALLOWED_MIME_TYPES.has(fileType)) {
    return json({ ok: false, error: 'invalid_file_type' }, 400);
  }

  // ── ตรวจ customer_id มีอยู่ ────────────────────────────────────────────────
  try {
    if (!(await customerExists(url, key, customerId))) {
      return json({ ok: false, error: 'customer_not_found' }, 404);
    }
  } catch (e) {
    console.error('[customer-photo-upload] customer lookup failed:', e instanceof Error ? e.message : e);
    return json({ ok: false, error: 'server_error' }, 500);
  }

  // ── decode data_url → bytes ────────────────────────────────────────────────
  const bytes = dataUrlToBytes(dataUrl);
  if (!bytes) return json({ ok: false, error: 'invalid_data_url' }, 400);

  // ── ตรวจขนาดไฟล์ ──────────────────────────────────────────────────────────
  if (bytes.length > IMG_MAX_BYTES) {
    return json({ ok: false, error: 'image_too_large', size: bytes.length }, 400);
  }

  // ── สร้าง storage path ─────────────────────────────────────────────────────
  const storagePath = buildStoragePath(customerId, fileType);

  // ── upload ไปยัง storage ───────────────────────────────────────────────────
  try {
    await uploadToStorage(url, key, storagePath, bytes, fileType);
  } catch (e) {
    console.error('[customer-photo-upload] storage upload failed:', e instanceof Error ? e.message : e);
    return json({ ok: false, error: 'storage_error' }, 500);
  }

  // ── update public.customers (photo = null) ─────────────────────────────────
  try {
    await updateCustomerPhoto(url, key, customerId, storagePath, bytes.length, fileType);
  } catch (e) {
    console.error('[customer-photo-upload] db update failed:', e instanceof Error ? e.message : e);
    // cleanup: ลบ storage object ที่ upload ไปแล้ว (best-effort)
    await deleteFromStorage(url, key, storagePath);
    return json({ ok: false, error: 'db_error' }, 500);
  }

  // ── audit log (metadata เท่านั้น — ❌ ไม่ log photo/base64/bytes) ──────────
  console.log(
    `[customer-photo-upload] ok customer=${customerId} file_type=${fileType}` +
    ` size=${bytes.length} storage_path=${storagePath} actor=${actor.code}`,
  );

  return json({
    ok:                   true,
    photo_storage_bucket: BUCKET,
    photo_storage_path:   storagePath,
    photo_file_size:      bytes.length,
    photo_mime_type:      fileType,
  });
});
