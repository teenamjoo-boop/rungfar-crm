// =============================================================
// LINE Attendance Notify — Supabase Edge Function
// เวอร์ชัน: 1.2.0  |  อัพเดต: 2026-05-26
//
// รับ POST { type, attendance_log_id }
// → query attendance_logs ด้วย service role (ห้าม trust frontend)
// → สร้าง Flex Message 2 แบบ แยก builder อิสระ:
//     buildGroupMainFlexMessage  — card สั้น (ชื่อ/สาขา/เวลา/รูป)
//     buildGroupAdminFlexMessage — card เต็ม (ครบทุก field)
// → push ไป "กลุ่มรวม" (MAIN) กลุ่มเดียว (single-group mode)
// → ถ้า Flex ส่งไม่ผ่าน → fallback เป็น text อัตโนมัติ
// → return 200 เสมอ — LINE fail ≠ attendance fail
// =============================================================

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// ─── Time & Date Helpers ───────────────────────────────────────────────────────

/**
 * แปลง ISO timestamptz UTC → HH:MM เวลาไทย (Asia/Bangkok)
 * เช่น "2026-05-23T17:27:28+00:00" → "00:27"
 * ใช้ sv-SE locale ซึ่งให้ "YYYY-MM-DD HH:MM:SS" — slice HH:MM ได้เสมอ
 */
function formatThaiTime(isoStr: string | null | undefined): string {
  if (!isoStr) return '—';
  try {
    const d = new Date(isoStr);
    if (isNaN(d.getTime())) return '—';
    const s = d.toLocaleString('sv-SE', { timeZone: 'Asia/Bangkok' });
    // sv-SE → "YYYY-MM-DD HH:MM:SS"
    return s.slice(11, 16); // HH:MM
  } catch {
    return '—';
  }
}

/**
 * แปลง YYYY-MM-DD → "24 พฤษภาคม 2569" (วันที่เต็ม เดือนเต็ม ปีพุทธศักราชเต็ม 4 หลัก)
 * log_date เป็น date-only ไม่มี timezone — parse ตรงได้เลย
 */
function formatThaiFullDate(dateStr: string | null | undefined): string {
  if (!dateStr) return '—';
  try {
    const m = dateStr.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (!m) return dateStr;
    const y = Number(m[1]), mo = Number(m[2]), d = Number(m[3]);
    const months = [
      'มกราคม','กุมภาพันธ์','มีนาคม','เมษายน','พฤษภาคม','มิถุนายน',
      'กรกฎาคม','สิงหาคม','กันยายน','ตุลาคม','พฤศจิกายน','ธันวาคม',
    ];
    const thYear = y + 543; // 2026 → 2569 (4 หลักเต็ม)
    return `${d} ${months[mo - 1]} ${thYear}`;
  } catch {
    return dateStr ?? '—';
  }
}

/** แปลง นาที → "X ชม. Y นาที" */
function formatWorkTime(minutes: number | null | undefined): string {
  if (!minutes || minutes <= 0) return '—';
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h > 0 && m > 0) return `${h} ชม. ${m} นาที`;
  if (h > 0) return `${h} ชม.`;
  return `${m} นาที`;
}

/** gps_status → ข้อความไทยธรรมชาติ */
function gpsStatusTH(status: string | null | undefined): string {
  switch (status) {
    case 'in_area':     return 'อยู่ในพื้นที่';
    case 'out_of_area': return 'อยู่นอกพื้นที่';
    case 'no_gps':      return 'ไม่มี GPS';
    case 'no_coords':   return 'ไม่มีพิกัดสาขา';
    default:            return status ?? 'ไม่ทราบ';
  }
}

/**
 * แปลง normal_checkin_time / normal_checkout_time → "08:30 - 17:30"
 * DB เก็บ format "HH:MM:SS" → ใช้ slice(0,5) ได้ HH:MM
 */
function formatBranchHours(
  cin:  string | null | undefined,
  cout: string | null | undefined,
): string {
  const inStr  = cin  ? String(cin).slice(0, 5)  : null;
  const outStr = cout ? String(cout).slice(0, 5) : null;
  if (inStr && outStr) return `${inStr} - ${outStr}`;
  if (inStr)           return `เริ่ม ${inStr}`;
  if (outStr)          return `ถึง ${outStr}`;
  return '-';
}

// ─── Flex Component Helpers ────────────────────────────────────────────────────

type FlexComponent = Record<string, unknown>;

/** แถว label : value แนวนอน */
function makeRow(label: string, value: string, bold = false): FlexComponent {
  return {
    type: 'box',
    layout: 'horizontal',
    contents: [
      {
        type: 'text', text: label,
        color: '#888888', size: 'sm', flex: 3, gravity: 'center',
      },
      {
        type: 'text', text: value || '—',
        size: 'sm', flex: 5,
        weight: bold ? 'bold' : 'regular',
        wrap: true, gravity: 'center',
      },
    ],
  };
}

/** เส้นคั่น */
function makeSep(): FlexComponent {
  return { type: 'separator', margin: 'sm' };
}

/** Footer */
function makeFooter(): FlexComponent {
  return {
    type: 'box',
    layout: 'vertical',
    paddingAll: '10px',
    backgroundColor: '#F5F5F5',
    contents: [{
      type: 'text', text: 'Rungfa Labor CRM',
      color: '#AAAAAA', size: 'xs', align: 'center',
    }],
  };
}

// ─── MAIN Flex Message (กลุ่มพนักงาน — card สั้น) ────────────────────────────
// แสดงเฉพาะ: วันที่ / พนักงาน (ชื่อเท่านั้น ไม่มีรหัส) / สาขา / เวลา / รูป
// ไม่มี GPS / ระยะทาง / สถานะ / OT / ชั่วโมงทำงาน
// builder นี้เป็นอิสระจาก Admin — แก้ไขแต่ละกลุ่มได้โดยไม่กระทบกัน

function buildGroupMainFlexMessage(log: Record<string, unknown>, type: string): FlexComponent {
  const isCheckin   = type === 'checkin';
  const name        = (log.employee_name as string) || '—';   // ชื่อเท่านั้น ไม่มีรหัส
  const branch      = (log.branch_name as string) || '—';
  const logDate     = formatThaiFullDate(log.log_date as string);

  // ── Header ──────────────────────────────────────────────────────
  // เขียว = เข้างาน, น้ำเงิน = ออกงาน — คงสีตามประเภทเสมอ ไม่เปลี่ยนตามสถานะ
  const headerColor = isCheckin ? '#27AE60' : '#1AACEE';
  const headerTitle = isCheckin ? 'เข้างาน' : 'ออกงาน';

  // ── Body rows ────────────────────────────────────────────────────
  let bodyRows: FlexComponent[];

  if (isCheckin) {
    const time = formatThaiTime(log.checkin_time as string);
    bodyRows = [
      makeRow('พนักงาน', name,   true),
      makeRow('สาขา',    branch),
      makeSep(),
      makeRow('เวลา',    time,   true),
    ];
  } else {
    const timeIn  = formatThaiTime(log.checkin_time  as string);
    const timeOut = formatThaiTime(log.checkout_time as string);
    bodyRows = [
      makeRow('พนักงาน',  name,    true),
      makeRow('สาขา',     branch),
      makeSep(),
      makeRow('เวลาเข้า', timeIn),
      makeRow('เวลาออก',  timeOut, true),
    ];
  }

  // ── Bubble ───────────────────────────────────────────────────────
  const bubble: FlexComponent = {
    type: 'bubble',
    header: {
      type: 'box',
      layout: 'vertical',
      paddingTop: '14px',
      paddingBottom: '12px',
      paddingStart: '16px',
      paddingEnd: '16px',
      backgroundColor: headerColor,
      contents: [
        {
          type: 'text',
          text: headerTitle,
          color: '#FFFFFF',
          size: 'xxl',
          weight: 'bold',
          align: 'center',
        },
        {
          type: 'text',
          text: logDate,
          color: '#FFFFFFCC',
          size: 'sm',
          align: 'center',
          margin: 'sm',
        },
      ],
    },
    body: {
      type: 'box',
      layout: 'vertical',
      paddingAll: '16px',
      spacing: 'sm',
      contents: bodyRows,
    },
    footer: makeFooter(),
  };

  const altText = isCheckin
    ? `แจ้งเตือนเข้างาน: ${name}`
    : `แจ้งเตือนออกงาน: ${name}`;

  return { type: 'flex', altText, contents: bubble };
}

/** Text fallback สำหรับ MAIN (กรณี Flex ส่งไม่ได้) */
function buildMainTextFallback(log: Record<string, unknown>, type: string): string {
  const isCheckin = type === 'checkin';
  const name      = (log.employee_name as string) || '—';
  const branch    = (log.branch_name as string) || '—';
  const date      = formatThaiFullDate(log.log_date as string);
  const time      = isCheckin
    ? formatThaiTime(log.checkin_time  as string)
    : formatThaiTime(log.checkout_time as string);
  return [
    isCheckin ? 'เข้างาน' : 'ออกงาน',
    `พนักงาน: ${name}`,
    `สาขา: ${branch}`,
    `วันที่: ${date}`,
    `เวลา: ${time}`,
  ].join('\n');
}

// ─── ADMIN Flex Message (card เต็ม — ข้อมูลละเอียด) ──────────────────────────
// builder นี้เป็นอิสระจาก MAIN — แก้ไขแต่ละกลุ่มได้โดยไม่กระทบกัน

function buildAdminFlexBubble(
  log: Record<string, unknown>,
  type: string,
  branchHours: string,        // "08:30 - 17:30" หรือ "-" จาก query branches
): FlexComponent {
  const isCheckin = type === 'checkin';
  const name      = (log.employee_name as string) || '—';
  // Stage 50A-11: ไม่แสดงรหัสพนักงาน (เช่น EMP003) บนการ์ดแล้ว — จึงไม่ต้องอ่าน employee_code
  const branch    = (log.branch_name as string) || '—';
  const logDate      = formatThaiFullDate(log.log_date as string);
  const gpsText      = gpsStatusTH(log.gps_status as string);
  const isOutside    = !!(log.is_out_of_area);

  // ── สีและหัวข้อ header (ไม่มี emoji) ──────────────────────────────
  let headerColor = '#27AE60'; // เขียว = เข้างานปกติ
  let headerTitle = 'เข้างาน';
  let statusText  = 'ปกติ';
  let bodyRows: FlexComponent[] = [];

  if (isCheckin) {
    const time      = formatThaiTime(log.checkin_time as string);
    const lateMin   = (log.late_minutes as number) || 0;
    const distM     = log.checkin_distance_m as number | null;
    const distText  = distM != null ? `${Math.round(distM)} ม.` : '—';
    const hasSelfie = log.checkin_selfie ? 'มีรูปในระบบ' : 'ไม่มีรูป';

    // header คงสีเขียวเสมอ ไม่ว่าจะสายหรือนอกพื้นที่
    // สถานะแสดงใน field "สถานะ" เท่านั้น
    if (isOutside)        statusText = 'อยู่นอกพื้นที่';
    else if (lateMin > 0) statusText = `สาย ${lateMin} นาที`;

    bodyRows = [
      makeRow('พนักงาน',    name, true),
      makeRow('สาขา',       branch),
      makeRow('เวลาทำการ',  branchHours),
      makeSep(),
      makeRow('เวลา',       time, true),
      makeRow('สถานะ',      statusText, lateMin > 0 || isOutside),
      makeSep(),
      makeRow('GPS',        gpsText),
      makeRow('ระยะจากสาขา', distText),
      makeSep(),
      makeRow('รูปเข้างาน', hasSelfie),
    ];

  } else {
    // checkout
    const timeIn    = formatThaiTime(log.checkin_time  as string);
    const timeOut   = formatThaiTime(log.checkout_time as string);
    const workText  = formatWorkTime(log.total_work_minutes as number);
    const otMin     = (log.ot_minutes as number) || 0;
    const otText    = otMin > 0 ? formatWorkTime(otMin) : '-';
    const earlyMin  = (log.early_leave_minutes as number) || 0;
    const distM    = log.checkout_distance_m as number | null;
    const distText = distM != null ? `${Math.round(distM)} ม.` : '—';
    // ไม่มี hasSelfie — ระบบไม่ถ่ายรูปตอนออกงาน จึงไม่แสดง row รูปออกงาน

    // สรุปงานรายวัน — แสดงเฉพาะรายการที่กรอก; รองรับ items array (ใหม่) + fallback เก่า
    type WsItem = { type: string; detail: string };
    const wsItems = (log.work_summary_items as WsItem[] | null);
    const wsSummaryRows: FlexComponent[] = [];
    if (wsItems && Array.isArray(wsItems) && wsItems.length > 0) {
      for (const item of wsItems) {
        const d = item.detail && item.detail.length > 100
          ? item.detail.slice(0, 100) + '...'
          : (item.detail || '-');
        wsSummaryRows.push(makeRow(item.type, d));
      }
    } else {
      // fallback: log เก่า ใช้ work_summary_type + work_summary_detail
      const wsTypeFb = (log.work_summary_type as string) || '';
      const wsRawFb  = (log.work_summary_detail as string) || '';
      if (wsRawFb || wsTypeFb) {
        const d = wsRawFb.length > 100 ? wsRawFb.slice(0, 100) + '...' : (wsRawFb || '-');
        const lbl = wsTypeFb && wsTypeFb !== 'multi' ? wsTypeFb : 'สรุปงาน';
        wsSummaryRows.push(makeRow(lbl, d));
      }
    }

    headerColor = '#1AACEE'; // ฟ้าสว่าง = ออกงาน
    headerTitle = 'ออกงาน';

    if (isOutside)         statusText = 'อยู่นอกพื้นที่';
    else if (earlyMin > 0) statusText = `ออกก่อน ${earlyMin} นาที`;

    bodyRows = [
      makeRow('พนักงาน',    name, true),
      makeRow('สาขา',       branch),
      makeRow('เวลาทำการ',  branchHours),
      makeSep(),
      makeRow('เวลาเข้า',  timeIn),
      makeRow('เวลาออก',   timeOut, true),
      makeRow('ชม.ทำงาน',  workText, true),
      makeRow('OT',         otText, otMin > 0),
      makeRow('สถานะ',      statusText, earlyMin > 0 || isOutside),
      makeSep(),
      makeRow('GPS',        gpsText),
      makeRow('ระยะจากสาขา', distText),
      ...(wsSummaryRows.length > 0 ? [
        makeSep(),
        // slim blue header bar (สีเดียวกับ header ออกงาน แต่บางกว่ามาก) — label กลาง ตัวอักษรขาว
        {
          type: 'box',
          layout: 'vertical',
          backgroundColor: '#1AACEE',
          paddingTop: '4px',
          paddingBottom: '4px',
          paddingStart: '8px',
          paddingEnd: '8px',
          cornerRadius: '4px',
          margin: 'sm',
          contents: [
            { type: 'text', text: 'สรุปงานรายวัน', size: 'xs', weight: 'bold',
              color: '#FFFFFF', align: 'center' },
          ],
        } as FlexComponent,
        ...wsSummaryRows,
      ] : []),
    ];
  }

  return {
    type: 'bubble',
    header: {
      type: 'box',
      layout: 'vertical',
      paddingTop: '10px',
      paddingBottom: '8px',
      paddingStart: '16px',
      paddingEnd: '16px',
      backgroundColor: headerColor,
      contents: [
        {
          // หัวข้อหลัก — กึ่งกลาง ไม่มี emoji (xl = ใหญ่ชัด แต่ compact ไม่ทำ header สูง)
          type: 'text',
          text: headerTitle,
          color: '#FFFFFF',
          size: 'xl',
          weight: 'bold',
          align: 'center',
        },
        {
          // วันที่เต็ม — กึ่งกลาง ใต้หัวข้อ
          type: 'text',
          text: logDate,
          color: '#FFFFFFCC',
          size: 'xs',
          align: 'center',
          margin: 'xs',
        },
      ],
    },
    body: {
      type: 'box',
      layout: 'vertical',
      paddingAll: '12px',
      spacing: 'xs',
      contents: bodyRows,
    },
    footer: makeFooter(),
  };
}

function buildGroupAdminFlexMessage(
  log: Record<string, unknown>,
  type: string,
  branchHours: string,
): FlexComponent {
  const isCheckin = type === 'checkin';
  const name      = (log.employee_name as string) || (log.employee_code as string) || '—';
  const lateMin   = (log.late_minutes as number) || 0;
  const isOutside = !!(log.is_out_of_area);
  let hint = '';
  if (isOutside)        hint = ' — อยู่นอกพื้นที่';
  else if (lateMin > 0) hint = ` — สาย ${lateMin} นาที`;
  const altText = isCheckin
    ? `แจ้งเตือนเข้างาน: ${name}${hint}`
    : `แจ้งเตือนออกงาน: ${name}`;
  return {
    type: 'flex',
    altText,
    contents: buildAdminFlexBubble(log, type, branchHours),
  };
}

/** Text fallback สำหรับ ADMIN (กรณี Flex ส่งไม่ได้) */
function buildAdminTextFallback(log: Record<string, unknown>, type: string): string {
  const isCheckin    = type === 'checkin';
  const name      = (log.employee_name as string) || '—';
  // Stage 50A-11: ไม่แสดงรหัสพนักงาน (เช่น EMP003) บนการ์ด/ข้อความ fallback แล้ว
  const branch    = (log.branch_name as string) || '—';
  const gpsText   = gpsStatusTH(log.gps_status as string);
  const isOutside = !!(log.is_out_of_area);
  const date      = formatThaiFullDate(log.log_date as string);

  if (isCheckin) {
    const time      = formatThaiTime(log.checkin_time as string);
    const lateMin   = (log.late_minutes as number) || 0;
    const distM     = log.checkin_distance_m as number | null;
    const distText  = distM != null ? `${Math.round(distM)} ม.` : '—';
    const hasSelfie = log.checkin_selfie ? 'มีรูปในระบบ' : 'ไม่มีรูป';
    let status = 'ปกติ';
    if (isOutside)        status = 'อยู่นอกพื้นที่';
    else if (lateMin > 0) status = `สาย ${lateMin} นาที`;
    return [
      'เข้างาน',
      `พนักงาน: ${name}`, `สาขา: ${branch}`,
      `วันที่: ${date}`, `เวลา: ${time}`, `สถานะ: ${status}`,
      `GPS: ${gpsText}`, `ระยะจากสาขา: ${distText}`,
      `รูปเข้างาน: ${hasSelfie}`,
    ].join('\n');
  } else {
    const timeIn    = formatThaiTime(log.checkin_time  as string);
    const timeOut   = formatThaiTime(log.checkout_time as string);
    const workText  = formatWorkTime(log.total_work_minutes as number);
    const otMin     = (log.ot_minutes as number) || 0;
    const otText    = otMin > 0 ? formatWorkTime(otMin) : '-';
    const earlyMin  = (log.early_leave_minutes as number) || 0;
    const distM    = log.checkout_distance_m as number | null;
    const distText = distM != null ? `${Math.round(distM)} ม.` : '—';
    // ไม่มี hasSelfie — ระบบไม่ถ่ายรูปตอนออกงาน
    let status = 'ปกติ';
    if (isOutside)         status = 'อยู่นอกพื้นที่';
    else if (earlyMin > 0) status = `ออกก่อน ${earlyMin} นาที`;
    // สรุปงานรายวัน — items array ใหม่ หรือ fallback เก่า
    const wsItemsFb = (log.work_summary_items as Array<{type: string; detail: string}> | null);
    let wsLines: string[] = [];
    if (wsItemsFb && Array.isArray(wsItemsFb) && wsItemsFb.length > 0) {
      wsLines = wsItemsFb.map(x => {
        const d = x.detail.length > 100 ? x.detail.slice(0, 100) + '...' : x.detail;
        return `${x.type}: ${d}`;
      });
    } else {
      const wsTypeFb = (log.work_summary_type as string) || '';
      const wsRawFb  = (log.work_summary_detail as string) || '';
      if (wsRawFb || wsTypeFb) {
        const d = wsRawFb.length > 100 ? wsRawFb.slice(0, 100) + '...' : (wsRawFb || '-');
        const lbl = wsTypeFb && wsTypeFb !== 'multi' ? wsTypeFb + ': ' : '';
        wsLines.push(lbl + d);
      }
    }
    return [
      'ออกงาน',
      `พนักงาน: ${name}`, `สาขา: ${branch}`,
      `วันที่: ${date}`, `เวลาเข้า: ${timeIn}`, `เวลาออก: ${timeOut}`,
      `ชม.ทำงาน: ${workText}`, `OT: ${otText}`,
      `สถานะ: ${status}`, `GPS: ${gpsText}`,
      `ระยะจากสาขา: ${distText}`,
      ...(wsLines.length > 0 ? ['สรุปงานรายวัน:', ...wsLines] : []),
    ].join('\n');
  }
}

// ─── LINE Push ─────────────────────────────────────────────────────────────────

async function pushLineMessages(
  groupId: string,
  messages: unknown[],
  token: string,
): Promise<void> {
  const res = await fetch('https://api.line.me/v2/bot/message/push', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify({ to: groupId, messages }),
  });
  if (!res.ok) {
    const errBody = await res.text();
    throw new Error(`LINE API ${res.status}: ${errBody}`);
  }
}

/**
 * ส่ง Flex ก่อน — ถ้าพัง fallback เป็น text
 * ไม่ throw ออกไป — return result object เสมอ
 */
async function sendGroupMessage(
  groupId: string | undefined,
  flexMsg: unknown,
  textFallback: string,
  token: string,
  label: string,
): Promise<{ sent: boolean; type: 'flex' | 'fallback' | 'none'; error: string | null }> {
  if (!groupId) {
    return { sent: false, type: 'none', error: `${label} Group ID not configured` };
  }
  // ── Try Flex ──
  try {
    await pushLineMessages(groupId, [flexMsg], token);
    return { sent: true, type: 'flex', error: null };
  } catch (flexErr) {
    const flexMsg2 = flexErr instanceof Error ? flexErr.message : String(flexErr);
    console.warn(`[LINE][${label}] Flex failed, trying text fallback:`, flexMsg2);
  }
  // ── Fallback: Text ──
  try {
    await pushLineMessages(groupId, [{ type: 'text', text: textFallback }], token);
    return { sent: true, type: 'fallback', error: null };
  } catch (textErr) {
    const textMsg = textErr instanceof Error ? textErr.message : String(textErr);
    console.warn(`[LINE][${label}] Text fallback also failed:`, textMsg);
    return { sent: false, type: 'none', error: textMsg };
  }
}

// ─── Main Handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  // ── CORS preflight ─────────────────────────────────────────────────
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }

  // ── Result — return 200 เสมอ เพราะ attendance บันทึกไปแล้ว ──────
  const result: {
    ok: boolean;
    log_found: boolean;
    main:         { sent: boolean; type: 'flex' | 'fallback' | 'none'; error: string | null };
    admin:        { sent: boolean; type: 'flex' | 'fallback' | 'none'; error: string | null };
    branch_hours: string | null;  // debug — เวลาทำการที่ query ได้จาก branches table
    warning:      string | null;
    timezone:     string;
  } = {
    ok: false,
    log_found: false,
    main:         { sent: false, type: 'none', error: null },
    admin:        { sent: false, type: 'none', error: null },
    branch_hours: null,
    warning:      null,
    timezone:     'Asia/Bangkok',
  };

  const json200 = () =>
    new Response(JSON.stringify(result), {
      status: 200,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });

  try {
    // ── Parse body ────────────────────────────────────────────────────
    let body: { type?: string; attendance_log_id?: unknown };
    try {
      body = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
        status: 400,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    const { type, attendance_log_id } = body;

    // ── Validate ──────────────────────────────────────────────────────
    if (!type || !['checkin', 'checkout'].includes(type)) {
      return new Response(
        JSON.stringify({ error: 'type must be "checkin" or "checkout"' }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }
    if (!attendance_log_id) {
      return new Response(
        JSON.stringify({ error: 'attendance_log_id is required' }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    // ── Read secrets ──────────────────────────────────────────────────
    // SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY inject อัตโนมัติโดย Supabase
    const supabaseUrl    = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const lineToken      = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN');
    const groupMain      = Deno.env.get('LINE_ATTENDANCE_GROUP_MAIN');
    const groupAdmin     = Deno.env.get('LINE_ATTENDANCE_GROUP_ADMIN');

    if (!supabaseUrl || !serviceRoleKey) {
      console.error('[line-attendance-notify] Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
      result.warning = 'Supabase env not available';
      return json200();
    }
    if (!lineToken) {
      console.warn('[line-attendance-notify] LINE_CHANNEL_ACCESS_TOKEN not set');
      result.warning = 'LINE token not configured';
      return json200();
    }

    // ── Query attendance_logs ด้วย service role ───────────────────────
    // ห้าม trust ข้อมูลจาก frontend — ดึงจาก DB เท่านั้น
    const dbUrl = `${supabaseUrl}/rest/v1/attendance_logs` +
      `?id=eq.${encodeURIComponent(String(attendance_log_id))}&limit=1`;

    const dbRes = await fetch(dbUrl, {
      headers: {
        'apikey':        serviceRoleKey,
        'Authorization': `Bearer ${serviceRoleKey}`,
        'Content-Type':  'application/json',
      },
    });

    if (!dbRes.ok) {
      const errText = await dbRes.text();
      console.error('[line-attendance-notify] DB query failed:', dbRes.status, errText);
      result.warning = `DB query failed (${dbRes.status})`;
      return json200();
    }

    const rows: Record<string, unknown>[] = await dbRes.json();
    if (!Array.isArray(rows) || rows.length === 0) {
      console.warn('[line-attendance-notify] log not found:', attendance_log_id);
      result.warning = `Log not found: ${attendance_log_id}`;
      return json200();
    }

    const log = rows[0];
    result.log_found = true;

    // ── Query branch working hours จาก table branches ─────────────────
    // ใช้ branch_id ก่อน (ถ้ามี) → fallback match ด้วย branch_name
    // ถ้า query ไม่ได้ → ใช้ '-' (ไม่ block การส่ง LINE)
    let branchHours = '-';
    try {
      const branchId   = log.branch_id;
      const branchName = log.branch_name as string | null;

      let branchUrl: string;
      if (branchId != null) {
        branchUrl = `${supabaseUrl}/rest/v1/branches` +
          `?id=eq.${encodeURIComponent(String(branchId))}` +
          `&select=normal_checkin_time,normal_checkout_time&limit=1`;
      } else if (branchName) {
        branchUrl = `${supabaseUrl}/rest/v1/branches` +
          `?name=eq.${encodeURIComponent(branchName)}` +
          `&select=normal_checkin_time,normal_checkout_time&limit=1`;
      } else {
        branchUrl = '';
      }

      if (branchUrl) {
        const brRes = await fetch(branchUrl, {
          headers: {
            'apikey':        serviceRoleKey!,
            'Authorization': `Bearer ${serviceRoleKey}`,
            'Content-Type':  'application/json',
          },
        });
        if (brRes.ok) {
          const brRows: Record<string, unknown>[] = await brRes.json();
          if (Array.isArray(brRows) && brRows.length > 0) {
            branchHours = formatBranchHours(
              brRows[0].normal_checkin_time  as string | null,
              brRows[0].normal_checkout_time as string | null,
            );
          }
        } else {
          console.warn('[line-attendance-notify] branch query failed:', brRes.status);
        }
      }
    } catch (brErr) {
      console.warn('[line-attendance-notify] branch hours query error:', brErr);
      // ไม่ throw — ใช้ '-' แทน
    }
    result.branch_hours = branchHours;

    // ── Build message ─────────────────────────────────────────────────
    // ส่ง "กลุ่มรวม" (MAIN) กลุ่มเดียว — ใช้ card ละเอียด (เดิมของ admin)
    // ไม่ส่งกลุ่ม ADMIN อีกต่อไป (groupAdmin ไม่ถูกใช้แล้ว)
    const mainFlex = buildGroupAdminFlexMessage(log, type, branchHours);
    const mainText = buildAdminTextFallback(log, type);

    // ── Send to MAIN group only (non-throwing) ────────────────────────
    const mainResult = await sendGroupMessage(groupMain, mainFlex, mainText, lineToken, 'MAIN');
    result.main = mainResult;

    // ADMIN group ปิดการส่งแล้ว — รายงานเป็น skipped ชัดเจน
    result.admin = { sent: false, type: 'none', error: 'admin group disabled (single-group mode)' };

    result.ok = result.main.sent;

  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[line-attendance-notify] Unexpected error:', msg);
    result.warning = msg;
    // ไม่ throw — attendance บันทึกไปแล้ว ห้ามทำ frontend fail
  }

  return json200();
});
