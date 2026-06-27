// =============================================================
// LINE Document Inbox — Supabase Edge Function (Stage 29B)
//
// บทบาท: "worker ภายใน" — ถูกเรียกจาก line-webhook-router เท่านั้น
//   (ไม่รับ LINE webhook ตรง ๆ — router ตรวจ x-line-signature ให้แล้ว)
//
// รับ POST (internal):
//   headers: Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>   ← internal auth
//   body:    { events: LineEvent[] }   ← เฉพาะ event ของกลุ่ม doc-inbox
//
// สำหรับแต่ละ event ที่เป็น image/file:
//   1) กันซ้ำด้วย line_message_id
//   2) ดาวน์โหลด bytes จาก LINE content API (ใช้ LINE_CHANNEL_ACCESS_TOKEN)
//   3) อัปโหลดเข้า private bucket line-doc-inbox  (เก็บ path เท่านั้น)
//   4) insert metadata → line_file_inbox (status='pending')
//   5) ❌ ไม่ตอบกลับกลุ่ม  ❌ ไม่เก็บ base64/bytes ในตาราง  ❌ ไม่เก็บ raw payload
//
// ตอบ 200 เสมอ (best-effort) — ไม่ทำให้ router/webhook fail
// =============================================================

const STORAGE_BUCKET = 'line-doc-inbox';

// ─── LINE webhook types (เฉพาะที่ใช้) ───────────────────────────────────────
interface LineSource { type?: string; groupId?: string; userId?: string }
interface LineMessage {
  id?: string;
  type?: string;          // 'image' | 'file' | 'text' | 'sticker' | ...
  fileName?: string;      // file message
  fileSize?: number;      // file message
}
interface LineEvent {
  type?: string;          // 'message' | ...
  timestamp?: number;
  webhookEventId?: string;
  source?: LineSource;
  message?: LineMessage;
}

// ─── Supabase REST helpers (service role) ────────────────────────────────────
function dbHeaders(key: string, extra: Record<string, string> = {}): Record<string, string> {
  return {
    'apikey':        key,
    'Authorization': `Bearer ${key}`,
    'Content-Type':  'application/json',
    ...extra,
  };
}

async function dbSelect(url: string, key: string, path: string): Promise<Record<string, unknown>[]> {
  const res = await fetch(`${url}/rest/v1/${path}`, { headers: dbHeaders(key) });
  if (!res.ok) throw new Error(`DB select ${res.status}: ${await res.text()}`);
  return await res.json();
}

async function dbInsert(
  url: string, key: string, table: string, row: Record<string, unknown>,
): Promise<void> {
  const res = await fetch(`${url}/rest/v1/${table}`, {
    method: 'POST',
    headers: dbHeaders(key, { 'Prefer': 'return=minimal' }),
    body: JSON.stringify(row),
  });
  if (!res.ok) throw new Error(`DB insert ${res.status}: ${await res.text()}`);
}

// ─── LINE content download ───────────────────────────────────────────────────
async function downloadLineContent(
  messageId: string, token: string,
): Promise<{ bytes: Uint8Array; contentType: string }> {
  const res = await fetch(`https://api-data.line.me/v2/bot/message/${messageId}/content`, {
    headers: { 'Authorization': `Bearer ${token}` },
  });
  if (!res.ok) throw new Error(`LINE content ${res.status}: ${await res.text()}`);
  const contentType = res.headers.get('content-type') || 'application/octet-stream';
  const buf = await res.arrayBuffer();
  return { bytes: new Uint8Array(buf), contentType };
}

// best-effort: ชื่อผู้ส่งในกลุ่ม — ไม่สำเร็จก็ปล่อย null (ไม่ทำให้ flow พัง)
async function fetchGroupDisplayName(
  groupId: string, userId: string, token: string,
): Promise<string | null> {
  try {
    const res = await fetch(
      `https://api.line.me/v2/bot/group/${encodeURIComponent(groupId)}/member/${encodeURIComponent(userId)}`,
      { headers: { 'Authorization': `Bearer ${token}` } },
    );
    if (!res.ok) return null;
    const data = await res.json();
    const name = typeof data.displayName === 'string' ? data.displayName.trim() : '';
    return name || null;
  } catch {
    return null;
  }
}

// ─── Storage upload ──────────────────────────────────────────────────────────
async function uploadToStorage(
  url: string, key: string, path: string, bytes: Uint8Array, contentType: string,
): Promise<void> {
  const res = await fetch(`${url}/storage/v1/object/${STORAGE_BUCKET}/${path}`, {
    method: 'POST',
    headers: {
      'apikey':        key,
      'Authorization': `Bearer ${key}`,
      'Content-Type':  contentType,
      'x-upsert':      'true',
    },
    body: bytes,
  });
  if (!res.ok) throw new Error(`Storage upload ${res.status}: ${await res.text()}`);
}

// ─── classify ────────────────────────────────────────────────────────────────
function extFromName(name: string): string {
  const m = /\.([a-z0-9]{1,8})$/i.exec(name || '');
  return m ? m[1].toLowerCase() : '';
}
function extFromContentType(ct: string): string {
  ct = (ct || '').toLowerCase();
  if (ct.includes('png'))  return 'png';
  if (ct.includes('webp')) return 'webp';
  if (ct.includes('gif'))  return 'gif';
  if (ct.includes('jpeg') || ct.includes('jpg')) return 'jpg';
  if (ct.includes('pdf'))  return 'pdf';
  if (ct.includes('spreadsheetml') || ct.includes('ms-excel')) return 'xlsx';
  if (ct.includes('csv'))  return 'csv';
  return 'bin';
}
function classifySourceType(msgType: string, fileName: string, contentType: string): string {
  if (msgType === 'image') return 'image';
  const e = extFromName(fileName);
  const ct = (contentType || '').toLowerCase();
  if (e === 'pdf' || ct.includes('pdf')) return 'pdf';
  if (['xlsx', 'xls', 'csv'].includes(e) || ct.includes('spreadsheetml') ||
      ct.includes('ms-excel') || ct.includes('csv')) return 'excel';
  if (['jpg', 'jpeg', 'png', 'webp', 'gif'].includes(e) || ct.startsWith('image/')) return 'image';
  return 'other';
}

function yyyymm(): string {
  const d = new Date();
  return `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
}

// ─── Process one event ───────────────────────────────────────────────────────
async function processEvent(
  ev: LineEvent,
  ctx: { url: string; key: string; lineToken: string },
): Promise<{ stored: boolean; skipped: string | null }> {
  const { url, key, lineToken } = ctx;
  if (ev.type !== 'message' || !ev.message) return { stored: false, skipped: 'not-message' };

  const msgType = ev.message.type || '';
  if (msgType !== 'image' && msgType !== 'file') return { stored: false, skipped: `ignore-${msgType}` };

  const groupId = ev.source?.groupId || null;
  const userId  = ev.source?.userId  || null;
  const msgId   = ev.message.id || '';
  if (!msgId) return { stored: false, skipped: 'no-msg-id' };

  // 1) dedup
  const dup = await dbSelect(
    url, key,
    `line_file_inbox?line_message_id=eq.${encodeURIComponent(msgId)}&select=id&limit=1`,
  );
  if (dup.length > 0) return { stored: false, skipped: 'duplicate' };

  // 2) download bytes from LINE
  const { bytes, contentType } = await downloadLineContent(msgId, lineToken);

  // 3) classify + path
  const fileNameRaw = ev.message.fileName || '';
  const sourceType  = classifySourceType(msgType, fileNameRaw, contentType);
  const ext  = extFromName(fileNameRaw) || extFromContentType(contentType);
  const path = `${groupId || 'unknown'}/${yyyymm()}/${msgId}.${ext}`;
  const fileName = fileNameRaw || `${msgId}.${ext}`;
  const fileSize = (typeof ev.message.fileSize === 'number' && ev.message.fileSize > 0)
    ? ev.message.fileSize : bytes.length;

  // 4) upload to private bucket (path only stored in DB)
  await uploadToStorage(url, key, path, bytes, contentType);

  // best-effort display name (non-fatal)
  const displayName = (groupId && userId)
    ? await fetchGroupDisplayName(groupId, userId, lineToken) : null;

  // 5) insert pending metadata (no bytes/base64; no raw payload)
  await dbInsert(url, key, 'line_file_inbox', {
    line_group_id:     groupId,
    line_user_id:      userId,
    line_display_name: displayName,
    line_message_id:   msgId,
    line_event_id:     ev.webhookEventId || null,
    file_name:         fileName,
    mime_type:         contentType,
    file_size:         fileSize,
    storage_path:      path,
    source_type:       sourceType,
    status:            'pending',
  });

  console.log(`[line-doc-inbox] stored group=${groupId ?? '-'} msg=${msgId} type=${sourceType} size=${fileSize}`);
  return { stored: true, skipped: null };
}

// ─── Main ────────────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const url     = Deno.env.get('SUPABASE_URL');
  const key     = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const lineToken = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN');

  if (!url || !key || !lineToken) {
    console.error('[line-doc-inbox] missing required secrets');
    return new Response(JSON.stringify({ ok: false, error: 'not configured' }), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    });
  }

  // internal auth — เรียกได้เฉพาะผู้ถือ service role key (router) เท่านั้น
  const auth = req.headers.get('Authorization') || '';
  const bearer = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (bearer !== key) {
    console.warn('[line-doc-inbox] unauthorized internal call');
    return new Response('Unauthorized', { status: 401 });
  }

  let payload: { events?: LineEvent[] };
  try {
    payload = await req.json();
  } catch {
    return new Response('Bad Request', { status: 400 });
  }

  const events = Array.isArray(payload.events) ? payload.events : [];
  const ctx = { url, key, lineToken };
  let stored = 0, skipped = 0;

  for (const ev of events) {
    try {
      const r = await processEvent(ev, ctx);
      if (r.stored) stored++; else skipped++;
    } catch (e) {
      skipped++;
      console.error('[line-doc-inbox] event error:', e instanceof Error ? e.message : e);
      // ไม่ throw — event อื่นต้องทำงานต่อ
    }
  }

  console.log(`[line-doc-inbox] done stored=${stored} skipped=${skipped} total=${events.length}`);
  return new Response(JSON.stringify({ ok: true, stored, skipped }), {
    status: 200, headers: { 'Content-Type': 'application/json' },
  });
});
