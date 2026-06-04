// =============================================================
// LINE AI Excel Helper — Supabase Edge Function (SIMPLE-B PDF-BATCH)
// เวอร์ชัน: 1.1.0  |  อัพเดต: 2026-06-01
//
// SIMPLE-A:
//   1. รับ LINE webhook + validate x-line-signature
//   2. ทำงานเฉพาะกลุ่ม LINE_AI_CONTROL_GROUP_ID (กลุ่ม AI แยก ฉัน+บอท)
//   3. รูป → ดาวน์โหลด → เก็บ Storage → เก็บ batch (collecting)
//   4. พิมพ์ "อ่าน" → ส่งรูปทั้ง batch เข้า Gemini → ตอบ TSV สำหรับ copy ลง Excel
//   5. คำสั่ง: อ่าน/read, รายการ, ล้าง, help
//
// SIMPLE-B (ใหม่):
//   6. พิมพ์ "pdf"/"ทำpdf" → รวมรูปทั้ง batch เป็น PDF เดียว (1 รูป = 1 หน้า A4)
//      → เก็บ Storage → ตอบ signed URL (อายุ 30 วัน)
//
// ยังไม่ทำ: สร้าง .xlsx / ส่ง PDF เป็นไฟล์แนบ LINE / ฟัง 3 กลุ่มงานจริง / Hybrid / เชื่อม CRM
//
// แยกจากระบบ CRM/attendance/line-attendance-notify โดยสิ้นเชิง
// =============================================================

// pdf-lib รันได้บน Deno / Supabase Edge ผ่าน esm.sh
import { PDFDocument, degrees, rgb } from 'https://esm.sh/pdf-lib@1.17.1';
// auto-rotate ด้วย Document AI OCR (shared กับ finalize-due) — ไม่ extract Excel
import { applyAutoRotateToBatch, effectiveRotationCW } from '../_shared/auto-rotate.ts';
// XLSX builder — รูปเรียงลง Excel ไม่มี OCR
import { buildXlsxFromImages } from '../_shared/excel.ts';
import type { XlsxImageInput } from '../_shared/excel.ts';

// ─── Secrets (inject อัตโนมัติ + ตั้งเอง) ────────────────────────────────────
// SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  → inject อัตโนมัติ
// LINE_CHANNEL_ACCESS_TOKEN                → token เดิม (download content + reply)
// LINE_CHANNEL_SECRET                      → ใช้ validate signature
// LINE_AI_CONTROL_GROUP_ID                 → groupId กลุ่ม AI แยก
// GEMINI_API_KEY                           → key Google Gemini (legacy, ไม่ใช้ใน "อ่าน" แล้ว)
//
// ─── Document AI OCR (DOCUMENT-AI-OCR-A) ─────────────────────────────────────
// OCR_PROVIDER                       → 'documentai' (default ใน flow ใหม่)
// DOCUMENT_AI_PROJECT_ID             → GCP project id
// DOCUMENT_AI_LOCATION               → เช่น 'us' / 'eu'
// DOCUMENT_AI_PROCESSOR_ID           → processor id (OCR / Document OCR)
// GOOGLE_SERVICE_ACCOUNT_JSON_BASE64 → base64 ของ service account JSON ทั้งไฟล์

const STORAGE_BUCKET = 'line-ai-excel-intake';
const BATCH_WINDOW_MS    = 30 * 60 * 1000; // 30 นาที — รวมรูปชุดเดียวกัน
const AUTO_FINALIZE_MS   = 45 * 1000;      // 45 วินาที — auto PDF หลังไม่มีรูปใหม่
// auto finalize จะไม่สร้าง PDF+Excel ถ้ารูปเกินจำนวนนี้ (กัน timeout/พัง) — "pdf" ยังสร้างได้
const MAX_IMAGES_PER_BATCH_FOR_AUTO = 15;
// Gemini (legacy) — ยังเก็บไว้เผื่อ fallback แต่ "อ่าน" ใหม่ใช้ Document AI
const GEMINI_MODEL_PRIMARY  = 'gemini-2.0-flash';
const GEMINI_MODEL_FALLBACK = 'gemini-1.5-flash';

// PDF / XLSX — เก็บใน bucket เดิม ใต้ path prefix แยก, signed URL อายุ 30 วัน
const PDF_PATH_PREFIX  = 'line-ai-excel-pdf';
const XLSX_PATH_PREFIX = 'line-ai-excel-xlsx';
const PDF_SIGNED_URL_SECONDS = 30 * 24 * 60 * 60; // 30 วัน
const TSV_PATH_PREFIX = 'line-ai-excel-tsv';
// A4 แนวตั้ง (points) + ขอบ
const A4_W = 595.28;
const A4_H = 841.89;
const PDF_MARGIN = 24;
// Source of truth: LINE event timestamp → event index → created_at → id
// page_no ถูก reindex หลัง sort นี้เสมอ ห้ามใช้ page_no เป็น primary sort
const FILE_PAGE_ORDER =
  'line_event_ts.asc.nullslast,' +
  'line_event_index.asc.nullslast,' +
  'created_at.asc,' +
  'id.asc';

// TSV header (8 คอลัมน์ สำหรับ copy วาง Excel เริ่มคอลัมน์ B)
// คอลัมน์ A ใน Excel ผู้ใช้ใส่เอง (ลำดับ/อื่นๆ) → ห้ามใส่คอลัมน์ลำดับใน TSV
const TSV_COLUMNS = [
  'วันที่ยื่น',
  'รูปถ่าย',
  'นายจ้าง',
  'รายชื่อ',
  'เลขประจำตัวต่างด้าว',
  'สัญชาติ',
  'เลขคำขอ',
  'ใบอนุญาตทำงานเลขที่',
];
const TSV_HEADER = TSV_COLUMNS.join('\t');

// ─── LINE Webhook Types (เฉพาะที่ใช้) ───────────────────────────────────────
interface LineSource {
  type: string;             // 'group' | 'user' | 'room'
  groupId?: string;
  userId?: string;
}
interface LineMessage {
  id: string;
  type: string;             // 'image' | 'text' | ...
  text?: string;
}
interface LineEvent {
  type: string;             // 'message' | ...
  timestamp?: number;       // LINE server timestamp (Unix ms) — ใช้เป็น sort key
  replyToken?: string;
  source?: LineSource;
  message?: LineMessage;
}

// ─── Signature Validation ────────────────────────────────────────────────────
// LINE ส่ง header x-line-signature = Base64(HMAC-SHA256(channelSecret, rawBody))
// ต้องคำนวณจาก raw body string ตรง ๆ (ห้าม re-serialize JSON)
async function validateSignature(
  rawBody: string,
  signature: string | null,
  channelSecret: string,
): Promise<boolean> {
  if (!signature) return false;
  try {
    const enc = new TextEncoder();
    const key = await crypto.subtle.importKey(
      'raw',
      enc.encode(channelSecret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign'],
    );
    const sigBuf = await crypto.subtle.sign('HMAC', key, enc.encode(rawBody));
    const computed = btoa(String.fromCharCode(...new Uint8Array(sigBuf)));
    if (computed.length !== signature.length) return false;
    let diff = 0;
    for (let i = 0; i < computed.length; i++) {
      diff |= computed.charCodeAt(i) ^ signature.charCodeAt(i);
    }
    return diff === 0;
  } catch (e) {
    console.error('[line-ai-excel] signature error:', e instanceof Error ? e.message : e);
    return false;
  }
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

async function dbSelect(
  url: string, key: string, path: string,
): Promise<Record<string, unknown>[]> {
  const res = await fetch(`${url}/rest/v1/${path}`, { headers: dbHeaders(key) });
  if (!res.ok) throw new Error(`DB select ${res.status}: ${await res.text()}`);
  return await res.json();
}

async function dbInsert(
  url: string, key: string, table: string, row: Record<string, unknown>,
): Promise<Record<string, unknown>[]> {
  const res = await fetch(`${url}/rest/v1/${table}`, {
    method: 'POST',
    headers: dbHeaders(key, { 'Prefer': 'return=representation' }),
    body: JSON.stringify(row),
  });
  if (!res.ok) throw new Error(`DB insert ${res.status}: ${await res.text()}`);
  return await res.json();
}

async function dbUpdate(
  url: string, key: string, table: string, filter: string, patch: Record<string, unknown>,
): Promise<void> {
  const res = await fetch(`${url}/rest/v1/${table}?${filter}`, {
    method: 'PATCH',
    headers: dbHeaders(key, { 'Prefer': 'return=minimal' }),
    body: JSON.stringify(patch),
  });
  if (!res.ok) throw new Error(`DB update ${res.status}: ${await res.text()}`);
}

// ─── LINE API helpers ────────────────────────────────────────────────────────
async function downloadLineContent(
  messageId: string, token: string,
): Promise<{ bytes: Uint8Array; contentType: string }> {
  const res = await fetch(`https://api-data.line.me/v2/bot/message/${messageId}/content`, {
    headers: { 'Authorization': `Bearer ${token}` },
  });
  if (!res.ok) throw new Error(`LINE content ${res.status}: ${await res.text()}`);
  const contentType = res.headers.get('content-type') || 'image/jpeg';
  const buf = await res.arrayBuffer();
  return { bytes: new Uint8Array(buf), contentType };
}

async function replyLineText(replyToken: string, text: string, token: string): Promise<void> {
  const res = await fetch('https://api.line.me/v2/bot/message/reply', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
    body: JSON.stringify({ replyToken, messages: [{ type: 'text', text }] }),
  });
  if (!res.ok) console.warn('[line-ai-excel] reply failed:', res.status, await res.text());
}

async function getLineSenderName(
  token: string, groupId: string, userId: string | null,
): Promise<string> {
  if (!userId) return '-';
  const endpoints = groupId
    ? [
        `https://api.line.me/v2/bot/group/${encodeURIComponent(groupId)}/member/${encodeURIComponent(userId)}`,
        `https://api.line.me/v2/bot/profile/${encodeURIComponent(userId)}`,
      ]
    : [`https://api.line.me/v2/bot/profile/${encodeURIComponent(userId)}`];

  for (const endpoint of endpoints) {
    try {
      const res = await fetch(endpoint, { headers: { 'Authorization': `Bearer ${token}` } });
      if (!res.ok) continue;
      const data = await res.json();
      const name = typeof data.displayName === 'string' ? data.displayName.trim() : '';
      if (name) return name;
    } catch (e) {
      console.warn('[line-ai-excel] LINE profile lookup failed:', e instanceof Error ? e.message : e);
    }
  }
  return '-';
}

// ─── Storage helpers ─────────────────────────────────────────────────────────
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

async function downloadFromStorage(
  url: string, key: string, path: string,
): Promise<{ bytes: Uint8Array; contentType: string }> {
  const res = await fetch(`${url}/storage/v1/object/${STORAGE_BUCKET}/${path}`, {
    headers: { 'apikey': key, 'Authorization': `Bearer ${key}` },
  });
  if (!res.ok) throw new Error(`Storage download ${res.status}: ${await res.text()}`);
  const contentType = res.headers.get('content-type') || 'image/jpeg';
  const buf = await res.arrayBuffer();
  return { bytes: new Uint8Array(buf), contentType };
}

/** สร้าง signed URL (private bucket) — คืน full URL */
async function createSignedUrl(
  url: string, key: string, path: string, expiresIn: number,
): Promise<string> {
  const res = await fetch(`${url}/storage/v1/object/sign/${STORAGE_BUCKET}/${path}`, {
    method: 'POST',
    headers: dbHeaders(key),
    body: JSON.stringify({ expiresIn }),
  });
  if (!res.ok) throw new Error(`Sign URL ${res.status}: ${await res.text()}`);
  const data = await res.json();
  // signedURL เป็น relative path เช่น "/object/sign/bucket/...?token=..."
  const signed = data.signedURL || data.signedUrl || '';
  return `${url}/storage/v1${signed}`;
}

// ─── Helpers ────────────────────────────────────────────────────────────────
function extFromContentType(ct: string): string {
  if (ct.includes('png'))  return 'png';
  if (ct.includes('webp')) return 'webp';
  if (ct.includes('gif'))  return 'gif';
  return 'jpg';
}

function bytesToBase64(bytes: Uint8Array): string {
  // แปลงเป็น base64 แบบ chunk กัน stack overflow ในรูปใหญ่
  let binary = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

/** base64 (มาตรฐาน) → Uint8Array */
function base64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

/** base64url encode (สำหรับ JWT) — ไม่มี padding */
function base64UrlEncode(bytes: Uint8Array): string {
  return bytesToBase64(bytes).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** หา batch ล่าสุดของกลุ่ม+user ที่ status='collecting' ภายในหน้าต่างเวลา */
async function findActiveBatch(
  url: string, key: string, groupId: string, userId: string | null,
): Promise<Record<string, unknown> | null> {
  const cutoff = new Date(Date.now() - BATCH_WINDOW_MS).toISOString();
  let path =
    `line_ai_excel_batches?group_id=eq.${encodeURIComponent(groupId)}` +
    `&status=eq.collecting&last_image_at=gte.${encodeURIComponent(cutoff)}` +
    `&order=last_image_at.desc&limit=1`;
  if (userId) path += `&user_id=eq.${encodeURIComponent(userId)}`;
  const rows = await dbSelect(url, key, path);
  return rows.length > 0 ? rows[0] : null;
}

/** list collecting batches ของ group+user ภายในหน้าต่างเวลา (เก่า→ใหม่) */
async function listCollectingBatches(
  url: string, key: string, groupId: string, userId: string | null,
): Promise<Record<string, unknown>[]> {
  const cutoff = new Date(Date.now() - BATCH_WINDOW_MS).toISOString();
  let path =
    `line_ai_excel_batches?group_id=eq.${encodeURIComponent(groupId)}` +
    `&status=eq.collecting&last_image_at=gte.${encodeURIComponent(cutoff)}` +
    `&order=created_at.asc,id.asc&select=id,image_count,created_at`;
  if (userId) path += `&user_id=eq.${encodeURIComponent(userId)}`;
  return await dbSelect(url, key, path);
}

/**
 * รวม batch ที่ซ้ำ (จาก album/race) เข้า canonical:
 *   - ย้าย file records ของ extra → canonical (storage_path เดิม ใช้ต่อได้)
 *   - cancel extra batch
 * idempotent: เรียกซ้ำได้ ไม่พัง
 */
async function mergeBatchesInto(
  url: string, key: string, canonicalId: string, extraIds: string[],
): Promise<void> {
  for (const exId of extraIds) {
    if (exId === canonicalId) continue;
    try {
      await dbUpdate(url, key, 'line_ai_excel_files', `batch_id=eq.${encodeURIComponent(exId)}`, {
        batch_id: canonicalId,
      });
      await dbUpdate(url, key, 'line_ai_excel_batches', `id=eq.${encodeURIComponent(exId)}`, {
        status: 'cancelled', updated_at: new Date().toISOString(),
      });
      console.log(`[line-ai-excel] merged batch ${exId} → ${canonicalId}`);
    } catch (e) {
      console.warn(`[line-ai-excel] merge ${exId}→${canonicalId} failed:`, e instanceof Error ? e.message : e);
    }
  }
}

/** อัปเดต image_count ของ batch จากจำนวน file จริง (กัน count เพี้ยนหลัง merge/race) */
async function recountBatchImages(url: string, key: string, batchId: string): Promise<number> {
  const files = await dbSelect(
    url, key,
    `line_ai_excel_files?batch_id=eq.${encodeURIComponent(batchId)}&select=id`,
  );
  return files.length;
}

/**
 * หา/สร้าง canonical collecting batch ของ group+user แบบกัน race:
 *   - มี collecting batch อยู่แล้ว → ใช้ตัวเก่าสุดเป็น canonical, merge ตัวซ้ำเข้ามา
 *   - ไม่มี → สร้างใหม่ แล้ว re-check กัน concurrent create (ถ้าแพ้ → ใช้ canonical ที่เก่ากว่า)
 * คืน { batchId, wasCreated } — wasCreated=true เฉพาะผู้สร้าง canonical จริง (ใช้คุม ack ไม่ให้ซ้ำ)
 */
async function resolveCollectingBatch(
  url: string, key: string, groupId: string, userId: string | null, nowIso: string,
): Promise<{ batchId: string; wasCreated: boolean }> {
  // 1) มี collecting batch อยู่แล้ว?
  const existing = await listCollectingBatches(url, key, groupId, userId);
  if (existing.length > 0) {
    const canonicalId = existing[0].id as string;
    if (existing.length > 1) {
      const extraIds = existing.slice(1).map(b => b.id as string);
      console.log(`[line-ai-excel] found ${existing.length} collecting batches → merge into ${canonicalId}`);
      await mergeBatchesInto(url, key, canonicalId, extraIds);
    }
    console.log(`[line-ai-excel] append existing batch ${canonicalId} group=${groupId} user=${userId ?? '-'}`);
    return { batchId: canonicalId, wasCreated: false };
  }

  // 2) ไม่มี → สร้างใหม่
  const created = await dbInsert(
    url, key, 'line_ai_excel_batches',
    { group_id: groupId, user_id: userId, status: 'collecting', image_count: 0, last_image_at: nowIso },
  );
  const newId = created[0].id as string;
  console.log(`[line-ai-excel] create new batch ${newId} group=${groupId} user=${userId ?? '-'} (no active batch)`);

  // 3) re-check กัน concurrent create (album ยิงพร้อมกันหลาย instance)
  const after = await listCollectingBatches(url, key, groupId, userId);
  if (after.length > 1) {
    const canonicalId = after[0].id as string;
    const extraIds = after.slice(1).map(b => b.id as string);
    if (canonicalId !== newId) {
      // batch เราไม่ใช่ canonical → merge ทุกตัวที่ไม่ใช่ canonical (รวมของเรา) เข้า canonical
      console.log(`[line-ai-excel] concurrent create detected → canonical=${canonicalId}, our=${newId} merged`);
      await mergeBatchesInto(url, key, canonicalId, extraIds);
      return { batchId: canonicalId, wasCreated: false };
    }
    // เราเป็น canonical → merge ตัวซ้ำที่เหลือเข้าเรา
    console.log(`[line-ai-excel] concurrent create detected → we are canonical=${newId}`);
    await mergeBatchesInto(url, key, newId, extraIds);
  }
  return { batchId: newId, wasCreated: true };
}

/**
 * ก่อน finalize: รวม collecting batch ซ้ำของ group+user เข้า canonical แล้ว cancel ตัวอื่น
 * → กัน auto finalize ส่ง card หลายใบจาก album ที่ถูกแยก batch
 */
async function mergeSiblingCollectingBatches(
  url: string, key: string, canonicalId: string, groupId: string, userId: string | null,
): Promise<void> {
  let path =
    `line_ai_excel_batches?group_id=eq.${encodeURIComponent(groupId)}` +
    `&status=eq.collecting&id=neq.${encodeURIComponent(canonicalId)}&select=id`;
  if (userId) path += `&user_id=eq.${encodeURIComponent(userId)}`;
  try {
    const siblings = await dbSelect(url, key, path);
    if (siblings.length > 0) {
      const ids = siblings.map(b => b.id as string);
      console.log(`[line-ai-excel] finalize merge ${ids.length} sibling batch(es) → ${canonicalId}`);
      await mergeBatchesInto(url, key, canonicalId, ids);
    }
  } catch (e) {
    console.warn('[line-ai-excel] mergeSiblingCollectingBatches failed:', e instanceof Error ? e.message : e);
  }
}

/** หา batch ล่าสุดของกลุ่ม+user ที่ collecting (ไม่จำกัดเวลา) — ใช้กับคำสั่ง ล้าง/จบ */
async function findLatestCollectingBatch(
  url: string, key: string, groupId: string, userId: string | null,
): Promise<Record<string, unknown> | null> {
  let path =
    `line_ai_excel_batches?group_id=eq.${encodeURIComponent(groupId)}` +
    `&status=eq.collecting&order=last_image_at.desc&limit=1`;
  if (userId) path += `&user_id=eq.${encodeURIComponent(userId)}`;
  const rows = await dbSelect(url, key, path);
  return rows.length > 0 ? rows[0] : null;
}

/**
 * หา batch ล่าสุดของกลุ่ม+user ไม่ว่าสถานะใด:
 *   collecting ก่อน → ถ้าไม่มีให้ดู finalized ล่าสุด
 * ใช้กับคำสั่ง รายการ/pdf/หมุน/สลับ/ย้าย/จัด/ปรับหมุน
 */
async function findLatestAnyBatch(
  url: string, key: string, groupId: string, userId: string | null,
): Promise<Record<string, unknown> | null> {
  const collecting = await findLatestCollectingBatch(url, key, groupId, userId);
  if (collecting) return collecting;
  // ไม่มี collecting → ลอง finalized ล่าสุด
  let path =
    `line_ai_excel_batches?group_id=eq.${encodeURIComponent(groupId)}` +
    `&status=eq.finalized&order=finalized_at.desc.nullslast&limit=1`;
  if (userId) path += `&user_id=eq.${encodeURIComponent(userId)}`;
  const rows = await dbSelect(url, key, path);
  return rows.length > 0 ? rows[0] : null;
}

/**
 * Atomic: เปลี่ยน status collecting → finalizing เฉพาะถ้ายัง collecting อยู่
 * Returns true ถ้าได้ lock (0 row = คนอื่นได้ก่อน → skip)
 */
async function tryLockBatch(url: string, key: string, batchId: string): Promise<boolean> {
  const res = await fetch(
    `${url}/rest/v1/line_ai_excel_batches?id=eq.${encodeURIComponent(batchId)}&status=eq.collecting`,
    {
      method: 'PATCH',
      headers: { ...dbHeaders(key, { 'Prefer': 'return=representation' }) },
      body: JSON.stringify({ status: 'finalizing', updated_at: new Date().toISOString() }),
    },
  );
  if (!res.ok) return false;
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0;
}

// ─── Gemini ───────────────────────────────────────────────────────────────────
function buildGeminiPrompt(): string {
  return [
    'คุณเป็นผู้ช่วยอ่านเอกสารแรงงานต่างด้าวจากรูปภาพหลายใบ',
    'ข้อมูลในรูปอาจมีภาษาไทย อังกฤษ และพม่า',
    '',
    'ให้ตอบเป็น TSV (คั่นด้วย Tab) เท่านั้น เพื่อ copy ไปวางใน Excel ได้',
    'ห้ามมีคำอธิบายใด ๆ ห้าม markdown table ห้าม bullet ห้าม code block',
    'บรรทัดแรกต้องเป็น header ตามนี้เป๊ะ:',
    TSV_HEADER,
    '',
    'กฎการอ่าน:',
    '- รายชื่อให้ใช้ภาษาอังกฤษเป็นหลัก เช่น MR / MRS / MISS',
    '- สัญชาติแปลงเป็นไทย เช่น เมียนมา / ลาว / กัมพูชา / เวียดนาม',
    '- คอลัมน์ "รูปถ่าย" = รอมี',
    '- ถ้าอ่านเลขไม่ชัด ให้ใส่ "-"',
    '- ถ้ามีเอกสารของหลายคนในชุด ให้แยกหลายแถว',
    '- ถ้าเป็นเอกสารของคนเดียวหลายใบ ให้รวมเป็นแถวเดียว',
    '- ห้ามสร้างข้อมูลเอง ห้ามเดาชื่อ/เลขที่มองไม่เห็น',
    '',
    'ตอบเฉพาะ TSV เท่านั้น',
  ].join('\n');
}

/**
 * ─ LOW-LEVEL ─ เรียก Gemini generateContent ครั้งเดียว
 * endpoint: /v1beta/models/{model}:generateContent?key=...
 * payload:  inlineData (camelCase) + mimeType (camelCase)  ← ผิดได้ถ้าใช้ snake_case
 * throw:    Error('GEMINI_API_ERROR:{status}: {msg}')  หรือ  Error('INVALID_GEMINI_RESPONSE:...')
 */
async function callGeminiWithModel(
  apiKey: string,
  images: { bytes: Uint8Array; contentType: string }[],
  model: string,
): Promise<{ text: string; raw: unknown }> {
  const parts: unknown[] = [{ text: buildGeminiPrompt() }];

  for (const img of images) {
    // Gemini REST API ใช้ camelCase เสมอ: inlineData + mimeType
    const mimeType = img.contentType.startsWith('image/') ? img.contentType : 'image/jpeg';
    parts.push({
      inlineData: { mimeType, data: bytesToBase64(img.bytes) },
    });
  }

  const endpoint =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent` +
    `?key=${apiKey}`;

  console.log(`[line-ai-excel] → Gemini model=${model} images=${images.length}`);

  const res = await fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ parts }],
      generationConfig: { temperature: 0, topP: 0.1 },
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    console.error(`[line-ai-excel] Gemini ${res.status} (model=${model}):`, errText.slice(0, 400));
    throw new Error(`GEMINI_API_ERROR:${res.status}: ${errText.slice(0, 200)}`);
  }

  const raw = await res.json();

  if (!raw?.candidates || raw.candidates.length === 0) {
    const block = raw?.promptFeedback?.blockReason;
    console.error(`[line-ai-excel] Gemini no candidates (model=${model}) blockReason=${block}`,
      JSON.stringify(raw).slice(0, 300));
    throw new Error(`INVALID_GEMINI_RESPONSE:no_candidates blockReason=${block || 'none'}`);
  }

  const text: string =
    raw.candidates[0]?.content?.parts
      ?.map((p: { text?: string }) => p.text || '')
      .join('') || '';

  if (!text.trim()) {
    console.warn(`[line-ai-excel] Gemini empty text (model=${model}):`, JSON.stringify(raw).slice(0, 200));
    throw new Error('INVALID_GEMINI_RESPONSE:empty_text');
  }

  return { text: text.trim(), raw };
}

/**
 * ─ HIGH-LEVEL ─ เรียก Gemini พร้อม auto-retry fallback เมื่อ 404
 * ลำดับ: model (primary/env) → GEMINI_MODEL_FALLBACK ถ้า 404
 * 404 = model ไม่มีหรือถูก deprecate → ลอง fallback อัตโนมัติ
 */
async function callGemini(
  apiKey: string,
  images: { bytes: Uint8Array; contentType: string }[],
  primaryModel: string,
): Promise<{ text: string; raw: unknown }> {
  try {
    return await callGeminiWithModel(apiKey, images, primaryModel);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    // 404 = model ไม่มีจริงในชื่อนั้น → ลอง fallback
    if (msg.includes('GEMINI_API_ERROR:404') && primaryModel !== GEMINI_MODEL_FALLBACK) {
      console.warn(
        `[line-ai-excel] model=${primaryModel} returned 404` +
        ` → retry with fallback model=${GEMINI_MODEL_FALLBACK}`,
      );
      return await callGeminiWithModel(apiKey, images, GEMINI_MODEL_FALLBACK);
    }
    throw e; // error อื่น (403, 429, 500, INVALID_RESPONSE) → โยนต่อ
  }
}

/** ตัด markdown / code fence ที่ Gemini อาจแถมมา ให้เหลือ TSV ล้วน */
function cleanTsv(text: string): string {
  let t = text.trim();
  // 1) ลบ ```tsv / ```plaintext / ``` ฯลฯ ที่ครอบ block ทั้งก้อน
  t = t.replace(/^```[a-zA-Z0-9]*\r?\n?/m, '').replace(/```\s*$/m, '').trim();
  // 2) ลบบรรทัดที่ขึ้นต้น ``` เดี่ยวที่อาจหลงเหลือ
  t = t.replace(/^`{1,3}\s*$/gm, '').trim();
  // 3) ลบ Markdown table separator ---|--- ที่ Gemini อาจแทรก
  t = t.replace(/^\|?[-| ]+\|?\s*$/gm, '').trim();
  // 4) ลบบรรทัดว่างที่ซ้ำ (เกิน 1 บรรทัด)
  t = t.replace(/\n{3,}/g, '\n\n').trim();
  return t;
}

// ─── Google Document AI (OCR) ───────────────────────────────────────────────────

interface DocAiConfig {
  projectId:   string;
  location:    string;
  processorId: string;
  saJson:      Record<string, unknown>; // service account JSON ที่ decode แล้ว
}

/** อ่าน + validate config Document AI จาก env — null ถ้าไม่ครบ */
function readDocAiConfig(): DocAiConfig | null {
  const projectId   = Deno.env.get('DOCUMENT_AI_PROJECT_ID');
  const location    = Deno.env.get('DOCUMENT_AI_LOCATION');
  const processorId = Deno.env.get('DOCUMENT_AI_PROCESSOR_ID');
  const saB64       = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON_BASE64');
  if (!projectId || !location || !processorId || !saB64) return null;
  try {
    const jsonStr = new TextDecoder().decode(base64ToBytes(saB64));
    const saJson = JSON.parse(jsonStr);
    if (!saJson.client_email || !saJson.private_key) return null;
    return { projectId, location, processorId, saJson };
  } catch (e) {
    console.error('[line-ai-excel] SA JSON decode failed:', e instanceof Error ? e.message : 'parse error');
    return null;
  }
}

/** แปลง PEM private key (PKCS#8) → CryptoKey สำหรับ RS256 */
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const der = base64ToBytes(body);
  return await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

/**
 * สร้าง OAuth access token จาก service account (JWT grant flow)
 * ห้าม log private_key / token
 */
async function getGoogleAccessToken(sa: Record<string, unknown>): Promise<string> {
  const clientEmail = sa.client_email as string;
  const privateKey  = sa.private_key as string;
  const tokenUri    = (sa.token_uri as string) || 'https://oauth2.googleapis.com/token';

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claim = {
    iss: clientEmail,
    scope: 'https://www.googleapis.com/auth/cloud-platform',
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  };

  const enc = new TextEncoder();
  const headerB64 = base64UrlEncode(enc.encode(JSON.stringify(header)));
  const claimB64  = base64UrlEncode(enc.encode(JSON.stringify(claim)));
  const signingInput = `${headerB64}.${claimB64}`;

  const cryptoKey = await importPrivateKey(privateKey);
  const sigBuf = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', cryptoKey, enc.encode(signingInput),
  );
  const jwt = `${signingInput}.${base64UrlEncode(new Uint8Array(sigBuf))}`;

  const res = await fetch(tokenUri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    console.error('[line-ai-excel] OAuth token failed:', res.status, errText.slice(0, 200));
    throw new Error('DOCUMENT_AI_AUTH_ERROR');
  }
  const data = await res.json();
  if (!data.access_token) throw new Error('DOCUMENT_AI_AUTH_ERROR');
  return data.access_token as string;
}

/**
 * ส่ง PDF (หรือรูป) เข้า Document AI :process → คืน OCR text ดิบ
 * throw: 'DOCUMENT_AI_AUTH_ERROR' | 'DOCUMENT_AI_API_ERROR:{status}' | 'EMPTY_OCR_TEXT'
 */
async function runDocumentAiOcr(
  cfg: DocAiConfig,
  content: Uint8Array,
  mimeType: string,
): Promise<string> {
  const accessToken = await getGoogleAccessToken(cfg.saJson);

  const endpoint =
    `https://${cfg.location}-documentai.googleapis.com/v1/projects/${cfg.projectId}` +
    `/locations/${cfg.location}/processors/${cfg.processorId}:process`;

  console.log(`[line-ai-excel] → Document AI process | mime=${mimeType} bytes=${content.length}`);

  const res = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      rawDocument: { content: bytesToBase64(content), mimeType },
    }),
  });

  console.log(`[line-ai-excel] Document AI HTTP ${res.status}`);

  if (!res.ok) {
    const errText = await res.text();
    console.error('[line-ai-excel] Document AI error:', res.status, errText.slice(0, 300));
    throw new Error(`DOCUMENT_AI_API_ERROR:${res.status}`);
  }

  const data = await res.json();
  const text: string = data?.document?.text || '';
  console.log(`[line-ai-excel] OCR text length=${text.length}`);
  if (!text.trim()) throw new Error('EMPTY_OCR_TEXT');
  return text;
}

// ─── OCR → TSV (rule/regex parser) ──────────────────────────────────────────────

/** map คำสัญชาติ (ไทย/อังกฤษ/รูปแบบต่าง ๆ) → ไทยมาตรฐาน */
function normalizeNationality(text: string): string {
  const t = text.toLowerCase();
  if (/myanmar|burma|burmese|เมียนมา|พม่า/.test(t)) return 'เมียนมา';
  if (/lao|laos|ลาว/.test(t))               return 'ลาว';
  if (/cambodia|cambodian|khmer|กัมพูชา|เขมร/.test(t)) return 'กัมพูชา';
  if (/vietnam|vietnamese|เวียดนาม/.test(t)) return 'เวียดนาม';
  return '-';
}

type ExcelRow = string[];

function cleanTsvCell(value: string | undefined | null): string {
  const v = (value || '').replace(/\t/g, ' ').replace(/\r?\n/g, ' ').replace(/\s{2,}/g, ' ').trim();
  return v || '-';
}

function normalizeOcrNumber(value: string | undefined | null): string {
  const digits = (value || '').replace(/\D/g, '');
  return digits || '-';
}

function getLines(text: string): string[] {
  return text.replace(/\r/g, '\n').split(/\n+/).map(line => line.trim()).filter(Boolean);
}

function stripKnownLabels(value: string): string {
  return value
    .replace(/^(?:ชื่อนายจ้าง\/สถานประกอบการ|ชื่อนายจ้าง|นายจ้าง|employer\s*name|company\s*name|name\s*of\s*employer)\s*:?\s*/i, '')
    .replace(/^\/?สถานประกอบการ\s*:?\s*/i, '')
    .replace(/^(?:สัญชาติ|nationality)\s*:?\s*/i, '')
    .replace(/^(?:ชื่อคนต่างด้าว|ชื่อผู้รับอนุญาตให้ทำงาน|name\s*of\s*(?:applicant|alien|work\s*permit\s*holder)|work\s*permit\s*name)\s*:?\s*/i, '')
    .replace(/^(?:เลขประจำตัวคนต่างด้าว(?:\/แรงงาน)?|เลขประจำตัวต่างด้าว|alien\s*(?:id|no|number)|identification\s*no\.?)\s*:?\s*/i, '')
    .replace(/^(?:เลขรับที่|เลขที่รับคำขอ|เลข(?:ที่)?คำขอ|request\s*no\.?|application\s*no\.?)\s*:?\s*/i, '')
    .replace(/^(?:ใบอนุญาตทำงานเลขที่|work\s*permit\s*(?:no\.?|number)|wp\s*no\.?)\s*:?\s*/i, '')
    .trim();
}

function cleanFieldValue(value: string | undefined | null): string {
  const cleaned = cleanTsvCell(stripKnownLabels(value || ''));
  if (
    cleaned === '-' ||
    /^[:/\\-]+$/.test(cleaned) ||
    /^(?:\/?สถานประกอบการ|employer\s*name\/company\s*name|company\s*name)$/i.test(cleaned)
  ) {
    return '-';
  }
  return cleaned;
}

function findValueNearLabel(text: string, labels: RegExp[], lookAheadLines = 2): string {
  const lines = getLines(text);
  for (let i = 0; i < lines.length; i++) {
    for (const label of labels) {
      label.lastIndex = 0;
      const m = label.exec(lines[i]);
      if (!m) continue;

      const sameLine = cleanFieldValue(lines[i].slice((m.index || 0) + m[0].length));
      if (sameLine !== '-') return sameLine;

      for (let j = 1; j <= lookAheadLines && i + j < lines.length; j++) {
        const next = cleanFieldValue(lines[i + j]);
        if (next !== '-') return next;
      }
    }
  }
  return '-';
}

function findCompanyName(text: string): string {
  const labeled = findValueNearLabel(text, [
    /ชื่อนายจ้าง\/สถานประกอบการ\s*:?\s*/i,
    /ชื่อนายจ้าง\s*:?\s*/i,
    /นายจ้าง\s*:?\s*/i,
    /employer\s*name\s*:?\s*/i,
    /company\s*name\s*:?\s*/i,
    /name\s*of\s*employer\s*:?\s*/i,
  ], 2);
  if (labeled !== '-') {
    const companyM = labeled.match(/((?:บริษัท|บจก\.?|หจก\.?|ห้างหุ้นส่วน).{1,90}?(?:จำกัด(?:\s*\(มหาชน\))?|มหาชน|ห้าง))/);
    return companyM ? cleanFieldValue(companyM[1]) : cleanFieldValue(
      labeled.replace(/\s+(เลขที่|address|ที่อยู่|โทร|tel|เบอร์|สัญชาติ|nationality).*$/i, ''),
    );
  }

  const forbidden = /ดำเนินการโดย|ที่อยู่|สถานที่ทำงาน|ผู้รับเงิน|ใบเสร็จ|หน่วยงาน|กรม|กระทรวง|receipt|payment|address/i;
  const lines = getLines(text);
  for (const line of lines) {
    if (forbidden.test(line)) continue;
    const companyM = line.match(/((?:บริษัท|บจก\.?|หจก\.?|ห้างหุ้นส่วน)[^\n]{1,80}?(?:จำกัด(?:\s*\(มหาชน\))?|มหาชน|ห้าง))/);
    if (companyM) return cleanFieldValue(companyM[1]);
  }
  return '-';
}

function findNationalityNear(text: string): string {
  const lines = getLines(text);
  const labelRe = /(?:สัญชาติ|nationality)\s*:?\s*/i;
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(labelRe);
    if (!m) continue;
    const sameLine = lines[i].slice((m.index || 0) + m[0].length);
    const sameLineNationality = normalizeNationality(sameLine);
    if (sameLineNationality !== '-') return sameLineNationality;

    const nearby = [lines[i + 1] || '', lines[i + 2] || ''].join(' ');
    const countryHits = nearby.match(/myanmar|burma|burmese|เมียนมา|พม่า|lao|laos|ลาว|cambodia|cambodian|กัมพูชา|vietnam|vietnamese|เวียดนาม/gi) || [];
    if (new Set(countryHits.map(hit => normalizeNationality(hit))).size > 1) continue;
    const normalized = normalizeNationality(nearby);
    if (normalized !== '-') return normalized;
  }
  return '-';
}

function findLabeledNumber(
  text: string,
  label: RegExp,
  minDigits: number,
  maxDigits: number,
  forbiddenNear?: RegExp,
): string {
  const matches = [...text.matchAll(label)];
  for (const m of matches) {
    const start = Math.max(0, (m.index || 0) - 20);
    const end = Math.min(text.length, (m.index || 0) + m[0].length + 120);
    const near = text.slice(start, end);
    const beforeLabel = text.slice(start, m.index || 0);
    if (forbiddenNear?.test(beforeLabel)) continue;
    const numM = near.match(/([0-9][0-9\s\-]{5,25}[0-9])/);
    const digits = normalizeOcrNumber(numM?.[1]);
    if (/payment\s*date|วันที่|เวลา|time/i.test(near) && digits.length <= 12) continue;
    if (digits !== '-' && digits.length >= minDigits && digits.length <= maxDigits) return digits;
  }
  return '-';
}

function findAlienId(text: string): string {
  const id = findLabeledNumber(
    text,
    /เลขประจำตัวคนต่างด้าว(?:\/แรงงาน)?|เลขประจำตัวต่างด้าว|alien\s*(?:id|no|number)|identification\s*no\.?/gi,
    13,
    13,
    /เลขประจำตัวนายจ้าง|employer\s*id|tax\s*id|เลขผู้เสียภาษี|เลขบริษัท|เลขนายจ้าง|bill\s*payment|receipt|เลขใบเสร็จ|เลขคำขอ|request\s*no|application\s*no|work\s*permit/i,
  );
  return id.length === 13 ? id : '-';
}

function findRequestNo(text: string): string {
  return findLabeledNumber(
    text,
    /เลขรับที่|เลขที่รับคำขอ|เลข(?:ที่)?คำขอ|เลขที่\s*(?=[0-9\s\-]{10,20})|application\s*no\.?|request\s*no\.?/gi,
    10,
    18,
    /receipt|bill\s*payment|payment\s*date|ใบเสร็จ|เลขใบเสร็จ|ผู้รับเงิน|เลขประจำตัวนายจ้าง|เลขประจำตัวคนต่างด้าว|work\s*permit|ใบอนุญาตทำงาน/i,
  );
}

function findWorkPermitNo(text: string): string {
  return findLabeledNumber(
    text,
    /ใบอนุญาตทำงานเลขที่|เลขที่ใบอนุญาตทำงาน|work\s*permit\s*(?:no\.?|number)|wp\s*no\.?/gi,
    10,
    18,
    /เลขคำขอ|application\s*no|request\s*no|receipt|bill\s*payment/i,
  );
}

function cleanPersonName(title: string, body: string): string {
  const cleanedBody = body
    .replace(/\s+(NATIONALITY|PASSPORT|WORK|PERMIT|APPLICATION|REQUEST|ALIEN|IDENTIFICATION|NO\.?|DATE|DOB|SEX|สัญชาติ|เลข).*$/i, '')
    .replace(/[^A-Z\s.'-]/g, ' ')
    .replace(/\s{2,}/g, ' ')
    .trim();
  if (!cleanedBody) return '-';
  return cleanTsvCell(`${title.toUpperCase().replace(/\.$/, '')} ${cleanedBody}`);
}

function findPersonMatches(ocrText: string): { name: string; index: number }[] {
  const flat = ocrText.replace(/\r/g, '\n');
  const matches: { name: string; index: number }[] = [];
  const labelRe =
    /(?:ชื่อคนต่างด้าว|ชื่อผู้รับอนุญาตให้ทำงาน|name\s*of\s*(?:applicant|alien|work\s*permit\s*holder)|work\s*permit\s*name)\s*:?\s*([^\n]{3,90})/gi;
  for (const m of flat.matchAll(labelRe)) {
    const named = m[1].match(/\b(MR|MRS|MISS|MS)\.?\s+([A-Z][A-Z\s.'-]{1,60})/i);
    if (!named) continue;
    const name = cleanPersonName(named[1], named[2]);
    if (name !== '-' && !matches.some(existing => existing.name === name)) {
      matches.push({ name, index: m.index || 0 });
    }
  }
  if (matches.length > 0) return matches.sort((a, b) => a.index - b.index);

  const re = /\b(MR|MRS|MISS|MS)\.?\s+([A-Z][A-Z\s.'-]{1,60})/gi;
  for (const m of flat.matchAll(re)) {
    const name = cleanPersonName(m[1], m[2]);
    if (name !== '-' && !matches.some(existing => existing.name === name)) {
      matches.push({ name, index: m.index || 0 });
    }
  }
  return matches;
}

function contextForPerson(ocrText: string, people: { name: string; index: number }[], idx: number): string {
  const prev = idx > 0 ? people[idx - 1].index : 0;
  const next = idx + 1 < people.length ? people[idx + 1].index : ocrText.length;
  const start = Math.max(0, Math.floor((prev + people[idx].index) / 2) - 400);
  const end = Math.min(ocrText.length, Math.floor((people[idx].index + next) / 2) + 800);
  return ocrText.slice(start, end);
}

function normalizePersonKey(name: string): string {
  return name.replace(/[^A-Z]/gi, '').toUpperCase();
}

function isSimilarPersonName(a: string, b: string): boolean {
  const ka = normalizePersonKey(a);
  const kb = normalizePersonKey(b);
  if (!ka || !kb) return false;
  return ka === kb || ka.startsWith(kb) || kb.startsWith(ka);
}

function pickLongerValue(a: string, b: string): string {
  if (a === '-') return b;
  if (b === '-') return a;
  return b.length > a.length ? b : a;
}

function mergeRows(rows: ExcelRow[]): ExcelRow[] {
  const merged: ExcelRow[] = [];
  for (const row of rows) {
    const existing = merged.find(candidate => isSimilarPersonName(candidate[3], row[3]));
    if (!existing) {
      merged.push([...row]);
      continue;
    }

    existing[0] = pickLongerValue(existing[0], row[0]);
    existing[1] = 'รอมี';
    existing[2] = pickLongerValue(existing[2], row[2]);
    existing[3] = pickLongerValue(existing[3], row[3]);
    existing[4] = existing[4] !== '-' ? existing[4] : row[4];
    existing[5] = existing[5] !== '-' ? existing[5] : row[5];
    existing[6] = existing[6] !== '-' ? existing[6] : row[6];
    existing[7] = existing[7] !== '-' ? existing[7] : row[7];
  }
  return merged;
}

function buildExcelRow(
  text: string, fullText: string, senderName: string, name: string,
): ExcelRow {
  const employerFromText = findCompanyName(text);
  const employer = employerFromText !== '-' ? employerFromText : findCompanyName(fullText);
  const nationalityFromText = findNationalityNear(text);
  const nationality = nationalityFromText !== '-' ? nationalityFromText : findNationalityNear(fullText);
  const alienIdFromText = findAlienId(text);
  const alienId = alienIdFromText !== '-' ? alienIdFromText : findAlienId(fullText);
  const reqNoFromText = findRequestNo(text);
  const reqNo = reqNoFromText !== '-' ? reqNoFromText : findRequestNo(fullText);
  const workPermitFromText = findWorkPermitNo(text);
  const workPermit = workPermitFromText !== '-' ? workPermitFromText : findWorkPermitNo(fullText);

  return [
    cleanTsvCell(senderName),
    'รอมี',
    cleanTsvCell(employer),
    cleanTsvCell(name),
    cleanTsvCell(alienId),
    cleanTsvCell(nationality),
    cleanTsvCell(reqNo),
    cleanTsvCell(workPermit),
  ];
}

function parseOcrToRows(ocrText: string, senderName: string): ExcelRow[] {
  const raw = ocrText.replace(/\r/g, '\n');
  const people = findPersonMatches(raw);

  // 1 batch = 1 person = 1 row
  // Group similar names, pick longest from first group
  let bestName = '-';
  if (people.length > 0) {
    const groups: string[][] = [];
    for (const p of people) {
      const existing = groups.find(g => g.some(n => isSimilarPersonName(n, p.name)));
      if (existing) {
        existing.push(p.name);
      } else {
        groups.push([p.name]);
      }
    }
    const firstGroup = groups[0];
    bestName = firstGroup.reduce((a, b) => b.length > a.length ? b : a);
  }

  // Use full OCR text for all field extraction (not split by person)
  const row = buildExcelRow(raw, raw, senderName, bestName);
  return [row];
}

function rowsToTsv(rows: ExcelRow[], includeHeader: boolean): string {
  const body = rows.map(row => row.map(cleanTsvCell).join('\t')).join('\n');
  return includeHeader ? `${TSV_HEADER}\n${body}` : body;
}

function splitTsvForLine(tsv: string): string[] {
  const LIMIT = 4800;
  if (tsv.length <= LIMIT) return [tsv];

  const rows = tsv.split('\n');
  const parts: string[] = [];
  let cur = '';
  for (const row of rows) {
    const candidate = cur ? `${cur}\n${row}` : row;
    if (candidate.length > LIMIT && cur) {
      parts.push(cur);
      cur = row;
    } else {
      cur = candidate;
    }
  }
  if (cur) parts.push(cur);
  return parts;
}

async function replyLineTextParts(replyToken: string, parts: string[], token: string): Promise<void> {
  const messages = parts.slice(0, 5).map(text => ({ type: 'text', text }));
  const res = await fetch('https://api.line.me/v2/bot/message/reply', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
    body: JSON.stringify({ replyToken, messages }),
  });
  if (!res.ok) console.warn('[line-ai-excel] reply parts failed:', res.status, await res.text());
}

async function pushLineTextParts(targetId: string, parts: string[], token: string): Promise<void> {
  for (let i = 0; i < parts.length; i += 5) {
    const messages = parts.slice(i, i + 5).map(text => ({ type: 'text', text }));
    const res = await fetch('https://api.line.me/v2/bot/message/push', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
      body: JSON.stringify({ to: targetId, messages }),
    });
    if (!res.ok) {
      console.warn('[line-ai-excel] push TSV parts failed:', res.status, await res.text());
      return;
    }
  }
}

async function replyTsv(replyToken: string, tsv: string, lineToken: string, targetId?: string): Promise<void> {
  const parts = splitTsvForLine(tsv);
  if (parts.length === 1) {
    await replyLineText(replyToken, parts[0], lineToken);
    return;
  }
  await replyLineTextParts(replyToken, parts, lineToken);
  if (parts.length > 5 && targetId) {
    await pushLineTextParts(targetId, parts.slice(5), lineToken);
  }
}

async function extractRowsFromLatestBatch(
  url: string,
  key: string,
  groupId: string,
  lineToken: string,
  userId: string | null,
  docAi: DocAiConfig,
): Promise<{ batchId: string; rows: ExcelRow[]; ocrText: string }> {
  const { batchId, images, rotationsCW } = await loadLatestBatchImages(url, key, groupId);
  if (!batchId) throw new Error('NO_BATCH');
  if (images.length === 0) throw new Error('IMAGE_LOAD_FAILED');

  const ocrText = await runDocAiOnBatch(docAi, images, rotationsCW);
  const senderName = await getLineSenderName(lineToken, groupId, userId);
  const rows = parseOcrToRows(ocrText, senderName);
  return { batchId, rows, ocrText };
}

async function saveReadResult(
  url: string,
  key: string,
  batchId: string,
  tsv: string,
  ocrText: string,
  rows: ExcelRow[],
  header: boolean,
): Promise<void> {
  const nowIso = new Date().toISOString();
  try {
    await dbInsert(url, key, 'line_ai_excel_results', {
      batch_id: batchId,
      result_text: tsv,
      raw_json: { type: 'ocr_tsv', ocr_chars: ocrText.length, rows: rows.length, header },
    });
    await dbUpdate(
      url, key, 'line_ai_excel_batches', `id=eq.${batchId}`,
      { status: 'read', read_at: nowIso, updated_at: nowIso },
    );
  } catch (e) {
    console.warn('[line-ai-excel] save result failed:', e instanceof Error ? e.message : e);
  }
}

/**
 * รวมรูป batch เป็น PDF (auto-rotate) แล้วส่งเข้า Document AI → คืน OCR text
 * ใช้ PDF logic เดิม (buildPdfFromImages) — reuse เพื่อให้ทิศตรงเหมือนคำสั่ง pdf
 * throw error code ที่ mapDocAiError จะแปลงเป็นข้อความ LINE
 */
async function runDocAiOnBatch(
  cfg: DocAiConfig,
  images: { bytes: Uint8Array; contentType: string }[],
  userRotationsCW: number[] = [],
): Promise<string> {
  const { pdf, pages } = await buildPdfFromImages(images, userRotationsCW);
  console.log(`[line-ai-excel] Document AI input PDF | pages=${pages} bytes=${pdf.length}`);
  if (pages === 0) throw new Error('IMAGE_LOAD_FAILED');
  return await runDocumentAiOcr(cfg, pdf, 'application/pdf');
}

/** แปลง error จาก Document AI flow → ข้อความ LINE (ไม่เปิด secret) */
function mapDocAiError(e: unknown): string {
  const msg = e instanceof Error ? e.message : String(e);
  console.error('[line-ai-excel] DocAI flow error:', msg);
  if (msg.includes('DOCUMENT_AI_AUTH_ERROR')) return 'OCR อ่านไม่สำเร็จ: DOCUMENT_AI_AUTH_ERROR';
  const apiM = msg.match(/DOCUMENT_AI_API_ERROR:(\d+)/);
  if (apiM) return `OCR อ่านไม่สำเร็จ: DOCUMENT_AI_API_ERROR_${apiM[1]}`;
  if (msg.includes('EMPTY_OCR_TEXT'))   return 'OCR อ่านไม่สำเร็จ: EMPTY_OCR_TEXT';
  if (msg.includes('IMAGE_LOAD_FAILED')) return 'OCR อ่านไม่สำเร็จ: IMAGE_LOAD_FAILED';
  return 'OCR อ่านไม่สำเร็จ: DOCUMENT_AI_API_ERROR';
}

// ─── PDF + Image orientation ──────────────────────────────────────────────────

/** ตรวจชนิดรูปจาก magic bytes (เชื่อถือกว่า content-type) */
function detectImageType(bytes: Uint8Array): 'png' | 'jpg' | 'unknown' {
  // PNG: 89 50 4E 47
  if (bytes.length >= 4 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
      bytes[2] === 0x4E && bytes[3] === 0x47) return 'png';
  // JPEG: FF D8 FF
  if (bytes.length >= 3 && bytes[0] === 0xFF && bytes[1] === 0xD8 &&
      bytes[2] === 0xFF) return 'jpg';
  return 'unknown';
}

/**
 * อ่าน EXIF Orientation tag จาก JPEG bytes (อ่านจาก raw bytes ตรง ๆ)
 * คืน: 1 (ปกติ), 3 (180°), 6 (CW 90°), 8 (CCW 90°)
 * ถ้า parse ไม่ได้คืน 1 (fallback = ไม่หมุน)
 */
function readJpegExifOrientation(bytes: Uint8Array): number {
  // JPEG SOI = FF D8
  if (bytes.length < 4 || bytes[0] !== 0xFF || bytes[1] !== 0xD8) return 1;

  let offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 0xFF) break;
    const marker = bytes[offset + 1];
    const segLen = (bytes[offset + 2] << 8) | bytes[offset + 3]; // includes 2-byte length field

    if (marker === 0xE1) { // APP1
      // "Exif\0\0" = 45 78 69 66 00 00
      const base = offset + 4;
      if (base + 6 <= bytes.length &&
          bytes[base]   === 0x45 && bytes[base+1] === 0x78 &&
          bytes[base+2] === 0x69 && bytes[base+3] === 0x66 &&
          bytes[base+4] === 0x00 && bytes[base+5] === 0x00) {

        const tiff = base + 6;
        const le = bytes[tiff] === 0x49; // II = little-endian, MM = big-endian

        const r16 = (p: number) => le
          ? (bytes[p] | (bytes[p+1] << 8))
          : ((bytes[p] << 8) | bytes[p+1]);
        const r32 = (p: number) => (le
          ? (bytes[p] | (bytes[p+1] << 8) | (bytes[p+2] << 16) | (bytes[p+3] << 24))
          : ((bytes[p] << 24) | (bytes[p+1] << 16) | (bytes[p+2] << 8) | bytes[p+3])
        ) >>> 0; // unsigned

        if (r16(tiff + 2) !== 42) return 1; // TIFF magic check
        const ifd0 = tiff + r32(tiff + 4);
        if (ifd0 + 2 > bytes.length) return 1;
        const numEntries = r16(ifd0);

        for (let i = 0; i < numEntries; i++) {
          const ep = ifd0 + 2 + i * 12;
          if (ep + 12 > bytes.length) break;
          if (r16(ep) === 0x0112) { // Orientation tag
            return r16(ep + 8); // value is inline for SHORT type
          }
        }
      }
    }

    if (marker === 0xDA) break; // SOS — start of scan, no more app headers after this
    offset += 2 + segLen;
  }
  return 1; // default: normal orientation
}

/**
 * แปลง EXIF Orientation → องศา CCW สำหรับ pdf-lib degrees()
 * (flip variants 2,4,5,7 ไม่พบใน LINE images จริง → treat as 0)
 */
function exifToDegreesCCW(orientation: number): number {
  switch (orientation) {
    case 3: return 180; // หมุน 180°
    case 6: return 270; // CW 90° = CCW 270°
    case 8: return 90;  // CCW 90°
    default: return 0;  // 1 = ปกติ
  }
}

/**
 * วาดรูปบนหน้า PDF พร้อม auto-rotate ตาม EXIF orientation
 * รูปจะอยู่กึ่งกลางหน้า A4, fit ในกรอบ, ไม่ crop, รักษาสัดส่วน
 *
 * สูตร centered rotation ใน pdf-lib (coordinate origin = bottom-left):
 *   x_draw = cx - (W/2)cos(θ) + (H/2)sin(θ)
 *   y_draw = cy - (W/2)sin(θ) - (H/2)cos(θ)
 * โดย W,H = scaled image dimensions (ยังไม่ rotate), cx,cy = center ของหน้า
 */
function drawImageOnPage(
  page: ReturnType<typeof PDFDocument.prototype.addPage>,
  embedded: { width: number; height: number },
  drawFn: (opts: {x:number;y:number;width:number;height:number;rotate:ReturnType<typeof degrees>}) => void,
  rotateDegCCW: number,
  imgIdx: number,
): void {
  const maxW = A4_W - PDF_MARGIN * 2;
  const maxH = A4_H - PDF_MARGIN * 2;

  // สำหรับ 90°/270°: ขนาดที่ปรากฎบนหน้ากระดาษจะสลับ W↔H
  const needsSwap = rotateDegCCW === 90 || rotateDegCCW === 270;
  const dispW = needsSwap ? embedded.height : embedded.width;
  const dispH = needsSwap ? embedded.width  : embedded.height;

  const scale = Math.min(maxW / dispW, maxH / dispH);
  // W, H คือขนาด "ดั้งเดิม" หลัง scale (ที่ส่งให้ pdf-lib)
  const W = embedded.width  * scale;
  const H = embedded.height * scale;

  const cx = A4_W / 2;
  const cy = A4_H / 2;
  const θ  = (rotateDegCCW * Math.PI) / 180;
  const cosT = Math.cos(θ);
  const sinT = Math.sin(θ);

  const x = cx - (W / 2) * cosT + (H / 2) * sinT;
  const y = cy - (W / 2) * sinT - (H / 2) * cosT;

  console.log(
    `[line-ai-excel] img[${imgIdx}] orig=${embedded.width}x${embedded.height}` +
    ` rot=${rotateDegCCW}° scaled=${Math.round(W)}x${Math.round(H)} pos=(${Math.round(x)},${Math.round(y)})`,
  );

  drawFn({ x, y, width: W, height: H, rotate: degrees(rotateDegCCW) });
}

/**
 * รวมรูปหลายใบเป็น PDF เดียว — 1 รูป = 1 หน้า A4 แนวตั้ง
 * userRotationsCW: การหมุน CW จาก DB (0/90/180/270) — override EXIF auto-detect
 * ลำดับ: auto EXIF (JPEG) + user CW → combined CCW สำหรับ pdf-lib
 * fit รูปในกรอบ (รักษาสัดส่วน, ไม่ crop), จัดกึ่งกลาง, พื้นหลังขาว
 */
async function buildPdfFromImages(
  images: { bytes: Uint8Array; contentType: string }[],
  userRotationsCW: number[] = [],
): Promise<{ pdf: Uint8Array; pages: number }> {
  const doc = await PDFDocument.create();
  let pages = 0;

  for (let idx = 0; idx < images.length; idx++) {
    const img = images[idx];
    // ─ ตรวจชนิด ─
    let kind = detectImageType(img.bytes);
    if (kind === 'unknown') {
      kind = img.contentType.includes('png') ? 'png'
           : img.contentType.includes('jpeg') || img.contentType.includes('jpg') ? 'jpg'
           : 'unknown';
    }

    // ─ embed ─
    let embedded;
    try {
      if (kind === 'png')      embedded = await doc.embedPng(img.bytes);
      else if (kind === 'jpg') embedded = await doc.embedJpg(img.bytes);
      else {
        try { embedded = await doc.embedJpg(img.bytes); }
        catch { embedded = await doc.embedPng(img.bytes); }
      }
    } catch (e) {
      console.warn(`[line-ai-excel] embed img[${idx}] failed, skip:`, e instanceof Error ? e.message : e);
      continue;
    }

    // ─ combine EXIF + user rotation ─
    // NOTE: LINE อาจ strip EXIF ออกจากรูปก่อนส่ง (พบได้บน iOS/Android บางรุ่น)
    // ถ้า EXIF ถูก strip → exifOrient=1 → exifCCW=0 → ไม่หมุน auto
    // ผู้ใช้ต้องใช้คำสั่ง "หมุน N ขวา/ซ้าย" เป็น manual fallback
    const exifOrient = kind === 'jpg' ? readJpegExifOrientation(img.bytes) : 1;
    const exifCCW    = exifToDegreesCCW(exifOrient);          // CCW จาก EXIF
    const userCW     = userRotationsCW[idx] ?? 0;             // CW จาก user command
    const userCCW    = (360 - userCW) % 360;                  // แปลง user CW → CCW
    const totalCCW   = (exifCCW + userCCW) % 360;             // รวม: EXIF + user
    console.log(`[line-ai-excel] img[${idx}] EXIF=${exifCCW}°CCW userCW=${userCW}° → totalCCW=${totalCCW}°`);

    // ─ วาดบนหน้า A4 ─
    const page = doc.addPage([A4_W, A4_H]);
    page.drawRectangle({ x: 0, y: 0, width: A4_W, height: A4_H, color: rgb(1, 1, 1) });
    drawImageOnPage(page, embedded, (opts) => page.drawImage(embedded, opts), totalCCW, idx);
    pages++;
  }

  const bytes = await doc.save();
  return { pdf: bytes, pages };
}

// ─── PDF helpers (PDF-only MVP) ───────────────────────────────────────────────

/** โหลดรูปทั้งหมดจาก batchId + สร้าง PDF + upload → คืน path + signedUrl
 * auto-rotate ด้วย Document AI (cache-aware) ก่อนวางลง PDF — manual rotation ชนะเสมอ
 */
async function buildAndUploadPdf(
  url: string, key: string, batchId: string,
): Promise<{ pages: number; pdfPath: string; signedUrl: string } | null> {
  // [PDF-only mode] auto-rotate ปิดชั่วคราว — ไม่เรียก Document AI OCR เพื่อประหยัดค่า Google AI
  // ถ้าต้องการเปิดใหม่: uncomment บล็อกด้านล่าง และ comment บรรทัด log
  // try {
  //   await applyAutoRotateToBatch(url, key, batchId, { force: false });
  // } catch (e) {
  //   console.warn('[line-ai-excel] auto-rotate skipped:', e instanceof Error ? e.message : e);
  // }
  console.log('[line-ai-excel] PDF-only mode: auto-rotate skipped (OCR disabled)');

  // 2) โหลด file records (รวม rotation columns) ตาม canonical order
  const files = await dbSelect(
    url, key,
    `line_ai_excel_files?batch_id=eq.${encodeURIComponent(batchId)}` +
    `&order=${FILE_PAGE_ORDER}` +
    `&select=id,storage_path,mime_type,page_no,rotation_deg,rotation_locked,auto_rotation_deg`,
  );
  if (files.length === 0) return null;
  await ensurePageNumbers(url, key, files);

  const images: { bytes: Uint8Array; contentType: string }[] = [];
  const rotationsCW: number[] = [];

  for (const f of files) {
    try {
      const got = await downloadFromStorage(url, key, f.storage_path as string);
      const mimeType = (f.mime_type as string) || got.contentType;
      images.push({ bytes: got.bytes, contentType: mimeType });
      // effective rotation: manual (locked) ชนะ ไม่งั้นใช้ auto
      rotationsCW.push(effectiveRotationCW(f));
    } catch (e) {
      console.warn('[line-ai-excel] buildAndUploadPdf storage fetch failed:', e instanceof Error ? e.message : e);
    }
  }

  if (images.length === 0) return null;

  const { pdf, pages } = await buildPdfFromImages(images, rotationsCW);
  if (pages === 0) return null;

  const pdfPath = `${PDF_PATH_PREFIX}/${batchId}.pdf`;
  await uploadToStorage(url, key, pdfPath, pdf, 'application/pdf');
  const signedUrl = await createSignedUrl(url, key, pdfPath, PDF_SIGNED_URL_SECONDS);
  return { pages, pdfPath, signedUrl };
}

/**
 * สร้าง Excel (.xlsx) จากรูปใน batch แล้วอัปโหลด Storage
 * ใช้ rotation เดียวกับ PDF (manual ชนะ) — ไม่มี OCR
 * error → return null (ไม่ throw ไม่ทำให้ PDF พัง)
 */
async function buildAndUploadExcel(
  url: string, key: string, batchId: string,
): Promise<{ xlsxPath: string; signedUrl: string } | null> {
  try {
    const files = await dbSelect(
      url, key,
      `line_ai_excel_files?batch_id=eq.${encodeURIComponent(batchId)}` +
      `&order=${FILE_PAGE_ORDER}` +
      `&select=id,storage_path,mime_type,page_no,rotation_deg,rotation_locked,auto_rotation_deg`,
    );
    if (files.length === 0) return null;
    await ensurePageNumbers(url, key, files);

    const xlsxImages: XlsxImageInput[] = [];
    for (const f of files) {
      try {
        const got = await downloadFromStorage(url, key, f.storage_path as string);
        xlsxImages.push({
          bytes:       got.bytes,
          contentType: (f.mime_type as string) || got.contentType,
          rotationCW:  effectiveRotationCW(f),
        });
      } catch (e) {
        console.warn('[line-ai-excel] buildAndUploadExcel img fetch failed:', e instanceof Error ? e.message : e);
      }
    }
    if (xlsxImages.length === 0) return null;

    const xlsxBytes = await buildXlsxFromImages(xlsxImages);
    const xlsxPath  = `${XLSX_PATH_PREFIX}/${batchId}.xlsx`;
    await uploadToStorage(url, key, xlsxPath, xlsxBytes,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    const signedUrl = await createSignedUrl(url, key, xlsxPath, PDF_SIGNED_URL_SECONDS);
    console.log(`[line-ai-excel] Excel built batch=${batchId} pages=${xlsxImages.length}`);
    return { xlsxPath, signedUrl };
  } catch (e) {
    console.error('[line-ai-excel] buildAndUploadExcel error:', e instanceof Error ? e.message : e);
    return null;
  }
}

/** สร้าง LINE Flex message การ์ดไฟล์ PDF แบบ compact พร้อมปุ่ม "เปิด PDF" */
function buildPdfFlexMessage(pages: number, signedUrl: string): unknown {
  return {
    type: 'flex',
    altText: `📄 เอกสาร PDF พร้อมแล้ว (${pages} รูป)`,
    contents: {
      type: 'bubble',
      size: 'kilo',
      body: {
        type: 'box',
        layout: 'vertical',
        backgroundColor: '#FFFFFF',
        paddingAll: '12px',
        paddingBottom: '8px',
        spacing: 'sm',
        contents: [
          // แถว icon + ข้อความ
          {
            type: 'box',
            layout: 'horizontal',
            spacing: 'sm',
            alignItems: 'center',
            contents: [
              // icon PDF จาก Storage
              {
                type: 'image',
                url: 'https://magwqolbjmwymqxelizl.supabase.co/storage/v1/object/public/line-assets/ChatGPT%20Image%20Jun%203,%202026,%2002_52_40%20PM.png',
                size: '44px',
                aspectRatio: '1:1',
                aspectMode: 'cover',
                flex: 0,
              },
              // ข้อความ
              {
                type: 'box',
                layout: 'vertical',
                flex: 1,
                spacing: 'none',
                contents: [
                  {
                    type: 'text',
                    text: 'เอกสาร PDF',
                    weight: 'bold',
                    size: 'sm',
                    color: '#333333',
                    wrap: false,
                  },
                  {
                    type: 'text',
                    text: `จำนวนรูป: ${pages} รูป`,
                    size: 'xs',
                    color: '#777777',
                  },
                ],
              },
            ],
          },
          // ปุ่ม เปิด PDF
          {
            type: 'button',
            style: 'primary',
            color: '#E53935',
            height: 'sm',
            action: { type: 'uri', label: 'เปิด PDF', uri: signedUrl },
          },
        ],
      },
    },
  };
}

/** reply Flex message พร้อมปุ่ม "เปิด PDF" — fallback เป็นข้อความถ้า Flex fail */
async function replyPdfFlex(
  replyToken: string, pages: number, signedUrl: string, lineToken: string,
): Promise<void> {
  const res = await fetch('https://api.line.me/v2/bot/message/reply', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${lineToken}` },
    body: JSON.stringify({ replyToken, messages: [buildPdfFlexMessage(pages, signedUrl)] }),
  });
  if (!res.ok) {
    console.warn('[line-ai-excel] flex reply failed, fallback text:', res.status);
    await replyLineText(
      replyToken,
      `สร้าง PDF แล้ว\nจำนวนรูป: ${pages} รูป\nเปิดไฟล์: ${signedUrl}`,
      lineToken,
    );
  }
}

/** push Flex message พร้อมปุ่ม "เปิด PDF" ไปที่ targetId (groupId) */
async function pushPdfFlex(
  targetId: string, pages: number, signedUrl: string, lineToken: string,
): Promise<void> {
  const res = await fetch('https://api.line.me/v2/bot/message/push', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${lineToken}` },
    body: JSON.stringify({ to: targetId, messages: [buildPdfFlexMessage(pages, signedUrl)] }),
  });
  if (!res.ok) {
    console.warn('[line-ai-excel] flex push failed, fallback text:', res.status);
    await fetch('https://api.line.me/v2/bot/message/push', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${lineToken}` },
      body: JSON.stringify({
        to: targetId,
        messages: [{
          type: 'text',
          text: `สร้าง PDF แล้ว\nจำนวนรูป: ${pages} รูป\nเปิดไฟล์: ${signedUrl}`,
        }],
      }),
    });
  }
}

/** สร้าง Flex card PDF+Excel (2 ปุ่ม) */
function buildPdfExcelFlexMessage(pages: number, pdfUrl: string, xlsxUrl: string): unknown {
  return {
    type: 'flex',
    altText: `📄 เอกสาร PDF + Excel พร้อมแล้ว (${pages} รูป)`,
    contents: {
      type: 'bubble',
      size: 'kilo',
      body: {
        type: 'box',
        layout: 'vertical',
        backgroundColor: '#FFFFFF',
        paddingAll: '12px',
        paddingBottom: '8px',
        spacing: 'sm',
        contents: [
          {
            type: 'box',
            layout: 'horizontal',
            spacing: 'sm',
            alignItems: 'center',
            contents: [
              // PDF icon (ซ้าย)
              {
                type: 'image',
                url: 'https://magwqolbjmwymqxelizl.supabase.co/storage/v1/object/public/line-assets/ChatGPT%20Image%20Jun%203,%202026,%2002_52_40%20PM.png',
                size: '44px', aspectRatio: '1:1', aspectMode: 'cover', flex: 0,
              },
              {
                type: 'box', layout: 'vertical', flex: 1, spacing: 'none',
                contents: [
                  { type: 'text', text: 'เอกสาร PDF + Excel', weight: 'bold', size: 'sm', color: '#333333', wrap: false },
                  { type: 'text', text: `จำนวนรูป: ${pages} รูป`, size: 'xs', color: '#777777' },
                ],
              },
              // Excel icon (ขวา) — รูป Excel
              {
                type: 'image',
                url: 'https://magwqolbjmwymqxelizl.supabase.co/storage/v1/object/public/line-assets/ChatGPT%20Image%20Jun%203,%202026,%2009_14_20%20PM.png',
                size: '44px', aspectRatio: '1:1', aspectMode: 'cover', flex: 0,
              },
            ],
          },
          {
            type: 'box', layout: 'horizontal', spacing: 'sm',
            contents: [
              {
                type: 'button', style: 'primary', color: '#E53935', height: 'sm', flex: 1,
                action: { type: 'uri', label: 'เปิด PDF', uri: pdfUrl },
              },
              {
                type: 'button', style: 'primary', color: '#1D6F42', height: 'sm', flex: 1,
                action: { type: 'uri', label: 'เปิด Excel', uri: xlsxUrl },
              },
            ],
          },
        ],
      },
    },
  };
}

/** reply PDF+Excel Flex card (สำหรับคำสั่ง "จบ") — fallback text ถ้า Flex fail */
async function replyPdfExcelFlex(
  replyToken: string, pages: number, pdfUrl: string, xlsxUrl: string, lineToken: string,
): Promise<void> {
  const res = await fetch('https://api.line.me/v2/bot/message/reply', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${lineToken}` },
    body: JSON.stringify({ replyToken, messages: [buildPdfExcelFlexMessage(pages, pdfUrl, xlsxUrl)] }),
  });
  if (!res.ok) {
    console.warn('[line-ai-excel] flex reply (pdf+xlsx) failed, fallback text:', res.status);
    await replyLineText(
      replyToken,
      `เอกสาร PDF + Excel พร้อมแล้ว\nจำนวนรูป: ${pages} รูป\nPDF: ${pdfUrl}\nExcel: ${xlsxUrl}`,
      lineToken,
    );
  }
}

/** push PDF+Excel Flex card */
async function pushPdfExcelFlex(
  targetId: string, pages: number, pdfUrl: string, xlsxUrl: string, lineToken: string,
): Promise<void> {
  const res = await fetch('https://api.line.me/v2/bot/message/push', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${lineToken}` },
    body: JSON.stringify({ to: targetId, messages: [buildPdfExcelFlexMessage(pages, pdfUrl, xlsxUrl)] }),
  });
  if (!res.ok) {
    console.warn('[line-ai-excel] flex push (pdf+xlsx) failed, fallback text:', res.status);
    await fetch('https://api.line.me/v2/bot/message/push', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${lineToken}` },
      body: JSON.stringify({
        to: targetId,
        messages: [{ type: 'text', text: `เอกสาร PDF + Excel พร้อมแล้ว\nจำนวนรูป: ${pages} รูป\nPDF: ${pdfUrl}\nExcel: ${xlsxUrl}` }],
      }),
    });
  }
}

/** ข้อความเตือนเมื่อรูปใน batch มากเกินไปสำหรับ auto finalize */
const OVERSIZE_WARN_TEXT =
  'รูปชุดนี้มีจำนวนมากเกินไปค่ะ\n' +
  `กรุณาแบ่งส่งใหม่เป็นชุดละไม่เกิน ${MAX_IMAGES_PER_BATCH_FOR_AUTO} รูป\n` +
  'หรือพิมพ์ "pdf" หากต้องการสร้าง PDF อย่างเดียว';

/** เคยเตือน oversize สำหรับ batch นี้แล้วหรือยัง (กัน spam ทุกรอบ cron) */
async function oversizeAlreadyWarned(url: string, key: string, batchId: string): Promise<boolean> {
  try {
    const rows = await dbSelect(
      url, key,
      `line_ai_excel_results?batch_id=eq.${encodeURIComponent(batchId)}` +
      `&result_text=eq.OVERSIZE_WARN&select=id&limit=1`,
    );
    return rows.length > 0;
  } catch {
    return false;
  }
}

/** push ข้อความเตือน oversize ไป group + บันทึก sentinel กันเตือนซ้ำ */
async function warnOversizeOnce(
  url: string, key: string, batchId: string, groupId: string, lineToken: string,
): Promise<void> {
  if (await oversizeAlreadyWarned(url, key, batchId)) {
    console.log(`[line-ai-excel] oversize already warned batch=${batchId}, skip`);
    return;
  }
  if (groupId) {
    await fetch('https://api.line.me/v2/bot/message/push', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${lineToken}` },
      body: JSON.stringify({ to: groupId, messages: [{ type: 'text', text: OVERSIZE_WARN_TEXT }] }),
    }).catch((e) => console.warn('[line-ai-excel] oversize warn push failed:', e instanceof Error ? e.message : e));
  }
  try {
    await dbInsert(url, key, 'line_ai_excel_results', {
      batch_id: batchId,
      result_text: 'OVERSIZE_WARN',
      raw_json: { type: 'oversize_warn', max: MAX_IMAGES_PER_BATCH_FOR_AUTO },
    });
  } catch (e) {
    console.warn('[line-ai-excel] oversize warn log failed:', e instanceof Error ? e.message : e);
  }
}

/**
 * ตรวจ batch ที่ last_image_at เกิน AUTO_FINALIZE_MS และยัง status='collecting'
 * → mark done + สร้าง PDF + Excel + push ไป group
 * ใช้ fire-and-forget (ไม่ block webhook)
 */
async function checkAndFinalizeStale(
  url: string, key: string, lineToken: string,
): Promise<void> {
  const cutoff = new Date(Date.now() - AUTO_FINALIZE_MS).toISOString();
  let staleBatches: Record<string, unknown>[] = [];
  try {
    staleBatches = await dbSelect(
      url, key,
      `line_ai_excel_batches?status=eq.collecting` +
      `&last_image_at=lt.${encodeURIComponent(cutoff)}` +
      `&image_count=gt.0` +
      `&order=last_image_at.asc&limit=10`,
    );
  } catch (e) {
    console.warn('[line-ai-excel] stale check query failed:', e instanceof Error ? e.message : e);
    return;
  }

  for (const batch of staleBatches) {
    const batchId = batch.id as string;
    const groupId = batch.group_id as string;
    const imgCount = (batch.image_count as number) || 0;
    console.log(`[line-ai-excel] auto-finalize | batch=${batchId} group=${groupId} count=${imgCount}`);

    // oversize: รูปเยอะเกิน → ไม่ lock ไม่สร้าง ไม่ finalize, เตือนครั้งเดียว (batch ยัง collecting → "pdf" ใช้ได้)
    if (imgCount > MAX_IMAGES_PER_BATCH_FOR_AUTO) {
      console.log(`[line-ai-excel] batch=${batchId} oversize (${imgCount}>${MAX_IMAGES_PER_BATCH_FOR_AUTO}) → skip auto, warn`);
      await warnOversizeOnce(url, key, batchId, groupId, lineToken);
      continue;
    }

    // Atomic lock: collecting → finalizing (กัน double-finalize)
    const locked = await tryLockBatch(url, key, batchId);
    if (!locked) {
      console.log(`[line-ai-excel] batch=${batchId} already locked, skip`);
      continue;
    }

    // safety net: รวม collecting batch ซ้ำของ group+user เข้า batch นี้ก่อนสร้างไฟล์
    // → กัน album ที่ถูกแยก batch ส่ง card หลายใบ
    const userId = (batch.user_id as string | null) ?? null;
    await mergeSiblingCollectingBatches(url, key, batchId, groupId, userId);

    try {
      // ── PDF (critical) ──
      const pdfResult = await buildAndUploadPdf(url, key, batchId);
      if (!pdfResult) {
        console.warn(`[line-ai-excel] auto-finalize: no images batch=${batchId}`);
        await dbUpdate(url, key, 'line_ai_excel_batches', `id=eq.${batchId}`, {
          status: 'cancelled', updated_at: new Date().toISOString(),
        });
        continue;
      }
      const { pages, pdfPath, signedUrl: pdfUrl } = pdfResult;
      const nowIso = new Date().toISOString();
      await dbUpdate(url, key, 'line_ai_excel_batches', `id=eq.${batchId}`, {
        status: 'finalized', finalized_at: nowIso,
        pdf_path: pdfPath, pdf_url: pdfUrl, updated_at: nowIso,
      });

      // ── Excel (non-critical) — PDF fail ไม่ได้เพราะ Excel fail ──
      const xlsxResult = await buildAndUploadExcel(url, key, batchId);
      if (xlsxResult) {
        console.log(`[line-ai-excel] auto-finalize Excel ok batch=${batchId}`);
      } else {
        console.warn(`[line-ai-excel] auto-finalize Excel skipped/failed batch=${batchId}`);
      }

      try {
        await dbInsert(url, key, 'line_ai_excel_results', {
          batch_id: batchId,
          result_text: `PDF+Excel auto: ${pdfPath} (${pages}p) xlsx=${xlsxResult ? 'ok' : 'fail'}`,
          raw_json: { type: 'pdf_excel_auto', path: pdfPath, pages, xlsx: xlsxResult?.xlsxPath ?? null },
        });
      } catch { /* non-critical */ }

      // ── ส่ง card เดียว: PDF+Excel ถ้า Excel สำเร็จ, PDF-only ถ้า Excel fail ──
      if (groupId) {
        if (xlsxResult) {
          await pushPdfExcelFlex(groupId, pages, pdfUrl, xlsxResult.signedUrl, lineToken);
        } else {
          await pushPdfFlex(groupId, pages, pdfUrl, lineToken);
        }
      }
    } catch (e) {
      console.error('[line-ai-excel] auto-finalize PDF failed:', e instanceof Error ? e.message : e);
      // revert ให้ตรวจรอบถัดไปได้
      await dbUpdate(url, key, 'line_ai_excel_batches', `id=eq.${batchId}`, {
        status: 'collecting', updated_at: new Date().toISOString(),
      }).catch(() => {});
    }
  }
}

// ─── Event Processing ─────────────────────────────────────────────────────────

/** รูปในกลุ่ม control → เก็บ batch + Storage
 * @param eventIndex index ของ event ใน webhook payload.events[] — ใช้เป็น tiebreaker ลำดับหน้า
 */
async function handleImage(
  ev: LineEvent,
  ctx: { url: string; key: string; lineToken: string },
  eventIndex = 0,
): Promise<void> {
  const { url, key, lineToken } = ctx;
  const groupId    = ev.source?.groupId || '';
  const userId     = ev.source?.userId  || null;
  const msgId      = ev.message?.id || '';
  const eventTs    = typeof ev.timestamp === 'number' ? ev.timestamp : null; // LINE server ms
  if (!groupId || !msgId) return;

  // กันซ้ำ: ถ้า message นี้บันทึกแล้ว ข้าม
  const dup = await dbSelect(
    url, key,
    `line_ai_excel_files?line_message_id=eq.${encodeURIComponent(msgId)}&select=id&limit=1`,
  );
  if (dup.length > 0) {
    console.log('[line-ai-excel] duplicate message skipped');
    return;
  }

  // 1) ดาวน์โหลดรูปจาก LINE
  const { bytes, contentType } = await downloadLineContent(msgId, lineToken);

  // 2) หา/สร้าง canonical batch แบบกัน race (album แยก batch / concurrent webhook)
  const nowIso = new Date().toISOString();
  const { batchId, wasCreated } = await resolveCollectingBatch(url, key, groupId, userId, nowIso);

  // 3) อัปโหลด Storage
  const ext  = extFromContentType(contentType);
  const path = `${groupId}/${batchId}/${msgId}.${ext}`;
  await uploadToStorage(url, key, path, bytes, contentType);

  // 4) บันทึก file record (page_no = approximate; ensurePageNumbers() จะ reindex ตาม line_event_ts)
  await dbInsert(
    url, key, 'line_ai_excel_files',
    {
      batch_id:          batchId,
      line_message_id:   msgId,
      line_event_ts:     eventTs,       // LINE event timestamp (ms) — primary sort key
      line_event_index:  eventIndex,    // index ใน events[] array — tiebreaker
      storage_path:      path,
      mime_type:         contentType,
      page_no:           0,             // ensurePageNumbers() จะ fix
      rotation_deg:      0,
    },
  );

  // 5) recount image_count จากไฟล์จริง (กันเพี้ยนหลัง merge/race) + อัปเดต last_image_at
  const newCount = await recountBatchImages(url, key, batchId);
  await dbUpdate(
    url, key, 'line_ai_excel_batches', `id=eq.${batchId}`,
    { image_count: newCount, last_image_at: nowIso, updated_at: nowIso },
  );

  console.log(`[line-ai-excel] stored image | group=${groupId} user=${userId ?? '-'} batch=${batchId} status=collecting count=${newCount} wasCreated=${wasCreated}`);

  // 6) reply ack เฉพาะผู้สร้าง canonical batch (รูปแรกจริง) — กัน ack ซ้ำจาก album เดียวกัน
  if (wasCreated && ev.replyToken) {
    await replyLineText(
      ev.replyToken,
      'รับรูปแล้ว ส่งเพิ่มได้เลยค่ะ\nระบบจะสร้าง PDF + Excel\nอัตโนมัติหลังไม่มีรูปใหม่\nประมาณ 30-90 วินาที\n\n(กรณีสร้างทันทีก่อน90วิ พิมพ์ "จบ"\nกรณีหมุนรูป พิมพ์ "หมุน เลขรูป\nขวา/ซ้าย")\nขอบคุณค่ะ 🙏🏻',
      lineToken,
    );
  } else if (!wasCreated) {
    console.log(`[line-ai-excel] suppress duplicate ack | batch=${batchId} (append, not first)`);
  }

  // 7) ตรวจ stale batches แบบ fire-and-forget (ไม่ block webhook)
  {
    const staleCheck = checkAndFinalizeStale(url, key, lineToken);
    try {
      // deno-lint-ignore no-explicit-any
      const rt = (globalThis as any).EdgeRuntime;
      if (rt?.waitUntil) {
        rt.waitUntil(staleCheck);
      } else {
        staleCheck.catch((e: unknown) =>
          console.warn('[line-ai-excel] stale check bg error:', e instanceof Error ? e.message : e));
      }
    } catch {
      staleCheck.catch(() => {});
    }
  }
}

/**
 * โหลดรูปทั้งหมดของ batch ล่าสุด (collecting) ตามลำดับ page_no, created_at, id
 * ถ้า batch ไม่มี → batch=null; ถ้าโหลดไม่ได้เลย → images=[]
 */
async function loadLatestBatchImages(
  url: string, key: string, groupId: string,
): Promise<{
  batchId: string | null;
  fileIds: string[];                                    // id ของแต่ละ file (ใช้ update rotation)
  images: { bytes: Uint8Array; contentType: string }[];
  rotationsCW: number[];                                // rotation_deg จาก DB (CW degrees)
}> {
  const batch = await findLatestCollectingBatch(url, key, groupId, null);
  if (!batch) return { batchId: null, fileIds: [], images: [], rotationsCW: [] };
  const batchId = batch.id as string;

  const files = await dbSelect(
    url, key,
    `line_ai_excel_files?batch_id=eq.${batchId}&order=${FILE_PAGE_ORDER}` +
    `&select=id,storage_path,mime_type,page_no,rotation_deg`,
  );
  await ensurePageNumbers(url, key, files);
  console.log(`[line-ai-excel] batch=${batchId} | file_records=${files.length}`);

  const images: { bytes: Uint8Array; contentType: string }[] = [];
  const fileIds: string[] = [];
  const rotationsCW: number[] = [];

  for (let fi = 0; fi < files.length; fi++) {
    const f = files[fi];
    const storagePath = f.storage_path as string;
    const storedMime  = (f.mime_type as string) || 'image/jpeg';
    const rotCW       = typeof f.rotation_deg === 'number' ? f.rotation_deg : 0;
    try {
      const got = await downloadFromStorage(url, key, storagePath);
      const mimeType = storedMime.startsWith('image/') ? storedMime : got.contentType;
      console.log(`[line-ai-excel] img[${fi}] path=${storagePath} bytes=${got.bytes.length} rot=${rotCW}°CW`);
      images.push({ bytes: got.bytes, contentType: mimeType });
      fileIds.push(f.id as string);
      rotationsCW.push(rotCW);
    } catch (e) {
      console.warn('[line-ai-excel] storage fetch failed | path=' + storagePath + ':',
        e instanceof Error ? e.message : e);
    }
  }
  return { batchId, fileIds, images, rotationsCW };
}

async function loadBatchFiles(
  url: string, key: string, batchId: string,
): Promise<Record<string, unknown>[]> {
  const files = await dbSelect(
    url, key,
    `line_ai_excel_files?batch_id=eq.${batchId}&order=${FILE_PAGE_ORDER}` +
    `&select=id,page_no,rotation_deg,rotation_locked,auto_rotation_deg,auto_rotation_confidence`,
  );
  await ensurePageNumbers(url, key, files);
  return files;
}

async function ensurePageNumbers(
  url: string, key: string, files: Record<string, unknown>[],
): Promise<void> {
  for (let i = 0; i < files.length; i++) {
    const expected = i + 1;
    if (files[i].page_no !== expected) {
      files[i].page_no = expected;
      await dbUpdate(
        url, key, 'line_ai_excel_files', `id=eq.${files[i].id}`,
        { page_no: expected },
      );
    }
  }
}

/** คำสั่ง text ในกลุ่ม control */
async function handleText(
  ev: LineEvent,
  ctx: {
    url: string; key: string; lineToken: string;
    geminiKey: string | undefined;
    docAi: DocAiConfig | null;
  },
): Promise<void> {
  const { url, key, lineToken } = ctx;
  const groupId    = ev.source?.groupId || '';
  const userId     = ev.source?.userId  || null;
  const replyToken = ev.replyToken;
  if (!replyToken || !groupId) return;

  const text = (ev.message?.text || '').trim();
  const cmd  = text.toLowerCase();

  // trigger stale check บน text event ทุกครั้ง (fire-and-forget)
  {
    const sc = checkAndFinalizeStale(url, key, lineToken);
    try {
      // deno-lint-ignore no-explicit-any
      const rt = (globalThis as any).EdgeRuntime;
      if (rt?.waitUntil) rt.waitUntil(sc); else sc.catch(() => {});
    } catch { sc.catch(() => {}); }
  }

  // ─── help ───
  if (cmd === 'help' || text === 'ช่วยเหลือ') {
    await replyLineText(
      replyToken,
      [
        'วิธีใช้:',
        'ส่งรูปเอกสารหลายใบ แล้วเลือก:',
        '"จบ" หรือ "pdf" = สร้าง PDF จากรูปทั้งหมดในชุด',
        '"รายการ"  = ดูจำนวนรูปและการหมุนแต่ละหน้า',
        '"ล้าง"    = เริ่มชุดใหม่',
        '',
        'ระบบจะสร้าง PDF อัตโนมัติหลังไม่มีรูปใหม่ประมาณ 1-2 นาที',
        'ระบบจะพยายามปรับหมุนหน้าด้วย OCR/AI ให้อัตโนมัติก่อนสร้าง PDF',
        '',
        '"ปรับหมุน"       = ตรวจหมุนอัตโนมัติด้วย OCR/AI ทันที',
        '"ตรวจหมุนใหม่"  = ล้าง cache แล้วตรวจ OCR ใหม่',
        '"ไม่หมุนออโต้"  = ปิดหมุนอัตโนมัติ ใช้ค่าปัจจุบัน',
        '',
        'ปรับการหมุนรูปแต่ละหน้า (manual ชนะ auto เสมอ):',
        '"หมุน 1 ขวา"     = หมุนหน้า 1 CW 90°',
        '"หมุน 1 ซ้าย"    = หมุนหน้า 1 CCW 90°',
        '"หมุน 1 กลับหัว" = หมุนหน้า 1 180°',
        '"หมุน 1 ตรง"     = reset หน้า 1 เป็น 0°',
        '"สลับ 2 3"       = สลับลำดับหน้า 2 กับ 3',
        '"ย้าย 4 ไป 1"    = ย้ายหน้า 4 ไปเป็นหน้า 1',
        '"จัด 1 3 2 4"    = ตั้งลำดับหน้า PDF ใหม่',
        'แล้ว "pdf" ใหม่เพื่อสร้าง PDF ที่หมุนแล้ว',
      ].join('\n'),
      lineToken,
    );
    return;
  }

  // ─── รายการ ───
  if (text === 'รายการ' || cmd === 'list') {
    const batch = await findLatestAnyBatch(url, key, groupId, userId);
    if (!batch) {
      await replyLineText(replyToken, 'ยังไม่มีรูปในชุดล่าสุด กรุณาส่งรูปเอกสารก่อน', lineToken);
      return;
    }
    const batchId = batch.id as string;
    const batchStatus = batch.status as string;
    const files = await loadBatchFiles(url, key, batchId);
    const count = files.length;
    if (count === 0) {
      await replyLineText(replyToken, 'ยังไม่มีรูปในชุดล่าสุด กรุณาส่งรูปเอกสารก่อน', lineToken);
      return;
    }
    const statusLabel = batchStatus === 'finalized' ? 'finalized (สร้าง PDF แล้ว)' : 'collecting (กำลังรวบรวม)';
    const pageLines = files.map((f, i) => {
      const locked = f.rotation_locked === true;
      const manualDeg = typeof f.rotation_deg === 'number' ? f.rotation_deg : 0;
      const autoDeg = typeof f.auto_rotation_deg === 'number' ? f.auto_rotation_deg : null;
      const autoConf = typeof f.auto_rotation_confidence === 'number' ? f.auto_rotation_confidence : 0;
      let label: string;
      if (locked) {
        label = `manual ${manualDeg}°`;
      } else if (autoDeg != null) {
        const confStr = autoConf > 0 ? ` conf ${autoConf.toFixed(2)}` : '';
        label = `auto ${autoDeg}°${confStr}`;
      } else {
        label = `0° (ยังไม่ตรวจ)`;
      }
      return `หน้า ${i + 1}: ${label}`;
    });
    const footerLines = batchStatus === 'finalized'
      ? [
          '',
          'สร้าง PDF แล้ว ยังสามารถพิมพ์ "pdf" เพื่อสร้างใหม่ได้หลังหมุน/จัดหน้า',
        ]
      : [
          '',
          'ระบบจะพยายามปรับหมุนด้วย OCR/AI ก่อนสร้าง PDF',
          'ระบบจะสร้าง PDF อัตโนมัติหลังไม่มีรูปใหม่ประมาณ 1-2 นาที',
          'หรือพิมพ์ "จบ" / "pdf" เพื่อสร้างทันที',
        ];
    await replyLineText(
      replyToken,
      [
        `ชุดล่าสุดของคุณ: ${count} รูป`,
        `สถานะ: ${statusLabel}`,
        ...pageLines,
        ...footerLines,
        'ถ้าหน้าไหนยังผิด ใช้ "หมุน N ขวา/ซ้าย/กลับหัว/ตรง"',
        'ถ้าลำดับไม่ตรง ใช้ "สลับ 2 3" หรือ "จัด 1 3 2 4"',
      ].join('\n'),
      lineToken,
    );
    return;
  }

  // ─── ล้าง ───
  if (text === 'ล้าง' || cmd === 'clear' || cmd === 'reset') {
    const batch = await findLatestCollectingBatch(url, key, groupId, userId);
    if (!batch) {
      await replyLineText(replyToken, 'ไม่มีชุดที่ต้องล้าง', lineToken);
      return;
    }
    await dbUpdate(
      url, key, 'line_ai_excel_batches', `id=eq.${batch.id}`,
      { status: 'cancelled', updated_at: new Date().toISOString() },
    );
    await replyLineText(replyToken, 'ล้างชุดล่าสุดแล้ว ส่งรูปใหม่ได้เลย', lineToken);
    return;
  }

  // ─── ชุดใหม่ / new — เริ่มชุดใหม่โดยไม่รวมรูปเก่า ──────────────────────
  if (text === 'ชุดใหม่' || cmd === 'new') {
    const batch = await findLatestCollectingBatch(url, key, groupId, userId);
    if (batch && (batch.image_count as number || 0) > 0) {
      await replyLineText(
        replyToken,
        `ยังมีชุดค้างอยู่ ${batch.image_count} รูป\nกรุณาพิมพ์ "จบ" เพื่อสร้าง PDF และเริ่มชุดใหม่\nหรือพิมพ์ "ล้าง" เพื่อยกเลิกชุดเดิมโดยไม่ได้ PDF`,
        lineToken,
      );
      return;
    }
    // ไม่มีชุดค้าง หรือชุดว่าง → พร้อมรับรูปชุดใหม่
    if (batch) {
      await dbUpdate(url, key, 'line_ai_excel_batches', `id=eq.${batch.id}`, {
        status: 'cancelled', updated_at: new Date().toISOString(),
      });
    }
    await replyLineText(replyToken, 'พร้อมรับรูปชุดใหม่แล้ว ส่งรูปได้เลย', lineToken);
    return;
  }

  // ─── จบ / done / finish — ปิด batch + สร้าง PDF + Excel ทันที (card เดียว) ──
  if (text === 'จบ' || cmd === 'done' || cmd === 'finish') {
    const batch = await findLatestCollectingBatch(url, key, groupId, userId);
    if (!batch) {
      await replyLineText(replyToken, 'ยังไม่มีรูปในชุด กรุณาส่งรูปเอกสารก่อน', lineToken);
      return;
    }
    const batchId = batch.id as string;
    // oversize: รูปเยอะเกิน → ไม่สร้าง PDF+Excel รวม, แจ้งให้แบ่งชุด (ยัง collecting → "pdf" ใช้ได้)
    const jobCount = (batch.image_count as number) || 0;
    if (jobCount > MAX_IMAGES_PER_BATCH_FOR_AUTO) {
      console.log(`[line-ai-excel] จบ oversize batch=${batchId} count=${jobCount} → reject combined`);
      await replyLineText(replyToken, OVERSIZE_WARN_TEXT, lineToken);
      return;
    }
    // Lock atomic: collecting → finalizing
    const locked = await tryLockBatch(url, key, batchId);
    if (!locked) {
      await replyLineText(replyToken, 'ระบบกำลังสร้างไฟล์อยู่ กรุณารอสักครู่', lineToken);
      return;
    }
    try {
      // ── PDF (critical) ──
      const result = await buildAndUploadPdf(url, key, batchId);
      if (!result) {
        await dbUpdate(url, key, 'line_ai_excel_batches', `id=eq.${batchId}`, {
          status: 'collecting', updated_at: new Date().toISOString(),
        });
        await replyLineText(replyToken, 'สร้าง PDF ไม่สำเร็จ ไม่พบรูปในชุด', lineToken);
        return;
      }
      const { pages, pdfPath, signedUrl: pdfUrl } = result;
      const nowIso = new Date().toISOString();
      // mark finalized ทันที — กัน auto ส่งซ้ำ
      await dbUpdate(url, key, 'line_ai_excel_batches', `id=eq.${batchId}`, {
        status: 'finalized', finalized_at: nowIso, pdf_path: pdfPath, pdf_url: pdfUrl, updated_at: nowIso,
      });

      // ── Excel (non-critical) — fail ไม่ทำให้ PDF พัง ──
      const xlsxResult = await buildAndUploadExcel(url, key, batchId);

      try {
        await dbInsert(url, key, 'line_ai_excel_results', {
          batch_id: batchId,
          result_text: `PDF+Excel done: ${pdfPath} (${pages}p) xlsx=${xlsxResult ? 'ok' : 'fail'}`,
          raw_json: { type: 'pdf_excel_done', path: pdfPath, pages, xlsx: xlsxResult?.xlsxPath ?? null },
        });
      } catch (e) {
        console.warn('[line-ai-excel] save result failed:', e instanceof Error ? e.message : e);
      }

      // ── ส่ง card เดียว: PDF+Excel ถ้า Excel สำเร็จ, PDF-only ถ้า Excel fail ──
      if (xlsxResult) {
        await replyPdfExcelFlex(replyToken, pages, pdfUrl, xlsxResult.signedUrl, lineToken);
      } else {
        await replyPdfFlex(replyToken, pages, pdfUrl, lineToken);
      }
    } catch (e) {
      console.error('[line-ai-excel] จบ PDF error:', e instanceof Error ? e.message : e);
      await dbUpdate(url, key, 'line_ai_excel_batches', `id=eq.${batchId}`, {
        status: 'collecting', updated_at: new Date().toISOString(),
      }).catch(() => {});
      await replyLineText(replyToken, 'สร้างไฟล์ไม่สำเร็จ กรุณาลองใหม่', lineToken);
    }
    return;
  }

  // ─── ปรับหมุน / ตรวจหมุนใหม่ / auto rotate — ตรวจ orientation ด้วย OCR/AI ───
  {
    const cmdNoSpace = cmd.replace(/\s+/g, '');
    const isAutoRotate =
      text === 'ปรับหมุน' || text === 'หมุนออโต้' ||
      text === 'ตรวจหมุนใหม่' || text === 'รีเช็กหมุน' ||
      cmdNoSpace === 'autorotate' || cmd === 'auto rotate' ||
      cmdNoSpace === 'rerotate';

    if (isAutoRotate) {
      const batch = await findLatestAnyBatch(url, key, groupId, userId);
      if (!batch) {
        await replyLineText(replyToken, 'ยังไม่มีรูปในชุด กรุณาส่งรูปเอกสารก่อน', lineToken);
        return;
      }
      if (!ctx.docAi) {
        await replyLineText(
          replyToken,
          'ระบบปรับหมุนอัตโนมัติยังไม่พร้อม (ไม่มี OCR config)\nใช้คำสั่ง "หมุน N ขวา/ซ้าย/กลับหัว/ตรง" เพื่อปรับเอง',
          lineToken,
        );
        return;
      }
      const batchId = batch.id as string;
      // [PDF-only mode] ปิด OCR auto-rotate ชั่วคราว — ไม่เสียค่า Google AI
      // ถ้าต้องการเปิดใหม่: ลบ 3 บรรทัดด้านล่าง และ uncomment บล็อก try/catch
      console.log('[line-ai-excel] PDF-only mode: ปรับหมุน/ตรวจหมุน OCR skipped');
      await replyLineText(
        replyToken,
        'ระบบอยู่ในโหมด PDF-only ชั่วคราว (ปิด OCR auto-rotate)\nใช้คำสั่ง "หมุน N ขวา/ซ้าย/กลับหัว/ตรง" เพื่อปรับการหมุนเอง\nพิมพ์ "pdf" เพื่อสร้าง PDF',
        lineToken,
      );
      /* [PDF-only mode] บล็อก OCR ด้านล่าง — uncomment เมื่อเปิด auto-rotate คืน
      // reindex page_no ก่อน เพื่อให้เลขหน้าตรงกับ PDF
      await loadBatchFiles(url, key, batchId);
      try {
        const results = await applyAutoRotateToBatch(url, key, batchId, { force: true });
        if (results.length === 0) {
          await replyLineText(replyToken, 'ยังไม่มีรูปในชุด กรุณาส่งรูปเอกสารก่อน', lineToken);
          return;
        }
        let hasOcrError = false;
        const lines = results.map((r) => {
          if (r.source === 'manual') return `หน้า ${r.pageNo}: manual ${r.rotationDeg}°`;
          if (r.source === 'auto-fail') { hasOcrError = true; return `หน้า ${r.pageNo}: OCR error fallback ${r.rotationDeg}°`; }
          if (r.source === 'none') return `หน้า ${r.pageNo}: ไม่มี OCR ${r.rotationDeg}°`;
          const confStr = r.confidence > 0 ? ` confidence ${r.confidence.toFixed(2)}` : '';
          let note = '';
          if (r.reason === 'no_clear_winner')          note = ' ไม่มั่นใจ จึงไม่หมุน';
          else if (r.reason === 'low_text_all_angles') note = ' อ่านข้อความน้อยทุกมุม';
          else if (r.reason === 'all_ocr_failed')      { note = ' OCR ไม่สำเร็จ'; hasOcrError = true; }
          else if (r.reason === 'decode_failed' || r.reason === 'decode_not_image') note = ' decode ไม่ได้';
          return `หน้า ${r.pageNo}: auto ${r.rotationDeg}°${confStr}${note}`;
        });
        const footer = ['', 'หน้าที่เป็น manual จะไม่ถูกปรับอัตโนมัติ', 'ถ้าหน้าไหนยังผิด ใช้ "หมุน N ขวา/ซ้าย/กลับหัว/ตรง"', 'พิมพ์ "pdf" เพื่อสร้าง PDF ใหม่'];
        if (hasOcrError) footer.push('บางหน้าตรวจ OCR ไม่สำเร็จ จึงไม่หมุนอัตโนมัติ');
        await replyLineText(replyToken, ['ตรวจหมุนอัตโนมัติแล้ว', ...lines, ...footer].join('\n'), lineToken);
      } catch (e) {
        console.error('[line-ai-excel] ปรับหมุน error:', e instanceof Error ? e.message : e);
        await replyLineText(replyToken, 'ปรับหมุนอัตโนมัติไม่สำเร็จ\nใช้คำสั่ง "หมุน N ขวา/ซ้าย/กลับหัว/ตรง" เพื่อปรับเอง', lineToken);
      }
      */ // end [PDF-only mode] comment — ลบบรรทัดนี้เมื่อเปิด auto-rotate คืน
      return;
    }
  }

  // ─── ไม่หมุนออโต้ / ปิดหมุนออโต้ — lock ทุกหน้าไว้ที่ค่าปัจจุบัน ──────────
  {
    const isDisableAuto =
      text === 'ไม่หมุนออโต้' || text === 'ปิดหมุนออโต้' || cmd === 'no auto rotate';

    if (isDisableAuto) {
      const batch = await findLatestAnyBatch(url, key, groupId, userId);
      if (!batch) {
        await replyLineText(replyToken, 'ยังไม่มีรูปในชุด กรุณาส่งรูปเอกสารก่อน', lineToken);
        return;
      }
      const batchId = batch.id as string;
      const files = await loadBatchFiles(url, key, batchId);
      // lock ทุกไฟล์ที่ค่า effective ปัจจุบัน → auto OCR จะข้ามชุดนี้
      for (const f of files) {
        const eff = effectiveRotationCW(f);
        await dbUpdate(url, key, 'line_ai_excel_files', `id=eq.${f.id}`, {
          rotation_deg: eff, rotation_locked: true,
        });
      }
      await replyLineText(
        replyToken,
        'ปิดการหมุนอัตโนมัติสำหรับชุดนี้แล้ว\nใช้คำสั่ง "หมุน N ขวา/ซ้าย/กลับหัว/ตรง" เพื่อปรับเอง\nพิมพ์ "pdf" เพื่อสร้าง PDF',
        lineToken,
      );
      return;
    }
  }

  // ─── หมุน [หน้า...] ทิศ ─────────────────────────────────────────────────────
  // รองรับ: "หมุน 2 ขวา" / "หมุน 2 3 5 7 ซ้าย" / "หมุน 2,3,5 ซ้าย" /
  //         "หมุน 2-3-5-7 ซ้าย" / "หมุน 2 ถึง 7 ซ้าย" / "rotate 2 right"
  {
    const rotM =
      text.match(/^หมุน\s+([\d][\d\s,\-]*|[\d]+\s*ถึง\s*[\d]+)\s*(ขวา|ซ้าย|กลับหัว|ตรง)$/i) ||
      text.match(/^rotate\s+([\d][\d\s,\-]*)\s+(right|left|180|reset)$/i);

    if (rotM) {
      const pagesRaw = rotM[1].trim();
      const dirRaw   = rotM[2].toLowerCase();
      const rotCW =
        dirRaw === 'ขวา'     || dirRaw === 'right' ? 90  :
        dirRaw === 'ซ้าย'    || dirRaw === 'left'  ? 270 :
        dirRaw === 'กลับหัว' || dirRaw === '180'   ? 180 :
        0;

      // parse page numbers: range "N ถึง M" หรือ space/comma/dash คั่น
      let pageNums: number[];
      const rangeM = pagesRaw.match(/^(\d+)\s*ถึง\s*(\d+)$/);
      if (rangeM) {
        const from = parseInt(rangeM[1], 10);
        const to   = parseInt(rangeM[2], 10);
        pageNums = [];
        for (let i = Math.min(from, to); i <= Math.max(from, to); i++) pageNums.push(i);
      } else {
        // split ด้วย space, comma, หรือ dash แล้ว dedupe + sort
        pageNums = [...new Set(
          pagesRaw.split(/[\s,\-]+/).map(s => parseInt(s, 10)).filter(n => !isNaN(n) && n > 0),
        )].sort((a, b) => a - b);
      }

      const batch = await findLatestAnyBatch(url, key, groupId, userId);
      if (!batch) {
        await replyLineText(replyToken, 'ไม่พบ batch ที่ต้องหมุน กรุณาส่งรูปก่อน', lineToken);
        return;
      }
      const batchId = batch.id as string;
      const files = await loadBatchFiles(url, key, batchId);

      const dirLabel =
        rotCW === 90  ? '90° (ขวา)' :
        rotCW === 270 ? '270° (ซ้าย)' :
        rotCW === 180 ? '180° (กลับหัว)' : '0° (ตรง)';

      const rotated: number[] = [];
      const skipped: number[] = [];

      for (const pageNum of pageNums) {
        if (pageNum < 1 || pageNum > files.length) {
          skipped.push(pageNum);
          continue;
        }
        const fileId = files[pageNum - 1].id as string;
        // manual override: lock ไว้เพื่อให้ auto OCR ไม่ override หน้านี้
        await dbUpdate(
          url, key, 'line_ai_excel_files', `id=eq.${fileId}`,
          { rotation_deg: rotCW, rotation_locked: true },
        );
        rotated.push(pageNum);
      }

      const replyLines: string[] = [];
      if (rotated.length > 0) {
        replyLines.push(`หมุนหน้า ${rotated.join(', ')} เป็น ${dirLabel} แล้ว (manual)`);
      }
      for (const p of skipped) {
        replyLines.push(`ข้ามหน้า ${p} เพราะไม่มีในชุดรูปนี้ (มีทั้งหมด ${files.length} หน้า)`);
      }
      replyLines.push('พิมพ์ "pdf" เพื่อสร้าง PDF ใหม่');
      await replyLineText(replyToken, replyLines.join('\n'), lineToken);
      return;
    }
  }

  // ─── สลับ A B — "สลับ 2 3" / "swap 2 3" ───────────────────────────────────
  {
    const swapM =
      text.match(/^สลับ\s*(\d+)\s+(\d+)$/i) ||
      text.match(/^swap\s+(\d+)\s+(\d+)$/i);

    if (swapM) {
      const fromPage = parseInt(swapM[1], 10);
      const toPage = parseInt(swapM[2], 10);
      const batch = await findLatestAnyBatch(url, key, groupId, userId);
      if (!batch) {
        await replyLineText(replyToken, 'ไม่พบ batch ที่ต้องสลับ กรุณาส่งรูปก่อน', lineToken);
        return;
      }
      const batchId = batch.id as string;
      const files = await loadBatchFiles(url, key, batchId);
      if (
        fromPage < 1 || fromPage > files.length ||
        toPage < 1 || toPage > files.length
      ) {
        await replyLineText(
          replyToken,
          `สลับไม่ได้: มีทั้งหมด ${files.length} หน้า`,
          lineToken,
        );
        return;
      }
      if (fromPage !== toPage) {
        const a = fromPage - 1;
        const b = toPage - 1;
        await dbUpdate(url, key, 'line_ai_excel_files', `id=eq.${files[a].id}`, { page_no: toPage });
        await dbUpdate(url, key, 'line_ai_excel_files', `id=eq.${files[b].id}`, { page_no: fromPage });
      }
      await replyLineText(
        replyToken,
        `สลับหน้า ${fromPage} กับ ${toPage} แล้ว\nพิมพ์ "รายการ" เพื่อตรวจลำดับ หรือ "pdf" เพื่อสร้าง PDF ใหม่`,
        lineToken,
      );
      return;
    }
  }

  // ─── ย้าย A ไป B — "ย้าย 4 ไป 1" / "move 4 to 1" ─────────────────────────
  {
    const moveM =
      text.match(/^ย้าย\s*(\d+)\s*ไป\s*(\d+)$/i) ||
      text.match(/^move\s+(\d+)\s+to\s+(\d+)$/i);

    if (moveM) {
      const fromPage = parseInt(moveM[1], 10);
      const toPage = parseInt(moveM[2], 10);
      const batch = await findLatestAnyBatch(url, key, groupId, userId);
      if (!batch) {
        await replyLineText(replyToken, 'ไม่พบ batch ที่ต้องย้าย กรุณาส่งรูปก่อน', lineToken);
        return;
      }
      const batchId = batch.id as string;
      const files = await loadBatchFiles(url, key, batchId);
      if (
        fromPage < 1 || fromPage > files.length ||
        toPage < 1 || toPage > files.length
      ) {
        await replyLineText(
          replyToken,
          `ย้ายไม่ได้: มีทั้งหมด ${files.length} หน้า`,
          lineToken,
        );
        return;
      }

      if (fromPage !== toPage) {
        const reordered = [...files];
        const [moved] = reordered.splice(fromPage - 1, 1);
        reordered.splice(toPage - 1, 0, moved);
        for (let i = 0; i < reordered.length; i++) {
          await dbUpdate(
            url, key, 'line_ai_excel_files', `id=eq.${reordered[i].id}`,
            { page_no: i + 1 },
          );
        }
      }

      await replyLineText(
        replyToken,
        `ย้ายหน้า ${fromPage} ไป ${toPage} แล้ว\nพิมพ์ "รายการ" เพื่อตรวจลำดับ หรือ "pdf" เพื่อสร้าง PDF ใหม่`,
        lineToken,
      );
      return;
    }
  }

  // ─── จัดลำดับทั้งหมด — "จัด 1 3 2 4" / "order 1 3 2 4" ───────────────────
  {
    const orderM =
      text.match(/^จัด\s+([0-9\s]+)$/i) ||
      text.match(/^order\s+([0-9\s]+)$/i);

    if (orderM) {
      const batch = await findLatestAnyBatch(url, key, groupId, userId);
      if (!batch) {
        await replyLineText(replyToken, 'ไม่พบ batch ที่ต้องจัดลำดับ กรุณาส่งรูปก่อน', lineToken);
        return;
      }
      const batchId = batch.id as string;
      const files = await loadBatchFiles(url, key, batchId);
      const requested = orderM[1].trim().split(/\s+/).map(n => parseInt(n, 10));
      const count = files.length;
      const valid =
        requested.length === count &&
        requested.every(n => Number.isInteger(n) && n >= 1 && n <= count) &&
        new Set(requested).size === count;

      if (!valid) {
        await replyLineText(
          replyToken,
          `จัดลำดับไม่ได้: ต้องใส่เลขครบทุกหน้า 1-${count} ห้ามซ้ำ ห้ามขาด`,
          lineToken,
        );
        return;
      }

      for (let i = 0; i < requested.length; i++) {
        const oldPage = requested[i];
        await dbUpdate(
          url, key, 'line_ai_excel_files', `id=eq.${files[oldPage - 1].id}`,
          { page_no: i + 1 },
        );
      }

      await replyLineText(
        replyToken,
        'จัดลำดับหน้าใหม่แล้ว พิมพ์ “pdf” เพื่อสร้าง PDF ใหม่',
        lineToken,
      );
      return;
    }
  }

  // ─── ocr / อ่านดิบ — คงไว้สำหรับ debug ──────────────────────────────────
  if (cmd === 'ocr' || text === 'อ่านดิบ') {
    if (!ctx.docAi) {
      await replyLineText(replyToken, 'OCR อ่านไม่สำเร็จ: MISSING_DOCUMENT_AI_CONFIG', lineToken);
      return;
    }
    const { batchId, images, rotationsCW } = await loadLatestBatchImages(url, key, groupId);
    if (!batchId || images.length === 0) {
      await replyLineText(replyToken, 'ยังไม่มีรูปสำหรับ OCR กรุณาส่งรูปเอกสารก่อน', lineToken);
      return;
    }
    try {
      const ocrText = await runDocAiOnBatch(ctx.docAi, images, rotationsCW);
      try {
        await dbInsert(url, key, 'line_ai_excel_results', {
          batch_id: batchId,
          result_text: ocrText.slice(0, 20000),
          raw_json: { type: 'ocr_raw', chars: ocrText.length },
        });
      } catch (e) {
        console.warn('[line-ai-excel] save ocr result failed:', e instanceof Error ? e.message : e);
      }
      const reply = ocrText.length > 4500
        ? `ข้อความ OCR (${ocrText.length} ตัวอักษร, แสดงช่วงแรก):\n\n` +
          ocrText.slice(0, 4500) + '\n\n... (ยาวเกิน ตัดบางส่วน)'
        : `ข้อความ OCR:\n\n${ocrText}`;
      await replyLineText(replyToken, reply, lineToken);
    } catch (e) {
      await replyLineText(replyToken, mapDocAiError(e), lineToken);
    }
    return;
  }

  // ─── อ่าน / อ่านหัวข้อ / txt — พักไว้ก่อน ──────────────────────
  // NOTE: excel/xlsx ถูกย้ายไป handler สร้าง Excel ด้านล่างแล้ว (ห้ามดักที่นี่)
  {
    const isReadCmd =
      text === 'อ่าน' || text === 'อ่านหัวข้อ' || text === 'ไฟล์' ||
      cmd === 'read' || cmd === 'readheader' || cmd === 'read header' ||
      cmd === 'txt';

    if (isReadCmd) {
      await replyLineText(
        replyToken,
        'ฟังก์ชันอ่าน Excel ยังอยู่ระหว่างปรับปรุง ตอนนี้แนะนำใช้ PDF ก่อนครับ\nพิมพ์ "pdf" หรือ "จบ" เพื่อสร้างไฟล์เอกสาร',
        lineToken,
      );
      return;
    }
  }

  // ─── pdf / ทำpdf / ทำ PDF — สร้าง PDF ทันที ──────────────────────────────
  {
    const cmdNoSpace = text.replace(/\s+/g, '').toLowerCase();
    if (cmd === 'pdf' || cmdNoSpace === 'pdf' || cmdNoSpace === 'ทำpdf') {
      const batch = await findLatestAnyBatch(url, key, groupId, userId);
      if (!batch) {
        await replyLineText(replyToken, 'ยังไม่มีรูปสำหรับทำ PDF กรุณาส่งรูปเอกสารก่อน', lineToken);
        return;
      }
      const batchId     = batch.id as string;
      const batchStatus = batch.status as string;
      try {
        const result = await buildAndUploadPdf(url, key, batchId);
        if (!result) {
          await replyLineText(replyToken, 'สร้าง PDF ไม่สำเร็จ กรุณาลองใหม่', lineToken);
          return;
        }
        const { pages, pdfPath, signedUrl } = result;
        const nowIso = new Date().toISOString();
        // ถ้า batch ยังเป็น collecting → mark finalized ทันทีเพื่อกัน cron ส่ง PDF ซ้ำ
        // ถ้าเป็น finalized แล้ว (re-create หลังหมุน) → update path ใหม่เท่านั้น
        if (batchStatus === 'collecting') {
          await dbUpdate(url, key, 'line_ai_excel_batches', `id=eq.${batchId}`, {
            status: 'finalized', finalized_at: nowIso,
            pdf_path: pdfPath, pdf_url: signedUrl, updated_at: nowIso,
          });
        } else {
          await dbUpdate(url, key, 'line_ai_excel_batches', `id=eq.${batchId}`, {
            pdf_path: pdfPath, pdf_url: signedUrl, updated_at: nowIso,
          });
        }
        try {
          await dbInsert(url, key, 'line_ai_excel_results', {
            batch_id: batchId,
            result_text: `PDF created: ${pdfPath} (${pages} pages)`,
            raw_json: { type: 'pdf_manual', path: pdfPath, pages },
          });
        } catch (e) {
          console.warn('[line-ai-excel] save pdf result failed:', e instanceof Error ? e.message : e);
        }
        await replyPdfFlex(replyToken, pages, signedUrl, lineToken);
      } catch (e) {
        console.error('[line-ai-excel] PDF error:', e instanceof Error ? e.message : e);
        await replyLineText(replyToken, 'สร้าง PDF ไม่สำเร็จ กรุณาลองใหม่', lineToken);
      }
      return;
    }
  }

  // ─── excel / xlsx / จบexcel — สร้าง Excel อย่างเดียว (สำหรับเทส) ──────────
  {
    const cmdNoSpace2 = text.replace(/\s+/g, '').toLowerCase();
    if (cmd === 'excel' || cmd === 'xlsx' || cmdNoSpace2 === 'excel' ||
        cmdNoSpace2 === 'xlsx' || cmdNoSpace2 === 'จบexcel') {
      const batch = await findLatestAnyBatch(url, key, groupId, userId);
      if (!batch) {
        await replyLineText(replyToken, 'ยังไม่มีรูปสำหรับทำ Excel กรุณาส่งรูปเอกสารก่อน', lineToken);
        return;
      }
      const batchId     = batch.id as string;
      const batchStatus = batch.status as string;
      // oversize: Excel รองรับไม่เกิน 15 รูปต่อชุด
      const xlCount = (batch.image_count as number) || 0;
      if (xlCount > MAX_IMAGES_PER_BATCH_FOR_AUTO) {
        console.log(`[line-ai-excel] excel oversize batch=${batchId} count=${xlCount} → reject`);
        await replyLineText(
          replyToken,
          `Excel รองรับไม่เกิน ${MAX_IMAGES_PER_BATCH_FOR_AUTO} รูปต่อชุด กรุณาแบ่งชุด`,
          lineToken,
        );
        return;
      }
      const xlsxResult = await buildAndUploadExcel(url, key, batchId);
      if (!xlsxResult) {
        await replyLineText(replyToken, 'สร้าง Excel ไม่สำเร็จ กรุณาลองใหม่', lineToken);
        return;
      }
      // mark finalized เพื่อกัน auto finalize ส่ง PDF+Excel card ซ้ำ (ถ้ายัง collecting)
      if (batchStatus === 'collecting') {
        const nowIso = new Date().toISOString();
        await dbUpdate(url, key, 'line_ai_excel_batches', `id=eq.${batchId}`, {
          status: 'finalized', finalized_at: nowIso, updated_at: nowIso,
        });
        try {
          await dbInsert(url, key, 'line_ai_excel_results', {
            batch_id: batchId,
            result_text: `Excel manual: ${xlsxResult.xlsxPath}`,
            raw_json: { type: 'xlsx_manual', path: xlsxResult.xlsxPath },
          });
        } catch (e) {
          console.warn('[line-ai-excel] save xlsx result failed:', e instanceof Error ? e.message : e);
        }
      }
      // reply Flex card Excel-only (single button)
      const excelFlex = {
        type: 'flex',
        altText: '📊 Excel พร้อมแล้ว',
        contents: {
          type: 'bubble', size: 'kilo',
          body: {
            type: 'box', layout: 'vertical', backgroundColor: '#FFFFFF',
            paddingAll: '12px', paddingBottom: '8px', spacing: 'sm',
            contents: [
              {
                type: 'box', layout: 'horizontal', spacing: 'sm', alignItems: 'center',
                contents: [
                  {
                    type: 'image',
                    url: 'https://magwqolbjmwymqxelizl.supabase.co/storage/v1/object/public/line-assets/ChatGPT%20Image%20Jun%203,%202026,%2009_14_20%20PM.png',
                    size: '44px', aspectRatio: '1:1', aspectMode: 'cover', flex: 0,
                  },
                  {
                    type: 'box', layout: 'vertical', flex: 1, spacing: 'none',
                    contents: [
                      { type: 'text', text: 'ไฟล์ Excel', weight: 'bold', size: 'sm', color: '#333333' },
                      { type: 'text', text: 'รูปเรียงใน worksheet Documents', size: 'xs', color: '#777777' },
                    ],
                  },
                ],
              },
              {
                type: 'button', style: 'primary', color: '#1D6F42', height: 'sm',
                action: { type: 'uri', label: 'เปิด Excel', uri: xlsxResult.signedUrl },
              },
            ],
          },
        },
      };
      const res = await fetch('https://api.line.me/v2/bot/message/reply', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${lineToken}` },
        body: JSON.stringify({ replyToken, messages: [excelFlex] }),
      });
      if (!res.ok) {
        console.warn('[line-ai-excel] excel flex reply failed:', res.status);
        await replyLineText(replyToken, `Excel พร้อมแล้ว\nเปิดไฟล์: ${xlsxResult.signedUrl}`, lineToken);
      }
      return;
    }
  }

  // คำสั่งอื่น — เงียบ
  console.log('[line-ai-excel] text (no command matched)');
}

// ─── Main Handler ──────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const rawBody = await req.text();
  const signature = req.headers.get('x-line-signature');

  // ── Secrets ──
  const url            = Deno.env.get('SUPABASE_URL');
  const key            = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const lineToken      = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN');
  const channelSecret  = Deno.env.get('LINE_CHANNEL_SECRET');
  const controlGroupId = Deno.env.get('LINE_AI_CONTROL_GROUP_ID') || '';
  // PDF_ALLOWED_GROUP_IDS: comma-separated group IDs เพิ่มเติม (นอกเหนือจาก LINE_AI_CONTROL_GROUP_ID)
  // รวมกัน: LINE_AI_CONTROL_GROUP_ID + PDF_ALLOWED_GROUP_IDS → allowed ทั้งหมด
  const allowedGroupRaw = Deno.env.get('PDF_ALLOWED_GROUP_IDS') || '';
  const allowedGroupIds: Set<string> = new Set([
    ...(controlGroupId ? [controlGroupId] : []),
    ...allowedGroupRaw.split(',').map(s => s.trim()).filter(Boolean),
  ]);
  console.log(`[line-ai-excel] allowed_groups=${allowedGroupIds.size} (${[...allowedGroupIds].join(',')})`);
  const geminiKey      = Deno.env.get('GEMINI_API_KEY');
  // OCR_PROVIDER: 'documentai' (default flow ใหม่) — อ่านไว้ log
  const ocrProvider    = Deno.env.get('OCR_PROVIDER') || 'documentai';
  // Document AI config — null ถ้า secrets ไม่ครบ (คำสั่ง อ่าน/ocr จะตอบ MISSING_DOCUMENT_AI_CONFIG)
  const docAi          = readDocAiConfig();
  console.log(`[line-ai-excel] ocr_provider=${ocrProvider} docAi_ready=${docAi ? 'yes' : 'no'}`);

  if (!url || !key || !lineToken || !channelSecret) {
    console.error('[line-ai-excel] missing required secrets');
    // ตอบ 200 กัน LINE retry ถล่ม
    return new Response(JSON.stringify({ ok: false, error: 'not configured' }), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    });
  }

  // ── Validate signature ──
  const valid = await validateSignature(rawBody, signature, channelSecret);
  if (!valid) {
    console.warn('[line-ai-excel] invalid signature');
    return new Response('Unauthorized', { status: 401 });
  }

  // ── Parse events ──
  let payload: { events?: LineEvent[] };
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return new Response('Bad Request', { status: 400 });
  }
  const events = payload.events || [];
  const ctx = { url, key, lineToken, geminiKey, docAi };

  // ใช้ index-based loop เพื่อส่ง eventIndex เป็น tiebreaker ลำดับหน้า PDF
  for (let evIdx = 0; evIdx < events.length; evIdx++) {
    const ev = events[evIdx];
    try {
      if (ev.type !== 'message' || !ev.source) continue;
      const groupId = ev.source.groupId || '';
      const msgType = ev.message?.type || '';

      // ── ทำงานเฉพาะกลุ่มที่อนุญาต (PDF_ALLOWED_GROUP_IDS หรือ LINE_AI_CONTROL_GROUP_ID) ──
      if (!groupId || !allowedGroupIds.has(groupId)) {
        console.log(
          `[line-ai-excel] ignore non-allowed source` +
          ` type=${ev.source?.type || 'unknown'}` +
          ` groupId=${groupId || '(none)'}` +
          ` userId=${ev.source?.userId || '(none)'}`,
        );
        continue;
      }

      console.log(`[line-ai-excel] event[${evIdx}] type=${msgType} ts=${ev.timestamp}`);

      if (msgType === 'image') {
        await handleImage(ev, ctx, evIdx);
      } else if (msgType === 'text') {
        await handleText(ev, ctx);
      }
    } catch (evErr) {
      console.error('[line-ai-excel] event error:', evErr instanceof Error ? evErr.message : evErr);
      // ไม่ throw — event อื่นต้องทำงานต่อ
    }
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200, headers: { 'Content-Type': 'application/json' },
  });
});
