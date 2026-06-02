// =============================================================
// _shared/auto-rotate.ts
// Auto-rotate รูปเอกสารด้วย Document AI OCR (ไม่ extract Excel)
//
// ใช้ร่วมกันโดย:
//   - line-ai-excel-helper       (คำสั่ง pdf / จบ / ปรับหมุน)
//   - line-ai-excel-finalize-due (cron auto finalize)
//
// หลักการ:
//   - ลองหมุนรูป candidate 0/90/180/270 (CW) แล้ว OCR แต่ละมุม
//   - ให้คะแนนตาม text length + ตัวอักษรไทย/อังกฤษ/เลข + keyword เอกสาร
//   - เลือกมุมที่คะแนนดีสุด "เฉพาะเมื่อชนะชัด" (มี threshold) ไม่งั้น = 0 (ไม่หมุน)
//   - cache ผลลง DB (auto_rotation_deg/confidence/checked_at) เพื่อประหยัดค่า OCR
//   - manual rotation (rotation_locked=true) ชนะเสมอ ไม่เรียก OCR
//
// ประหยัดค่า: ถ้า 0° อ่านได้ชัดอยู่แล้ว (upright) → early-exit เรียก OCR ครั้งเดียว
//
// ห้าม log: private_key / access token / signed URL เต็ม
// =============================================================

import { Image } from 'https://deno.land/x/imagescript@1.2.15/mod.ts';

const STORAGE_BUCKET = 'line-ai-excel-intake';

// ต้องตรงกับ FILE_PAGE_ORDER ในทั้งสอง function
const FILE_PAGE_ORDER =
  'line_event_ts.asc.nullslast,' +
  'line_event_index.asc.nullslast,' +
  'created_at.asc,' +
  'id.asc';

// downscale ก่อน OCR เพื่อลด memory/CPU/ค่าใช้จ่าย (orientation detection ไม่ต้องการความละเอียดสูง)
const OCR_MAX_DIM = 1000;
const OCR_JPEG_QUALITY = 80;

// keyword เอกสารแรงงานต่างด้าว — ใช้ช่วยตัดสินว่าหน้าหันถูกทาง
const DOC_KEYWORDS = [
  'ใบรับคำขอ', 'ใบอนุญาตทำงาน', 'ใบอนุญาต', 'หนังสือเดินทาง',
  'สัญชาติ', 'เลขประจำตัว', 'นายจ้าง', 'คำขอ', 'กรมการจัดหางาน',
  'Work Permit', 'WORK PERMIT', 'Passport', 'PASSPORT',
  'Nationality', 'NATIONALITY', 'Employer', 'EMPLOYER', 'Alien', 'Application',
];

// threshold สำหรับตัดสินใจหมุน
const MIN_BEST_SCORE   = 25;   // ถ้าคะแนนดีสุดยังต่ำกว่านี้ = OCR อ่านอะไรไม่ค่อยได้ → ไม่หมุน
const WIN_MARGIN       = 1.25; // คะแนนดีสุดต้องชนะอันดับสองอย่างน้อย 25%
const UPRIGHT_TEXT_LEN = 80;   // 0° ถ้าได้ข้อความยาวพอ + keyword → ถือว่า upright (early exit)
const UPRIGHT_KEYWORDS = 2;

export interface DocAiConfig {
  projectId:   string;
  location:    string;
  processorId: string;
  saJson:      Record<string, unknown>;
}

export interface AutoRotateFileResult {
  fileId:      string;
  pageNo:      number;        // ลำดับหน้า (1..N) ตาม canonical order
  source:      'manual' | 'auto' | 'auto-cache' | 'auto-fail' | 'none';
  rotationDeg: number;        // CW degrees ที่จะใช้จริง
  confidence:  number;        // 0..1 (สำหรับ auto)
  reason:      string;
}

// ─── base64 helpers ─────────────────────────────────────────────────────────
function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}
function base64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}
function base64UrlEncode(bytes: Uint8Array): string {
  return bytesToBase64(bytes).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// ─── Config ─────────────────────────────────────────────────────────────────
export function readDocAiConfig(): DocAiConfig | null {
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
    console.error('[auto-rotate] SA JSON decode failed:', e instanceof Error ? e.message : 'parse error');
    return null;
  }
}

// ─── Google OAuth (service account JWT) ──────────────────────────────────────
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const der = base64ToBytes(body);
  return await crypto.subtle.importKey(
    'pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
}

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
  const sigBuf = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, enc.encode(signingInput));
  const jwt = `${signingInput}.${base64UrlEncode(new Uint8Array(sigBuf))}`;

  const res = await fetch(tokenUri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }),
  });
  if (!res.ok) {
    console.error('[auto-rotate] OAuth token failed:', res.status);
    throw new Error('DOCUMENT_AI_AUTH_ERROR');
  }
  const data = await res.json();
  if (!data.access_token) throw new Error('DOCUMENT_AI_AUTH_ERROR');
  return data.access_token as string;
}

// ─── Document AI OCR (image → text) ──────────────────────────────────────────
async function ocrImage(cfg: DocAiConfig, accessToken: string, jpegBytes: Uint8Array): Promise<string> {
  const endpoint =
    `https://${cfg.location}-documentai.googleapis.com/v1/projects/${cfg.projectId}` +
    `/locations/${cfg.location}/processors/${cfg.processorId}:process`;
  const res = await fetch(endpoint, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ rawDocument: { content: bytesToBase64(jpegBytes), mimeType: 'image/jpeg' } }),
  });
  if (!res.ok) {
    console.error('[auto-rotate] Document AI HTTP', res.status);
    throw new Error(`DOCUMENT_AI_API_ERROR:${res.status}`);
  }
  const data = await res.json();
  return (data?.document?.text as string) || '';
}

// ─── Storage + DB helpers ────────────────────────────────────────────────────
function dbHeaders(key: string, extra: Record<string, string> = {}): Record<string, string> {
  return { 'apikey': key, 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json', ...extra };
}
async function dbSelect(url: string, key: string, path: string): Promise<Record<string, unknown>[]> {
  const res = await fetch(`${url}/rest/v1/${path}`, { headers: dbHeaders(key) });
  if (!res.ok) throw new Error(`DB select ${res.status}`);
  return await res.json();
}
async function dbUpdate(url: string, key: string, filter: string, patch: Record<string, unknown>): Promise<void> {
  const res = await fetch(`${url}/rest/v1/line_ai_excel_files?${filter}`, {
    method: 'PATCH',
    headers: dbHeaders(key, { 'Prefer': 'return=minimal' }),
    body: JSON.stringify(patch),
  });
  if (!res.ok) console.warn('[auto-rotate] dbUpdate failed:', res.status);
}
async function storageDownload(url: string, key: string, path: string): Promise<Uint8Array> {
  const res = await fetch(`${url}/storage/v1/object/${STORAGE_BUCKET}/${path}`, {
    headers: { 'apikey': key, 'Authorization': `Bearer ${key}` },
  });
  if (!res.ok) throw new Error(`Storage download ${res.status}`);
  return new Uint8Array(await res.arrayBuffer());
}

// ─── Scoring ─────────────────────────────────────────────────────────────────
interface TextScore { score: number; textLen: number; keywordHits: number; }

function scoreText(text: string): TextScore {
  const t = text || '';
  const compactLen = t.replace(/\s+/g, '').length;
  const thai  = (t.match(/[฀-๿]/g) || []).length; // อักษรไทย
  const latin = (t.match(/[A-Za-z]/g) || []).length;
  const digit = (t.match(/[0-9]/g) || []).length;
  let kw = 0;
  for (const k of DOC_KEYWORDS) if (t.includes(k)) kw++;
  const score = compactLen + (thai + latin + digit) * 0.3 + kw * 60;
  return { score, textLen: compactLen, keywordHits: kw };
}

// ─── Image rotation (ImageScript) ────────────────────────────────────────────
/**
 * หมุนภาพตามเข็มนาฬิกา (CW) cwDeg องศา แล้ว encode เป็น JPEG เล็ก
 * NOTE: ImageScript.rotate(deg) = clockwise. ใช้ทิศเดียวกับ pdf-lib pipeline (CW)
 *       ถ้าทิศกลับ ผลคะแนนจะต่ำและไม่ถูกเลือกอยู่ดี (conservative)
 */
async function rotateCwToJpeg(base: Image, cwDeg: number): Promise<Uint8Array> {
  const img = base.clone();
  if (cwDeg !== 0) img.rotate(cwDeg);
  return await img.encodeJPEG(OCR_JPEG_QUALITY);
}

/**
 * ตรวจมุมหมุนที่ดีที่สุด (CW) จากรูปต้นฉบับ
 * คืน rotationDeg ∈ {0,90,180,270}, confidence 0..1, reason
 * ถ้าไม่มั่นใจ → rotationDeg = 0
 */
async function detectBestRotationCW(
  cfg: DocAiConfig, accessToken: string, imageBytes: Uint8Array,
): Promise<{ rotationDeg: number; confidence: number; reason: string }> {
  let base: Image;
  try {
    // Image.decode รองรับ PNG/JPEG (รูปจาก LINE) — คืน Image นิ่ง
    base = await Image.decode(imageBytes);
    if (!base || typeof base.width !== 'number') {
      return { rotationDeg: 0, confidence: 0, reason: 'decode_not_image' };
    }
  } catch (e) {
    console.warn('[auto-rotate] decode failed:', e instanceof Error ? e.message : e);
    return { rotationDeg: 0, confidence: 0, reason: 'decode_failed' };
  }

  // downscale เพื่อประหยัด
  try {
    const maxSide = Math.max(base.width, base.height);
    if (maxSide > OCR_MAX_DIM) {
      if (base.width >= base.height) base.resize(OCR_MAX_DIM, Image.RESIZE_AUTO);
      else base.resize(Image.RESIZE_AUTO, OCR_MAX_DIM);
    }
  } catch (e) {
    console.warn('[auto-rotate] resize failed (continue full-size):', e instanceof Error ? e.message : e);
  }

  const candidates = [0, 90, 180, 270];
  const results: { cw: number; s: TextScore }[] = [];

  for (const cw of candidates) {
    let text = '';
    try {
      const jpeg = await rotateCwToJpeg(base, cw);
      text = await ocrImage(cfg, accessToken, jpeg);
    } catch (e) {
      console.warn(`[auto-rotate] OCR candidate ${cw}° failed:`, e instanceof Error ? e.message : e);
      results.push({ cw, s: { score: -1, textLen: 0, keywordHits: 0 } });
      continue;
    }
    const s = scoreText(text);
    console.log(`[auto-rotate] cand cw=${cw}° score=${s.score.toFixed(1)} len=${s.textLen} kw=${s.keywordHits}`);
    results.push({ cw, s });

    // early-exit: 0° อ่านชัดอยู่แล้ว → ประหยัด ไม่ต้องลองมุมอื่น
    if (cw === 0 && s.textLen >= UPRIGHT_TEXT_LEN && s.keywordHits >= UPRIGHT_KEYWORDS) {
      return { rotationDeg: 0, confidence: 0.9, reason: 'upright_early_exit' };
    }
  }

  const sorted = [...results].sort((a, b) => b.s.score - a.s.score);
  const best = sorted[0];
  const second = sorted[1] || { cw: -1, s: { score: 0, textLen: 0, keywordHits: 0 } };

  // best เป็น 0° อยู่แล้ว
  if (best.cw === 0) {
    return { rotationDeg: 0, confidence: 0.6, reason: 'best_is_upright' };
  }
  // OCR อ่านอะไรแทบไม่ได้เลย → ไม่หมุน
  if (best.s.score < MIN_BEST_SCORE) {
    return { rotationDeg: 0, confidence: 0, reason: 'low_text_all_angles' };
  }
  // ชนะไม่ชัดพอ → ไม่หมุน (กันหมุนมั่ว)
  if (best.s.score < second.s.score * WIN_MARGIN) {
    return { rotationDeg: 0, confidence: 0, reason: 'no_clear_winner' };
  }
  const confidence = Math.max(0, Math.min(1, (best.s.score - second.s.score) / (best.s.score || 1)));
  return { rotationDeg: best.cw, confidence, reason: 'rotated' };
}

// ─── Public: apply auto-rotate to a whole batch (cache-aware) ─────────────────
/**
 * ตรวจ + cache auto rotation ของทุกไฟล์ใน batch ตาม canonical order
 *  - manual (rotation_locked=true) → ข้าม OCR, source='manual'
 *  - มี cache (auto_rotation_checked_at) และไม่ force → ใช้ cache
 *  - ไม่งั้น → OCR detect + บันทึก cache
 *  - ถ้าไม่มี Document AI config → source='none', ใช้ค่าเดิม/0 (ยังสร้าง PDF ได้)
 *  - error ใด ๆ → fallback rotation เดิม/0 ไม่ throw
 *
 * คืน array ตามลำดับหน้า (page 1..N)
 */
export async function applyAutoRotateToBatch(
  url: string, key: string, batchId: string, opts: { force?: boolean } = {},
): Promise<AutoRotateFileResult[]> {
  const force = opts.force === true;
  const cfg = readDocAiConfig();

  let files: Record<string, unknown>[] = [];
  try {
    files = await dbSelect(
      url, key,
      `line_ai_excel_files?batch_id=eq.${encodeURIComponent(batchId)}` +
      `&order=${FILE_PAGE_ORDER}` +
      `&select=id,storage_path,rotation_deg,rotation_locked,auto_rotation_deg,auto_rotation_confidence,auto_rotation_checked_at`,
    );
  } catch (e) {
    console.warn('[auto-rotate] load files failed:', e instanceof Error ? e.message : e);
    return [];
  }

  const out: AutoRotateFileResult[] = [];
  let accessToken: string | null = null;

  for (let i = 0; i < files.length; i++) {
    const f = files[i];
    const fileId = f.id as string;
    const pageNo = i + 1;
    const manualLocked = f.rotation_locked === true;
    const manualDeg = typeof f.rotation_deg === 'number' ? f.rotation_deg : 0;
    const cachedAuto = typeof f.auto_rotation_deg === 'number' ? f.auto_rotation_deg : null;
    const cachedConf = typeof f.auto_rotation_confidence === 'number' ? f.auto_rotation_confidence : 0;
    const checked = f.auto_rotation_checked_at != null;

    // 1) manual ชนะเสมอ — ห้าม OCR override
    if (manualLocked) {
      out.push({ fileId, pageNo, source: 'manual', rotationDeg: manualDeg, confidence: 1, reason: 'manual_locked' });
      continue;
    }

    // 2) ไม่มี config → ไม่ทำ OCR
    if (!cfg) {
      out.push({ fileId, pageNo, source: 'none', rotationDeg: cachedAuto ?? 0, confidence: cachedConf, reason: 'no_docai_config' });
      continue;
    }

    // 3) มี cache และไม่ force → ใช้ cache
    if (checked && !force) {
      out.push({ fileId, pageNo, source: 'auto-cache', rotationDeg: cachedAuto ?? 0, confidence: cachedConf, reason: 'cache_hit' });
      continue;
    }

    // 4) ต้อง OCR detect
    try {
      if (!accessToken) accessToken = await getGoogleAccessToken(cfg.saJson);
      const bytes = await storageDownload(url, key, f.storage_path as string);
      const det = await detectBestRotationCW(cfg, accessToken, bytes);
      await dbUpdate(url, key, `id=eq.${fileId}`, {
        auto_rotation_deg: det.rotationDeg,
        auto_rotation_confidence: det.confidence,
        auto_rotation_checked_at: new Date().toISOString(),
      });
      console.log(`[auto-rotate] batch=${batchId} page=${pageNo} → ${det.rotationDeg}° (${det.reason}, conf=${det.confidence.toFixed(2)})`);
      out.push({ fileId, pageNo, source: 'auto', rotationDeg: det.rotationDeg, confidence: det.confidence, reason: det.reason });
    } catch (e) {
      console.warn(`[auto-rotate] detect failed batch=${batchId} page=${pageNo}:`, e instanceof Error ? e.message : e);
      // fallback: ใช้ค่า cache เดิม/0 — ไม่ทำให้ PDF fail
      out.push({ fileId, pageNo, source: 'auto-fail', rotationDeg: cachedAuto ?? 0, confidence: cachedConf, reason: 'ocr_error' });
    }
  }

  return out;
}

/**
 * คำนวณมุมหมุนที่ใช้จริง (CW) จาก file record
 *   - locked (manual) → rotation_deg
 *   - ไม่งั้น → auto_rotation_deg ?? 0
 */
export function effectiveRotationCW(file: Record<string, unknown>): number {
  if (file.rotation_locked === true) {
    return typeof file.rotation_deg === 'number' ? file.rotation_deg : 0;
  }
  return typeof file.auto_rotation_deg === 'number' ? file.auto_rotation_deg : 0;
}
