// ============================================================================
// STAGE STORAGE-CLEANUP — storage-cleanup
//
// ล้างไฟล์ใน Storage ที่ไม่ใช้แล้ว (เรียกจาก pg_cron ทุกวัน หรือสั่งเองผ่าน
// public.app_storage_cleanup_kick(run) ใน SQL Editor)
//
//   รายการไฟล์ = public.app_storage_cleanup_candidates(line_days, orphan_hours)
//     1) ไฟล์กำพร้าใน customer-documents / customer-photos (ไม่มีเอกสาร/รูปแรงงานอ้างถึง)
//     2) ไฟล์ระบบสร้าง PDF/Excel ทาง LINE + กล่องรับเอกสาร LINE ที่เกินอายุ
//   ❌ ไม่แตะ line-assets / bucket อื่น · ไม่ลบแถวในตาราง
//
// Security
//   * Verify JWT = OFF เพราะตรวจ token เอง: header x-cleanup-token ต้องตรงกับ
//     Vault secret `storage_cleanup_token` (ตรวจผ่าน RPC service_role-only)
//   * service-role key อยู่ใน Edge runtime เท่านั้น ไม่ส่งออก/ไม่ log
//   * POST เท่านั้น · body ≤ 1 KiB · bucket allowlist ซ้ำอีกชั้นก่อนลบ
//   * ค่าเริ่มต้น = นับอย่างเดียว (run:false) ต้องส่ง run:true ถึงจะลบจริง
//   * audit_logs บันทึกแค่จำนวน/ขนาด — ไม่มี path ไฟล์
// ============================================================================

const ALLOWED_BUCKETS = new Set([
  'customer-documents', 'customer-photos', 'line-ai-excel-intake', 'line-doc-inbox',
]);
const DEFAULT_LINE_DAYS = 3;
const DEFAULT_ORPHAN_HOURS = 24;
const DELETE_CHUNK = 100;
const MAX_BODY_BYTES = 1024;

type Candidate = { bucket: string; name: string; reason: string; size_bytes: number };

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

function clampInt(v: unknown, def: number, min: number, max: number): number {
  const n = typeof v === 'number' ? Math.floor(v) : NaN;
  return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : def;
}

async function rpc(url: string, key: string, fn: string, args: unknown): Promise<unknown> {
  const r = await fetch(`${url}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(args),
  });
  if (!r.ok) throw new Error(`rpc_${fn}_${r.status}`);
  return await r.json();
}

async function removeChunk(url: string, key: string, bucket: string, names: string[]): Promise<number> {
  const r = await fetch(`${url}/storage/v1/object/${encodeURIComponent(bucket)}`, {
    method: 'DELETE',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ prefixes: names }),
  });
  if (!r.ok) throw new Error(`storage_delete_${r.status}`);
  const out = await r.json().catch(() => []);
  return Array.isArray(out) ? out.length : 0;
}

function summarize(list: Candidate[]) {
  const by: Record<string, { files: number; mb: number }> = {};
  for (const c of list) {
    const k = `${c.bucket}:${c.reason}`;
    by[k] = by[k] || { files: 0, mb: 0 };
    by[k].files++;
    by[k].mb += (c.size_bytes || 0) / 1048576;
  }
  for (const k of Object.keys(by)) by[k].mb = Math.round(by[k].mb * 10) / 10;
  return by;
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json(405, { ok: false, error: 'method_not_allowed' });

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return json(500, { ok: false, error: 'server_not_configured' });

  // ── auth: token จาก Vault ──
  const token = req.headers.get('x-cleanup-token') || '';
  if (token.length < 32 || token.length > 200) return json(401, { ok: false, error: 'unauthorized' });
  try {
    const ok = await rpc(url, key, 'app_storage_cleanup_check_token', { p_token: token });
    if (ok !== true) return json(401, { ok: false, error: 'unauthorized' });
  } catch (_) {
    return json(500, { ok: false, error: 'auth_check_failed' });
  }

  // ── body ──
  let body: Record<string, unknown> = {};
  try {
    const raw = await req.text();
    if (raw.length > MAX_BODY_BYTES) return json(413, { ok: false, error: 'body_too_large' });
    body = raw ? JSON.parse(raw) : {};
  } catch (_) {
    return json(400, { ok: false, error: 'invalid_json' });
  }
  const run = body.run === true;
  const lineDays = clampInt(body.line_days, DEFAULT_LINE_DAYS, 1, 90);
  const orphanHours = clampInt(body.orphan_hours, DEFAULT_ORPHAN_HOURS, 1, 24 * 30);

  // ── candidates ──
  let list: Candidate[] = [];
  try {
    const res = await rpc(url, key, 'app_storage_cleanup_candidates', {
      p_line_days: lineDays, p_orphan_hours: orphanHours,
    });
    list = (Array.isArray(res) ? res : []).filter((c: Candidate) =>
      c && ALLOWED_BUCKETS.has(c.bucket) && typeof c.name === 'string' && c.name.length > 0);
  } catch (_) {
    return json(500, { ok: false, error: 'candidates_failed' });
  }

  const found = { files: list.length, mb: Math.round(list.reduce((a, c) => a + (c.size_bytes || 0), 0) / 104857.6) / 10 };
  let deleted = 0;
  let failedChunks = 0;

  if (run && list.length) {
    const byBucket = new Map<string, string[]>();
    for (const c of list) {
      if (!byBucket.has(c.bucket)) byBucket.set(c.bucket, []);
      byBucket.get(c.bucket)!.push(c.name);
    }
    for (const [bucket, names] of byBucket) {
      for (let i = 0; i < names.length; i += DELETE_CHUNK) {
        try {
          deleted += await removeChunk(url, key, bucket, names.slice(i, i + DELETE_CHUNK));
        } catch (_) {
          failedChunks++;
        }
      }
    }
  }

  const result = {
    ok: failedChunks === 0,
    run,
    line_days: lineDays,
    orphan_hours: orphanHours,
    found,
    deleted,
    failed_chunks: failedChunks,
    by: summarize(list),
  };

  // ── audit (เฉพาะตอนลบจริงและมีไฟล์) — ไม่มี path ──
  if (run && list.length) {
    try {
      await rpc(url, key, 'app_storage_cleanup_log', {
        p_detail: { found: result.found, deleted, failed_chunks: failedChunks, by: result.by, line_days: lineDays },
      });
    } catch (_) { /* audit best-effort */ }
  }

  return json(200, result);
});
