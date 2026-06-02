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
import { PDFDocument, degrees } from 'https://esm.sh/pdf-lib@1.17.1';

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
const BATCH_WINDOW_MS = 30 * 60 * 1000; // 30 นาที — รวมรูปชุดเดียวกัน
// Gemini (legacy) — ยังเก็บไว้เผื่อ fallback แต่ "อ่าน" ใหม่ใช้ Document AI
const GEMINI_MODEL_PRIMARY  = 'gemini-2.0-flash';
const GEMINI_MODEL_FALLBACK = 'gemini-1.5-flash';

// PDF — เก็บใน bucket เดิม ใต้ path prefix แยก, signed URL อายุ 30 วัน
const PDF_PATH_PREFIX = 'line-ai-excel-pdf';
const PDF_SIGNED_URL_SECONDS = 30 * 24 * 60 * 60; // 30 วัน
// A4 แนวตั้ง (points) + ขอบ
const A4_W = 595.28;
const A4_H = 841.89;
const PDF_MARGIN = 24;

// TSV header (คอลัมน์ที่ต้องการ) — ใช้ทั้งใน prompt และ fallback
const TSV_HEADER =
  'วันที่ยื่น\tรูปถ่าย\tนายจ้าง\tรายชื่อ\tเลขประจำตัวต่างด้าว\tสัญชาติ\t' +
  'เลขคำขอ\tใบอนุญาตทำงานเลขที่\tประเภทเอกสาร\tวันนัด\tเวลา\tสถานที่\tหมายเหตุ';

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

/** หา batch ล่าสุดของกลุ่มที่ status='collecting' ภายในหน้าต่างเวลา */
async function findActiveBatch(
  url: string, key: string, groupId: string,
): Promise<Record<string, unknown> | null> {
  const cutoff = new Date(Date.now() - BATCH_WINDOW_MS).toISOString();
  const rows = await dbSelect(
    url, key,
    `line_ai_excel_batches?group_id=eq.${encodeURIComponent(groupId)}` +
    `&status=eq.collecting&last_image_at=gte.${encodeURIComponent(cutoff)}` +
    `&order=last_image_at.desc&limit=1`,
  );
  return rows.length > 0 ? rows[0] : null;
}

/** หา batch ล่าสุดของกลุ่มที่ collecting (ไม่จำกัดเวลา) — ใช้กับคำสั่ง อ่าน/รายการ/ล้าง */
async function findLatestCollectingBatch(
  url: string, key: string, groupId: string,
): Promise<Record<string, unknown> | null> {
  const rows = await dbSelect(
    url, key,
    `line_ai_excel_batches?group_id=eq.${encodeURIComponent(groupId)}` +
    `&status=eq.collecting&order=last_image_at.desc&limit=1`,
  );
  return rows.length > 0 ? rows[0] : null;
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
    '- ถ้ามีรูปหน้าคน/รูปถ่ายในชุด คอลัมน์ "รูปถ่าย" = มีรูป',
    '- ถ้าไม่มีรูปถ่ายคน คอลัมน์ "รูปถ่าย" = ไม่มีรูป',
    '- ถ้าอ่านเลขไม่ชัด ให้ใส่ "-"',
    '- ถ้าไม่มั่นใจ ให้ใส่ "ตรวจสอบ" ในคอลัมน์หมายเหตุ',
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
  if (/myanmar|burma|เมียนมา|พม่า/.test(t)) return 'เมียนมา';
  if (/lao|laos|ลาว/.test(t))               return 'ลาว';
  if (/cambodia|khmer|กัมพูชา|เขมร/.test(t)) return 'กัมพูชา';
  if (/vietnam|เวียดนาม/.test(t))           return 'เวียดนาม';
  return '-';
}

/**
 * สรุป OCR text → 1 แถว TSV ด้วย rule/regex เบื้องต้น
 * ปรัชญา: ห้ามเดา — ถ้าไม่เจอ field ให้ "-" และเติมหมายเหตุ "ตรวจสอบ OCR"
 *
 * คืน array ของ 13 ช่อง (ตาม TSV_HEADER)
 */
function parseOcrToRow(ocrText: string, hasPhoto: boolean): string[] {
  const DASH = '-';
  const notes: string[] = [];

  // รวมข้อความเป็นบรรทัด ลบช่องว่างซ้ำ
  const raw = ocrText.replace(/\r/g, '');
  const flat = raw.replace(/[ \t]+/g, ' ');

  // helper: หา match แรกของ pattern, คืน group 1 (trim) หรือ DASH
  const find = (re: RegExp): string => {
    const m = flat.match(re);
    return m && m[1] ? m[1].trim() : DASH;
  };

  // ── รายชื่อ (MR/MRS/MISS + ตัวอักษรอังกฤษ) ──
  let name = DASH;
  const nameM = flat.match(/\b(MR|MRS|MISS|MS)\.?\s+([A-Z][A-Z\s.]{2,40})/);
  if (nameM) {
    name = `${nameM[1].toUpperCase()} ${nameM[2].trim().replace(/\s{2,}/g, ' ')}`;
    // ตัดหางที่อาจติด keyword อื่น
    name = name.replace(/\s+(NATIONALITY|PASSPORT|NO|DATE|สัญชาติ).*$/i, '').trim();
  }

  // ── สัญชาติ ──
  let nationality = DASH;
  const natM = flat.match(/(?:nationality|สัญชาติ)\s*:?\s*([A-Za-zก-๙]+)/i);
  if (natM) nationality = normalizeNationality(natM[1]);
  if (nationality === DASH) {
    // เผื่อสะกดลอย ๆ ในข้อความ
    const guess = normalizeNationality(flat);
    if (guess !== DASH) nationality = guess;
  }

  // ── เลขประจำตัวต่างด้าว (13 หลัก หรือ ป้ายกำกับ) ──
  let alienId = find(/(?:เลขประจำตัว(?:คนต่างด้าว|บุคคล)?|alien\s*(?:id|no|number))\s*:?\s*([0-9][0-9\- ]{8,20})/i);
  if (alienId === DASH) {
    const m13 = flat.match(/\b(\d{13})\b/); // เลข 13 หลักลอย ๆ
    if (m13) alienId = m13[1];
  }
  alienId = alienId.replace(/[ \-]/g, '') === '' ? DASH : alienId.replace(/\s/g, '');

  // ── เลขคำขอ ──
  const reqNo = find(/(?:เลขคำขอ|เลขที่คำขอ|request\s*no)\s*:?\s*([0-9][0-9\- ]{6,20})/i)
    .replace(/\s/g, '');

  // ── ใบอนุญาตทำงานเลขที่ ──
  const workPermit = find(/(?:ใบอนุญาตทำงาน(?:เลขที่)?|work\s*permit\s*(?:no)?)\s*:?\s*([0-9][0-9\- ]{6,20})/i)
    .replace(/\s/g, '');

  // ── นายจ้าง ──
  let employer = find(/(?:นายจ้าง|employer|สถานประกอบการ)\s*:?\s*([^\n]{3,60})/i);
  // ตัดหางหลังคำสำคัญ
  if (employer !== DASH) {
    employer = employer.replace(/\s+(เลขที่|address|ที่อยู่|โทร|tel).*$/i, '').trim();
  }
  // ถ้าเจอ "บริษัท ... จำกัด" ให้ดึงรูปแบบนั้น
  const compM = raw.match(/(บริษัท[^\n]{2,50}?จำกัด)/);
  if (compM) employer = compM[1].trim();

  // ── วันที่ยื่น ──
  const submitDate = find(/(?:วันที่ยื่น|วันยื่น|submit(?:ted)?\s*date)\s*:?\s*([0-9]{1,2}[\/\-. ][0-9]{1,2}[\/\-. ][0-9]{2,4})/i);

  // ── วันนัด ──
  const apptDate = find(/(?:วันนัด|นัดหมาย|appointment)\s*:?\s*([0-9]{1,2}[\/\-. ][0-9]{1,2}[\/\-. ][0-9]{2,4})/i);

  // ── เวลา ──
  const apptTime = find(/(?:เวลา|time)\s*:?\s*([0-9]{1,2}[:.][0-9]{2}(?:\s*น\.?)?)/i);

  // ── สถานที่ ──
  let place = find(/(?:สถานที่|สถานที่นัด|location|venue)\s*:?\s*([^\n]{3,50})/i);
  if (place !== DASH) place = place.replace(/\s+(เวลา|time|วันที่).*$/i, '').trim();

  // ── ประเภทเอกสาร ──
  let docType = DASH;
  if (/ต่ออายุ|renew/i.test(flat))            docType = 'ต่ออายุ';
  else if (/เปลี่ยนนายจ้าง/i.test(flat))      docType = 'เปลี่ยนนายจ้าง';
  else if (/90\s*วัน/i.test(flat))            docType = '90 วัน';
  else if (/mou/i.test(flat))                 docType = 'MOU';
  else if (/นัดถ่ายบัตร|ถ่ายบัตร/i.test(flat)) docType = 'นัดถ่ายบัตร';

  // ── หมายเหตุ: ถ้าจับ field หลักไม่ได้ ให้เตือนตรวจสอบ ──
  if (name === DASH || (alienId === DASH && reqNo === DASH && workPermit === DASH)) {
    notes.push('ตรวจสอบ OCR');
  }
  const note = notes.length > 0 ? notes.join(', ') : DASH;

  // คอลัมน์ตาม TSV_HEADER:
  // วันที่ยื่น, รูปถ่าย, นายจ้าง, รายชื่อ, เลขประจำตัวต่างด้าว, สัญชาติ,
  // เลขคำขอ, ใบอนุญาตทำงานเลขที่, ประเภทเอกสาร, วันนัด, เวลา, สถานที่, หมายเหตุ
  return [
    submitDate,
    hasPhoto ? 'มีรูป' : 'ไม่มีรูป',
    employer,
    name,
    alienId,
    nationality,
    reqNo,
    workPermit,
    docType,
    apptDate,
    apptTime,
    place,
    note,
  ];
}

/** สร้าง TSV เต็ม (header + 1 แถว) จาก OCR text */
function ocrToTsv(ocrText: string, hasPhoto: boolean): string {
  const row = parseOcrToRow(ocrText, hasPhoto);
  return TSV_HEADER + '\n' + row.join('\t');
}

/**
 * รวมรูป batch เป็น PDF (auto-rotate) แล้วส่งเข้า Document AI → คืน OCR text
 * ใช้ PDF logic เดิม (buildPdfFromImages) — reuse เพื่อให้ทิศตรงเหมือนคำสั่ง pdf
 * throw error code ที่ mapDocAiError จะแปลงเป็นข้อความ LINE
 */
async function runDocAiOnBatch(
  cfg: DocAiConfig,
  images: { bytes: Uint8Array; contentType: string }[],
): Promise<string> {
  const { pdf, pages } = await buildPdfFromImages(images);
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
 * auto-rotate ตาม EXIF Orientation (JPEG เท่านั้น)
 * fit รูปในกรอบ (รักษาสัดส่วน, ไม่ crop), จัดกึ่งกลาง, พื้นหลังขาว
 * คืน Uint8Array ของ PDF + จำนวนหน้าที่ embed สำเร็จ
 */
async function buildPdfFromImages(
  images: { bytes: Uint8Array; contentType: string }[],
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

    // ─ auto-rotate EXIF (JPEG only; PNG default = 0) ─
    const exifOrient = kind === 'jpg' ? readJpegExifOrientation(img.bytes) : 1;
    const rotateCCW  = exifToDegreesCCW(exifOrient);
    if (exifOrient !== 1) {
      console.log(`[line-ai-excel] img[${idx}] EXIF orient=${exifOrient} → rotate ${rotateCCW}° CCW`);
    }

    // ─ วาดบนหน้า A4 พร้อม auto-rotate ─
    const page = doc.addPage([A4_W, A4_H]);
    drawImageOnPage(page, embedded, (opts) => page.drawImage(embedded, opts), rotateCCW, idx);
    pages++;
  }

  const bytes = await doc.save();
  return { pdf: bytes, pages };
}

// ─── Event Processing ─────────────────────────────────────────────────────────

/** รูปในกลุ่ม control → เก็บ batch + Storage */
async function handleImage(
  ev: LineEvent,
  ctx: { url: string; key: string; lineToken: string },
): Promise<void> {
  const { url, key, lineToken } = ctx;
  const groupId = ev.source?.groupId || '';
  const userId  = ev.source?.userId  || null;
  const msgId   = ev.message?.id || '';
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

  // 2) หา/สร้าง batch
  const existing = await findActiveBatch(url, key, groupId);
  let batchId: string;
  let newCount: number;
  let isFirstImage = false;
  const nowIso = new Date().toISOString();

  if (existing) {
    batchId  = existing.id as string;
    newCount = ((existing.image_count as number) || 0) + 1;
    await dbUpdate(
      url, key, 'line_ai_excel_batches', `id=eq.${batchId}`,
      { image_count: newCount, last_image_at: nowIso, updated_at: nowIso },
    );
  } else {
    const created = await dbInsert(
      url, key, 'line_ai_excel_batches',
      { group_id: groupId, user_id: userId, status: 'collecting', image_count: 1, last_image_at: nowIso },
    );
    batchId  = created[0].id as string;
    newCount = 1;
    isFirstImage = true;
  }

  // 3) อัปโหลด Storage
  const ext  = extFromContentType(contentType);
  const path = `${groupId}/${batchId}/${msgId}.${ext}`;
  await uploadToStorage(url, key, path, bytes, contentType);

  // 4) บันทึก file record
  await dbInsert(
    url, key, 'line_ai_excel_files',
    { batch_id: batchId, line_message_id: msgId, storage_path: path, mime_type: contentType },
  );

  console.log(`[line-ai-excel] stored image | batch=${batchId} count=${newCount}`);

  // 5) reply เฉพาะรูปแรกของ batch (กันรก)
  if (isFirstImage && ev.replyToken) {
    await replyLineText(
      ev.replyToken,
      'รับรูปแล้ว ส่งเพิ่มได้เลย\nพิมพ์ "อ่าน" เมื่อต้องการให้ AI สรุปเป็นตาราง Excel',
      lineToken,
    );
  }
}

/**
 * โหลดรูปทั้งหมดของ batch ล่าสุด (collecting) ตามลำดับเวลา
 * คืน { batch, images } — images[] เรียงตาม created_at.asc
 * ถ้า batch ไม่มี → batch=null; ถ้าโหลดไม่ได้เลย → images=[]
 */
async function loadLatestBatchImages(
  url: string, key: string, groupId: string,
): Promise<{ batchId: string | null; images: { bytes: Uint8Array; contentType: string }[] }> {
  const batch = await findLatestCollectingBatch(url, key, groupId);
  if (!batch) return { batchId: null, images: [] };
  const batchId = batch.id as string;

  const files = await dbSelect(
    url, key,
    `line_ai_excel_files?batch_id=eq.${batchId}&order=created_at.asc` +
    `&select=storage_path,mime_type`,
  );
  console.log(`[line-ai-excel] batch=${batchId} | file_records=${files.length}`);

  const images: { bytes: Uint8Array; contentType: string }[] = [];
  for (let fi = 0; fi < files.length; fi++) {
    const f = files[fi];
    const storagePath = f.storage_path as string;
    const storedMime  = (f.mime_type as string) || 'image/jpeg';
    try {
      const got = await downloadFromStorage(url, key, storagePath);
      const mimeType = storedMime.startsWith('image/') ? storedMime : got.contentType;
      console.log(`[line-ai-excel] img[${fi}] path=${storagePath} bytes=${got.bytes.length} mime=${mimeType}`);
      images.push({ bytes: got.bytes, contentType: mimeType });
    } catch (e) {
      console.warn('[line-ai-excel] storage fetch failed | path=' + storagePath + ':',
        e instanceof Error ? e.message : e);
    }
  }
  return { batchId, images };
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
  const { url, key, lineToken, docAi } = ctx;
  const groupId = ev.source?.groupId || '';
  const replyToken = ev.replyToken;
  if (!replyToken || !groupId) return;

  const text = (ev.message?.text || '').trim();
  const cmd = text.toLowerCase();

  // ─── help ───
  if (cmd === 'help' || text === 'ช่วยเหลือ') {
    await replyLineText(
      replyToken,
      [
        'วิธีใช้:',
        'ส่งรูปเอกสารหลายใบ แล้วเลือก:',
        '"อ่าน" = OCR แล้วสรุปเป็นตาราง Excel',
        '"ocr" = อ่านข้อความดิบจากเอกสาร',
        '"pdf" = รวมรูปเป็นไฟล์ PDF เดียว',
        '"รายการ" = ดูจำนวนรูปในชุดล่าสุด',
        '"ล้าง" = เริ่มชุดใหม่',
      ].join('\n'),
      lineToken,
    );
    return;
  }

  // ─── รายการ ───
  if (text === 'รายการ' || cmd === 'list') {
    const batch = await findLatestCollectingBatch(url, key, groupId);
    const count = batch ? (batch.image_count as number) || 0 : 0;
    if (!batch || count === 0) {
      await replyLineText(replyToken, 'ยังไม่มีรูปในชุดล่าสุด กรุณาส่งรูปเอกสารก่อน', lineToken);
      return;
    }
    await replyLineText(
      replyToken,
      [
        `ชุดล่าสุด: ${count} รูป`,
        'พิมพ์ "อ่าน" เพื่อให้ AI อ่านชุดนี้',
        'พิมพ์ "ล้าง" เพื่อล้างชุดนี้',
      ].join('\n'),
      lineToken,
    );
    return;
  }

  // ─── ล้าง ───
  if (text === 'ล้าง' || cmd === 'clear' || cmd === 'reset') {
    const batch = await findLatestCollectingBatch(url, key, groupId);
    if (!batch) {
      await replyLineText(replyToken, 'ไม่มีชุดที่ต้องล้าง', lineToken);
      return;
    }
    await dbUpdate(
      url, key, 'line_ai_excel_batches', `id=eq.${batch.id}`,
      { status: 'cancelled', updated_at: new Date().toISOString() },
    );
    await replyLineText(replyToken, 'ล้างชุดล่าสุดแล้ว', lineToken);
    return;
  }

  // ─── ocr / OCR / อ่านดิบ ──────────────────────────────────────────────────
  // OCR ด้วย Document AI → ตอบข้อความดิบ (ไม่สรุปเป็นตาราง)
  if (cmd === 'ocr' || text === 'อ่านดิบ') {
    if (!docAi) {
      console.error('[line-ai-excel] MISSING_DOCUMENT_AI_CONFIG');
      await replyLineText(replyToken, 'OCR อ่านไม่สำเร็จ: MISSING_DOCUMENT_AI_CONFIG', lineToken);
      return;
    }
    const { batchId, images } = await loadLatestBatchImages(url, key, groupId);
    if (!batchId || images.length === 0) {
      await replyLineText(replyToken, 'ยังไม่มีรูปสำหรับ OCR กรุณาส่งรูปเอกสารก่อน', lineToken);
      return;
    }

    try {
      const ocrText = await runDocAiOnBatch(docAi, images);
      // บันทึก raw OCR
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
        ? `ข้อความ OCR (${ocrText.length} ตัวอักษร, แสดงช่วงแรก):\n\n` + ocrText.slice(0, 4500) + '\n\n... (ยาวเกิน ตัดบางส่วน)'
        : `ข้อความ OCR:\n\n${ocrText}`;
      await replyLineText(replyToken, reply, lineToken);
    } catch (e) {
      await replyLineText(replyToken, mapDocAiError(e), lineToken);
    }
    return;
  }

  // ─── อ่าน / read ──────────────────────────────────────────────────────────
  // Document AI OCR → สรุปเป็น TSV ด้วย rule/regex (ไม่เรียก Gemini)
  if (text === 'อ่าน' || cmd === 'read') {
    if (!docAi) {
      console.error('[line-ai-excel] MISSING_DOCUMENT_AI_CONFIG');
      await replyLineText(replyToken, 'OCR อ่านไม่สำเร็จ: MISSING_DOCUMENT_AI_CONFIG', lineToken);
      return;
    }
    console.log(`[line-ai-excel] อ่าน cmd (Document AI) | group=${groupId}`);

    const { batchId, images } = await loadLatestBatchImages(url, key, groupId);
    if (!batchId) {
      await replyLineText(replyToken, 'ยังไม่มีรูปให้อ่าน กรุณาส่งรูปเอกสารก่อน', lineToken);
      return;
    }
    if (images.length === 0) {
      console.error('[line-ai-excel] IMAGE_LOAD_FAILED | batch=' + batchId);
      await replyLineText(replyToken, 'OCR อ่านไม่สำเร็จ: IMAGE_LOAD_FAILED', lineToken);
      return;
    }

    // มีรูปคนในชุดไหม → ใช้กำหนดคอลัมน์ "รูปถ่าย"
    // เกณฑ์เบื้องต้น: ถือว่ามีรูปเสมอเมื่อมี image ในชุด (เอกสารแรงงานมักมีรูปติดเอกสาร)
    const hasPhoto = images.length > 0;

    let ocrText = '';
    try {
      ocrText = await runDocAiOnBatch(docAi, images);
      console.log(`[line-ai-excel] OCR OK | chars=${ocrText.length}`);
    } catch (e) {
      await replyLineText(replyToken, mapDocAiError(e), lineToken);
      return;
    }

    // สรุปเป็น TSV ด้วย rule/regex
    const tsv = ocrToTsv(ocrText, hasPhoto);
    console.log(`[line-ai-excel] parsed TSV | chars=${tsv.length}`);

    // บันทึกผล + mark batch read
    const nowIso = new Date().toISOString();
    try {
      await dbInsert(url, key, 'line_ai_excel_results', {
        batch_id: batchId,
        result_text: tsv,
        raw_json: { type: 'ocr_tsv', ocr_chars: ocrText.length },
      });
      await dbUpdate(
        url, key, 'line_ai_excel_batches', `id=eq.${batchId}`,
        { status: 'read', read_at: nowIso, updated_at: nowIso },
      );
    } catch (e) {
      console.warn('[line-ai-excel] save result failed:', e instanceof Error ? e.message : e);
    }

    const reply = tsv.length > 4800
      ? tsv.slice(0, 4800) + '\n\n... (ข้อมูลยาวเกิน ตัดบางส่วน — copy ส่วนที่เห็นได้เลย)'
      : tsv;
    await replyLineText(replyToken, reply, lineToken);
    return;
  }

  // ─── pdf / ทำpdf / ทำ PDF ───
  // normalize: เอา space ออก + lowercase → 'pdf' หรือ 'ทำpdf'
  const cmdNoSpace = text.replace(/\s+/g, '').toLowerCase();
  if (cmd === 'pdf' || cmdNoSpace === 'pdf' || cmdNoSpace === 'ทำpdf') {
    const batch = await findLatestCollectingBatch(url, key, groupId);
    if (!batch) {
      await replyLineText(replyToken, 'ยังไม่มีรูปสำหรับทำ PDF กรุณาส่งรูปเอกสารก่อน', lineToken);
      return;
    }
    const batchId = batch.id as string;
    const files = await dbSelect(
      url, key,
      `line_ai_excel_files?batch_id=eq.${batchId}&order=created_at.asc` +
      `&select=storage_path,mime_type`,
    );
    if (files.length === 0) {
      await replyLineText(replyToken, 'ยังไม่มีรูปสำหรับทำ PDF กรุณาส่งรูปเอกสารก่อน', lineToken);
      return;
    }

    // ดึงรูปทั้งหมดตามลำดับเวลา (created_at.asc) → เรียงหน้า PDF ตามลำดับที่ส่ง
    const images: { bytes: Uint8Array; contentType: string }[] = [];
    for (const f of files) {
      try {
        const got = await downloadFromStorage(url, key, f.storage_path as string);
        images.push(got);
      } catch (e) {
        console.warn('[line-ai-excel] storage fetch failed:', e instanceof Error ? e.message : e);
      }
    }
    if (images.length === 0) {
      await replyLineText(replyToken, 'ไม่สามารถโหลดรูปจากที่เก็บได้ กรุณาส่งรูปใหม่', lineToken);
      return;
    }

    // สร้าง PDF + อัปโหลด + signed URL
    try {
      const { pdf, pages } = await buildPdfFromImages(images);
      if (pages === 0) {
        await replyLineText(replyToken, 'สร้าง PDF ไม่สำเร็จ กรุณาลองใหม่', lineToken);
        return;
      }
      const pdfPath = `${PDF_PATH_PREFIX}/${batchId}.pdf`;
      await uploadToStorage(url, key, pdfPath, pdf, 'application/pdf');
      const signedUrl = await createSignedUrl(url, key, pdfPath, PDF_SIGNED_URL_SECONDS);

      // บันทึกผลลง results (ใช้ตารางเดิม — เรียบง่าย)
      try {
        await dbInsert(url, key, 'line_ai_excel_results', {
          batch_id: batchId,
          result_text: `PDF created: ${pdfPath} (${pages} pages)`,
          raw_json: { type: 'pdf', path: pdfPath, pages, signed_url_seconds: PDF_SIGNED_URL_SECONDS },
        });
      } catch (e) {
        console.warn('[line-ai-excel] save pdf result failed:', e instanceof Error ? e.message : e);
      }

      await replyLineText(
        replyToken,
        [
          'สร้าง PDF แล้ว',
          `จำนวนหน้า: ${pages} หน้า`,
          `เปิดไฟล์: ${signedUrl}`,
        ].join('\n'),
        lineToken,
      );
    } catch (e) {
      console.error('[line-ai-excel] PDF error:', e instanceof Error ? e.message : e);
      await replyLineText(replyToken, 'สร้าง PDF ไม่สำเร็จ กรุณาลองใหม่', lineToken);
    }
    return;
  }

  // คำสั่งอื่น — เงียบ (ไม่รบกวน)
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

  for (const ev of events) {
    try {
      if (ev.type !== 'message' || !ev.source) continue;
      const groupId = ev.source.groupId || '';
      const msgType = ev.message?.type || '';

      // ── ทำงานเฉพาะกลุ่ม control เท่านั้น — กลุ่มอื่น/แชทอื่น ignore ──
      if (!groupId || groupId !== controlGroupId) {
        console.log('[line-ai-excel] ignore non-control source');
        continue;
      }

      console.log(`[line-ai-excel] event | type=${msgType}`);

      if (msgType === 'image') {
        await handleImage(ev, ctx);
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
