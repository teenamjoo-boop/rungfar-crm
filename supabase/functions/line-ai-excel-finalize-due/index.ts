// =============================================================
// line-ai-excel-finalize-due — Supabase Edge Function (Cron)
// ตั้ง Supabase Cron ให้ POST มาที่ function นี้ทุก 1 นาที
// ทำหน้าที่: หา batch ที่ status='collecting' และ last_image_at เกิน 45 วินาที
//            → lock (finalizing) → สร้าง PDF → push LINE Flex → finalized
// =============================================================

import { PDFDocument, degrees, rgb } from 'https://esm.sh/pdf-lib@1.17.1';
// auto-rotate ด้วย Document AI OCR (shared กับ line-ai-excel-helper)
import { applyAutoRotateToBatch, effectiveRotationCW } from '../_shared/auto-rotate.ts';

// ─── Constants ───────────────────────────────────────────────────────────────
const STORAGE_BUCKET       = 'line-ai-excel-intake';
const PDF_PATH_PREFIX      = 'line-ai-excel-pdf';
const PDF_SIGNED_URL_SECS  = 30 * 24 * 60 * 60; // 30 วัน
const AUTO_FINALIZE_MS     = 30 * 1000;           // 30 วินาที (idle threshold — cron ยิงทุก 1 นาที → รอจริง 30–90 วิ)
// ต้องตรงกับ FILE_PAGE_ORDER ใน line-ai-excel-helper เสมอ
const FILE_PAGE_ORDER =
  'line_event_ts.asc.nullslast,' +
  'line_event_index.asc.nullslast,' +
  'created_at.asc,' +
  'id.asc';
const A4_W = 595.28;
const A4_H = 841.89;
const PDF_MARGIN = 24;

// ─── DB helpers ──────────────────────────────────────────────────────────────
function dbHeaders(key: string, extra: Record<string, string> = {}): Record<string, string> {
  return { 'apikey': key, 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json', ...extra };
}

async function dbSelect(url: string, key: string, path: string): Promise<Record<string, unknown>[]> {
  const res = await fetch(`${url}/rest/v1/${path}`, { headers: dbHeaders(key) });
  if (!res.ok) throw new Error(`DB select ${res.status}: ${await res.text()}`);
  return await res.json();
}

async function dbUpdate(url: string, key: string, table: string, filter: string, patch: Record<string, unknown>): Promise<void> {
  const res = await fetch(`${url}/rest/v1/${table}?${filter}`, {
    method: 'PATCH',
    headers: dbHeaders(key, { 'Prefer': 'return=minimal' }),
    body: JSON.stringify(patch),
  });
  if (!res.ok) throw new Error(`DB update ${res.status}: ${await res.text()}`);
}

async function dbInsert(url: string, key: string, table: string, row: Record<string, unknown>): Promise<void> {
  const res = await fetch(`${url}/rest/v1/${table}`, {
    method: 'POST',
    headers: dbHeaders(key, { 'Prefer': 'return=minimal' }),
    body: JSON.stringify(row),
  });
  if (!res.ok) console.warn(`[finalize-due] dbInsert ${res.status}: ${(await res.text()).slice(0, 200)}`);
}

/** Atomic: collecting → finalizing. Returns true ถ้าได้ lock */
async function tryLockBatch(url: string, key: string, batchId: string): Promise<boolean> {
  const res = await fetch(
    `${url}/rest/v1/line_ai_excel_batches?id=eq.${encodeURIComponent(batchId)}&status=eq.collecting`,
    {
      method: 'PATCH',
      headers: dbHeaders(key, { 'Prefer': 'return=representation' }),
      body: JSON.stringify({ status: 'finalizing', updated_at: new Date().toISOString() }),
    },
  );
  if (!res.ok) return false;
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0;
}

// ─── Storage helpers ──────────────────────────────────────────────────────────
async function downloadFromStorage(url: string, key: string, path: string): Promise<{ bytes: Uint8Array; contentType: string }> {
  const res = await fetch(`${url}/storage/v1/object/${STORAGE_BUCKET}/${path}`, {
    headers: { 'apikey': key, 'Authorization': `Bearer ${key}` },
  });
  if (!res.ok) throw new Error(`Storage download ${res.status}`);
  return { bytes: new Uint8Array(await res.arrayBuffer()), contentType: res.headers.get('content-type') || 'image/jpeg' };
}

async function uploadToStorage(url: string, key: string, path: string, bytes: Uint8Array, contentType: string): Promise<void> {
  const res = await fetch(`${url}/storage/v1/object/${STORAGE_BUCKET}/${path}`, {
    method: 'POST',
    headers: { 'apikey': key, 'Authorization': `Bearer ${key}`, 'Content-Type': contentType, 'x-upsert': 'true' },
    body: bytes,
  });
  if (!res.ok) throw new Error(`Storage upload ${res.status}`);
}

async function createSignedUrl(url: string, key: string, path: string, expiresIn: number): Promise<string> {
  const res = await fetch(`${url}/storage/v1/object/sign/${STORAGE_BUCKET}/${path}`, {
    method: 'POST',
    headers: dbHeaders(key),
    body: JSON.stringify({ expiresIn }),
  });
  if (!res.ok) throw new Error(`Sign URL ${res.status}`);
  const data = await res.json();
  const signed = data.signedURL || data.signedUrl || '';
  return `${url}/storage/v1${signed}`;
}

// ─── Image helpers ────────────────────────────────────────────────────────────
function detectImageType(bytes: Uint8Array): 'png' | 'jpg' | 'unknown' {
  if (bytes.length >= 4 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) return 'png';
  if (bytes.length >= 3 && bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) return 'jpg';
  return 'unknown';
}

function readJpegExifOrientation(bytes: Uint8Array): number {
  if (bytes.length < 4 || bytes[0] !== 0xFF || bytes[1] !== 0xD8) return 1;
  let offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 0xFF) break;
    const marker = bytes[offset + 1];
    const segLen = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (marker === 0xE1) {
      const base = offset + 4;
      if (base + 6 <= bytes.length &&
          bytes[base] === 0x45 && bytes[base+1] === 0x78 && bytes[base+2] === 0x69 &&
          bytes[base+3] === 0x66 && bytes[base+4] === 0x00 && bytes[base+5] === 0x00) {
        const tiff = base + 6;
        const le = bytes[tiff] === 0x49;
        const r16 = (p: number) => le ? (bytes[p] | (bytes[p+1] << 8)) : ((bytes[p] << 8) | bytes[p+1]);
        const r32 = (p: number) => (le
          ? (bytes[p] | (bytes[p+1] << 8) | (bytes[p+2] << 16) | (bytes[p+3] << 24))
          : ((bytes[p] << 24) | (bytes[p+1] << 16) | (bytes[p+2] << 8) | bytes[p+3])) >>> 0;
        if (r16(tiff + 2) !== 42) return 1;
        const ifd0 = tiff + r32(tiff + 4);
        if (ifd0 + 2 > bytes.length) return 1;
        const numEntries = r16(ifd0);
        for (let i = 0; i < numEntries; i++) {
          const ep = ifd0 + 2 + i * 12;
          if (ep + 12 > bytes.length) break;
          if (r16(ep) === 0x0112) return r16(ep + 8);
        }
      }
    }
    if (marker === 0xDA) break;
    offset += 2 + segLen;
  }
  return 1;
}

function exifToDegreesCCW(o: number): number {
  return o === 3 ? 180 : o === 6 ? 270 : o === 8 ? 90 : 0;
}

async function buildPdfFromImages(
  images: { bytes: Uint8Array; contentType: string }[],
  userRotationsCW: number[] = [],
): Promise<{ pdf: Uint8Array; pages: number }> {
  const doc = await PDFDocument.create();
  let pages = 0;
  for (let idx = 0; idx < images.length; idx++) {
    const img = images[idx];
    let kind = detectImageType(img.bytes);
    if (kind === 'unknown') {
      kind = img.contentType.includes('png') ? 'png' : img.contentType.includes('jpeg') || img.contentType.includes('jpg') ? 'jpg' : 'unknown';
    }
    let embedded;
    try {
      if (kind === 'png') embedded = await doc.embedPng(img.bytes);
      else if (kind === 'jpg') embedded = await doc.embedJpg(img.bytes);
      else { try { embedded = await doc.embedJpg(img.bytes); } catch { embedded = await doc.embedPng(img.bytes); } }
    } catch { continue; }

    const exifCCW  = exifToDegreesCCW(kind === 'jpg' ? readJpegExifOrientation(img.bytes) : 1);
    const userCCW  = (360 - (userRotationsCW[idx] ?? 0)) % 360;
    const totalCCW = (exifCCW + userCCW) % 360;

    const page = doc.addPage([A4_W, A4_H]);
    page.drawRectangle({ x: 0, y: 0, width: A4_W, height: A4_H, color: rgb(1, 1, 1) });

    const maxW = A4_W - PDF_MARGIN * 2;
    const maxH = A4_H - PDF_MARGIN * 2;
    const needsSwap = totalCCW === 90 || totalCCW === 270;
    const dispW = needsSwap ? embedded.height : embedded.width;
    const dispH = needsSwap ? embedded.width  : embedded.height;
    const scale = Math.min(maxW / dispW, maxH / dispH);
    const W = embedded.width * scale;
    const H = embedded.height * scale;
    const cx = A4_W / 2;
    const cy = A4_H / 2;
    const θ = (totalCCW * Math.PI) / 180;
    const x = cx - (W / 2) * Math.cos(θ) + (H / 2) * Math.sin(θ);
    const y = cy - (W / 2) * Math.sin(θ) - (H / 2) * Math.cos(θ);
    page.drawImage(embedded, { x, y, width: W, height: H, rotate: degrees(totalCCW) });
    pages++;
  }
  return { pdf: await doc.save(), pages };
}

// ─── LINE helpers ─────────────────────────────────────────────────────────────
async function pushPdfFlex(targetId: string, pages: number, signedUrl: string, lineToken: string): Promise<void> {
  const flexMsg = {
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
          {
            type: 'box',
            layout: 'horizontal',
            spacing: 'sm',
            alignItems: 'center',
            contents: [
              {
                type: 'image',
                url: 'https://magwqolbjmwymqxelizl.supabase.co/storage/v1/object/public/line-assets/ChatGPT%20Image%20Jun%203,%202026,%2002_52_40%20PM.png',
                size: '44px',
                aspectRatio: '1:1',
                aspectMode: 'cover',
                flex: 0,
              },
              {
                type: 'box',
                layout: 'vertical',
                flex: 1,
                spacing: 'none',
                contents: [
                  { type: 'text', text: 'เอกสาร PDF', weight: 'bold', size: 'sm', color: '#333333', wrap: false },
                  { type: 'text', text: `จำนวนรูป: ${pages} รูป`, size: 'xs', color: '#777777' },
                ],
              },
            ],
          },
          { type: 'button', style: 'primary', color: '#E53935', height: 'sm', action: { type: 'uri', label: 'เปิด PDF', uri: signedUrl } },
        ],
      },
    },
  };
  const res = await fetch('https://api.line.me/v2/bot/message/push', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${lineToken}` },
    body: JSON.stringify({ to: targetId, messages: [flexMsg] }),
  });
  if (!res.ok) {
    console.warn('[finalize-due] flex push failed, fallback text:', res.status);
    await fetch('https://api.line.me/v2/bot/message/push', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${lineToken}` },
      body: JSON.stringify({ to: targetId, messages: [{ type: 'text', text: `สร้าง PDF แล้ว\nจำนวนรูป: ${pages} รูป\nเปิดไฟล์: ${signedUrl}` }] }),
    });
  }
}

// ─── Core finalize logic ─────────────────────────────────────────────────────
async function finalizeDueBatches(url: string, key: string, lineToken: string): Promise<number> {
  const cutoff = new Date(Date.now() - AUTO_FINALIZE_MS).toISOString();

  const staleBatches = await dbSelect(
    url, key,
    `line_ai_excel_batches?status=eq.collecting` +
    `&last_image_at=lt.${encodeURIComponent(cutoff)}` +
    `&image_count=gt.0` +
    `&order=last_image_at.asc&limit=20`,
  );

  console.log(`[finalize-due] stale batches found: ${staleBatches.length}`);
  let finalized = 0;

  for (const batch of staleBatches) {
    const batchId = batch.id as string;
    const groupId = batch.group_id as string;
    console.log(`[finalize-due] processing batch=${batchId} group=${groupId}`);

    // Atomic lock
    const locked = await tryLockBatch(url, key, batchId);
    if (!locked) {
      console.log(`[finalize-due] batch=${batchId} already locked, skip`);
      continue;
    }

    try {
      // [PDF-only mode] auto-rotate ปิดชั่วคราว — ไม่เรียก Document AI OCR เพื่อประหยัดค่า Google AI
      // ถ้าต้องการเปิดใหม่: uncomment บล็อก try/catch ด้านล่าง และ comment บรรทัด log
      // try {
      //   await applyAutoRotateToBatch(url, key, batchId, { force: false });
      // } catch (e) {
      //   console.warn('[finalize-due] auto-rotate skipped:', e instanceof Error ? e.message : e);
      // }
      console.log(`[finalize-due] PDF-only mode: auto-rotate skipped batch=${batchId}`);

      // Load files (รวม rotation columns) ตาม canonical order
      const files = await dbSelect(
        url, key,
        `line_ai_excel_files?batch_id=eq.${encodeURIComponent(batchId)}` +
        `&order=${FILE_PAGE_ORDER}` +
        `&select=storage_path,mime_type,rotation_deg,rotation_locked,auto_rotation_deg`,
      );
      if (files.length === 0) {
        await dbUpdate(url, key, 'line_ai_excel_batches', `id=eq.${batchId}`, {
          status: 'cancelled', updated_at: new Date().toISOString(),
        });
        continue;
      }

      // Download images — effective rotation: manual (locked) ชนะ ไม่งั้นใช้ auto
      const images: { bytes: Uint8Array; contentType: string }[] = [];
      const rotationsCW: number[] = [];
      for (const f of files) {
        try {
          const got = await downloadFromStorage(url, key, f.storage_path as string);
          images.push({ bytes: got.bytes, contentType: (f.mime_type as string) || got.contentType });
          rotationsCW.push(effectiveRotationCW(f));
        } catch (e) {
          console.warn('[finalize-due] img download failed:', e instanceof Error ? e.message : e);
        }
      }

      if (images.length === 0) {
        await dbUpdate(url, key, 'line_ai_excel_batches', `id=eq.${batchId}`, {
          status: 'cancelled', updated_at: new Date().toISOString(),
        });
        continue;
      }

      // Build PDF
      const { pdf, pages } = await buildPdfFromImages(images, rotationsCW);
      if (pages === 0) throw new Error('PDF has 0 pages');

      // Upload + signed URL
      const pdfPath = `${PDF_PATH_PREFIX}/${batchId}.pdf`;
      await uploadToStorage(url, key, pdfPath, pdf, 'application/pdf');
      const signedUrl = await createSignedUrl(url, key, pdfPath, PDF_SIGNED_URL_SECS);

      // Update batch status
      const nowIso = new Date().toISOString();
      await dbUpdate(url, key, 'line_ai_excel_batches', `id=eq.${batchId}`, {
        status: 'finalized',
        finalized_at: nowIso,
        pdf_path: pdfPath,
        pdf_url: signedUrl,
        updated_at: nowIso,
      });

      // Save result log (non-critical)
      await dbInsert(url, key, 'line_ai_excel_results', {
        batch_id: batchId,
        result_text: `PDF auto: ${pdfPath} (${pages}p)`,
        raw_json: { type: 'pdf_auto', path: pdfPath, pages },
      });

      // Push LINE Flex
      if (groupId) await pushPdfFlex(groupId, pages, signedUrl, lineToken);

      finalized++;
      console.log(`[finalize-due] done batch=${batchId} pages=${pages}`);
    } catch (e) {
      console.error('[finalize-due] error batch=' + batchId + ':', e instanceof Error ? e.message : e);
      // Revert lock → collecting ให้ลองใหม่รอบหน้า
      await dbUpdate(url, key, 'line_ai_excel_batches', `id=eq.${batchId}`, {
        status: 'collecting', updated_at: new Date().toISOString(),
      }).catch(() => {});
    }
  }

  return finalized;
}

// ─── Main Handler ─────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  // รับ POST เท่านั้น
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  // ตรวจ Authorization header กัน spam
  // ตั้ง secret ใน Supabase Vault / env: LINE_AI_CRON_SECRET
  const cronSecret = Deno.env.get('LINE_AI_CRON_SECRET');
  if (cronSecret) {
    const auth = req.headers.get('Authorization') || req.headers.get('authorization') || '';
    const bearer = auth.replace(/^Bearer\s+/i, '');
    if (bearer !== cronSecret) {
      return new Response('Unauthorized', { status: 401 });
    }
  }

  const url       = Deno.env.get('SUPABASE_URL');
  const key       = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const lineToken = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN');

  if (!url || !key || !lineToken) {
    return new Response(JSON.stringify({ ok: false, error: 'missing secrets' }), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    });
  }

  try {
    const finalized = await finalizeDueBatches(url, key, lineToken);
    console.log(`[finalize-due] run complete, finalized=${finalized}`);
    return new Response(JSON.stringify({ ok: true, finalized }), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('[finalize-due] fatal error:', e instanceof Error ? e.message : e);
    return new Response(JSON.stringify({ ok: false, error: String(e) }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    });
  }
});
