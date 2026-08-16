// =============================================================
// LINE Webhook Router — Supabase Edge Function (Stage 29B)
// =============================================================

interface LineSource { type?: string; groupId?: string; userId?: string }
interface LineEvent {
  type?: string;
  replyToken?: string;
  source?: LineSource;
  message?: { type?: string; text?: string };
}

type MeetangCommand = 'help' | 'status' | 'document-count' | 'unknown';
type LineGroupIntakeMode = 'none' | 'observe' | 'capture';
type LineGroupRoutingMode = 'none' | 'source' | 'destination' | 'both';

interface MeetangCommandEvent {
  command: MeetangCommand;
  groupId: string;
  userId: string;
  replyToken: string;
}

interface LineGroupRegistryPlan {
  groupId: string;
  hasJoin: boolean;
  hasCommand: boolean;
  hasLeave: boolean;
}

interface LineGroupSummary {
  groupName: string | null;
  pictureUrl: string | null;
}

interface StoredLineGroup {
  group_id: string;
  joined_at?: string | null;
  command_mode?: string | null;
  intake_mode?: string | null;
  routing_mode?: string | null;
}

interface LineGroupPolicy {
  commandEnabled: boolean;
  intakeMode: LineGroupIntakeMode;
  routingMode: LineGroupRoutingMode;
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
  const match = /^มีตัง(?:\s*[:：]\s*|\s+|$)(.*)$/u.exec(text.trim());
  if (!match) return null;

  const body = match[1].trim().toLowerCase();
  if (!body || ['help', 'ช่วย', 'ช่วยอะไรได้บ้าง', 'คำสั่ง', 'ดูคำสั่ง'].includes(body)) {
    return 'help';
  }
  if (['status', 'สถานะ', 'เช็กสถานะ', 'เช็คสถานะ'].includes(body)) return 'status';
  if (
    ['เอกสาร', 'จำนวนเอกสาร', 'เอกสารทั้งหมด', 'เอกสารวันนี้', 'เอกสารวันนี้กี่ไฟล์'].includes(body) ||
    (body.startsWith('เอกสาร') && /(กี่|จำนวน|วันนี้|ทั้งหมด)/u.test(body))
  ) return 'document-count';
  return 'unknown';
}

function bangkokDayRange(now = new Date()): { start: string; end: string } {
  const bangkokOffsetMs = 7 * 60 * 60 * 1000;
  const local = new Date(now.getTime() + bangkokOffsetMs);
  const startMs = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()) - bangkokOffsetMs;
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
  if (!Number.isSafeInteger(total) || total < 0) throw new Error('document count missing Content-Range');
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

class RegistryHttpError extends Error {
  status: number;
  constructor(status: number) {
    super('registry HTTP request failed');
    this.status = status;
  }
}

const REGISTRY_FETCH_TIMEOUT_MS = 4_000;
const REGISTRY_LOOKUP_BATCH_SIZE = 100;
const REGISTRY_SUMMARY_MAX_CONCURRENCY = 3;

function registryHeaders(serviceKey: string): Record<string, string> {
  return {
    'Authorization': `Bearer ${serviceKey}`,
    'apikey': serviceKey,
    'Content-Type': 'application/json',
  };
}

async function fetchLineGroupSummary(
  groupId: string,
  channelAccessToken: string | undefined,
): Promise<LineGroupSummary> {
  if (!channelAccessToken) throw new Error('LINE channel access token unavailable');
  const res = await fetch(
    `https://api.line.me/v2/bot/group/${encodeURIComponent(groupId)}/summary`,
    {
      method: 'GET',
      headers: { 'Authorization': `Bearer ${channelAccessToken}` },
      signal: AbortSignal.timeout(REGISTRY_FETCH_TIMEOUT_MS),
    },
  );
  if (!res.ok) throw new RegistryHttpError(res.status);

  let body: unknown;
  try {
    body = await res.json();
  } catch {
    throw new Error('invalid LINE group summary');
  }
  if (!body || typeof body !== 'object') throw new Error('invalid LINE group summary');
  const summary = body as Record<string, unknown>;
  return {
    groupName: typeof summary.groupName === 'string' ? summary.groupName : null,
    pictureUrl: typeof summary.pictureUrl === 'string' ? summary.pictureUrl : null,
  };
}

function quotePostgrestValue(value: string): string {
  return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

async function findStoredLineGroups(
  supabaseUrl: string,
  serviceKey: string,
  groupIds: string[],
): Promise<Map<string, StoredLineGroup>> {
  const stored = new Map<string, StoredLineGroup>();
  for (let i = 0; i < groupIds.length; i += REGISTRY_LOOKUP_BATCH_SIZE) {
    const chunk = groupIds.slice(i, i + REGISTRY_LOOKUP_BATCH_SIZE);
    const params = new URLSearchParams({
      select: 'group_id,joined_at,command_mode,intake_mode,routing_mode',
      group_id: `in.(${chunk.map(quotePostgrestValue).join(',')})`,
    });
    const res = await fetch(`${supabaseUrl}/rest/v1/line_bot_groups?${params}`, {
      method: 'GET',
      headers: registryHeaders(serviceKey),
      signal: AbortSignal.timeout(REGISTRY_FETCH_TIMEOUT_MS),
    });
    if (!res.ok) throw new RegistryHttpError(res.status);

    let rows: unknown;
    try {
      rows = await res.json();
    } catch {
      throw new Error('invalid registry response');
    }
    if (!Array.isArray(rows)) throw new Error('invalid registry response');

    for (const row of rows) {
      if (!row || typeof row !== 'object') throw new Error('invalid registry response');
      const record = row as Record<string, unknown>;
      const groupId = record.group_id;
      if (typeof groupId !== 'string') throw new Error('invalid registry response');
      if (record.command_mode !== undefined && record.command_mode !== null && typeof record.command_mode !== 'string') {
        throw new Error('invalid registry response');
      }
      stored.set(groupId, row as StoredLineGroup);
    }
  }
  return stored;
}

async function upsertLineBotGroup(
  supabaseUrl: string,
  serviceKey: string,
  values: Record<string, unknown>,
): Promise<void> {
  const res = await fetch(`${supabaseUrl}/rest/v1/line_bot_groups?on_conflict=group_id`, {
    method: 'POST',
    headers: {
      ...registryHeaders(serviceKey),
      'Prefer': 'resolution=merge-duplicates,return=minimal',
    },
    body: JSON.stringify(values),
    signal: AbortSignal.timeout(REGISTRY_FETCH_TIMEOUT_MS),
  });
  if (!res.ok) throw new RegistryHttpError(res.status);
}

async function updateLineBotGroup(
  supabaseUrl: string,
  serviceKey: string,
  groupId: string,
  values: Record<string, unknown>,
): Promise<void> {
  const url = `${supabaseUrl}/rest/v1/line_bot_groups?group_id=eq.${encodeURIComponent(groupId)}`;
  const res = await fetch(url, {
    method: 'PATCH',
    headers: {
      ...registryHeaders(serviceKey),
      'Prefer': 'return=minimal',
    },
    body: JSON.stringify(values),
    signal: AbortSignal.timeout(REGISTRY_FETCH_TIMEOUT_MS),
  });
  if (!res.ok) throw new RegistryHttpError(res.status);
}

type RegistryOperation = 'lookup' | 'summary' | 'discover' | 'join' | 'command' | 'leave';

function logRegistryFailure(operation: RegistryOperation, error: unknown): void {
  const httpStatus = error instanceof RegistryHttpError ? ` HTTP ${error.status}` : '';
  console.error(`[line-router] group registry ${operation} failed${httpStatus}`);
}

function registryOperationForPlan(plan: LineGroupRegistryPlan): RegistryOperation {
  if (plan.hasLeave) return 'leave';
  if (plan.hasJoin) return 'join';
  if (plan.hasCommand) return 'command';
  return 'discover';
}

async function fetchLineGroupSummaries(
  plans: LineGroupRegistryPlan[],
  channelAccessToken: string | undefined,
): Promise<Map<string, LineGroupSummary | null>> {
  const summaries = new Map<string, LineGroupSummary | null>();
  for (let i = 0; i < plans.length; i += REGISTRY_SUMMARY_MAX_CONCURRENCY) {
    const chunk = plans.slice(i, i + REGISTRY_SUMMARY_MAX_CONCURRENCY);
    await Promise.all(chunk.map(async (plan) => {
      try {
        summaries.set(plan.groupId, await fetchLineGroupSummary(plan.groupId, channelAccessToken));
      } catch (error) {
        logRegistryFailure('summary', error);
        summaries.set(plan.groupId, null);
      }
    }));
  }
  return summaries;
}

async function syncLineGroupRegistryPlan(
  plan: LineGroupRegistryPlan,
  existing: StoredLineGroup | undefined,
  summary: LineGroupSummary | null | undefined,
  seenAt: string,
  supabaseUrl: string,
  serviceKey: string,
): Promise<void> {
  const isKnown = Boolean(existing);
  const needsWrite = !isKnown || plan.hasJoin || plan.hasCommand || plan.hasLeave;
  if (!needsWrite) return;

  if (isKnown && plan.hasCommand && !plan.hasJoin && !plan.hasLeave) {
    await updateLineBotGroup(supabaseUrl, serviceKey, plan.groupId, {
      last_seen_at: seenAt,
      updated_at: seenAt,
    });
    return;
  }

  const values: Record<string, unknown> = {
    group_id: plan.groupId,
    last_seen_at: seenAt,
    updated_at: seenAt,
  };
  if (!isKnown) values.is_active = true;
  if (summary) {
    values.group_name = summary.groupName;
    values.picture_url = summary.pictureUrl;
  }
  if (plan.hasJoin) {
    values.is_active = true;
    values.joined_at = existing?.joined_at || seenAt;
    values.left_at = null;
  }
  if (plan.hasLeave) {
    values.is_active = false;
    values.left_at = seenAt;
  }
  await upsertLineBotGroup(supabaseUrl, serviceKey, values);
}

async function syncLineGroupRegistry(
  plans: LineGroupRegistryPlan[],
  stored: Map<string, StoredLineGroup>,
  supabaseUrl: string,
  serviceKey: string,
  channelAccessToken: string | undefined,
): Promise<void> {
  if (plans.length === 0) return;
  const summaryPlans = plans.filter((plan) => plan.hasJoin || !stored.has(plan.groupId));
  const summaries = await fetchLineGroupSummaries(summaryPlans, channelAccessToken);
  const seenAt = new Date().toISOString();

  for (const plan of plans) {
    try {
      await syncLineGroupRegistryPlan(
        plan,
        stored.get(plan.groupId),
        summaries.get(plan.groupId),
        seenAt,
        supabaseUrl,
        serviceKey,
      );
    } catch (error) {
      logRegistryFailure(registryOperationForPlan(plan), error);
    }
  }
}

function normalizeIntakeMode(value: unknown): LineGroupIntakeMode {
  return value === 'observe' || value === 'capture' ? value : 'none';
}

function normalizeRoutingMode(value: unknown): LineGroupRoutingMode {
  return value === 'source' || value === 'destination' || value === 'both' ? value : 'none';
}

function lineGroupPolicy(existing: StoredLineGroup | undefined): LineGroupPolicy {
  // Unknown groups keep the historical default-enabled behavior. Known groups are fail-closed:
  // only explicit `enabled` accepts commands; `disabled`, `customer_safe`, null, or unknown values stay silent.
  return {
    commandEnabled: !existing || existing.command_mode === 'enabled',
    intakeMode: normalizeIntakeMode(existing?.intake_mode),
    routingMode: normalizeRoutingMode(existing?.routing_mode),
  };
}

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
    for (let i = 0; i < computed.length; i++) diff |= computed.charCodeAt(i) ^ signature.charCodeAt(i);
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

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const rawBody = await req.text();
  const signature = req.headers.get('x-line-signature');
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const channelSecret = Deno.env.get('LINE_CHANNEL_SECRET');
  const channelAccessToken = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN');

  const docinboxSet = parseGroupSet(Deno.env.get('LINE_DOCINBOX_GROUP_IDS'));
  const meetangCommandMode = Deno.env.get('MITANG_COMMAND_MODE')?.trim();
  const pdfSet = parseGroupSet(
    Deno.env.get('LINE_PDF_HELPER_GROUP_IDS'),
    Deno.env.get('PDF_ALLOWED_GROUP_IDS'),
    Deno.env.get('LINE_AI_CONTROL_GROUP_ID'),
  );
  const docInboxUrl = `${supabaseUrl}/functions/v1/line-doc-inbox`;
  const helperUrl = Deno.env.get('LINE_AI_EXCEL_HELPER_URL') || `${supabaseUrl}/functions/v1/line-ai-excel-helper`;

  if (!supabaseUrl || !serviceKey || !channelSecret) {
    console.error('[line-router] missing required secrets');
    return new Response(JSON.stringify({ ok: false, error: 'not configured' }), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    });
  }

  const valid = await validateSignature(rawBody, signature, channelSecret);
  if (!valid) {
    console.warn('[line-router] invalid signature');
    return new Response('Unauthorized', { status: 401 });
  }

  let payload: { events?: LineEvent[] };
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return new Response('Bad Request', { status: 400 });
  }
  const events = Array.isArray(payload.events) ? payload.events : [];

  const docinboxEvents: LineEvent[] = [];
  const commandCandidates: MeetangCommandEvent[] = [];
  const registryPlans = new Map<string, LineGroupRegistryPlan>();
  let hasPdfGroupEvent = false;

  for (const ev of events) {
    const gid = ev.source?.groupId || '';
    if (!gid) continue;

    if (ev.source?.type === 'group') {
      let plan = registryPlans.get(gid);
      if (!plan) {
        plan = { groupId: gid, hasJoin: false, hasCommand: false, hasLeave: false };
        registryPlans.set(gid, plan);
      }
      if (ev.type === 'join') plan.hasJoin = true;
      else if (ev.type === 'leave') plan.hasLeave = true;
    }

    if (docinboxSet.has(gid)) docinboxEvents.push(ev);
    else if (pdfSet.has(gid)) hasPdfGroupEvent = true;

    if (meetangCommandMode === 'all_groups' && ev.source?.type === 'group') {
      const command = ev.message?.type === 'text' ? parseMeetangCommand(ev.message.text) : null;
      if (command && ev.replyToken) {
        commandCandidates.push({
          command,
          groupId: gid,
          userId: ev.source?.userId || '',
          replyToken: ev.replyToken,
        });
      }
    }
  }

  const registryPlanList = [...registryPlans.values()];
  const storedGroupsPromise: Promise<Map<string, StoredLineGroup> | null> = findStoredLineGroups(
    supabaseUrl,
    serviceKey,
    registryPlanList.map((plan) => plan.groupId),
  ).catch((error) => {
    logRegistryFailure('lookup', error);
    return null;
  });

  // Start existing doc/PDF routes while the registry lookup is in flight.
  // Command enforcement waits for the lookup; unrelated routes do not.
  if (docinboxEvents.length > 0) {
    try {
      const res = await fetch(docInboxUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${serviceKey}`,
          'apikey': serviceKey,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ events: docinboxEvents }),
      });
      if (!res.ok) console.error(`[line-router] doc-inbox call ${res.status}: ${await res.text()}`);
    } catch (e) {
      console.error('[line-router] doc-inbox call error:', e instanceof Error ? e.message : e);
    }
  }

  if (hasPdfGroupEvent) {
    try {
      const res = await fetch(helperUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-line-signature': signature || '',
        },
        body: rawBody,
      });
      if (!res.ok) console.error(`[line-router] helper forward ${res.status}: ${await res.text()}`);
    } catch (e) {
      console.error('[line-router] helper forward error:', e instanceof Error ? e.message : e);
    }
  }

  const storedGroups = await storedGroupsPromise;
  const meetangEvents: MeetangCommandEvent[] = [];
  if (storedGroups) {
    for (const item of commandCandidates) {
      if (!lineGroupPolicy(storedGroups.get(item.groupId)).commandEnabled) continue;
      meetangEvents.push(item);
      const plan = registryPlans.get(item.groupId);
      if (plan) plan.hasCommand = true;
    }
  }

  // When registry lookup fails, command enforcement fails closed and registry sync is skipped.
  const registrySync = storedGroups
    ? syncLineGroupRegistry(registryPlanList, storedGroups, supabaseUrl, serviceKey, channelAccessToken)
    : Promise.resolve();

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

  await registrySync;

  console.log(
    `[line-router] events=${events.length} docinbox=${docinboxEvents.length} ` +
      `pdfForward=${hasPdfGroupEvent} commands=${meetangEvents.length}`,
  );
  return new Response(JSON.stringify({ ok: true }), {
    status: 200, headers: { 'Content-Type': 'application/json' },
  });
});
