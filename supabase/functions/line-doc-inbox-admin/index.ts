// =============================================================
// LINE Document Inbox — review helper (Supabase Edge Function, Stage 29C → 29G → 33C)
//
// บทบาท: ฝั่ง "ผู้ใช้ CRM ที่ล็อกอินอยู่ (staff/admin)" เรียกใช้เพื่อ
//   A) sign    → สร้าง signed URL อายุสั้นจาก private bucket line-doc-inbox (พรีวิว/เปิดไฟล์)
//   B) approve → อ่าน bytes จาก line-doc-inbox (service role) →
//                อัปโหลดไฟล์เข้า private bucket customer-documents (Stage 33C) →
//                insert เข้า public.documents (storage_path มีค่า, file_data = null) →
//                อัปเดต line_file_inbox = linked
//                ❌ ไม่เก็บ base64 ใน documents.file_data อีกต่อไป (เดิม Stage 29G)
//   C) reject  → อัปเดต line_file_inbox = rejected (❌ ไม่ลบไฟล์ใน storage)
//
// ความปลอดภัย (Stage 29G + 33C):
//   * ทุก action ต้องส่ง { user_id, username } ของผู้ใช้ปัจจุบัน → ตรวจด้วย
//     app_verify_session เดิม (โมเดลตัวตนเดียวกับ guardSession ทั้งระบบ:
//     user_id+username ต้องตรงกับ app_users ที่ is_active=true, role ไม่ null)
//     → staff หรือ admin ที่ active ใช้ได้ ไม่ต้องใส่รหัสผ่าน
//   * ใช้ SUPABASE_SERVICE_ROLE_KEY ภายในฝั่ง server เท่านั้น — ❌ ไม่ส่งกลับ client
//   * identity ผู้ทำรายการ (code/name) ดึงจาก app_verify_session ที่ผ่านการตรวจ
//     ไม่เชื่อชื่อ/รหัสที่ client ส่งมาตรง ๆ
//   * source path (line-doc-inbox) + destination path (customer-documents) คำนวณ
//     ฝั่ง server ทั้งคู่ — ❌ ไม่รับ storage_path จาก client
//   * destination path เป็น ASCII ล้วน (timestamp + random + ext) — ❌ ไม่ใช้ชื่อไฟล์เดิม
//
// ⚠️ ข้อจำกัด: custom session ของ CRM พิสูจน์ตัวตนด้วย (user_id, username)+is_active
//    เท่านั้น ไม่มี secret token ฝั่ง client → ฟังก์ชันนี้เชื่อถือ "เท่ากับ" staff
//    workflow อื่นทั้งหมด ไม่มากกว่า (สอดคล้องตามที่ผู้ใช้รับทราบ)
//
// ❌ ไม่แตะ line-webhook-router / line-doc-inbox (worker รับไฟล์) / line-ai-excel-*
//    ❌ ไม่ลบไฟล์ต้นทางใน line-doc-inbox — เก็บไว้เป็นประวัติ
// ❗ Deploy: verify_jwt ปล่อย default ได้ (เรียกด้วย anon apikey — เป็น JWT ที่ valid)
//    ฟังก์ชันบังคับตรวจ session ในตัวเองเสมอ
// =============================================================

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const STORAGE_BUCKET = 'line-doc-inbox';        // ต้นทาง (ไฟล์จาก LINE)
const CUST_DOC_BUCKET = 'customer-documents';   // ปลายทาง (เอกสารลูกค้าจริง — Stage 33C)
const SIGN_EXPIRES_SEC = 1800;                 // 30 นาที — signed URL อายุสั้น
const MAX_ATTACH_BYTES = 10 * 1024 * 1024;     // 10MB — เพดานเดิมของระบบเอกสาร (PDF/อื่นๆ)
const IMG_MAX_BYTES = Math.round(1.5 * 1024 * 1024); // ~1.5MB — เพดานรูป (เท่า DOC_MAX_BYTES ฝั่ง CRM)
//   หมายเหตุ: การอัปโหลดรูปผ่านหน้าลูกค้าจะ "บีบอัด" ก่อน แต่ inbox approve เป็น
//   server-side ไม่บีบอัด → จึงจำกัดรูปดิบไว้ที่เพดานเดียวกับเอกสารรูปที่บีบแล้ว
//   เพื่อความสม่ำเสมอกับ pipeline ฝั่ง CRM (Stage 33C: เก็บใน Storage ไม่ใช่ base64)

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

// ─── Session auth: app_verify_session (active staff/admin — เหมือน guardSession) ──
//   พิสูจน์ตัวตนด้วย (user_id, username)+is_active เท่านั้น (custom session ของ CRM)
//   identity (code/name) ดึงจากผลลัพธ์ DB ไม่เชื่อค่าที่ client ส่งมา
async function verifyUser(
  url: string, key: string, userId: string, username: string,
): Promise<{ ok: boolean; code: string | null; name: string | null }> {
  if (!userId || !username) return { ok: false, code: null, name: null };
  const vr = await fetch(`${url}/rest/v1/rpc/app_verify_session`, {
    method: 'POST',
    headers: svcHeaders(key),
    body: JSON.stringify({ p_user_id: userId, p_username: username }),
  });
  if (!vr.ok) return { ok: false, code: null, name: null };
  let data: unknown;
  try { data = await vr.json(); } catch { data = null; }
  // app_verify_session คืน user object (jsonb) ถ้า active, มิฉะนั้น null
  const u = (data && typeof data === 'object' && !Array.isArray(data))
    ? data as { id?: unknown; username?: string; full_name?: string; role?: string }
    : null;
  if (!u || u.id == null) return { ok: false, code: null, name: null };
  return { ok: true, code: u.username || username, name: u.full_name || username };
}

// ─── Storage helpers ─────────────────────────────────────────────────────────
async function createSignedUrl(url: string, key: string, path: string): Promise<string> {
  const res = await fetch(
    `${url}/storage/v1/object/sign/${STORAGE_BUCKET}/${path}`,
    {
      method: 'POST',
      headers: svcHeaders(key),
      body: JSON.stringify({ expiresIn: SIGN_EXPIRES_SEC }),
    },
  );
  if (!res.ok) throw new Error(`sign ${res.status}: ${await res.text()}`);
  const data = await res.json();
  // signedURL = "/object/sign/<bucket>/<path>?token=..." → ต่อ prefix ให้เป็น URL เต็ม
  return `${url}/storage/v1${data.signedURL}`;
}

async function downloadObject(url: string, key: string, path: string): Promise<Uint8Array> {
  const res = await fetch(`${url}/storage/v1/object/${STORAGE_BUCKET}/${path}`, {
    headers: { 'apikey': key, 'Authorization': `Bearer ${key}` },
  });
  if (!res.ok) throw new Error(`download ${res.status}: ${await res.text()}`);
  return new Uint8Array(await res.arrayBuffer());
}

// ─── customer-documents helpers (Stage 33C) ─────────────────────────────────
// upload bytes ไปยัง private bucket customer-documents (ปลายทางเอกสารลูกค้า)
async function uploadCustomerDoc(
  url: string, key: string, path: string, bytes: Uint8Array, contentType: string,
): Promise<void> {
  const res = await fetch(`${url}/storage/v1/object/${CUST_DOC_BUCKET}/${path}`, {
    method: 'POST',
    headers: {
      'apikey':        key,
      'Authorization': `Bearer ${key}`,
      'Content-Type':  contentType,
      'x-upsert':      'false',
    },
    body: bytes,
  });
  if (!res.ok) throw new Error(`cust-doc upload ${res.status}: ${await res.text()}`);
}

// cleanup: ลบ object ที่อัปโหลดแล้ว (best-effort — เรียกเมื่อ DB insert ล้ม)
async function deleteCustomerDoc(url: string, key: string, path: string): Promise<void> {
  await fetch(`${url}/storage/v1/object/${CUST_DOC_BUCKET}`, {
    method: 'DELETE',
    headers: svcHeaders(key),
    body:    JSON.stringify({ prefixes: [path] }),
  }).catch(() => { /* best-effort */ });
}

// ดึงนามสกุลไฟล์ ASCII จาก source path (worker ตั้ง ext ปลอดภัยไว้แล้ว เช่น jpg/pdf/xlsx)
function extFromPath(path: string): string {
  const m = /\.([a-zA-Z0-9]{1,8})$/.exec(path || '');
  return m ? m[1].toLowerCase() : 'bin';
}

// สร้าง destination path ใน customer-documents (ASCII ล้วน — ❌ ไม่ใช้ชื่อไฟล์เดิม)
function buildCustomerDocPath(customerId: number, ext: string): string {
  const now  = new Date();
  const yyyy = now.getUTCFullYear();
  const mm   = String(now.getUTCMonth() + 1).padStart(2, '0');
  const ts   = Date.now();
  const rand = Math.random().toString(36).slice(2, 8); // 6 random alphanumeric chars
  const safeExt = /^[a-z0-9]{1,8}$/.test(ext) ? ext : 'bin';
  return `customers/${customerId}/${yyyy}/${mm}/${ts}_${rand}.${safeExt}`;
}

// ─── Inbox row helpers ───────────────────────────────────────────────────────
interface InboxRow {
  id: string;
  status: string;
  storage_path: string;
  mime_type: string | null;
  file_name: string | null;
  source_type: string | null;
}

async function getInboxRow(url: string, key: string, id: string): Promise<InboxRow | null> {
  const res = await fetch(
    `${url}/rest/v1/line_file_inbox?id=eq.${encodeURIComponent(id)}` +
    `&select=id,status,storage_path,mime_type,file_name,source_type&limit=1`,
    { headers: svcHeaders(key) },
  );
  if (!res.ok) throw new Error(`inbox select ${res.status}: ${await res.text()}`);
  const rows = await res.json();
  return Array.isArray(rows) && rows[0] ? rows[0] as InboxRow : null;
}

async function patchInbox(
  url: string, key: string, id: string, patch: Record<string, unknown>,
): Promise<void> {
  const res = await fetch(`${url}/rest/v1/line_file_inbox?id=eq.${encodeURIComponent(id)}`, {
    method: 'PATCH',
    headers: svcHeaders(key, { 'Prefer': 'return=minimal' }),
    body: JSON.stringify(patch),
  });
  if (!res.ok) throw new Error(`inbox patch ${res.status}: ${await res.text()}`);
}

// ─── Main ────────────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST') return json({ ok: false, error: 'method' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) {
    console.error('[doc-inbox-admin] missing required secrets');
    return json({ ok: false, error: 'not_configured' });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: 'bad_request' }, 400);
  }

  const action   = String(body.action || '');
  const userId   = String(body.user_id || '');
  const username = String(body.username || '');

  // ── auth (active staff/admin session) ──
  const actor = await verifyUser(url, key, userId, username);
  if (!actor.ok) {
    console.warn('[doc-inbox-admin] unauthorized');
    return json({ ok: false, error: 'unauthorized' }, 401);
  }

  try {
    // ── A) sign ──────────────────────────────────────────────────────────
    if (action === 'sign') {
      const inboxId = String(body.inbox_id || '');
      if (!inboxId) return json({ ok: false, error: 'bad_request' }, 400);
      const signRow = await getInboxRow(url, key, inboxId);
      if (!signRow) return json({ ok: false, error: 'not_found' }, 404);
      if (!signRow.storage_path) return json({ ok: false, error: 'no_file' });
      const signed = await createSignedUrl(url, key, signRow.storage_path);
      return json({ ok: true, url: signed, expires_in: SIGN_EXPIRES_SEC });
    }

    // ── B) approve ───────────────────────────────────────────────────────
    if (action === 'approve') {
      const inboxId    = String(body.inbox_id || '');
      const customerId = body.customer_id;
      const docType    = String(body.doc_type || 'other');
      const docName    = (body.doc_name != null && String(body.doc_name).trim())
        ? String(body.doc_name).trim() : null;
      const note       = (body.note != null && String(body.note).trim())
        ? String(body.note).trim() : null;
      const custName   = (body.customer_name != null) ? String(body.customer_name) : null;

      if (!inboxId)    return json({ ok: false, error: 'bad_request' }, 400);
      if (customerId == null || customerId === '') return json({ ok: false, error: 'no_customer' }, 400);
      const custId = Number(customerId);
      if (!Number.isInteger(custId) || custId <= 0) return json({ ok: false, error: 'no_customer' }, 400);

      const row = await getInboxRow(url, key, inboxId);
      if (!row)                       return json({ ok: false, error: 'not_found' }, 404);
      if (row.status !== 'pending')   return json({ ok: false, error: 'not_pending' });
      if (!row.storage_path)          return json({ ok: false, error: 'no_file' });

      // อ่าน bytes จาก line-doc-inbox (ต้นทาง) — server-side
      const bytes = await downloadObject(url, key, row.storage_path);
      const mime    = row.mime_type || 'application/octet-stream';
      const isImage = row.source_type === 'image' || mime.startsWith('image/');
      // รูป: จำกัด ~1.5MB (ไม่บีบอัดฝั่ง server) · PDF/อื่นๆ: 10MB เดิม
      // เกินเพดาน → ❌ ไม่อัปโหลด, ❌ ไม่ลบไฟล์ต้นทาง, คง inbox = pending
      if (isImage && bytes.length > IMG_MAX_BYTES) {
        return json({ ok: false, error: 'image_too_large', size: bytes.length });
      }
      if (!isImage && bytes.length > MAX_ATTACH_BYTES) {
        return json({ ok: false, error: 'too_large', size: bytes.length });
      }

      const finalName = docName || row.file_name || null;

      // ── Stage 33C: อัปโหลดเข้า customer-documents (ปลายทาง) แทนการเก็บ base64 ──
      // destination path ASCII ล้วน · ext ดึงจาก source path ที่ worker ตั้งไว้แล้ว
      const destPath = buildCustomerDocPath(custId, extFromPath(row.storage_path));
      await uploadCustomerDoc(url, key, destPath, bytes, mime);

      // insert เอกสารลูกค้าจริง (service role, file_data = null) → ขอ id กลับ
      // ถ้า insert ล้ม → cleanup object ที่เพิ่งอัปโหลด (กัน orphan ใน storage)
      let docId: unknown = null;
      try {
        const insRes = await fetch(`${url}/rest/v1/documents`, {
          method: 'POST',
          headers: svcHeaders(key, { 'Prefer': 'return=representation' }),
          body: JSON.stringify({
            customer_id:    custId,
            doc_type:       docType,
            doc_name:       finalName,
            file_type:      mime,
            mime_type:      mime,
            file_size:      bytes.length,
            storage_bucket: CUST_DOC_BUCKET,
            storage_path:   destPath,
            thumbnail_path: null,
            uploaded_by:    actor.name,
            file_data:      null,           // ❌ ไม่เก็บ base64 ใน DB อีกต่อไป
          }),
        });
        if (!insRes.ok) throw new Error(`documents insert ${insRes.status}: ${await insRes.text()}`);
        const insRows = await insRes.json();
        docId = Array.isArray(insRows) && insRows[0] ? insRows[0].id : null;
      } catch (e) {
        await deleteCustomerDoc(url, key, destPath); // best-effort cleanup
        throw e;
      }

      // อัปเดต inbox = linked (❌ ไม่ลบไฟล์ต้นทางใน line-doc-inbox)
      await patchInbox(url, key, inboxId, {
        status:             'linked',
        linked_customer_id: custId,
        linked_document_id: docId,
        doc_type:           docType,
        note:               note,
        approved_by_code:   actor.code,
        approved_by_name:   actor.name,
        approved_at:        new Date().toISOString(),
      });

      console.log(`[doc-inbox-admin] approve inbox=${inboxId} doc=${docId} cust=${custId} storage_path=${destPath}`);
      return json({
        ok: true, document_id: docId,
        file_name: finalName, source_type: row.source_type, customer_name: custName,
      });
    }

    // ── C) reject ────────────────────────────────────────────────────────
    if (action === 'reject') {
      const inboxId = String(body.inbox_id || '');
      const reason  = (body.reason != null && String(body.reason).trim())
        ? String(body.reason).trim() : null;
      if (!inboxId) return json({ ok: false, error: 'bad_request' }, 400);

      const row = await getInboxRow(url, key, inboxId);
      if (!row)                     return json({ ok: false, error: 'not_found' }, 404);
      if (row.status !== 'pending') return json({ ok: false, error: 'not_pending' });

      // ❌ ไม่ลบไฟล์ใน storage — เก็บประวัติไว้
      await patchInbox(url, key, inboxId, {
        status:           'rejected',
        rejected_by_code: actor.code,
        rejected_by_name: actor.name,
        rejected_at:      new Date().toISOString(),
        reject_reason:    reason,
      });

      console.log(`[doc-inbox-admin] reject inbox=${inboxId}`);
      return json({ ok: true, file_name: row.file_name });
    }

    return json({ ok: false, error: 'unknown_action' }, 400);
  } catch (e) {
    console.error('[doc-inbox-admin] error:', e instanceof Error ? e.message : e);
    return json({ ok: false, error: 'server_error' }, 500);
  }
});
