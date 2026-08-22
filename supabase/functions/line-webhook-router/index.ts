// =============================================================
// LINE Webhook Router — Supabase Edge Function (Stage 29B)
// =============================================================

interface LineSource { type?: string; groupId?: string; userId?: string }
interface LineEvent {
  type?: string;
  replyToken?: string;
  webhookEventId?: string;
  timestamp?: number;
  source?: LineSource;
  message?: { id?: string; type?: string; text?: string };
  unsend?: { messageId?: string };
}

type MeetangCommand = 'help' | 'status' | 'document-count' | 'price' | 'location' | 'unknown';
type LineGroupIntakeMode = 'none' | 'observe' | 'capture';
type LineGroupRoutingMode = 'none' | 'source' | 'destination' | 'both';

interface MeetangCommandEvent {
  command: MeetangCommand;
  groupId: string;
  userId: string;
  replyToken: string;
  // Text after the Mitang prefix. Only the price and location commands read it;
  // every other command is fully determined by `command` alone.
  queryText: string;
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

interface LineIntakeCandidate {
  groupId: string;
  lineMessageId: string;
  lineEventId: string | null;
  textBody: string;
  textLength: number;
  textTruncated: boolean;
  sourceUserId: string | null;
  eventTimestamp: string | null;
}

// Deliberately carries no text and no sender identity: an unsend only needs to
// name the message being retracted.
interface LineUnsendCandidate {
  groupId: string;
  lineMessageId: string;
  lineEventId: string | null;
  eventTimestamp: string | null;
}

const MEETANG_HELP = [
  'มีตัง 🐱💰 พร้อมช่วยงานแบบคำสั่งพื้นฐาน',
  '',
  'คำสั่งที่ใช้ได้:',
  '• มีตัง ช่วยอะไรได้บ้าง',
  '• มีตัง สถานะ',
  '• มีตัง จำนวนเอกสาร',
  // Two examples only. Help must make the price command discoverable without
  // becoming a catalog, so no price figure and no service list appears here.
  '• มีตัง ราคาตีวีซ่า',
  '• มีตัง ราคาพาสลาว',
  // One example only, for the same reason: Help points at the location command
  // without becoming a branch directory.
  '• มีตังโลปทุม',
  '',
  'ตอนนี้ยังไม่ใช้ AI และจะไม่ตอบข้อความทั่วไปในกลุ่ม',
].join('\n');

// "มีตัง " / "มีตัง:" — the historical form. Everything after the delimiter is a
// command body, including an unrecognized one.
const MEETANG_DELIMITED = /^มีตัง(?:ค์)?(?:\s*[:：]\s*|\s+|$)(.*)$/u;
// "มีตัง…" with nothing between the prefix and the body.
const MEETANG_JOINED = /^มีตัง(?:ค์)?(.+)$/u;
// A price question is anything that mentions a price or a cost. This is checked
// only after every existing exact-match family, so no body that used to resolve
// to help, status or document-count can be diverted here.
const MEETANG_PRICE_HINT = /(ราคา|ทุน)/u;

// -------------------------------------------------------------
// Branch locations
// -------------------------------------------------------------

// The five map links are Owner-supplied constants. They are never generated,
// resolved, expanded, shortened or looked up: the whole location path is string
// data plus literal matching, so it makes no Maps API call, no geocoding call
// and no network request of any kind. Array order is the all-branches order.
interface MitangBranch {
  name: string;
  url: string;
  // Already space-free and lowercase, so a normalized query can be compared by
  // equality. Matching is exact — never fuzzy, never a prefix guess.
  aliases: readonly string[];
}

const MITANG_BRANCH_LABEL = 'รุ่งฟ้าสาขา';

const MITANG_BRANCHES: readonly MitangBranch[] = [
  {
    name: 'ปทุมธานี',
    url: 'https://maps.app.goo.gl/uo4h6RGiDm4ZP1Fy9?g_st=ic',
    aliases: ['ปทุม', 'ปทุมธานี'],
  },
  {
    name: 'คลอง4',
    url: 'https://maps.app.goo.gl/Z1r41gRVWCZJBRiV7?g_st=ic',
    aliases: ['คลอง4', 'คลองสี่'],
  },
  {
    name: 'อยุธยา',
    url: 'https://maps.app.goo.gl/E29KsjzPudQyx3M9A?g_st=ic',
    aliases: ['อยุธ', 'อยุธยา'],
  },
  {
    name: 'สระบุรี',
    url: 'https://maps.app.goo.gl/uYokLR7R9box2Pax7?g_st=ic',
    aliases: ['สระ', 'สระบุรี'],
  },
  {
    name: 'ระยอง',
    url: 'https://maps.app.goo.gl/iF8WSKdDgXdeQoEP7?g_st=ic',
    aliases: ['ระยอง'],
  },
];

// Longest first, so "โลเคชั่น" is never truncated to the short "โล". `strict`
// marks the one prefix that is also an ordinary Thai word fragment: an
// unrecognized tail after it is chatter, not a failed lookup.
const MITANG_LOCATION_PREFIXES: readonly { prefix: string; strict: boolean }[] = [
  { prefix: 'ขอโลเคชั่น', strict: false },
  { prefix: 'โลเคชั่น', strict: false },
  { prefix: 'location', strict: false },
  { prefix: 'แผนที่', strict: false },
  { prefix: 'ขอโล', strict: false },
  { prefix: 'แมพ', strict: false },
  { prefix: 'โล', strict: true },
];

const MITANG_LOCATION_ALL = ['ทั้งหมด', 'ทุกสาขา', 'ทุกที่', 'สาขาทั้งหมด'];

type MitangLocationRequest =
  | { kind: 'branch'; branch: MitangBranch }
  | { kind: 'all' }
  | { kind: 'select' }
  | { kind: 'unknown' };

// Spacing is the only thing folded, so "คลอง 4" and "คลอง4" are one branch.
// Canonical names and URLs never pass through here.
function mitangLocationNormalize(text: string): string {
  return text.replace(/\s+/gu, '').toLowerCase();
}

// Returns null when the text is not a location request at all, which is what
// keeps "มีตังโลกสวย" and "มีตังโล่งใจ" ordinary chatter.
function parseMitangLocation(body: string): MitangLocationRequest | null {
  const norm = mitangLocationNormalize(body);
  for (const { prefix, strict } of MITANG_LOCATION_PREFIXES) {
    if (!norm.startsWith(prefix)) continue;
    const rest = norm.slice(prefix.length);
    if (!rest) return { kind: 'select' };
    if (MITANG_LOCATION_ALL.includes(rest)) return { kind: 'all' };
    const branchSelector = rest.startsWith('สาขา') ? rest.slice('สาขา'.length) : rest;
    const branch = MITANG_BRANCHES.find((item) => item.aliases.includes(branchSelector));
    if (branch) return { kind: 'branch', branch };
    // An unreadable tail is only reported as a missing branch when the prefix
    // was unambiguous. After the short "โล" it stays chatter.
    return strict ? null : { kind: 'unknown' };
  }
  return null;
}

function mitangBranchBlock(branch: MitangBranch): string {
  return `📍 ${MITANG_BRANCH_LABEL}${branch.name}\n${branch.url}`;
}

function buildLocationReply(body: string): string {
  const request = parseMitangLocation(body);
  if (request?.kind === 'branch') return mitangBranchBlock(request.branch);
  if (request?.kind === 'all') return MITANG_BRANCHES.map(mitangBranchBlock).join('\n\n');
  if (request?.kind === 'unknown') {
    // Names the branches that exist rather than inventing a link for one that
    // does not.
    return [
      'ไม่พบโลเคชั่นสาขานี้',
      `มีสาขา: ${MITANG_BRANCHES.map((item) => item.name).join(' / ')}`,
    ].join('\n');
  }
  // Bare request, and the defensive fallback: offer the list, never guess.
  return [
    'เลือกสาขาที่ต้องการ:',
    ...MITANG_BRANCHES.map((item) => `• ${MITANG_BRANCH_LABEL}${item.name}`),
    '',
    'พิมพ์สั้น ๆ เช่น “มีตังโลปทุม”',
  ].join('\n');
}

// The single place command families are defined. Both prefix forms resolve
// through this, so the rules are never duplicated.
function meetangCommandFamily(body: string): MeetangCommand {
  const key = body.toLowerCase();
  if (!key || ['help', 'ช่วย', 'ช่วยอะไรได้บ้าง', 'คำสั่ง', 'ดูคำสั่ง'].includes(key)) {
    return 'help';
  }
  if (['status', 'สถานะ', 'เช็กสถานะ', 'เช็คสถานะ'].includes(key)) return 'status';
  if (
    ['เอกสาร', 'จำนวนเอกสาร', 'เอกสารทั้งหมด', 'เอกสารวันนี้', 'เอกสารวันนี้กี่ไฟล์'].includes(key) ||
    (key.startsWith('เอกสาร') && /(กี่|จำนวน|วันนี้|ทั้งหมด)/u.test(key))
  ) return 'document-count';
  if (MEETANG_PRICE_HINT.test(key)) return 'price';
  // Checked after price so no body that used to resolve to price can be
  // diverted here; no location phrasing contains ราคา or ทุน.
  if (parseMitangLocation(key)) return 'location';
  return 'unknown';
}

// The delimiter form keeps its exact historical contract, unknown bodies
// included. The joined form is deliberately stricter: without a delimiter there
// is nothing separating a command from an ordinary word that merely starts with
// มีตัง, so it is accepted only when the body resolves to a known family.
// "มีตังสถานะ" is a command; "มีตังใจทำงาน" stays chatter.
function meetangCommandBody(text: string | undefined): string | null {
  if (typeof text !== 'string') return null;
  const trimmed = text.trim();

  const delimited = MEETANG_DELIMITED.exec(trimmed);
  if (delimited) return delimited[1].trim();

  const joined = MEETANG_JOINED.exec(trimmed);
  if (!joined) return null;
  const body = joined[1].trim();
  return meetangCommandFamily(body) === 'unknown' ? null : body;
}

function parseMeetangCommand(text: string | undefined): MeetangCommand | null {
  const body = meetangCommandBody(text);
  if (body === null) return null;
  return meetangCommandFamily(body);
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
  queryText = '',
): Promise<string> {
  if (command === 'help') return MEETANG_HELP;
  if (command === 'price') {
    return buildPriceReply(await lookupLinePrice(supabaseUrl, serviceKey, queryText));
  }
  // Answered entirely from the seeded constants above: no fetch, no RPC, no
  // persistence.
  if (command === 'location') return buildLocationReply(queryText);
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
const INTAKE_TEXT_MAX_CHARS = 2_000;
const INTAKE_UNSEND_RETRY_DELAY_MS = 250;
// Monitoring is not the privacy transaction, so it uses a shorter budget than the
// unsend RPC and never shares its retry policy.
const OPS_ALERT_FETCH_TIMEOUT_MS = 2_000;
const OPS_ALERT_BUCKET_MS = 15 * 60 * 1_000;
const OPS_ALERT_KIND = 'intake-unsend-failure';

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

// Counts Unicode code points so the bound matches PostgreSQL char_length(), which
// the line_intake_events check constraint enforces independently.
function buildIntakeText(raw: string): { body: string; length: number; truncated: boolean } {
  const chars = [...raw];
  if (chars.length <= INTAKE_TEXT_MAX_CHARS) {
    return { body: raw, length: chars.length, truncated: false };
  }
  return {
    body: chars.slice(0, INTAKE_TEXT_MAX_CHARS).join(''),
    length: chars.length,
    truncated: true,
  };
}

function buildIntakeCandidate(ev: LineEvent, groupId: string): LineIntakeCandidate | null {
  if (ev.source?.type !== 'group') return null;
  if (ev.type !== 'message') return null;
  if (ev.message?.type !== 'text') return null;
  const messageId = ev.message.id;
  if (typeof messageId !== 'string' || messageId === '') return null;
  const text = ev.message.text;
  if (typeof text !== 'string') return null;
  // Command exclusion is evaluated directly and never via MITANG_COMMAND_MODE, so
  // Mitang commands stay out of intake even when command dispatch is switched off.
  if (parseMeetangCommand(text) !== null) return null;

  const intakeText = buildIntakeText(text);
  return {
    groupId,
    lineMessageId: messageId,
    lineEventId: typeof ev.webhookEventId === 'string' && ev.webhookEventId !== ''
      ? ev.webhookEventId
      : null,
    textBody: intakeText.body,
    textLength: intakeText.length,
    textTruncated: intakeText.truncated,
    sourceUserId: ev.source?.userId || null,
    eventTimestamp: typeof ev.timestamp === 'number' && Number.isFinite(ev.timestamp)
      ? new Date(ev.timestamp).toISOString()
      : null,
  };
}

async function insertLineIntakeEvents(
  supabaseUrl: string,
  serviceKey: string,
  candidates: LineIntakeCandidate[],
): Promise<void> {
  // resolution=ignore-duplicates maps to ON CONFLICT DO NOTHING, so duplicate LINE
  // deliveries stay at one row without a read-before-write and without UPDATE rights.
  const res = await fetch(`${supabaseUrl}/rest/v1/line_intake_events?on_conflict=line_message_id`, {
    method: 'POST',
    headers: {
      ...registryHeaders(serviceKey),
      'Prefer': 'resolution=ignore-duplicates,return=minimal',
    },
    body: JSON.stringify(candidates.map((candidate) => ({
      group_id: candidate.groupId,
      line_message_id: candidate.lineMessageId,
      line_event_id: candidate.lineEventId,
      text_body: candidate.textBody,
      text_length: candidate.textLength,
      text_truncated: candidate.textTruncated,
      source_user_id: candidate.sourceUserId,
      event_timestamp: candidate.eventTimestamp,
    }))),
    signal: AbortSignal.timeout(REGISTRY_FETCH_TIMEOUT_MS),
  });
  if (!res.ok) throw new RegistryHttpError(res.status);
}

// One row per (service, cost) from app_lookup_line_price. Pricing facts only:
// the RPC exposes no customer, case, document or registry data.
interface LinePriceRow {
  service_key: string;
  service_name: string;
  variant_name: string | null;
  cost_status: string;
  location_name: string | null;
  cost_amount: number | string | null;
  sale_price_min: number | string;
  sale_price_max: number | string;
  note: string | null;
}

// A LINE reply must stay short. Ambiguous queries legitimately return several
// services, but the answer is capped rather than allowed to grow unbounded.
const PRICE_MAX_SERVICES = 5;

async function lookupLinePrice(
  supabaseUrl: string,
  serviceKey: string,
  query: string,
): Promise<LinePriceRow[]> {
  const res = await fetch(`${supabaseUrl}/rest/v1/rpc/app_lookup_line_price`, {
    method: 'POST',
    headers: registryHeaders(serviceKey),
    body: JSON.stringify({ p_query: query }),
    signal: AbortSignal.timeout(REGISTRY_FETCH_TIMEOUT_MS),
  });
  if (!res.ok) throw new RegistryHttpError(res.status);

  let rows: unknown;
  try {
    rows = await res.json();
  } catch {
    throw new Error('invalid price lookup response');
  }
  if (!Array.isArray(rows)) throw new Error('invalid price lookup response');
  return rows as LinePriceRow[];
}

// PostgREST may serialize numeric as a string, so the value is coerced once here
// rather than trusted as a number.
function formatBaht(value: number | string): string {
  const amount = Number(value);
  return Number.isFinite(amount) ? amount.toLocaleString('th-TH') : String(value);
}

function buildPriceReply(rows: LinePriceRow[]): string {
  // Deterministic miss. There is no AI fallback and no guess.
  if (rows.length === 0) return 'ไม่พบราคากลางรายการนี้';

  // The RPC already orders rows; grouping preserves that order.
  const order: string[] = [];
  const grouped = new Map<string, LinePriceRow[]>();
  for (const row of rows) {
    let bucket = grouped.get(row.service_key);
    if (!bucket) {
      bucket = [];
      grouped.set(row.service_key, bucket);
      order.push(row.service_key);
    }
    bucket.push(row);
  }

  const blocks: string[] = [];
  for (const key of order.slice(0, PRICE_MAX_SERVICES)) {
    const bucket = grouped.get(key) || [];
    const head = bucket[0];
    const lines: string[] = [
      head.variant_name ? `${head.service_name} ${head.variant_name}` : head.service_name,
    ];

    const costs = bucket.filter((row) => row.cost_amount !== null && row.cost_amount !== undefined);
    if (head.cost_status !== 'confirmed' || costs.length === 0) {
      // Never print a number the catalog does not confirm.
      lines.push('ทุน: ยังไม่ยืนยัน');
    } else if (costs.length === 1 && !costs[0].location_name) {
      lines.push(`ทุน: ${formatBaht(costs[0].cost_amount as number | string)} บาท`);
    } else {
      lines.push('ทุน:');
      for (const cost of costs) {
        const where = cost.location_name ? `${cost.location_name} ` : '';
        lines.push(`- ${where}${formatBaht(cost.cost_amount as number | string)} บาท`);
      }
    }

    const min = formatBaht(head.sale_price_min);
    const max = formatBaht(head.sale_price_max);
    lines.push(min === max ? `ราคาขาย: ${min} บาท` : `ราคาขาย: ${min}–${max} บาท`);
    if (head.note) lines.push(`หมายเหตุ: ${head.note}`);
    blocks.push(lines.join('\n'));
  }

  if (order.length > PRICE_MAX_SERVICES) {
    blocks.push(`(แสดง ${PRICE_MAX_SERVICES} รายการแรก จากทั้งหมด ${order.length} รายการ)`);
  }
  return blocks.join('\n\n');
}

// Unsend recognition is intentionally independent of intake_mode, routing_mode,
// command_mode, registry lookup success, and the document/PDF allowlists: a row
// captured earlier may still need removal after any of those changed.
function buildUnsendCandidate(ev: LineEvent, groupId: string): LineUnsendCandidate | null {
  if (ev.source?.type !== 'group') return null;
  if (ev.type !== 'unsend') return null;
  const messageId = ev.unsend?.messageId;
  if (typeof messageId !== 'string' || messageId === '') return null;

  return {
    groupId,
    lineMessageId: messageId,
    lineEventId: typeof ev.webhookEventId === 'string' && ev.webhookEventId !== ''
      ? ev.webhookEventId
      : null,
    eventTimestamp: typeof ev.timestamp === 'number' && Number.isFinite(ev.timestamp)
      ? new Date(ev.timestamp).toISOString()
      : null,
  };
}

async function callUnsendIntakeEvent(
  supabaseUrl: string,
  serviceKey: string,
  candidate: LineUnsendCandidate,
): Promise<void> {
  // The RPC tombstones and deletes inside one transaction under the Patch #13
  // advisory lock, so service_role needs EXECUTE only and never table DELETE.
  let lastError: unknown;
  for (let attempt = 0; attempt < 2; attempt++) {
    if (attempt > 0) {
      await new Promise((resolve) => setTimeout(resolve, INTAKE_UNSEND_RETRY_DELAY_MS));
    }
    try {
      const res = await fetch(`${supabaseUrl}/rest/v1/rpc/app_unsend_line_intake_event`, {
        method: 'POST',
        headers: registryHeaders(serviceKey),
        body: JSON.stringify({
          p_group_id: candidate.groupId,
          p_line_message_id: candidate.lineMessageId,
          p_unsent_event_id: candidate.lineEventId,
          p_unsent_event_timestamp: candidate.eventTimestamp,
        }),
        signal: AbortSignal.timeout(REGISTRY_FETCH_TIMEOUT_MS),
      });
      if (!res.ok) throw new RegistryHttpError(res.status);
      return;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

class OpsAlertError extends Error {
  status: number | null;
  constructor(status: number | null) {
    super('ops alert delivery failed');
    this.status = status;
  }
}

interface EdgeRuntimeGlobal {
  waitUntil(task: Promise<unknown>): void;
}

// EdgeRuntime is not present in Deno's ambient declarations, so it is narrowed off
// globalThis rather than declared. When it is unavailable (local harness) the task
// still runs, detached, with its own error handling.
function edgeWaitUntil(task: Promise<unknown>): void {
  const runtime = (globalThis as { EdgeRuntime?: EdgeRuntimeGlobal }).EdgeRuntime;
  if (runtime && typeof runtime.waitUntil === 'function') runtime.waitUntil(task);
  else void task;
}

function opsAlertBucketId(nowMs: number): number {
  // 15-minute buckets are whole-hour aligned, so this identity is the same whether
  // it is read as UTC or Bangkok time.
  return Math.floor(nowMs / OPS_ALERT_BUCKET_MS);
}

function opsAlertBucketLabel(bucketId: number): string {
  const bangkokOffsetMs = 7 * 60 * 60 * 1000;
  const local = new Date(bucketId * OPS_ALERT_BUCKET_MS + bangkokOffsetMs);
  const pad = (value: number) => String(value).padStart(2, '0');
  return `${local.getUTCFullYear()}-${pad(local.getUTCMonth() + 1)}-${pad(local.getUTCDate())} ` +
    `${pad(local.getUTCHours())}:${pad(local.getUTCMinutes())} (+07)`;
}

// Deterministic so every isolate handling a failure in the same window sends an
// identical key; LINE then accepts at most one push per target per window. The
// version and variant nibbles are fixed so the value is a syntactically valid UUID.
async function opsAlertRetryKey(seed: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(seed));
  const hex = Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
    .slice(0, 32)
    .split('');
  hex[12] = '5';
  hex[16] = ((parseInt(hex[16], 16) & 0x3 | 0x8)).toString(16);
  const value = hex.join('');
  return `${value.slice(0, 8)}-${value.slice(8, 12)}-${value.slice(12, 16)}-` +
    `${value.slice(16, 20)}-${value.slice(20, 32)}`;
}

// Deliberately free of message text, sender identity, message ids, source group and
// payload: this is an operational signal, not a forensic record.
function opsAlertText(bucketId: number): string {
  return [
    '⚠️ มีตัง: พบปัญหา Unsend Privacy',
    'ระบบหยุดการเก็บข้อความใหม่ของ request ที่เกี่ยวข้องแล้ว',
    `ช่วงเวลา: ${opsAlertBucketLabel(bucketId)}`,
    'กรุณาตรวจ Edge Function logs',
  ].join('\n');
}

async function pushOpsAlert(
  channelAccessToken: string,
  targetGroupId: string,
  text: string,
  retryKey: string,
): Promise<void> {
  let lastStatus: number | null = null;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const res = await fetch('https://api.line.me/v2/bot/message/push', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${channelAccessToken}`,
          'Content-Type': 'application/json',
          'X-Line-Retry-Key': retryKey,
        },
        body: JSON.stringify({ to: targetGroupId, messages: [{ type: 'text', text }] }),
        signal: AbortSignal.timeout(OPS_ALERT_FETCH_TIMEOUT_MS),
      });
      if (res.ok) return;
      // The same retry key was already accepted, so the alert for this window exists.
      if (res.status === 409) return;
      lastStatus = res.status;
      // Only transient failures are retried; other 4xx will not succeed on a retry.
      if (res.status < 500) throw new OpsAlertError(res.status);
    } catch (error) {
      if (error instanceof OpsAlertError) throw error;
    }
  }
  throw new OpsAlertError(lastStatus);
}

// Best effort only. This never re-enables intake, never clears unsendFailed, and
// never changes the webhook response.
function scheduleUnsendOpsAlert(channelAccessToken: string | undefined, nowMs: number): void {
  const targetGroupId = Deno.env.get('LINE_OPS_ALERT_GROUP_ID')?.trim();
  if (!targetGroupId || !channelAccessToken) {
    console.error('[line-router] intake unsend ALERT UNCONFIGURED');
    return;
  }

  const bucketId = opsAlertBucketId(nowMs);
  edgeWaitUntil((async () => {
    try {
      const retryKey = await opsAlertRetryKey(`${OPS_ALERT_KIND}:${targetGroupId}:${bucketId}`);
      await pushOpsAlert(channelAccessToken, targetGroupId, opsAlertText(bucketId), retryKey);
    } catch (error) {
      const httpStatus = error instanceof OpsAlertError && error.status !== null
        ? ` HTTP ${error.status}`
        : '';
      console.error(`[line-router] intake unsend ALERT FAILED${httpStatus} bucket=${bucketId}`);
    }
  })());
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
  const intakeCandidates: LineIntakeCandidate[] = [];
  const unsendCandidates: LineUnsendCandidate[] = [];
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

    const unsendCandidate = buildUnsendCandidate(ev, gid);
    if (unsendCandidate) unsendCandidates.push(unsendCandidate);

    // Patch #12 proves generic text intake only. Groups already selected by the
    // document or PDF/Excel allowlists keep their existing behavior untouched and
    // never capture, regardless of intake_mode.
    if (!docinboxSet.has(gid) && !pdfSet.has(gid)) {
      const intakeCandidate = buildIntakeCandidate(ev, gid);
      if (intakeCandidate) intakeCandidates.push(intakeCandidate);
    }

    // Command dispatch is scoped to original message events. A messageEdited event
    // carries the same text shape and a replyToken, so without this gate an edited
    // message could execute a Mitang command. The document and PDF/Excel routes
    // above are deliberately left untouched and still see every event type.
    if (
      meetangCommandMode === 'all_groups' &&
      ev.source?.type === 'group' &&
      ev.type === 'message'
    ) {
      const command = ev.message?.type === 'text' ? parseMeetangCommand(ev.message.text) : null;
      if (command && ev.replyToken) {
        commandCandidates.push({
          command,
          groupId: gid,
          userId: ev.source?.userId || '',
          replyToken: ev.replyToken,
          queryText: meetangCommandBody(ev.message?.text) || '',
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

  // Unsend runs to completion before any generic intake write starts, and after
  // the document/PDF routes so it cannot delay or alter them. Suppression is
  // enforced in memory as well as in the database: a message unsent in this same
  // payload must never be persisted even if the RPC result is unknown.
  const unsentMessageIds = new Set(unsendCandidates.map((item) => item.lineMessageId));
  let unsendFailed = false;
  for (const candidate of unsendCandidates) {
    try {
      await callUnsendIntakeEvent(supabaseUrl, serviceKey, candidate);
    } catch (error) {
      const httpStatus = error instanceof RegistryHttpError ? ` HTTP ${error.status}` : '';
      console.error(
        `[line-router] intake unsend FAILED${httpStatus} ` +
          `group=${candidate.groupId} message=${candidate.lineMessageId}`,
      );
      unsendFailed = true;
    }
  }

  // Monitoring only. The FAILED marker above remains the authoritative privacy
  // signal, and the alert's outcome cannot influence intake suppression below.
  if (unsendFailed) scheduleUnsendOpsAlert(channelAccessToken, Date.now());

  const storedGroups = await storedGroupsPromise;
  const meetangEvents: MeetangCommandEvent[] = [];
  if (storedGroups) {
    for (const item of commandCandidates) {
      const existing = storedGroups.get(item.groupId);
      if (!lineGroupPolicy(existing).commandEnabled) continue;
      // Pricing exposes internal cost data, so it is stricter than the other
      // command families: it requires an explicitly trusted group. An unknown
      // group's historical default-enabled behavior does not grant it, and
      // customer_safe and disabled never reach here at all.
      if (item.command === 'price' && existing?.command_mode !== 'enabled') continue;
      meetangEvents.push(item);
      const plan = registryPlans.get(item.groupId);
      if (plan) plan.hasCommand = true;
    }
  }

  // Intake fails closed with the same rules as commands: a failed registry lookup
  // captures nothing, and an unknown group has no stored policy so its effective
  // intake mode is none. observe is recognized but performs zero database writes.
  // A failed unsend leaves retracted text at risk, so every generic intake write
  // for this request is suppressed until the retraction is known to have applied.
  const intakeEvents: LineIntakeCandidate[] = [];
  let intakeObserved = 0;
  if (storedGroups && !unsendFailed) {
    for (const candidate of intakeCandidates) {
      if (unsentMessageIds.has(candidate.lineMessageId)) continue;
      const existing = storedGroups.get(candidate.groupId);
      if (!existing) continue;
      const intakeMode = lineGroupPolicy(existing).intakeMode;
      if (intakeMode === 'observe') intakeObserved++;
      else if (intakeMode === 'capture') intakeEvents.push(candidate);
    }
  }

  // When registry lookup fails, command enforcement fails closed and registry sync is skipped.
  const registrySync = storedGroups
    ? syncLineGroupRegistry(registryPlanList, storedGroups, supabaseUrl, serviceKey, channelAccessToken)
    : Promise.resolve();

  // Intake persistence is best-effort: it never rejects, so it cannot affect the
  // document route, the PDF route, command replies, or the webhook response.
  const intakeSync = intakeEvents.length > 0
    ? insertLineIntakeEvents(supabaseUrl, serviceKey, intakeEvents).catch((error) => {
      const httpStatus = error instanceof RegistryHttpError ? ` HTTP ${error.status}` : '';
      console.error(`[line-router] intake capture failed${httpStatus}`);
    })
    : Promise.resolve();

  if (meetangEvents.length > 0) {
    if (!channelAccessToken) {
      console.error('[line-router] LINE_CHANNEL_ACCESS_TOKEN missing; commands skipped');
    } else {
      for (const item of meetangEvents) {
        try {
          let reply: string;
          try {
            reply = await buildMeetangReply(
              item.command,
              item.groupId,
              supabaseUrl,
              serviceKey,
              item.queryText,
            );
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
  await intakeSync;

  console.log(
    `[line-router] events=${events.length} docinbox=${docinboxEvents.length} ` +
      `pdfForward=${hasPdfGroupEvent} commands=${meetangEvents.length} ` +
      `intake=${intakeEvents.length} intakeObserved=${intakeObserved} ` +
      `unsend=${unsendCandidates.length} unsendFailed=${unsendFailed}`,
  );
  return new Response(JSON.stringify({ ok: true }), {
    status: 200, headers: { 'Content-Type': 'application/json' },
  });
});
