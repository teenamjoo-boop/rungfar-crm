// =============================================================
// LINE Webhook Router — Supabase Edge Function (Stage 29B)
//
// บทบาท: เป็น "URL webhook เดียว" ของ LINE OA (ตั้งใน LINE Developers)
//   ใช้ OA เดียว / channel secret เดียว — แล้ว route ตาม groupId
//
//   A) กลุ่มใน LINE_DOCINBOX_GROUP_IDS  → ส่ง event รูป/ไฟล์ ให้ line-doc-inbox
//                                          (เก็บเป็น pending ใน CRM, เงียบ ไม่ตอบกลุ่ม)
//   B) กลุ่มใน LINE_PDF_HELPER_GROUP_IDS / PDF_ALLOWED_GROUP_IDS / LINE_AI_CONTROL_GROUP_ID
//                                        → forward raw body + x-line-signature เดิม
//                                          ไปยัง line-ai-excel-helper (ของเดิม ไม่แตะ internals)
//   C) กลุ่มอื่น                          → เงียบ (200)
//
// หมายเหตุสำคัญ:
//   * Attendance notify เป็น "ขาออก" (CRM → LINE push) — ไม่เกี่ยวกับ webhook นี้
//     กลุ่มหลักจึงรับทั้ง attendance (ขาออก) และ doc inbox (ขาเข้า) พร้อมกันได้
//   * helper ตรวจ signature เองอยู่แล้ว และ filter เฉพาะกลุ่มที่อนุญาตของมันเอง
//     → forward raw body ทั้งก้อนได้ปลอดภัย ตราบใดที่ docinbox/pdf group "ไม่ทับกัน"
//   * ❗ ตั้ง Edge Function นี้ให้ verify_jwt = false (รับ LINE webhook ที่ไม่มี Supabase JWT)
// =============================================================

interface LineSource { type?: string; groupId?: string; userId?: string }
interface LineEvent {
  type?: string;
  source?: LineSource;
  message?: { type?: string };
}

// ─── Signature validation (Base64(HMAC-SHA256(channelSecret, rawBody))) ───────
//    timing-safe compare — ต้องคำนวณจาก raw body ตรง ๆ (ห้าม re-serialize)
async function validateSignature(
  rawBody: string, signature: string | null, channelSecret: string,
): Promise<boolean> {
  if (!signature) return false;
  try {
    const enc = new TextEncoder();
    const key = await crypto.subtle.importKey(
      'raw', enc.encode(channelSecret),
      { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
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
    console.error('[line-router] signature error:', e instanceof Error ? e.message : e);
    return false;
  }
}

function parseGroupSet(...raws: (string | undefined)[]): Set<string> {
  const s = new Set<string>();
  for (const raw of raws) {
    if (!raw) continue;
    for (const part of raw.split(',')) {
      const v = part.trim();
      if (v) s.add(v);
    }
  }
  return s;
}

// ─── Main ────────────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const rawBody   = await req.text();
  const signature = req.headers.get('x-line-signature');

  // ── secrets ──
  const supabaseUrl   = Deno.env.get('SUPABASE_URL');
  const serviceKey    = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const channelSecret = Deno.env.get('LINE_CHANNEL_SECRET');

  // routing config
  const docinboxSet = parseGroupSet(Deno.env.get('LINE_DOCINBOX_GROUP_IDS'));
  const pdfSet = parseGroupSet(
    Deno.env.get('LINE_PDF_HELPER_GROUP_IDS'),
    Deno.env.get('PDF_ALLOWED_GROUP_IDS'),
    Deno.env.get('LINE_AI_CONTROL_GROUP_ID'),
  );
  // ปลายทางของ sibling functions
  const docInboxUrl = `${supabaseUrl}/functions/v1/line-doc-inbox`;
  const helperUrl   = Deno.env.get('LINE_AI_EXCEL_HELPER_URL')
    || `${supabaseUrl}/functions/v1/line-ai-excel-helper`;

  if (!supabaseUrl || !serviceKey || !channelSecret) {
    console.error('[line-router] missing required secrets');
    // ตอบ 200 กัน LINE retry ถล่ม
    return new Response(JSON.stringify({ ok: false, error: 'not configured' }), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    });
  }

  // ── verify signature (mandatory) ──
  const valid = await validateSignature(rawBody, signature, channelSecret);
  if (!valid) {
    console.warn('[line-router] invalid signature');
    return new Response('Unauthorized', { status: 401 });
  }

  // ── parse ──
  let payload: { events?: LineEvent[] };
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return new Response('Bad Request', { status: 400 });
  }
  const events = Array.isArray(payload.events) ? payload.events : [];

  // ── split events by destination ──
  const docinboxEvents: LineEvent[] = [];
  let hasPdfGroupEvent = false;
  for (const ev of events) {
    const gid = ev.source?.groupId || '';
    if (!gid) continue;
    if (docinboxSet.has(gid)) docinboxEvents.push(ev);
    else if (pdfSet.has(gid)) hasPdfGroupEvent = true;
    // อื่น ๆ: เงียบ
  }

  // ── A) doc-inbox: ส่ง subset ให้ worker (internal, service-role auth) ──
  if (docinboxEvents.length > 0) {
    try {
      const res = await fetch(docInboxUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${serviceKey}`,
          'apikey':        serviceKey,
          'Content-Type':  'application/json',
        },
        body: JSON.stringify({ events: docinboxEvents }),
      });
      if (!res.ok) console.error(`[line-router] doc-inbox call ${res.status}: ${await res.text()}`);
    } catch (e) {
      console.error('[line-router] doc-inbox call error:', e instanceof Error ? e.message : e);
    }
  }

  // ── B) PDF helper: forward raw body + original signature (helper self-validates) ──
  //    helper filter กลุ่มของมันเอง → ส่ง raw ทั้งก้อนปลอดภัย
  if (hasPdfGroupEvent) {
    try {
      const res = await fetch(helperUrl, {
        method: 'POST',
        headers: {
          'Content-Type':     'application/json',
          'x-line-signature': signature || '',
        },
        body: rawBody,
      });
      if (!res.ok) console.error(`[line-router] helper forward ${res.status}: ${await res.text()}`);
    } catch (e) {
      console.error('[line-router] helper forward error:', e instanceof Error ? e.message : e);
    }
  }

  console.log(
    `[line-router] events=${events.length} docinbox=${docinboxEvents.length} pdfForward=${hasPdfGroupEvent}`,
  );
  // ── C) + valid-but-ignored: ตอบ 200 เสมอ กัน LINE retry ──
  return new Response(JSON.stringify({ ok: true }), {
    status: 200, headers: { 'Content-Type': 'application/json' },
  });
});
