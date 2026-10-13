// =============================================================
// employer-share-view — หน้าลิงก์ให้นายจ้างดูข้อมูลแรงงาน (read-only, ไม่ต้องล็อกอิน)
// Stage SHARE-001
//
// บทบาท:
//   หน้าเว็บ share.html ส่ง token จากลิงก์มา → ฟังก์ชันนี้คืน "เฉพาะ" ข้อมูลแรงงาน
//   ของนายจ้างเจ้าของลิงก์ + ลิงก์รูปชั่วคราว (signed URL อายุสั้น)
//
//   POST { t }            → รายชื่อแรงงาน + วันหมดอายุ + รูปแรงงาน + id เอกสารที่เปิดดูได้
//   POST { t, doc_id }    → ลิงก์ชั่วคราวของเอกสาร 1 ชิ้น (ต้องเป็นของแรงงานนายจ้างนี้เท่านั้น)
//   Stage SHARE-GROUP: ลิงก์รวมของกลุ่ม (group_share_links) — แสดงแรงงานทุกคนในกลุ่มจากหลายนายจ้าง
//   Stage SHARE-S6: POST { t|c, worker_id } → รูปตัวอย่างเอกสาร (ลิงก์ชั่วคราว) ของแรงงานคนนั้น
//   Stage SHARE-S4: ส่ง { c } (รหัสลิงก์สั้น = 64 บิตแรกของ token, base62) แทน { t } ได้
//   Stage SHARE-FAST: ดึงข้อมูลที่ไม่ขึ้นต่อกันพร้อมกัน (เดิมทีละขั้น ~11 รอบ → ~4 รอบ) · นับจำนวนเปิดดูหลังตอบกลับ
//   Stage SHARE-GROUP-BANNER: ลิงก์กลุ่มใช้รูปพื้นหลังของกลุ่มเอง (documents owner_type='group') ก่อน
//   Stage SHARE-SCALE: โหลดเอกสารเป็นชุดละ 150 คน (รองรับลิงก์ที่มีแรงงานหลายร้อยคน)
//   Stage SHARE-STATUS: ส่ง "สถานะงาน" (customers.status_note) ให้หน้าลิงก์แสดงด้านขวาของแต่ละคน
//
// ความปลอดภัย:
//   * verify_jwt = false — ฟังก์ชันตรวจ token เอง (pattern เดียวกับ n8n-read-api: Edge ตรวจเอง)
//   * token ต้องเป็น hex 64 ตัว + ต้องมีแถว active ใน employer_share_links (ไม่ revoked / ไม่หมดอายุ)
//   * ข้อมูลทุกอย่างดึงฝั่ง server ด้วย service role — ❌ ไม่รับ employer_id / path ใด ๆ จาก client
//   * คืนเฉพาะ field ที่อนุญาต (whitelist) — ❌ ไม่คืน storage_path / bucket / service key / เบอร์โทร / ค่าธรรมเนียม
//   * เอกสารเปิดได้ทุกประเภทของแรงงานที่ไม่ถูกลบ ยกเว้นเอกสารการเงินของบริษัท (ใบเสร็จ / หลักฐานชำระเงิน)
//     — Stage S2: เดิมเปิดได้เฉพาะ passport / visa / work permit
//   * signed URL อายุ 15 นาที
//
// ❌ ไม่เขียนข้อมูลธุรกิจใด ๆ — เขียนแค่ last_viewed_at / view_count ของลิงก์ (best-effort)
// =============================================================

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SIGN_EXPIRES_SEC   = 900;                 // 15 นาที
const PHOTO_BUCKET       = 'customer-photos';
const DOC_BUCKET         = 'customer-documents';
const LEGACY_PHOTO_MAX   = 400_000;             // รูป base64 เดิมใหญ่กว่านี้ไม่ส่ง (กันหน้าเว็บช้า)
const LEGACY_DOC_MAX     = 8_000_000;
const TOKEN_RE           = /^[0-9a-f]{64}$/;

// กลุ่มเอกสารที่ให้นายจ้างเปิดดูได้ (doc_type ใน public.documents)
const DOC_GROUPS: Record<string, string[]> = {
  passport: ['passport_photo', 'passport', 'ci'],
  visa:     ['visa'],
  wp:       ['wp', 'work_permit'],
};
const PROFILE_DOC_TYPES = ['profile_photo', 'photo'];
// Stage S2: ไม่ให้นายจ้างเห็นเอกสารการเงินของบริษัท
const HIDDEN_DOC_TYPES = ['receipt', 'payment_proof'];
const MAX_FILES_PER_WORKER = 80;
// Stage SHARE-S3: รูปพื้นหลังแถบบนของนายจ้าง (เอกสารนายจ้าง doc_type นี้ ล่าสุด 1 รูป)
const BANNER_DOC_TYPE = 'share_banner';
const docVisible = (t: string | null): boolean => !!t && !HIDDEN_DOC_TYPES.includes(t);

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

function svcHeaders(key: string, extra: Record<string, string> = {}): Record<string, string> {
  return { 'apikey': key, 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json', ...extra };
}

async function rest<T = unknown>(url: string, key: string, path: string): Promise<{ ok: boolean; status: number; data: T | null }> {
  const res = await fetch(`${url}/rest/v1/${path}`, { headers: svcHeaders(key) });
  let data: T | null = null;
  try { data = await res.json() as T; } catch { data = null; }
  return { ok: res.ok, status: res.status, data };
}

const asDate = (v: unknown): string | null => {
  if (v == null) return null;
  const s = String(v).trim();
  return /^\d{4}-\d{2}-\d{2}/.test(s) ? s.slice(0, 10) : null;
};

// ─── ตรวจ token → แถวลิงก์ที่ active ─────────────────────────────────────────
interface LinkRow {
  id: number; employer_id: number | null; expires_at: string | null; view_count: number;
  group_id?: number | null; kind?: 'employer' | 'group';   // Stage SHARE-GROUP
}
const linkTable = (l: LinkRow) => l.kind === 'group' ? 'group_share_links' : 'employer_share_links';
// ขอบเขตแรงงานที่ลิงก์นี้เห็น: ตามนายจ้าง หรือ ตามกลุ่ม
const linkScope = (l: LinkRow) => l.kind === 'group' ? `group_id=eq.${l.group_id}` : `employer_id=eq.${l.employer_id}`;

// ค้นหาแถวลิงก์ในตารางนายจ้างก่อน แล้วตารางกลุ่ม (filter = token=eq.… หรือ token=like.…*)
async function findLink(url: string, key: string, filter: string, limit: number): Promise<LinkRow | null> {
  const tries: [string, string, 'employer' | 'group'][] = [
    ['employer_share_links', 'id,employer_id,expires_at,view_count', 'employer'],
    ['group_share_links', 'id,group_id,expires_at,view_count', 'group'],
  ];
  // Stage SHARE-FAST: ถามทั้ง 2 ตารางพร้อมกัน (ลำดับความสำคัญเหมือนเดิม: นายจ้างก่อน แล้วกลุ่ม)
  const res = await Promise.all(tries.map(([table, cols]) =>
    rest<LinkRow[]>(url, key, `${table}?${filter}&revoked_at=is.null&select=${cols}&limit=${limit}`)));
  for (let i = 0; i < tries.length; i++) {
    const r = res[i], kind = tries[i][2];
    if (!r.ok || !Array.isArray(r.data) || !r.data.length) continue;   // ตารางกลุ่มยังไม่ถูกสร้าง = ข้าม
    if (r.data.length !== 1) return null;                             // รหัสซ้ำ = ใช้ไม่ได้
    const row = { ...r.data[0], kind } as LinkRow;
    if (kind === 'group') row.employer_id = null;
    if (row.expires_at && new Date(row.expires_at).getTime() < Date.now()) return null;
    return row;
  }
  return null;
}

async function getLink(url: string, key: string, token: string): Promise<LinkRow | null> {
  if (!TOKEN_RE.test(token)) return null;
  return await findLink(url, key, `token=eq.${token}`, 1);
}

// ─── Stage SHARE-S4: ลิงก์สั้น — รหัส base62 (≤11 ตัว) = 16 ตัวแรกของ token (64 บิต) ─────
const B62 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
function codeToHex(c: string): string | null {
  if (!/^[0-9A-Za-z]{6,16}$/.test(c)) return null;
  let n = 0n;
  for (const ch of c) n = n * 62n + BigInt(B62.indexOf(ch));
  if (n >= (1n << 64n)) return null;
  return n.toString(16).padStart(16, '0');
}

async function getLinkByCode(url: string, key: string, code: string): Promise<LinkRow | null> {
  const hex = codeToHex(code);
  if (!hex) return null;
  return await findLink(url, key, `token=like.${hex}*`, 2);
}

async function touchLink(url: string, key: string, link: LinkRow): Promise<void> {
  try {
    await fetch(`${url}/rest/v1/${linkTable(link)}?id=eq.${link.id}`, {
      method: 'PATCH',
      headers: svcHeaders(key, { 'Prefer': 'return=minimal' }),
      body: JSON.stringify({ last_viewed_at: new Date().toISOString(), view_count: (link.view_count || 0) + 1 }),
    });
  } catch { /* best-effort */ }
}

// Stage SHARE-FAST: งานเบื้องหลังหลังส่งคำตอบแล้ว (นับจำนวนเปิดดู) — ผู้ใช้ไม่ต้องรอ
function background(p: Promise<unknown>): void {
  const er = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } }).EdgeRuntime;
  try { if (er && typeof er.waitUntil === 'function') { er.waitUntil(p); return; } } catch { /* ignore */ }
  p.catch(() => { /* best-effort */ });
}

// ─── Signed URL (เดี่ยว / หลายไฟล์) ───────────────────────────────────────────
async function signOne(url: string, key: string, bucket: string, path: string): Promise<string | null> {
  const res = await fetch(`${url}/storage/v1/object/sign/${bucket}/${path}`, {
    method: 'POST', headers: svcHeaders(key), body: JSON.stringify({ expiresIn: SIGN_EXPIRES_SEC }),
  });
  if (!res.ok) return null;
  const d = await res.json().catch(() => null);
  return d && d.signedURL ? `${url}/storage/v1${d.signedURL}` : null;
}

async function signMany(url: string, key: string, bucket: string, paths: string[]): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  if (!paths.length) return out;
  const res = await fetch(`${url}/storage/v1/object/sign/${bucket}`, {
    method: 'POST', headers: svcHeaders(key), body: JSON.stringify({ expiresIn: SIGN_EXPIRES_SEC, paths }),
  });
  if (!res.ok) return out;
  const arr = await res.json().catch(() => []);
  if (Array.isArray(arr)) {
    for (const it of arr) {
      if (it && it.path && it.signedURL && !it.error) out.set(it.path, `${url}/storage/v1${it.signedURL}`);
    }
  }
  return out;
}

// Stage SHARE-FAST: เซ็นหลายไฟล์หลาย bucket พร้อมกัน → key `${bucket}/${path}`
async function signGrouped(url: string, key: string, req: Map<string, string[]>): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  const parts = await Promise.all([...req].map(async ([b, paths]) => [b, await signMany(url, key, b, paths)] as const));
  for (const [b, m] of parts) for (const [p, u] of m) out.set(`${b}/${p}`, u);
  return out;
}

// ─── ข้อมูลแรงงานของนายจ้าง ────────────────────────────────────────────────────
interface Cust {
  id: number; employer_id?: number | null; name: string | null; name_th: string | null; nationality: string | null;
  passport_no: string | null; exp_passport: unknown; exp_visa: unknown; exp_wp: unknown;
  next_90: unknown; exp_mou: unknown; photo: string | null;
  alien_id?: string | null; license_no?: string | null; wp_no?: string | null; dob?: unknown; worker_category?: string | null;
  status_note?: string | null;   // Stage SHARE-STATUS
  photo_storage_bucket: string | null; photo_storage_path: string | null;
}
interface Doc {
  id: number; customer_id: number | null; owner_type: string | null; owner_id: number | null;
  doc_type: string | null; doc_expiry: unknown; storage_bucket: string | null; storage_path: string | null;
  created_at: string | null; doc_name?: string | null; file_type?: string | null; mime_type?: string | null;
}

const CUST_COLS = 'id,employer_id,name,name_th,nationality,passport_no,exp_passport,exp_visa,exp_wp,next_90,exp_mou,' +
                  'photo,photo_storage_bucket,photo_storage_path';
// Stage S2: ข้อมูลส่วนตัวเพิ่ม (❌ ไม่มีเบอร์โทร / ค่าธรรมเนียม / หมายเหตุภายใน)
const CUST_COLS_EXT = CUST_COLS + ',alien_id,license_no,wp_no,dob,worker_category,status_note';   // Stage SHARE-STATUS: + สถานะงาน (ข้อความที่เจ้าหน้าที่เขียน)

async function loadWorkers(url: string, key: string, scope: string): Promise<Cust[]> {
  const q = (cols: string) => `customers?${scope}&select=${cols}&order=name.asc&limit=1000`;
  let r = await rest<Cust[]>(url, key, q(CUST_COLS_EXT) + '&deleted_at=is.null');
  if (!r.ok) r = await rest<Cust[]>(url, key, q(CUST_COLS) + '&deleted_at=is.null');   // ยังไม่มีคอลัมน์ worker_category
  if (!r.ok) r = await rest<Cust[]>(url, key, q(CUST_COLS));                          // environment ที่ยังไม่มี deleted_at
  if (!r.ok || !Array.isArray(r.data)) throw new Error(`customers ${r.status}`);
  return r.data;
}

// Stage SHARE-SCALE: แบ่งแรงงานเป็นชุดละ 150 คน ดึงพร้อมกัน
//   กัน URL ยาวเกิน (ลิงก์ที่มีแรงงานหลายร้อยคน) และกันเอกสารถูกตัดที่ 5000 แถวต่อครั้ง
const DOC_CHUNK = 150;
async function loadDocs(url: string, key: string, ids: number[]): Promise<Doc[]> {
  if (!ids.length) return [];
  const parts: number[][] = [];
  for (let i = 0; i < ids.length; i += DOC_CHUNK) parts.push(ids.slice(i, i + DOC_CHUNK));
  const res = await Promise.all(parts.map(p => loadDocsChunk(url, key, p)));
  const seen = new Set<number>();
  const out: Doc[] = [];
  for (const list of res) for (const d of list) { if (!seen.has(d.id)) { seen.add(d.id); out.push(d); } }
  return out;   // แรงงาน 1 คนอยู่ชุดเดียว → ลำดับใหม่→เก่าต่อคนยังเหมือนเดิม
}

async function loadDocsChunk(url: string, key: string, ids: number[]): Promise<Doc[]> {
  if (!ids.length) return [];
  const list = ids.join(',');
  const hidden = HIDDEN_DOC_TYPES.join(',');
  const sel = 'select=id,customer_id,owner_type,owner_id,doc_type,doc_name,file_type,mime_type,doc_expiry,storage_bucket,storage_path,created_at';
  let r = await rest<Doc[]>(url, key,
    `documents?or=(customer_id.in.(${list}),and(owner_type.eq.customer,owner_id.in.(${list})))` +
    `&doc_type=not.in.(${hidden})&${sel}&order=created_at.desc&limit=5000`);
  if (!r.ok) {
    r = await rest<Doc[]>(url, key,
      `documents?customer_id=in.(${list})&doc_type=not.in.(${hidden})` +
      `&select=id,customer_id,doc_type,doc_name,file_type,doc_expiry,storage_bucket,storage_path,created_at&order=created_at.desc&limit=5000`);
  }
  return r.ok && Array.isArray(r.data) ? r.data : [];
}

const docOwner = (d: Doc): number | null =>
  (d.owner_type && d.owner_type !== 'customer') ? null : (d.owner_id ?? d.customer_id ?? null);

async function handleList(url: string, key: string, link: LinkRow): Promise<Response> {
  const isGroup = link.kind === 'group';

  // Stage SHARE-FAST รอบที่ 1 — ข้อมูลที่ไม่ขึ้นต่อกัน ดึงพร้อมกัน
  //   หัวหน้า (กลุ่ม/นายจ้าง) · ค่าแจ้งเตือน (ALERT-SETTINGS-DB) · รายชื่อแรงงาน · รูปพื้นหลังของกลุ่ม (SHARE-GROUP-BANNER)
  const [headR, ar, workers, gbR] = await Promise.all([
    isGroup
      ? rest<Record<string, unknown>[]>(url, key, `groups?id=eq.${link.group_id}&select=id,name&limit=1`)
      : rest<Record<string, unknown>[]>(url, key, `employers?id=eq.${link.employer_id}&select=*&limit=1`),
    rest<Record<string, unknown>[]>(url, key, 'app_alert_settings?id=eq.1&select=passport,visa,wp,next90,mou&limit=1'),
    loadWorkers(url, key, linkScope(link)),
    isGroup
      ? rest<Doc[]>(url, key,
          `documents?owner_type=eq.group&owner_id=eq.${link.group_id}&doc_type=eq.${BANNER_DOC_TYPE}` +
          `&select=id,storage_bucket,storage_path&order=created_at.desc&limit=1`)
      : Promise.resolve(null),
  ]);
  const head = headR.ok && Array.isArray(headR.data) ? headR.data[0] : null;
  if (!head) return json({ ok: false, error: 'invalid' }, 404);
  const emp: Record<string, unknown> | null = isGroup ? null : head;
  const groupName = isGroup ? String(head.name ?? '') : '';
  const alerts = ar.ok && Array.isArray(ar.data) && ar.data[0] ? ar.data[0] : null;

  // Stage SHARE-GROUP: นายจ้างของแรงงานในลิงก์นี้
  const empIds = isGroup
    ? [...new Set(workers.map(w => Number(w.employer_id)).filter(n => Number.isInteger(n) && n > 0))]
    : [Number(link.employer_id)];
  const ids = workers.map(w => w.id);

  // รูปแรงงานที่มี path ใน customers ตรง ๆ — เซ็นได้เลยไม่ต้องรอเอกสาร
  const directReq = new Map<string, string[]>();
  const photoKey = new Map<number, [string, string]>();
  for (const w of workers) {
    if (!w.photo_storage_path) continue;
    const b = w.photo_storage_bucket || PHOTO_BUCKET, p = w.photo_storage_path;
    if (!directReq.has(b)) directReq.set(b, []);
    directReq.get(b)!.push(p);
    photoKey.set(w.id, [b, p]);
  }

  // Stage SHARE-FAST รอบที่ 2 — ชื่อนายจ้าง · รูปพื้นหลัง · เอกสาร · รูปแรงงาน พร้อมกัน
  const namesP = (async (): Promise<Map<number, string>> => {
    const m = new Map<number, string>();
    if (isGroup && empIds.length) {
      const en = await rest<{ id: number; name: string | null }[]>(url, key, `employers?id=in.(${empIds.join(',')})&select=id,name`);
      if (en.ok && Array.isArray(en.data)) for (const x of en.data) m.set(Number(x.id), String(x.name ?? ''));
    } else if (emp) m.set(Number(link.employer_id), String(emp.name ?? ''));
    return m;
  })();
  // Stage SHARE-S3 / SHARE-GROUP-BANNER: รูปพื้นหลัง — ลิงก์กลุ่มใช้ของกลุ่มก่อน ไม่มีค่อยใช้รูปล่าสุดของนายจ้างในกลุ่ม
  const bannerP = (async (): Promise<string | null> => {
    try {
      let bd: Doc | null = gbR && gbR.ok && Array.isArray(gbR.data) ? (gbR.data[0] ?? null) : null;
      if (!bd && empIds.length) {
        const br = await rest<Doc[]>(url, key,
          `documents?owner_type=eq.employer&owner_id=in.(${empIds.join(',')})&doc_type=eq.${BANNER_DOC_TYPE}` +
          `&select=id,storage_bucket,storage_path&order=created_at.desc&limit=1`);
        bd = br.ok && Array.isArray(br.data) ? (br.data[0] ?? null) : null;
      }
      return bd && bd.storage_path ? await signOne(url, key, bd.storage_bucket || DOC_BUCKET, bd.storage_path) : null;
    } catch { return null; }
  })();
  const [empName, banner, docs, signed] = await Promise.all([
    namesP, bannerP, loadDocs(url, key, ids), signGrouped(url, key, directReq),
  ]);

  // เอกสารล่าสุดต่อกลุ่ม ต่อแรงงาน (docs เรียงใหม่→เก่าแล้ว)
  const byWorker = new Map<number, { groups: Record<string, Doc>; profile: Doc | null; files: Doc[] }>();
  for (const d of docs) {
    const owner = docOwner(d);
    if (owner == null || !docVisible(d.doc_type)) continue;
    const slot = byWorker.get(owner) ?? { groups: {}, profile: null, files: [] };
    if (slot.files.length < MAX_FILES_PER_WORKER) slot.files.push(d);
    for (const [g, types] of Object.entries(DOC_GROUPS)) {
      if (d.doc_type && types.includes(d.doc_type) && !slot.groups[g]) slot.groups[g] = d;
    }
    if (d.doc_type && PROFILE_DOC_TYPES.includes(d.doc_type) && d.storage_path && !slot.profile) slot.profile = d;
    byWorker.set(owner, slot);
  }

  // รอบที่ 3 (เฉพาะเมื่อจำเป็น) — แรงงานที่ไม่มีรูปใน customers ใช้รูปถ่ายจากเอกสารแทน
  const fallbackReq = new Map<string, string[]>();
  for (const w of workers) {
    if (w.photo_storage_path) continue;
    const prof = byWorker.get(w.id)?.profile;
    if (prof && prof.storage_path && !(w.photo && w.photo.startsWith('data:image'))) {
      const b = prof.storage_bucket || DOC_BUCKET, p = prof.storage_path;
      if (!fallbackReq.has(b)) fallbackReq.set(b, []);
      fallbackReq.get(b)!.push(p);
      photoKey.set(w.id, [b, p]);
    }
  }
  if (fallbackReq.size) for (const [k, u] of await signGrouped(url, key, fallbackReq)) signed.set(k, u);

  const out = workers.map(w => {
    const slot = byWorker.get(w.id) ?? { groups: {}, profile: null, files: [] as Doc[] };
    const pk = photoKey.get(w.id);
    let photo: string | null = pk ? (signed.get(`${pk[0]}/${pk[1]}`) ?? null) : null;
    if (!photo && w.photo && w.photo.startsWith('data:image') && w.photo.length <= LEGACY_PHOTO_MAX) photo = w.photo;
    const g = slot.groups;
    return {
      id: w.id,
      name_th: w.name_th || null,
      name_en: w.name || null,
      nationality: w.nationality || null,
      passport_no: w.passport_no || null,
      employer: empName.get(Number(w.employer_id)) || null,   // Stage SHARE-GROUP
      alien_id: w.alien_id || null,
      license_no: w.license_no || null,
      request_no: w.wp_no || null,
      dob: asDate(w.dob),
      category: w.worker_category || null,
      status: (w.status_note || '').trim().slice(0, 120) || null,   // Stage SHARE-STATUS
      photo,
      dates: {
        passport: asDate(w.exp_passport) ?? asDate(g.passport?.doc_expiry),
        visa:     asDate(w.exp_visa)     ?? asDate(g.visa?.doc_expiry),
        wp:       asDate(w.exp_wp)       ?? asDate(g.wp?.doc_expiry),
        d90:      asDate(w.next_90),
        mou:      asDate(w.exp_mou),
      },
      docs: {
        passport: g.passport?.id ?? null,
        visa:     g.visa?.id ?? null,
        wp:       g.wp?.id ?? null,
      },
      // Stage S2: เอกสารทั้งหมดของแรงงาน (ใหม่ → เก่า) — ❌ ไม่มี path/bucket
      files: slot.files.map(d => ({
        id: d.id,
        name: d.doc_name || null,
        type: d.doc_type || null,
        date: asDate(d.created_at),
        expiry: asDate(d.doc_expiry),
        pdf: /pdf/i.test(String(d.mime_type || d.file_type || '')),
      })),
    };
  });

  const area = emp ? [emp.district, emp.province].filter(v => typeof v === 'string' && (v as string).trim()).join(' ') : '';
  background(touchLink(url, key, link));   // Stage SHARE-FAST: ไม่รอ
  return json({
    ok: true,
    employer: { name: isGroup ? groupName : String(emp?.name ?? ''), area: area || null, banner, group: isGroup, employers: isGroup ? empIds.length : 1 },
    generated_at: new Date().toISOString(),
    alerts,
    workers: out,
  });
}

async function handleDoc(url: string, key: string, link: LinkRow, docId: number): Promise<Response> {
  const dr = await rest<(Doc & { file_type: string | null })[]>(url, key,
    `documents?id=eq.${docId}&select=id,customer_id,owner_type,owner_id,doc_type,storage_bucket,storage_path,file_type&limit=1`);
  const d = dr.ok && Array.isArray(dr.data) ? dr.data[0] : null;
  if (!d || !docVisible(d.doc_type)) return json({ ok: false, error: 'not_found' }, 404);
  const owner = docOwner(d);
  if (owner == null) return json({ ok: false, error: 'not_found' }, 404);

  // แรงงานต้องเป็นของนายจ้างเจ้าของลิงก์ และไม่ถูกลบ
  const base = `customers?id=eq.${owner}&${linkScope(link)}&select=id&limit=1`;
  let cr = await rest<{ id: number }[]>(url, key, base + '&deleted_at=is.null');
  if (!cr.ok) cr = await rest<{ id: number }[]>(url, key, base);
  if (!cr.ok || !Array.isArray(cr.data) || !cr.data[0]) return json({ ok: false, error: 'not_found' }, 404);

  if (d.storage_path) {
    const u = await signOne(url, key, d.storage_bucket || DOC_BUCKET, d.storage_path);
    if (!u) return json({ ok: false, error: 'server_error' }, 500);
    return json({ ok: true, url: u, file_type: d.file_type || null, expires_in: SIGN_EXPIRES_SEC });
  }
  // เอกสารเดิม (base64 ใน file_data)
  const fr = await rest<{ file_data: string | null }[]>(url, key, `documents?id=eq.${docId}&select=file_data&limit=1`);
  let fd = fr.ok && Array.isArray(fr.data) && fr.data[0] ? fr.data[0].file_data : null;
  if (!fd) return json({ ok: false, error: 'no_file' }, 404);
  if (fd.length > LEGACY_DOC_MAX) return json({ ok: false, error: 'too_large' }, 413);
  if (!fd.startsWith('data:')) fd = `data:${d.file_type || 'image/jpeg'};base64,${fd}`;
  return json({ ok: true, data_url: fd, file_type: d.file_type || null });
}

// ─── Stage SHARE-S6: รูปตัวอย่างเอกสาร (เฉพาะไฟล์รูป) ของแรงงาน 1 คน — โหลดตอนเปิดหน้าแรงงาน ──
async function handleThumbs(url: string, key: string, link: LinkRow, workerId: number): Promise<Response> {
  const base = `customers?id=eq.${workerId}&${linkScope(link)}&select=id&limit=1`;
  // Stage SHARE-FAST: ตรวจแรงงาน + โหลดเอกสารพร้อมกัน (ไม่ผ่านการตรวจ = ทิ้งผลเอกสาร)
  const [cr0, docsAll] = await Promise.all([
    rest<{ id: number }[]>(url, key, base + '&deleted_at=is.null'),
    loadDocs(url, key, [workerId]),
  ]);
  let cr = cr0;
  if (!cr.ok) cr = await rest<{ id: number }[]>(url, key, base);
  if (!cr.ok || !Array.isArray(cr.data) || !cr.data[0]) return json({ ok: false, error: 'not_found' }, 404);
  const docs = docsAll
    .filter(d => docOwner(d) === workerId && docVisible(d.doc_type) && d.storage_path &&
                 /^image\//i.test(String(d.mime_type || d.file_type || '')))
    .slice(0, MAX_FILES_PER_WORKER);
  const byBucket = new Map<string, Doc[]>();
  for (const d of docs) {
    const b = d.storage_bucket || DOC_BUCKET;
    if (!byBucket.has(b)) byBucket.set(b, []);
    byBucket.get(b)!.push(d);
  }
  const thumbs: Record<string, string> = {};
  for (const [b, list] of byBucket) {
    const m = await signMany(url, key, b, list.map(d => d.storage_path as string));
    for (const d of list) { const u = m.get(d.storage_path as string); if (u) thumbs[String(d.id)] = u; }
  }
  return json({ ok: true, thumbs, expires_in: SIGN_EXPIRES_SEC });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST')   return json({ ok: false, error: 'method' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) {
    console.error('[employer-share-view] missing required secrets');
    return json({ ok: false, error: 'not_configured' }, 500);
  }

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ ok: false, error: 'bad_request' }, 400); }

  const token = String(body.t ?? '').trim().toLowerCase();
  const code  = String(body.c ?? '').trim();   // Stage SHARE-S4: ลิงก์สั้น
  try {
    const link = (!token && code) ? await getLinkByCode(url, key, code) : await getLink(url, key, token);
    if (!link) return json({ ok: false, error: 'invalid' }, 404);   // ❌ ไม่บอกว่าผิดเพราะอะไร

    if (body.worker_id != null) {   // Stage SHARE-S6
      const wid = Number(body.worker_id);
      if (!Number.isInteger(wid) || wid <= 0) return json({ ok: false, error: 'bad_request' }, 400);
      return await handleThumbs(url, key, link, wid);
    }
    if (body.doc_id != null) {
      const docId = Number(body.doc_id);
      if (!Number.isInteger(docId) || docId <= 0) return json({ ok: false, error: 'bad_request' }, 400);
      return await handleDoc(url, key, link, docId);
    }
    return await handleList(url, key, link);
  } catch (e) {
    console.error('[employer-share-view] error:', e instanceof Error ? e.message : e);   // ❌ ไม่ log token
    return json({ ok: false, error: 'server_error' }, 500);
  }
});
