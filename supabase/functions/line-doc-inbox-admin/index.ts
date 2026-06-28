// =============================================================
// LINE Document Inbox — Admin helper (Supabase Edge Function, Stage 29C)
//
// บทบาท: ฝั่ง "แอดมิน CRM" เรียกใช้เพื่อ
//   A) sign    → สร้าง signed URL อายุสั้นจาก private bucket line-doc-inbox (พรีวิว/เปิดไฟล์)
//   B) approve → อ่าน bytes จาก storage (service role) → แปลง base64 →
//                insert เข้า public.documents (เอกสารลูกค้าจริง) →
//                อัปเดต line_file_inbox = linked
//   C) reject  → อัปเดต line_file_inbox = rejected (❌ ไม่ลบไฟล์ใน storage)
//
// ความปลอดภัย:
//   * ทุก action ต้องส่ง { username, password } ของผู้ใช้ → ตรวจด้วย
//     app_verify_login เดิม + ยืนยัน role=admin (เหมือน RPC แอดมินอื่น)
//   * ใช้ SUPABASE_SERVICE_ROLE_KEY ภายในฝั่ง server เท่านั้น — ❌ ไม่ส่งกลับ client
//   * identity ของผู้อนุมัติ (code/name) ดึงจาก app_users ตาม credential ที่ผ่านการตรวจ
//     ไม่เชื่อค่าที่ client ส่งมา
//
// ❌ ไม่แตะ line-webhook-router / line-doc-inbox (worker รับไฟล์) / line-ai-excel-*
// ❗ Deploy: verify_jwt ปล่อย default ได้ (เรียกด้วย anon apikey — เป็น JWT ที่ valid)
//    ฟังก์ชันบังคับตรวจ admin credential ในตัวเองเสมอ
// =============================================================

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const STORAGE_BUCKET = 'line-doc-inbox';
const SIGN_EXPIRES_SEC = 1800;                 // 30 นาที — signed URL อายุสั้น
const MAX_ATTACH_BYTES = 10 * 1024 * 1024;     // 10MB — เพดานเดิมของระบบเอกสาร (PDF/อื่นๆ)
const IMG_MAX_BYTES = Math.round(1.5 * 1024 * 1024); // ~1.5MB — เพดานรูป (เท่า DOC_MAX_BYTES ฝั่ง CRM)
//   หมายเหตุ: การอัปโหลดรูปผ่านหน้าลูกค้าจะ "บีบอัด" ก่อนเก็บ base64 แต่ inbox approve
//   เป็น server-side ไม่บีบอัด → จึงจำกัดรูปดิบไว้ที่เพดานเดียวกับเอกสารรูปที่บีบแล้ว
//   กัน documents.file_data (base64) บวมฐานข้อมูล

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

// chunked base64 — กัน stack overflow กับไฟล์ใหญ่
function bytesToBase64(bytes: Uint8Array): string {
  let bin = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

// ─── Admin auth: app_verify_login + role=admin ───────────────────────────────
async function verifyAdmin(
  url: string, key: string, username: string, password: string,
): Promise<{ ok: boolean; code: string | null; name: string | null }> {
  if (!username || !password) return { ok: false, code: null, name: null };
  // 1) ตรวจรหัสผ่านด้วย RPC login เดิม
  const vr = await fetch(`${url}/rest/v1/rpc/app_verify_login`, {
    method: 'POST',
    headers: svcHeaders(key),
    body: JSON.stringify({ p_username: username, p_password: password }),
  });
  if (!vr.ok) return { ok: false, code: null, name: null };
  let rows: unknown;
  try { rows = await vr.json(); } catch { rows = null; }
  if (!Array.isArray(rows) || rows.length < 1) return { ok: false, code: null, name: null };
  // 2) ยืนยัน role=admin + ดึง identity จาก app_users (ไม่เชื่อค่าจาก client)
  const ur = await fetch(
    `${url}/rest/v1/app_users?username=eq.${encodeURIComponent(username)}&select=username,full_name,role&limit=1`,
    { headers: svcHeaders(key) },
  );
  if (!ur.ok) return { ok: false, code: null, name: null };
  let urows: Array<{ username?: string; full_name?: string; role?: string }> = [];
  try { urows = await ur.json(); } catch { urows = []; }
  const u = urows[0];
  if (!u || String(u.role || '').toLowerCase() !== 'admin') {
    return { ok: false, code: null, name: null };
  }
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
  const username = String(body.username || '');
  const password = String(body.password || '');

  // ── auth (admin) ──
  const admin = await verifyAdmin(url, key, username, password);
  if (!admin.ok) {
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

      const row = await getInboxRow(url, key, inboxId);
      if (!row)                       return json({ ok: false, error: 'not_found' }, 404);
      if (row.status !== 'pending')   return json({ ok: false, error: 'not_pending' });
      if (!row.storage_path)          return json({ ok: false, error: 'no_file' });

      // อ่าน bytes server-side
      const bytes = await downloadObject(url, key, row.storage_path);
      const mime    = row.mime_type || 'application/octet-stream';
      const isImage = row.source_type === 'image' || mime.startsWith('image/');
      // รูป: จำกัด ~1.5MB (ไม่บีบอัดฝั่ง server) · PDF/อื่นๆ: 10MB เดิม
      // เกินเพดาน → ❌ ไม่แนบ, ❌ ไม่ลบไฟล์ใน storage, คง inbox = pending
      if (isImage && bytes.length > IMG_MAX_BYTES) {
        return json({ ok: false, error: 'image_too_large', size: bytes.length });
      }
      if (!isImage && bytes.length > MAX_ATTACH_BYTES) {
        return json({ ok: false, error: 'too_large', size: bytes.length });
      }

      const dataUrl = `data:${mime};base64,${bytesToBase64(bytes)}`;
      const finalName = docName || row.file_name || null;

      // insert เอกสารลูกค้าจริง (service role) → ขอ id กลับ
      const insRes = await fetch(`${url}/rest/v1/documents`, {
        method: 'POST',
        headers: svcHeaders(key, { 'Prefer': 'return=representation' }),
        body: JSON.stringify({
          customer_id: customerId,
          doc_type:    docType,
          doc_name:    finalName,
          file_data:   dataUrl,
          file_type:   mime,
          uploaded_by: admin.name,
        }),
      });
      if (!insRes.ok) throw new Error(`documents insert ${insRes.status}: ${await insRes.text()}`);
      const insRows = await insRes.json();
      const docId = Array.isArray(insRows) && insRows[0] ? insRows[0].id : null;

      // อัปเดต inbox = linked
      await patchInbox(url, key, inboxId, {
        status:             'linked',
        linked_customer_id: customerId,
        linked_document_id: docId,
        doc_type:           docType,
        note:               note,
        approved_by_code:   admin.code,
        approved_by_name:   admin.name,
        approved_at:        new Date().toISOString(),
      });

      console.log(`[doc-inbox-admin] approve inbox=${inboxId} doc=${docId} cust=${customerId}`);
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
        rejected_by_code: admin.code,
        rejected_by_name: admin.name,
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
