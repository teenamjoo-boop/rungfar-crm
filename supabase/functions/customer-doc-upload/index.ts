// =============================================================
// customer-doc-upload — อัปโหลดเอกสารลูกค้าไปยัง Supabase Storage
// Stage 33B
//
// บทบาท: รับ data_url จาก CRM frontend → decode → upload ไปยัง private
//   bucket customer-documents → insert row ใน public.documents
//   (file_data = null, storage_path มีค่า)
//
// ความปลอดภัย:
//   * ทุก request ต้องส่ง { user_id, username } → ตรวจด้วย app_verify_session
//     (active staff/admin — โมเดลตัวตนเดียวกับ customer-doc-sign และ line-doc-inbox-admin)
//   * SUPABASE_SERVICE_ROLE_KEY ใช้ฝั่ง server เท่านั้น — ❌ ไม่ส่งกลับ client
//   * storage_path คำนวณฝั่ง server — ❌ ไม่รับ path จาก client
//   * audit log บันทึก metadata เท่านั้น — ❌ ไม่ log file_data/base64/bytes
//   * ถ้า DB insert ล้มเหลวหลัง storage upload → พยายาม cleanup object ที่ upload ไปแล้ว
//
// ❌ ไม่แตะ: line-webhook-router / line-doc-inbox / line-ai-excel-* / attendance / import
// =============================================================

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const BUCKET = 'customer-documents';

const ALLOWED_DOC_TYPES = new Set([
  'passport_photo', 'visa', 'wp', 'employer_card', 'receipt', 'photo', 'pow', 'other',
]);

// STAGE 54A-1B: owner generalization — ค่า owner_type ที่ schema รองรับ
// stage นี้ "อัปโหลดได้เฉพาะ customer" — employer/establishment/case จะเปิดใน
// stage ถัดไปเมื่อมีตาราง/UI ให้ validate เจ้าของได้จริง (กัน orphan write)
const ALLOWED_OWNER_TYPES = new Set(['customer', 'employer', 'establishment', 'case']);
const SUPPORTED_OWNER_TYPES = new Set(['customer']);

const ALLOWED_MIME_TYPES = new Set([
  'image/jpeg', 'image/png', 'application/pdf',
]);

const PDF_MAX_BYTES = 10 * 1024 * 1024;        // 10MB — PDF limit
const IMG_MAX_BYTES = Math.round(1.5 * 1024 * 1024); // 1.5MB — image limit after frontend compression

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

// ─── Session auth: app_verify_session (เหมือน customer-doc-sign / line-doc-inbox-admin) ──
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
// ใช้ timestamp + random suffix เท่านั้น — ❌ ไม่ใช้ชื่อไฟล์เดิม (อาจมี Thai/space/emoji)
// doc_name ใน documents table เก็บชื่อที่อ่านได้ตามปกติ
function buildStoragePath(customerId: number, fileType: string): string {
  const now = new Date();
  const yyyy = now.getUTCFullYear();
  const mm   = String(now.getUTCMonth() + 1).padStart(2, '0');
  const ts   = Date.now();
  const rand = Math.random().toString(36).slice(2, 8); // 6 random alphanumeric chars
  const ext  = fileType === 'application/pdf' ? 'pdf'
    : fileType === 'image/png'  ? 'png'
    : 'jpg';
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

// ─── Cleanup: ลบ object ที่ upload แล้ว (best-effort — เรียกเมื่อ DB insert ล้ม) ──
async function deleteFromStorage(url: string, key: string, path: string): Promise<void> {
  await fetch(`${url}/storage/v1/object/${BUCKET}`, {
    method:  'DELETE',
    headers: svcHeaders(key),
    body:    JSON.stringify({ prefixes: [path] }),
  }).catch(() => { /* best-effort */ });
}

// ─── Insert row ใน public.documents (file_data = null) ──────────────────────
interface DocInsert {
  customerId:   number;
  docType:      string;
  docName:      string;
  fileType:     string;
  fileSize:     number;
  storagePath:  string;
  uploadedBy:   string;
  ownerType:    string;   // STAGE 54A-1B: dual-write เจ้าของ (ตอนนี้ = 'customer' เสมอ)
  ownerId:      number;   // STAGE 54A-1B: = customerId สำหรับ owner_type='customer'
}

async function insertDocument(
  url: string, key: string, d: DocInsert,
): Promise<Record<string, unknown>> {
  const res = await fetch(`${url}/rest/v1/documents`, {
    method:  'POST',
    headers: svcHeaders(key, { 'Prefer': 'return=representation' }),
    body:    JSON.stringify({
      customer_id:    d.customerId,
      doc_type:       d.docType,
      doc_name:       d.docName,
      file_type:      d.fileType,
      mime_type:      d.fileType,
      file_size:      d.fileSize,
      storage_bucket: BUCKET,
      storage_path:   d.storagePath,
      thumbnail_path: null,
      uploaded_by:    d.uploadedBy,
      file_data:      null,           // ❌ ไม่เก็บ base64 ใน DB
      // STAGE 54A-1B: dual-write — customer_id ยังถูก set เสมอสำหรับเอกสารลูกค้า
      // (ต้อง apply migration 20260731_documents_owner_generalization.sql ก่อน deploy ไฟล์นี้)
      owner_type:     d.ownerType,
      owner_id:       d.ownerId,
    }),
  });
  if (!res.ok) throw new Error(`documents insert ${res.status}: ${await res.text()}`);
  const rows = await res.json();
  if (!Array.isArray(rows) || !rows[0]) throw new Error('documents insert: no row returned');
  return rows[0] as Record<string, unknown>;
}

// ─── Main ────────────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST')   return json({ ok: false, error: 'method' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) {
    console.error('[customer-doc-upload] missing required secrets');
    return json({ ok: false, error: 'not_configured' });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: 'bad_request' }, 400);
  }

  const userId       = String(body.user_id    ?? '').trim();
  const username     = String(body.username   ?? '').trim();
  const customerIdRaw = body.customer_id;
  const docType      = String(body.doc_type   ?? '').trim();
  const docNameRaw   = String(body.doc_name   ?? '').trim();
  const fileName     = String(body.file_name  ?? '').trim();
  const fileType     = String(body.file_type  ?? '').trim();
  const dataUrl      = String(body.data_url   ?? '').trim();

  if (!userId || !username || customerIdRaw == null || !docType || !docNameRaw || !dataUrl) {
    return json({ ok: false, error: 'bad_request' }, 400);
  }

  const customerId = Number(customerIdRaw);
  if (!Number.isInteger(customerId) || customerId <= 0) {
    return json({ ok: false, error: 'invalid_customer_id' }, 400);
  }

  // ── STAGE 54A-1B: owner_type / owner_id (optional — ไม่ส่ง = พฤติกรรมเดิม 100%) ──
  //   * ไม่ส่ง → owner_type='customer', owner_id=customer_id (dual-write)
  //   * ส่ง 'customer' → owner_id (ถ้าส่ง) ต้องตรงกับ customer_id (กันชี้คนละคน)
  //   * ส่ง employer/establishment/case → ยังไม่เปิดใน stage นี้ (รอตาราง/UI ให้
  //     validate เจ้าของจริงได้ก่อน — กัน orphan write) → คืน error ชัดเจน
  const ownerTypeRaw = String(body.owner_type ?? '').trim().toLowerCase();
  const ownerType    = ownerTypeRaw || 'customer';
  if (!ALLOWED_OWNER_TYPES.has(ownerType)) {
    return json({ ok: false, error: 'invalid_owner_type' }, 400);
  }
  if (!SUPPORTED_OWNER_TYPES.has(ownerType)) {
    return json({ ok: false, error: 'owner_type_not_supported' }, 400);
  }
  let ownerId = customerId;
  if (body.owner_id != null && String(body.owner_id).trim() !== '') {
    const n = Number(body.owner_id);
    if (!Number.isInteger(n) || n <= 0) {
      return json({ ok: false, error: 'invalid_owner_id' }, 400);
    }
    if (n !== customerId) {
      return json({ ok: false, error: 'owner_mismatch' }, 400);
    }
    ownerId = n;
  }

  const docName = docNameRaw.slice(0, 255);

  // ── ตรวจ session (active staff/admin) ─────────────────────────────────────
  const actor = await verifyUser(url, key, userId, username);
  if (!actor.ok) {
    console.warn('[customer-doc-upload] unauthorized user_id=%s', userId);
    return json({ ok: false, error: 'unauthorized' }, 401);
  }

  // ── ตรวจ doc_type ──────────────────────────────────────────────────────────
  if (!ALLOWED_DOC_TYPES.has(docType)) {
    return json({ ok: false, error: 'invalid_doc_type' }, 400);
  }

  // ── ตรวจ file_type (MIME) ──────────────────────────────────────────────────
  if (!ALLOWED_MIME_TYPES.has(fileType)) {
    return json({ ok: false, error: 'invalid_file_type' }, 400);
  }

  // ── ตรวจ customer_id มีอยู่ ────────────────────────────────────────────────
  try {
    if (!(await customerExists(url, key, customerId))) {
      return json({ ok: false, error: 'customer_not_found' }, 404);
    }
  } catch (e) {
    console.error('[customer-doc-upload] customer lookup failed:', e instanceof Error ? e.message : e);
    return json({ ok: false, error: 'server_error' }, 500);
  }

  // ── decode data_url → bytes ────────────────────────────────────────────────
  const bytes = dataUrlToBytes(dataUrl);
  if (!bytes) return json({ ok: false, error: 'invalid_data_url' }, 400);

  // ── ตรวจขนาดไฟล์ ──────────────────────────────────────────────────────────
  const isPdf   = fileType === 'application/pdf';
  const maxBytes = isPdf ? PDF_MAX_BYTES : IMG_MAX_BYTES;
  if (bytes.length > maxBytes) {
    return json({
      ok:    false,
      error: isPdf ? 'pdf_too_large' : 'image_too_large',
      size:  bytes.length,
    }, 400);
  }

  // ── สร้าง storage path ─────────────────────────────────────────────────────
  const storagePath = buildStoragePath(customerId, fileType);

  // ── upload ไปยัง storage ───────────────────────────────────────────────────
  try {
    await uploadToStorage(url, key, storagePath, bytes, fileType);
  } catch (e) {
    console.error('[customer-doc-upload] storage upload failed:', e instanceof Error ? e.message : e);
    return json({ ok: false, error: 'storage_error' }, 500);
  }

  // ── insert ลงใน public.documents ──────────────────────────────────────────
  let docRow: Record<string, unknown>;
  try {
    docRow = await insertDocument(url, key, {
      customerId,
      docType,
      docName,
      fileType,
      fileSize:    bytes.length,
      storagePath,
      uploadedBy:  actor.name || actor.code || username,
      ownerType,           // STAGE 54A-1B: 'customer' เสมอใน stage นี้
      ownerId,             // STAGE 54A-1B: = customerId
    });
  } catch (e) {
    console.error('[customer-doc-upload] db insert failed:', e instanceof Error ? e.message : e);
    // cleanup: ลบ storage object ที่ upload ไปแล้ว (best-effort)
    await deleteFromStorage(url, key, storagePath);
    return json({ ok: false, error: 'db_error' }, 500);
  }

  // ── audit log (metadata เท่านั้น — ❌ ไม่ log file_data/bytes) ─────────────
  console.log(
    `[customer-doc-upload] ok customer=${customerId} doc_type=${docType}` +
    ` file_type=${fileType} size=${bytes.length} storage_path=${storagePath} actor=${actor.code}`,
  );

  return json({ ok: true, doc: docRow });
});
