// ============================================================================
// STAGE LINE-DOC-ALERT — line-doc-alert
//
// แจ้งเตือนเอกสารแรงงานใกล้หมดอายุ เข้ากลุ่ม LINE ของนายจ้าง (บอทมีตัง · LINE Messaging API push)
//   เรียกจาก pg_cron ทุกวัน 09:00 น. (public.line_doc_alert_kick(null))
//   หรือปุ่ม "ส่งตอนนี้" ใน CRM (public.app_line_alert_send_now → line_doc_alert_kick(<กลุ่ม>))
//
//   ข้อความ + รายการ = public.line_doc_alert_messages(group, false, share_base)
//     (ฐานข้อมูลสร้างข้อความเอง — หน้าดูตัวอย่างใน CRM ใช้ฟังก์ชันเดียวกัน ข้อความตรงกันเสมอ)
//   ส่งเป็นการ์ด LINE (Flex carousel) จาก card · ถ้าการ์ดส่งไม่ผ่าน → ส่งข้อความธรรมดา (parts) แทน
//   หัวการ์ดใช้รูปพื้นหลังหน้าลิงก์ของนายจ้าง (share_banner) ถ้ามี — ย่อเป็น ≤1024px เก็บใน bucket สาธารณะ line-alert-media
//   ไอคอนสีอยู่ใน bucket เดียวกัน (อัปโหลดเองครั้งแรก)
//   หัวการ์ดวาดเป็นรูป (ฟอนต์ Prompt + กรอบใส แบบหน้าลิงก์นายจ้าง) ด้วย resvg — ถ้าวาดไม่ได้จะใช้หัวการ์ดแบบเดิม
//   ส่งสำเร็จ → public.line_doc_alert_mark(group, items) กันเตือนซ้ำ
//   ส่งไม่สำเร็จ → ไม่บันทึก (พรุ่งนี้ลองใหม่เอง)
//
// Security
//   * Verify JWT = OFF เพราะตรวจ token เอง: header x-alert-token ต้องตรงกับ Vault secret
//     `line_doc_alert_token` (ตรวจผ่าน RPC service_role-only)
//   * service-role key / LINE token อยู่ใน Edge runtime เท่านั้น ไม่ส่งออก/ไม่ log
//   * POST เท่านั้น · body ≤ 1 KiB · log / audit มีแค่จำนวน ไม่มีชื่อแรงงาน
// ============================================================================

const MAX_BODY_BYTES = 1024;
const MAX_MSGS_PER_PUSH = 5;            // LINE push รับได้ครั้งละ 5 ข้อความ
const GROUP_ID_RE = /^[CR][0-9a-f]{32}$/;

type CardDoc = { kind: string; label: string; date: string; days: number };
type CardWorker = { name: string; employer: string | null; docs: CardDoc[] };
type Card = {
  target: string; target_kind: string; url: string | null; count: number; workers: CardWorker[];
  banner: { bucket: string; path: string } | null;
};
type Msg = { line_group_id: string; target_name: string | null; item_count: number; items: unknown[]; parts: string[]; card: Card | null };
type Media = { icon: (k: string) => string | null; hero: string | null; card?: string | null };

// ─── รูปในการ์ด: ไอคอนสี + รูปพื้นหลังของนายจ้าง (bucket สาธารณะ line-alert-media) ───────────────
const MEDIA_BUCKET = 'line-alert-media';
const ICON_VER = 'v3';
const HERO_MAX = 1024;               // LINE รับรูปไม่เกิน 1024×1024
// ไอคอนสี (PNG 96×96 · พื้นสีอ่อน + เส้นสีเข้ม) — อัปโหลดเข้า bucket สาธารณะ line-alert-media ครั้งแรกที่ใช้
const ICONS: Record<string, string> = {
  bell: 'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAYAAADimHc4AAALSElEQVR4nOyde2wUxx3Hv7N35/cLG/M2BYLBPEvURxRoMAaMFWgpqIiWVIJIRU3VJmlCH0pUSEmUpo36T5U/qkpVQ6I2hRJSAiiUUMjFlJC0gUCwEwzmVZ7Gxm/f+XV3k99vz77bvTuDz767XeP9SOedmZ3dO/9+O/Ob+c3sjB0xRFYfyYfPu5ZC0yHFGAiMpfBYSFBYpGMoIaWLfvNNCtXQ76ejvEn/z2ewJb8tpi6oRYwQGCSyqnwy4FtLd1pF0QdicU+TI0k5H0JR3obw/lMULrmAQTBgYckq51ch5Mt0i8UYzkh5EDbbM6Kw+CQGQNQKkGfK55DmX6TiuTJiBkcKkJwKKA7QD+s52umbFAwppA/weqhwd9PR6z92tgPdHX3kx1v0/z4nChd+jiiISgHyrPPXdNgadiI5A0jJ8Ate2HBPw4rpcJEy2ujjinAeW0RRyYvoJ/1SgLx6LBfuzn9QcKnuREomkJHnf8KHI1xCXPVAe2vomUOwe9aI+0qb73aLuypAVpffTy2bfZR1fCBRFXwuCd4BC8LTBbQ1+EtFL1JeoSpp1d1swx0VQFXO9+iwPZibsmeN9lc3FuF0UElovhWauk5ML9nR1yV9KkBWv/8gvLKccvgfczaiI8b5jaxF37CRbrpBRtvnj0uQ9ZYlomjxB5GyR1SAPOOcRE3ME/TE56oJXMez8G1JsOgHXCWxEthGMFLWI0l+RUxZ8v/QrGFtQ1n9URap5WBA+FztjBhvCT8a7El+mfU2vYXIQ7fYL2udYXW3TgFSSgW+9l2kgMJAYs5Yy9gOBJZZzhhNgpiJBuxSZaxBXwLOOTfS39JAPGMkkJQGiwHCssscGYwLlKG6fIM2S0ABUu6kHpTYHLyYjG16DiwGSVqOvuHi822V0hnoOAVLQHU+P/0FgXjmKFjEiKz8YFiIiTiHRwNR/iMrK5PgqDuPXgWkZtFFlgJiSsutYI+ZO2nTxX1ClHj8JSD5dhl6hc+tHnYvWMSW9Dy/bBkuBdWSZd5TBXnlikBGdqwp97hDzQi4L6X1IEgs50OPDZDfCpxIHloDV0MKnWz97nwhq47MJf/+pz2JwKgpwaJiEVukBGovcsAfV2yzFAifpvpJs4QfT1i2PGbSi/QupyrINy+QYLccbXFH2yeQ+DJ3CIJdNbtlfOOOohm8khipV4AyTEe2EolexiMV1kIfJy3igU1Xy1AJEGJE8KTl9Yw7+vFztQoKmmWrBRR/tLNGBDKsOsdghqQCfO4m+jTD52pS4wq5zZW0bPoMPff50FCApxPtVUfhqjiI9gonfB0tEbMp5MVNnb0Y6XOWIbVoAf13yTA7Qp51ykBs9FSYChJ8y9E30Hz4z/S0N0Z1qZKei+zSHyJr/iP+MVozcet8IGhaBbRXHEL9rq3wtt7GYLBl5yNvzQtInVUC06BRgClnzLY4/4LabY8PWviMt7kOta/+GK3lr8OMmM4GNNBT33psxx3zJBXMhj1vIuzZo9W4p/kWPPVX0HW1MvIF5IVs2PNbdDdcRe7qzTATplJA04FX+hS+LWcMshauR/r9K6haGR0xj5cU4frkHbQceY3C4S+xtP7nb7BRSym77HGYBdPYAPenB1D3+lNh6SIlHbnffhYZD6xBNLQe247GvS9DdoXP589/9BWkzV0GwzCbDfC2NeD2358JS7fnT8LYTbujFj6TOX+deq09ryDs3O3tz6rfaQZMoYCmfb+HDHnzxJaVjzE/3QHHyIkYKI5RkzHm6TfVe2mRnS407f8DzIDhCui6fgZtH+/WJ5JXNn/jn9T6erDwPfheoZ7eto92oqvmPIzGcAWwwQwlu/QxJE+YhVjB98pe/IOw9NbybTAaQxUgfV64Tx/Spdky85G95DHEmqylP6Le8QhdmrvyME9IhpEYqoDOi8fV+lhL5vzvQsTBdaAkpSLzwbW6NHbmdV06ASMxVAFdVyrC0lJnFiNepM5cFJbWefU0jMTQjpin6WZYmmPCbMQL7kGH4m2M2aoDA8LQEuBtqtHFubko4jgqJ2jINdQORHoIEomhCvC01OnibIDjjS1bP+vb22JsCTDWF0StIB1K/MekRUh/QHq7YCTWmLDBWAowGEsBBmMpwGAsBRiMpQCDsRRgMJYCDMZSgMFYCjAYcynAiJUVDV7N0bBv99ReQnfdJRhNd+1F9bcYhSEK4Lk6tdueoNEwty49dPZCPAibIdHhQu1rT0acP5QIDFFA/Ztb0H0rfEbCiIefQrwZseLpsLTummr6Tc/BCBJuA9r+uwuuE/vC0pMmzoHr9LsAf+IMf1focKjrxF6kTP36gCaBDYaETk3k+ZrXf7MU0mOsD74veDJAwfNHIXi5nnhi1NTEjrMfmFb4DP829+fvI5EktApKmjATZscxphCJJKElwDFuOjK/8X3YckbDbNhzJyBv3UtIGj8DicTc74j10HXtM7iO76VB/Fqkzy1F2rzlEfO5T74DV8Vh2KmpmfG11XCML4Ip0diAIeGKqN/xK3TdqFLD7lP/woSJ82DLHafL4224gbq//iwQ77h4HGM3vQWzY/pdFXztzQHh9+KqPBiWz1VxQBfnUsPXmh3TK0BJzVbfktHSeTl8OmHnpVP661Ky1GvNjqLuFtSLwTOF+yJpvL71xK8zdZ7/XyDeUf0h3BX6WdZJBbGb3h5TpE8Tli47BHjB+ylqgs9jyhVTshasQ92Fj4MJ9E/U/HH9na8p3gBT4vMEwwI1VAJEcMeB0JlqJoFbPZFmNveZf05pVPkTik9bAlgBpIVAgtcDs5K35nk4+tFMdoyagtzvGONY6xfaEgDBJQDBEqCtn0wGd97G/Xw3sst+EnnTIKo6+dy4X+xJiFt7wHg1tQw9/GQD5MnARhr8pmK8HVGDgYScU/aE+sJ2x9ljqt9GKDakFj2ElOnzh0SrB92dwbDESSGrnRPgw1U1gYfnRk2BRbzghVsvaWuafEUUllyjdL9znE90tcMiTrBsg8I/JaaX3PZ3xBTsD2TS7oVlEVs6tC8kSlXmPT1hJagA3gvLxMZ4yCLJ+GpX+pLQKKBw4dFANcTtVJOso3BP0VYf9DRIVPbuK6YqQAjBj/wvA5nd5MTydsMiRrAs3ZqnXxGbAsHegCgqYXfiYX+MNNVaD4sY0aZZ+UvCKaYt+ndvVO8N9SnBORtsjDtaYTFIuN7XGl87ntSe1ilAzChmO/C7QAKvOmU1SwcOy063cpd8SUwt0a2rFvZeqLrT2zmnk04tVBMU0lFugbWudLTw7I/Ga1rn2yFMW1TWY28DhA3IqBnSUlarWy0xfIPG6/4bWvQPT2fojqqXkWJfGyp8JuKImCiY30AOr9X+rVjh95I2kDa73LC4C7z6S8N1jWdZdkIqK8WXHoq48myfQ5KicOEn1FwKjmpw56yRtBrlCrbDCpYNrz2hG/XC+h7bGpF+bGn+XjG8YjflDK5ywfugsMt3CKzNnBC4yuF1L7Tr3kk0wq58U0wtPnanS/u1OIO6wbMCbrvqR0TYdZ2eG9k/PxzgaoZ7uOHN9SryMD8sZpRcvtst+r06hrrRs6+dJ9osDbsF77zKO/Dx7IV7fRsUFjrX8/xRm+hhExkOUV2xWowq6ZdXM+rlSeRZ5wb6zq105aSIGRzJ/h3jWBG8X4ri8JcQg18FihoeH+fhQ/7wKJaP2iP8Qol2QEULt3SAzeRReANRMKD1YdT9cKuxET65hdqt4zCskdTkwQuYJl7l3VERJYNaoEfK4w5Utywj7fNqeKvodiYez4wlkqfc7SHp7USheHcggu8lpiskyar3VlKJeIRCkylKRkFkknIydC2ooQS3ZASoLpdsZblOv0BpO8iVvBcx4gsAAAD//ygfTjkAAAAGSURBVAMAI7eyAvwJLj0AAAAASUVORK5CYII=',
  passport: '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',
  visa: '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',
  wp: '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',
  d90: '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',
  mou: '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',
};

const pub = (url: string, path: string) => `${url}/storage/v1/object/public/${MEDIA_BUCKET}/${path}`;

async function exists(u: string): Promise<boolean> {
  try { const r = await fetch(u, { method: 'HEAD' }); await r.body?.cancel(); return r.ok; } catch { return false; }
}
async function upload(url: string, key: string, path: string, bytes: Uint8Array, type: string): Promise<boolean> {
  const r = await fetch(`${url}/storage/v1/object/${MEDIA_BUCKET}/${path}`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': type, 'x-upsert': 'true', 'Cache-Control': 'max-age=31536000' },
    body: new Blob([bytes as BlobPart], { type }),
  });
  await r.text().catch(() => '');
  return r.ok;
}
const b64 = (s: string) => Uint8Array.from(atob(s), c => c.charCodeAt(0));

// ไอคอน: มีครบแล้วไม่ต้องอัปโหลดซ้ำ · พังก็ส่งการ์ดแบบไม่มีไอคอน
async function ensureIcons(url: string, key: string): Promise<boolean> {
  if (await exists(pub(url, `icons/${ICON_VER}/mou.png`))) return true;
  let ok = true;
  for (const [k, v] of Object.entries(ICONS)) ok = (await upload(url, key, `icons/${ICON_VER}/${k}.png`, b64(v), 'image/png')) && ok;
  return ok;
}

// ขนาดรูป JPEG จากหัวไฟล์ (ไม่ต้องถอดรหัสทั้งรูป)
function jpegSize(b: Uint8Array): { w: number; h: number } | null {
  if (b[0] !== 0xFF || b[1] !== 0xD8) return null;
  let i = 2;
  while (i + 9 < b.length) {
    if (b[i] !== 0xFF) { i++; continue; }
    const m = b[i + 1];
    if (m >= 0xC0 && m <= 0xCF && m !== 0xC4 && m !== 0xC8 && m !== 0xCC) return { h: (b[i + 5] << 8) | b[i + 6], w: (b[i + 7] << 8) | b[i + 8] };
    i += 2 + ((b[i + 2] << 8) | b[i + 3]);
  }
  return null;
}

// ย่อรูป (เฉลี่ยพิกเซล) — RGBA
function downscale(src: Uint8Array, w: number, h: number, W: number, H: number): Uint8Array {
  const out = new Uint8Array(W * H * 4); const sx = w / W, sy = h / H;
  for (let y = 0; y < H; y++) {
    const y0 = Math.floor(y * sy), y1 = Math.min(h, Math.max(y0 + 1, Math.floor((y + 1) * sy)));
    for (let x = 0; x < W; x++) {
      const x0 = Math.floor(x * sx), x1 = Math.min(w, Math.max(x0 + 1, Math.floor((x + 1) * sx)));
      let r = 0, g = 0, bl = 0, n = 0;
      for (let yy = y0; yy < y1; yy++) { let k = (yy * w + x0) * 4; for (let xx = x0; xx < x1; xx++, k += 4) { r += src[k]; g += src[k + 1]; bl += src[k + 2]; n++; } }
      const o = (y * W + x) * 4; out[o] = r / n; out[o + 1] = g / n; out[o + 2] = bl / n; out[o + 3] = 255;
    }
  }
  return out;
}

// รูปพื้นหลังนายจ้าง → JPEG ไม่เกิน 1024 px เก็บไว้ใช้ซ้ำ · ชื่อไฟล์สุ่มจาก path ต้นฉบับ (เดาไม่ได้)
//   ทำไม่ได้ (ไม่ใช่ JPEG / ถอดรหัสไม่ได้) → การ์ดใช้แถบส้มแทน ไม่กระทบการส่ง
async function heroUrl(url: string, key: string, b: { bucket: string; path: string } | null): Promise<string | null> {
  if (!b || !b.bucket || !b.path) return null;
  try {
    const h = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${b.bucket}/${b.path}`)));
    const name = `banner/${[...h.slice(0, 16)].map(x => x.toString(16).padStart(2, '0')).join('')}.jpg`;
    const u = pub(url, name);
    if (await exists(u)) return u;
    const r = await fetch(`${url}/storage/v1/object/${encodeURIComponent(b.bucket)}/${b.path.split('/').map(encodeURIComponent).join('/')}`,
      { headers: { apikey: key, Authorization: `Bearer ${key}` } });
    if (!r.ok) { await r.text().catch(() => ''); return null; }
    const raw = new Uint8Array(await r.arrayBuffer());
    const dim = jpegSize(raw);
    if (!dim || raw.length > 12_000_000) return null;
    let out: Uint8Array = raw;
    if (dim.w > HERO_MAX || dim.h > HERO_MAX || raw.length > 1_900_000) {
      const jpeg = (await import('npm:jpeg-js@0.4.4')).default;
      const d = jpeg.decode(raw, { useTArray: true, maxMemoryUsageInMB: 256 });
      const sc = Math.min(1, HERO_MAX / Math.max(d.width, d.height));
      const W = Math.max(1, Math.round(d.width * sc)), H = Math.max(1, Math.round(d.height * sc));
      out = new Uint8Array(jpeg.encode({ data: downscale(d.data as Uint8Array, d.width, d.height, W, H), width: W, height: H }, 82).data);
    }
    return (await upload(url, key, name, out, 'image/jpeg')) ? u : null;
  } catch (e) {
    console.warn('[line-doc-alert] hero failed', e instanceof Error ? e.message : 'error');
    return null;
  }
}

// ─── หัวการ์ดเป็นรูป (ฟอนต์ Prompt + ชื่อนายจ้างในกล่องใส แบบหน้าลิงก์นายจ้าง) ─────────────────────
//   วาด SVG → PNG ด้วย resvg (wasm) แล้วบีบเป็น JPEG · ทำไม่ได้ → ใช้หัวการ์ดแบบเดิม (ไม่กระทบการส่ง)
const HERO_W = 1024, HERO_H = 512;
const HERO_VER = 'h2';
const RESVG_WASM_URL = 'https://cdn.jsdelivr.net/npm/@resvg/resvg-wasm@2.6.2/index_bg.wasm';
const FONT_URL = (w: string) => `https://raw.githubusercontent.com/google/fonts/main/ofl/prompt/Prompt-${w}.ttf`;
// deno-lint-ignore no-explicit-any
let _rv: Promise<any> | null = null;
let _fonts: Promise<Uint8Array[]> | null = null;

// deno-lint-ignore no-explicit-any
function resvgLib(): Promise<any> {
  _rv ??= (async () => {
    const mod = await import('npm:@resvg/resvg-wasm@2.6.2');
    const local = Deno.env.get('RESVG_WASM_FILE');
    await mod.initWasm(local ? await Deno.readFile(local) : fetch(RESVG_WASM_URL));
    return mod;
  })();
  _rv.catch(() => { _rv = null; });
  return _rv;
}
function fonts(): Promise<Uint8Array[]> {
  _fonts ??= Promise.all(['Regular', 'SemiBold'].map(async w => {
    const dir = Deno.env.get('PROMPT_FONT_DIR');
    if (dir) return await Deno.readFile(`${dir}/Prompt-${w}.ttf`);
    const r = await fetch(FONT_URL(w));
    if (!r.ok) throw new Error(`font_${r.status}`);
    return new Uint8Array(await r.arrayBuffer());
  }));
  _fonts.catch(() => { _fonts = null; });
  return _fonts;
}
// สระอำ แยกเป็น นิคหิต + สระอา (resvg วางสระอำทับตัวถัดไป) · escape XML
const xml = (s: string) => s.replace(/\u0E33/g, '\u0E4D\u0E32').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

// วัดความกว้างตัวหนังสือ (px) ด้วย resvg เอง — ภาษาไทยวางวรรณยุกต์ถูกต้อง
// deno-lint-ignore no-explicit-any
function textWidth(lib: any, fb: Uint8Array[], text: string, size: number, weight: number): number {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="4000" height="200"><text x="0" y="150" font-family="Prompt" font-weight="${weight}" font-size="${size}">${xml(text)}</text></svg>`;
  const r = new lib.Resvg(svg, { font: { fontBuffers: fb, loadSystemFonts: false, defaultFontFamily: 'Prompt' } });
  const bb = r.getBBox(); r.free?.();
  return bb ? bb.width : text.length * size * 0.55;
}

// แบ่งชื่อเป็นไม่เกิน 2 บรรทัด (ตัดที่ช่องว่าง) · ยาวเกิน → ลดขนาดตัวหนังสือ
// deno-lint-ignore no-explicit-any
function fitName(lib: any, fb: Uint8Array[], name: string, maxW: number): { lines: string[]; size: number } {
  const words = name.trim().split(/\s+/).filter(Boolean);
  for (const size of [58, 52, 46, 42, 38]) {
    const lines: string[] = []; let cur = '';
    let ok = true;
    for (const w of words) {
      const t = cur ? `${cur} ${w}` : w;
      if (textWidth(lib, fb, t, size, 600) <= maxW) { cur = t; continue; }
      if (!cur) { ok = false; break; }
      lines.push(cur); cur = w;
      if (textWidth(lib, fb, w, size, 600) > maxW) { ok = false; break; }
    }
    if (cur) lines.push(cur);
    if (ok && lines.length <= 2) return { lines, size };
  }
  // ยาวมาก: 2 บรรทัดแรก + …
  const size = 38, lines: string[] = []; let cur = '';
  for (const ch of [...name]) {
    if (textWidth(lib, fb, cur + ch, size, 600) > maxW) { lines.push(cur); cur = ch; if (lines.length === 2) break; } else cur += ch;
  }
  if (lines.length < 2 && cur) lines.push(cur);
  if (lines.length === 2) lines[1] = lines[1].replace(/.{1}$/u, '…');
  return { lines: lines.slice(0, 2), size };
}

const BELL_PATH = '<path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2H4.5z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>';

// หัวการ์ด 1024×512: รูปพื้นหลัง · กระดิ่งส้มอ่อนมุมซ้ายบน · ชื่อนายจ้าง (Prompt) ในกล่องใส · คำแจ้งเตือนมุมล่างขวา
function heroSvg(name: { lines: string[]; size: number }, nameW: number, banner: Uint8Array | null): string {
  const W = HERO_W, H = HERO_H, M = 36;
  let b64 = '';
  if (banner) { let bin = ''; for (let i = 0; i < banner.length; i += 0x8000) bin += String.fromCharCode(...banner.subarray(i, i + 0x8000)); b64 = btoa(bin); }
  const mime = banner && banner[0] === 0x89 ? 'image/png' : 'image/jpeg';
  const bg = banner
    ? `<image href="data:${mime};base64,${b64}" x="0" y="0" width="${W}" height="${H}" preserveAspectRatio="xMidYMid slice"/>
       <rect width="${W}" height="${H}" fill="url(#shade)"/>`
    : `<rect width="${W}" height="${H}" fill="url(#orange)"/>
       <circle cx="${W - 80}" cy="40" r="190" fill="#FFFFFF" fill-opacity="0.08"/>`;
  const lh = Math.round(name.size * 1.3), padX = 28, padY = 18;
  const boxH = lh * name.lines.length + padY * 2 - Math.round(name.size * 0.22);
  const boxW = Math.min(W - M * 2, nameW + padX * 2);
  const boxY = H - 74 - boxH;
  const texts = name.lines.map((l, i) => {
    const y = boxY + padY + Math.round(name.size * 0.98) + i * lh;
    return `<text x="${M + padX}" y="${y}" font-family="Prompt" font-weight="600" font-size="${name.size}" fill="#FFFFFF">${xml(l)}</text>`;
  }).join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <defs>
    <linearGradient id="shade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity="0.10"/><stop offset="0.5" stop-color="#000" stop-opacity="0.08"/><stop offset="1" stop-color="#000" stop-opacity="0.55"/></linearGradient>
    <linearGradient id="orange" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#F26B1D"/><stop offset="1" stop-color="#F7A44A"/></linearGradient>
  </defs>
  ${bg}
  <rect x="${M}" y="${M}" width="116" height="116" rx="32" fill="#FFF0E3" stroke="#FFD9BF" stroke-width="3"/>
  <g transform="translate(${M + 24},${M + 24}) scale(${68 / 24})" fill="none" stroke="#E0620B" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">${BELL_PATH}</g>
  <rect x="${M}" y="${boxY}" width="${boxW}" height="${boxH}" rx="26" fill="#FFFFFF" fill-opacity="0.16" stroke="#FFFFFF" stroke-opacity="0.5" stroke-width="2.5"/>
  ${texts}
  <text x="${W - M}" y="${H - 26}" text-anchor="end" font-family="Prompt" font-weight="400" font-size="36" fill="#FFFFFF" fill-opacity="0.95">แจ้งเตือนเอกสารใกล้หมดอายุ</text>
</svg>`;
}

// สร้างรูปหัวการ์ด → JPEG
async function renderHero(target: string, banner: Uint8Array | null): Promise<Uint8Array> {
  const [lib, fb] = await Promise.all([resvgLib(), fonts()]);
  const name = fitName(lib, fb, target || '-', HERO_W - 72 - 56);
  const nameW = Math.max(...name.lines.map(l => textWidth(lib, fb, l, name.size, 600)));
  const r = new lib.Resvg(heroSvg(name, nameW, banner), {
    fitTo: { mode: 'width', value: HERO_W },
    font: { fontBuffers: fb, loadSystemFonts: false, defaultFontFamily: 'Prompt' },
  });
  const img = r.render();
  const px: Uint8Array = img.pixels; const w: number = img.width, h: number = img.height;
  img.free?.(); r.free?.();
  const jpeg = (await import('npm:jpeg-js@0.4.4')).default;
  return new Uint8Array(jpeg.encode({ data: px, width: w, height: h }, 84).data);
}

// รูปหัวการ์ดของนายจ้าง/กลุ่มนี้ (ชื่อ + รูปพื้นหลังเดิม → ใช้รูปเดิม ไม่วาดใหม่)
async function heroCardUrl(url: string, key: string, card: Card): Promise<string | null> {
  try {
    const sig = JSON.stringify([HERO_VER, card.target, card.banner?.bucket, card.banner?.path]);
    const h = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(sig)));
    const name = `hero/${[...h.slice(0, 16)].map(x => x.toString(16).padStart(2, '0')).join('')}.jpg`;
    const u = pub(url, name);
    if (await exists(u)) return u;
    let banner: Uint8Array | null = null;
    if (card.banner?.bucket && card.banner?.path) {
      const r = await fetch(`${url}/storage/v1/object/${encodeURIComponent(card.banner.bucket)}/${card.banner.path.split('/').map(encodeURIComponent).join('/')}`,
        { headers: { apikey: key, Authorization: `Bearer ${key}` } });
      if (r.ok) { const b = new Uint8Array(await r.arrayBuffer()); if (b.length < 8_000_000) banner = b; } else await r.text().catch(() => '');
    }
    const jpg = await renderHero(card.target, banner);
    return (await upload(url, key, name, jpg, 'image/jpeg')) ? u : null;
  } catch (e) {
    console.warn('[line-doc-alert] hero card failed', e instanceof Error ? e.message : 'error');
    return null;
  }
}

// ─── การ์ด LINE (Flex) ───────────────────────────────────────────────────────
const BRAND = '#F26B1D';
const WORKERS_PER_BUBBLE = 6;      // แรงงานต่อการ์ด 1 ใบสูงสุด (เลื่อนดูใบถัดไปได้)
const BUBBLE_MAX_BYTES = 9000;     // LINE จำกัดการ์ดละ 10 KB → เผื่อไว้
const BUBBLES_PER_MSG = 10;        // carousel รับได้ไม่เกิน 12 ใบ
const CAROUSEL_MAX_BYTES = 45000;  // LINE จำกัดข้อความการ์ดละ 50 KB → เผื่อไว้

function chip(days: number) {
  const [bg, fg] = days <= 7 ? ['#FDE8E8', '#C62828'] : days <= 30 ? ['#FFF1DE', '#B45309'] : ['#E5F4EA', '#1F8A4C'];
  return {
    type: 'box', layout: 'vertical', flex: 0, backgroundColor: bg, cornerRadius: 'xxl',
    paddingTop: '1px', paddingBottom: '1px', paddingStart: '6px', paddingEnd: '6px',
    contents: [{ type: 'text', text: days <= 0 ? 'วันนี้' : `${days} วัน`, size: 'xs', color: fg, weight: 'bold' }],
  };
}

function docRow(d: CardDoc, m: Media) {
  const ic = m.icon(d.kind);
  return {
    type: 'box', layout: 'horizontal', spacing: 'sm', alignItems: 'center', margin: 'sm',
    contents: [
      ...(ic ? [{ type: 'image', url: ic, size: '20px', flex: 0, aspectRatio: '1:1' }] : []),
      { type: 'text', text: d.label || '-', size: 'xs', color: '#4A4A4A', flex: 1, wrap: true },
      { type: 'text', text: d.date || '', size: 'xs', color: '#222222', weight: 'bold', flex: 0 },
      chip(Number(d.days) || 0),
    ],
  };
}

function workerBox(w: CardWorker, no: number, m: Media) {
  const head: unknown[] = [{ type: 'text', text: `${no}. ${w.name || '-'}`, size: 'xs', weight: 'bold', color: '#222222', wrap: true }];
  if (w.employer) head.push({ type: 'text', text: w.employer, size: 'xxs', color: '#9A9A9A', wrap: true });
  return { type: 'box', layout: 'vertical', contents: [...head, ...(w.docs || []).map(d => docRow(d, m))] };
}

// หัวการ์ด: ชื่อนายจ้าง (ตัวไม่หนา) · คำว่า "แจ้งเตือนเอกสารใกล้หมดอายุ" มุมล่างขวา
const nameText = (card: Card) => ({ type: 'text', text: card.target || '-', size: 'md', color: '#FFFFFF', wrap: true, maxLines: 2 });
const labelText = { type: 'text', text: 'แจ้งเตือนเอกสารใกล้หมดอายุ', size: 'xxs', color: '#FFE9DB', align: 'end', margin: 'xs' };

function bubble(card: Card, workers: CardWorker[], startNo: number, page: number, pages: number, m: Media) {
  // มีรูปพื้นหลังนายจ้าง → รูป + กระดิ่งมุมซ้ายบน + ชื่อบนแถบเข้มด้านล่าง · ไม่มี → แถบส้มไล่สี + กระดิ่งหน้าชื่อ
  const bell = m.icon('bell');
  const top = m.hero
    ? {
      type: 'box', layout: 'vertical', paddingAll: '0px',
      contents: [
        { type: 'image', url: m.hero, size: 'full', aspectRatio: '2:1', aspectMode: 'cover' },
        ...(bell ? [{ type: 'image', url: bell, size: '36px', aspectRatio: '1:1', position: 'absolute', offsetTop: '10px', offsetStart: '10px' }] : []),
        {
          type: 'box', layout: 'vertical', position: 'absolute', offsetBottom: '0px', offsetStart: '0px', offsetEnd: '0px',
          paddingAll: '12px', paddingTop: '26px', paddingBottom: '8px', spacing: 'none',
          background: { type: 'linearGradient', angle: '0deg', startColor: '#000000B3', endColor: '#00000000' },
          contents: [nameText(card), labelText],
        },
      ],
    }
    : {
      type: 'box', layout: 'vertical', paddingAll: '12px', paddingBottom: '8px',
      background: { type: 'linearGradient', angle: '90deg', startColor: '#F26B1D', endColor: '#F59E3B' },
      contents: [
        {
          type: 'box', layout: 'horizontal', spacing: 'md', alignItems: 'center',
          contents: [...(bell ? [{ type: 'image', url: bell, size: '36px', aspectRatio: '1:1', flex: 0 }] : []), { ...nameText(card), flex: 1 }],
        },
        labelText,
      ],
    };
  const count = { type: 'text', text: `${card.count} รายการ${pages > 1 ? ` · หน้า ${page}/${pages}` : ''}`, size: 'sm', weight: 'bold', color: '#F26B1D', align: 'center' };
  // หัวการ์ดเป็นรูป (ฟอนต์ Prompt + ชื่อในกล่องใส)
  if (m.card) {
    const bb: Record<string, unknown> = {
      type: 'bubble', size: 'kilo',
      hero: { type: 'image', url: m.card, size: 'full', aspectRatio: `${HERO_W}:${HERO_H}`, aspectMode: 'cover' },
      body: {
        type: 'box', layout: 'vertical', paddingAll: '12px', spacing: 'md',
        contents: [count, ...workers.flatMap((w, i) => [{ type: 'separator', color: '#F0F0F0' }, workerBox(w, startNo + i, m)])],
      },
    };
    if (card.url) bb.footer = { type: 'box', layout: 'vertical', paddingAll: '10px', paddingTop: '0px',
      contents: [{ type: 'button', style: 'primary', color: BRAND, height: 'sm', action: { type: 'uri', label: 'ดูรายละเอียดเอกสาร', uri: card.url } }] };
    return bb;
  }
  const b: Record<string, unknown> = {
    type: 'bubble', size: 'kilo',
    header: top,
    body: {
      type: 'box', layout: 'vertical', paddingAll: '12px', spacing: 'md',
      contents: [count, ...workers.flatMap((w, i) => [{ type: 'separator', color: '#F0F0F0' }, workerBox(w, startNo + i, m)])],
    },
  };
  if (card.url) {
    b.footer = {
      type: 'box', layout: 'vertical', paddingAll: '10px', paddingTop: '0px',
      contents: [{ type: 'button', style: 'primary', color: BRAND, height: 'sm', action: { type: 'uri', label: 'ดูรายละเอียดเอกสาร', uri: card.url } }],
    };
  }
  return b;
}

// การ์ดทั้งหมดของกลุ่ม → ข้อความ Flex (carousel) · แบ่งตามจำนวนคน/ขนาดที่ LINE รับได้
function flexMessages(card: Card, m: Media): unknown[] {
  const ws = Array.isArray(card.workers) ? card.workers : [];
  const size = (x: unknown) => new TextEncoder().encode(JSON.stringify(x)).length;
  const chunks: CardWorker[][] = [];
  let cur: CardWorker[] = [];
  for (const w of ws) {
    const next = [...cur, w];
    if (cur.length && (next.length > WORKERS_PER_BUBBLE || size(bubble(card, next, 1, 99, 99, m)) > BUBBLE_MAX_BYTES)) {
      chunks.push(cur); cur = [w];
    } else cur = next;
  }
  if (cur.length) chunks.push(cur);
  let no = 1;
  const bubbles = chunks.map((c, i) => { const b = bubble(card, c, no, i + 1, chunks.length, m); no += c.length; return b; });
  const groups: unknown[][] = [];
  let g: unknown[] = [], gBytes = 0;
  for (const b of bubbles) {
    const n = size(b);
    if (g.length && (g.length >= BUBBLES_PER_MSG || gBytes + n > CAROUSEL_MAX_BYTES)) { groups.push(g); g = []; gBytes = 0; }
    g.push(b); gBytes += n;
  }
  if (g.length) groups.push(g);
  return groups.map(part => ({
    type: 'flex',
    altText: `แจ้งเตือนเอกสารใกล้หมดอายุ · ${card.target} · ${card.count} รายการ`.slice(0, 400),
    contents: part.length === 1 ? part[0] : { type: 'carousel', contents: part },
  }));
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
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

async function push(token: string, to: string, all: unknown[]): Promise<void> {
  for (let i = 0; i < all.length; i += MAX_MSGS_PER_PUSH) {
    const messages = all.slice(i, i + MAX_MSGS_PER_PUSH);
    const r = await fetch('https://api.line.me/v2/bot/message/push', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify({ to, messages }),
    });
    if (!r.ok) {
      await r.text().catch(() => '');
      throw new Error(`line_push_${r.status}`);
    }
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json(405, { ok: false, error: 'method_not_allowed' });

  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const lineToken = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN');
  if (!url || !key) return json(500, { ok: false, error: 'server_not_configured' });

  // ── auth: token จาก Vault ──
  const token = req.headers.get('x-alert-token') || '';
  if (token.length < 32 || token.length > 200) return json(401, { ok: false, error: 'unauthorized' });
  try {
    const ok = await rpc(url, key, 'line_doc_alert_check_token', { p_token: token });
    if (ok !== true) return json(401, { ok: false, error: 'unauthorized' });
  } catch (_) {
    return json(500, { ok: false, error: 'auth_check_failed' });
  }
  if (!lineToken) return json(500, { ok: false, error: 'line_token_not_configured' });

  // ── body: { group?: "C…" } ──
  let group: string | null = null;
  try {
    const raw = await req.text();
    if (raw.length > MAX_BODY_BYTES) return json(413, { ok: false, error: 'body_too_large' });
    const body = raw ? JSON.parse(raw) : {};
    if (body && typeof body.group === 'string' && body.group) {
      if (!GROUP_ID_RE.test(body.group)) return json(400, { ok: false, error: 'invalid_group' });
      group = body.group;
    }
  } catch (_) {
    return json(400, { ok: false, error: 'invalid_json' });
  }

  // ลิงก์ในข้อความ: ระบบทดสอบ → /st/s/… · ระบบจริง → /s/…
  const shareBase = Deno.env.get('LINE_ALERT_SHARE_BASE')
    || (url.includes('bzwtknqvhvdmatangzqf') ? 'https://rungfa.com/st' : 'https://rungfa.com');

  let list: Msg[] = [];
  try {
    const res = await rpc(url, key, 'line_doc_alert_messages', {
      p_line_group_id: group, p_include_disabled: false, p_share_base: shareBase,
    });
    list = Array.isArray(res) ? res as Msg[] : [];
  } catch (_) {
    return json(500, { ok: false, error: 'messages_failed' });
  }

  let sent = 0, items = 0, failed = 0;
  const iconsOk = list.length ? await ensureIcons(url, key) : false;
  for (const m of list) {
    if (!m || !GROUP_ID_RE.test(String(m.line_group_id)) || !Array.isArray(m.parts) || !m.parts.length) continue;
    const texts = m.parts.map(t => ({ type: 'text', text: String(t).slice(0, 5000) }));
    let ok = false;
    if (m.card && Array.isArray(m.card.workers) && m.card.workers.length) {
      const media: Media = {
        icon: (k: string) => iconsOk && ICONS[k] ? pub(url, `icons/${ICON_VER}/${k}.png`) : null,
        hero: null,
        card: await heroCardUrl(url, key, m.card),
      };
      if (!media.card) media.hero = await heroUrl(url, key, m.card.banner);   // วาดรูปหัวการ์ดไม่ได้ → หัวการ์ดแบบเดิม
      try { await push(lineToken, m.line_group_id, flexMessages(m.card, media)); ok = true; }
      catch (e) { console.warn('[line-doc-alert] flex failed', e instanceof Error ? e.message : 'error'); }
      if (!ok && media.card) {   // การ์ดรูปไม่ผ่าน → ลองการ์ดหัวแบบเดิม
        media.card = null; media.hero = await heroUrl(url, key, m.card.banner);
        try { await push(lineToken, m.line_group_id, flexMessages(m.card, media)); ok = true; }
        catch (e) { console.warn('[line-doc-alert] flex retry failed, fallback text', e instanceof Error ? e.message : 'error'); }
      }
    }
    if (!ok) {
      try { await push(lineToken, m.line_group_id, texts); ok = true; }
      catch (e) { console.warn('[line-doc-alert] push failed', e instanceof Error ? e.message : 'error'); }
    }
    if (!ok) { failed++; continue; }
    sent++;
    try {
      const n = await rpc(url, key, 'line_doc_alert_mark', { p_line_group_id: m.line_group_id, p_items: m.items, p_skipped: false });
      items += typeof n === 'number' ? n : 0;
    } catch (_) {
      console.warn('[line-doc-alert] mark failed');
    }
  }

  const detail = { groups: list.length, sent, items, failed };
  if (list.length) { try { await rpc(url, key, 'line_doc_alert_audit', { p_detail: detail }); } catch (_) { /* best effort */ } }
  return json(200, { ok: true, ...detail });
});
