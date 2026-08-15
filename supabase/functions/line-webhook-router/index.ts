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
//   C) ข้อความในกลุ่ม MITANG_COMMAND_GROUP_IDS ที่ขึ้นต้นด้วย "มีตัง"
//                                        → ตอบคำสั่งพื้นฐานแบบ deterministic (ไม่ใช้ AI)
//   D) ข้อความทั่วไป / กลุ่มอื่น         → เงียบ (200)
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
  replyToken?: string;
  source?: LineSource;
  message?: { type?: string; text?: string };
}

type MeetangCommand = 'help' | 'status' | 'document-count' | 'unknown';

interface MeetangCommandEvent {
  command: MeetangCommand;
  groupId: string;
  userId: string;
  replyToken: string;
}

const MEETANG_HELP = [
  'มีตัง 🐱💰 พร้อมช่วยงานแบบคำสั่งพื้นฐาน',
  '',
  'คำสั่งที่ใช้ได้:',
  '• มีตัง ช่วยอะไรได้บ้าง',
  '• มีตัง สถานะ',
  '• มีตัง จำนวนเอกสาร',
  '',
  'ตอนนี้ยังไม่ใช้ AI และจะไม่ตอบข้อความทั่วไปในกลุ่ม',
].join('\n');

function parseMeetangCommand(text: string | undefined): MeetangCommand | null {
  if (typeof text !== 'string') return null;

  // ต้องขึ้นต้นด้วยชื่อบอทโดยตรง (ไม่ต้อง @) และไม่จับคำที่เพียงขึ้นต้นคล้ายกัน เช่น "มีตังค์"
  const match = /^มีตัง(?:\s*[:：]\s*|\s+|$)(.*)$/u.exec(text.trim());
  if (!match) return null;

  const body = match[1].trim().toLowerCase();
  if (!body || ['help', 'ช่วย', 'ช่วยอะไรได้บ้าง', 'คำสั่ง', 'ดูคำสั่ง'].includes(body)) {
    return 'help';
  }
  if (['status', 'สถานะ', 'เช็กสถานะ', 'เช็คสถานะ'].includes(body)) {
    return 'status';
  }
  if (
    ['เอกสาร', 'จำนวนเอกสาร', 'เอกสารทั้งหมด', 'เอกสารวันนี้', 'เอกสารวันนี้กี่ไฟล์'].includes(body) ||
    (body.startsWith('เอกสาร') && /(กี่|จำนวน|วันนี้|ทั้งหมด)/u.test(body))
  ) {
    return 'document-count';
  }
  return 'unknown';
}

function bangkokDayRange(now = new Date()): { start: string; end: string } {
  // Bangkok is UTC+7 year-round (no daylight-saving time).
  const bangkokOffsetMs = 7 * 60 * 60 * 1000;
  const local = new Date(now.getTime() + bangkokOffsetMs);
  const startMs = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()) -
    bangkokOffsetMs;
  return {
    start: new Date(startMs).toISOString(),
    end: new Date(startMs + 24 * 60 * 60 * 1000).toISOString(),
  };
}

async function countLineInbox(
  supabaseUrl: string,
  serviceKey: string,
  groupId: string,
  extraFilters = '',
): Promise<number> {
  const url = `${supabaseUrl}/rest/v1/line_file_inbox` +
    `?select=id&line_group_id=eq.${encodeURIComponent(groupId)}${extraFilters}`;
  const res = await fetch(url, {
    method: 'HEAD',
    headers: {
      'Authorization': `Bearer ${serviceKey}`,
      'apikey': serviceKey,
      'Prefer': 'count=exact',
      'Range': '0-0',
      'Range-Unit': 'items',
    },
  });
  if (!res.ok) throw new Error(`document count ${res.status}`);

  const contentRange = res.headers.get('content-range') || '';
  const total = Number(contentRange.split('/').pop());
  if (!Number.isSafeInteger(total) || total < 0) {
    throw new Error('document count missing Content-Range');
  }
  return total;
}

async function buildMeetangReply(
  command: MeetangCommand,
  groupId: string,
  supabaseUrl: string,
  serviceKey: string,
): Promise<string> {
  if (command === 'help') return MEETANG_HELP;
  if (command === 'status') {
    return [
      'มีตังพร้อมใช้งาน 🐱💰',
      'สถานะ: คำสั่งพื้นฐาน V1',
      'AI: ปิด',
      'การรับรูป/PDF/Excel: ใช้ระบบเดิม',
    ].join('\n');
  }
  if (command === 'unknown') {
    return 'มีตังยังไม่รู้จักคำสั่งนี้\nพิมพ์ “มีตัง ช่วยอะไรได้บ้าง” เพื่อดูคำสั่งที่ใช้ได้';
  }

  const { start, end } = bangkokDayRange();
  const [today, pending, total] = await Promise.all([
    countLineInbox(
      supabaseUrl,
      serviceKey,
      groupId,
      `&created_at=gte.${encodeURIComponent(start)}&created_at=lt.${encodeURIComponent(end)}`,
    ),
    countLineInbox(supabaseUrl, serviceKey, groupId, '&status=eq.pending'),
    countLineInbox(supabaseUrl, serviceKey, groupId),
  ]);
  return [
    'จำนวนเอกสารของกลุ่มนี้',
    `วันนี้: ${today.toLocaleString('th-TH')} ไฟล์`,
    `รอดำเนินการ: ${pending.toLocaleString('th-TH')} ไฟล์`,
    `ทั้งหมด: ${total.toLocaleString('th-TH')} ไฟล์`,
  ].join('\n');
}

async function replyLineText(replyToken: string, text: string, channelAccessToken: string): Promise<void> {
  const res = await fetch('https://api.line.me/v2/bot/message/reply', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${channelAccessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ replyToken, messages: [{ type: 'text', text }] }),
  });
  if (!res.ok) throw new Error(`LINE reply HTTP ${res.status}`);
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
  const channelAccessToken = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN');

  // routing config
  const docinboxSet = parseGroupSet(Deno.env.get('LINE_DOCINBOX_GROUP_IDS'));
  // แยกจาก doc-inbox โดยตั้งใจ; ไม่ตั้งค่าหรือค่าว่าง = ไม่มี command group (fail-closed)
  const meetangCommandSet = parseGroupSet(Deno.env.get('MITANG_COMMAND_GROUP_IDS'));
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
  const meetangEvents: MeetangCommandEvent[] = [];
  let hasPdfGroupEvent = false;
  for (const ev of events) {
    const gid = ev.source?.groupId || '';
    if (!gid) continue;
    if (docinboxSet.has(gid)) {
      // คง flow เดิมครบทุก event; line-doc-inbox จะเลือกเก็บเฉพาะ image/file เอง
      docinboxEvents.push(ev);
    } else if (pdfSet.has(gid)) hasPdfGroupEvent = true;

    // command allowlist เป็นอิสระจาก doc-inbox; Set ว่างจะไม่ผ่านเงื่อนไขนี้ทั้งหมด
    if (meetangCommandSet.has(gid)) {
      const command = ev.message?.type === 'text'
        ? parseMeetangCommand(ev.message.text)
        : null;
      if (command && ev.replyToken) {
        meetangEvents.push({
          command,
          groupId: gid,
          userId: ev.source?.userId || '',
          replyToken: ev.replyToken,
        });
      }
    }
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

  // ── C) มีตัง: ตอบเฉพาะข้อความที่ขึ้นต้นด้วยชื่อ ใน command group ที่อนุญาต ──
  // ข้อความทั่วไปไม่มี entry ใน meetangEvents จึงเงียบเหมือนเดิม
  if (meetangEvents.length > 0) {
    if (!channelAccessToken) {
      console.error('[line-router] LINE_CHANNEL_ACCESS_TOKEN missing; commands skipped');
    } else {
      for (const item of meetangEvents) {
        try {
          let reply: string;
          try {
            reply = await buildMeetangReply(item.command, item.groupId, supabaseUrl, serviceKey);
          } catch (e) {
            console.error('[line-router] command data error:', e instanceof Error ? e.message : e);
            reply = 'มีตังตรวจข้อมูลไม่สำเร็จในขณะนี้ กรุณาลองใหม่อีกครั้ง';
          }
          await replyLineText(item.replyToken, reply, channelAccessToken);
        } catch (e) {
          console.error('[line-router] command reply error:', e instanceof Error ? e.message : e);
        }
      }
    }
  }

  console.log(
    `[line-router] events=${events.length} docinbox=${docinboxEvents.length} ` +
      `pdfForward=${hasPdfGroupEvent} commands=${meetangEvents.length}`,
  );
  // ── D) + valid-but-ignored: ตอบ 200 เสมอ กัน LINE retry ──
  return new Response(JSON.stringify({ ok: true }), {
    status: 200, headers: { 'Content-Type': 'application/json' },
  });
});
