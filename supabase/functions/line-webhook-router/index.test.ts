// =============================================================
// LINE Webhook Router — local source harness (messageEdited V1)
//
// Drives the real request handler out of index.ts. Deno.serve is stubbed before
// the dynamic import so importing the module captures the handler instead of
// binding a port, and globalThis.fetch is stubbed so every outbound effect is
// recorded and nothing leaves the machine. No network, no database, no deploy.
//
//   deno test --allow-env --allow-read \
//     supabase/functions/line-webhook-router/index.test.ts
// =============================================================

type Handler = (req: Request) => Promise<Response>;

interface RecordedCall {
  method: string;
  url: string;
  body: string | null;
}

const SUPABASE_URL = 'https://project.supabase.co';
const SERVICE_KEY = 'test-service-role-key';
const CHANNEL_SECRET = 'test-channel-secret';
const CHANNEL_TOKEN = 'test-channel-access-token';
const HELPER_URL = 'https://helper.test/line-ai-excel-helper';

const GENERIC_GROUP = 'Cgeneric000000000000000000000000';
const DOC_GROUP = 'Cdoc0000000000000000000000000000';
const PDF_GROUP = 'Cpdf0000000000000000000000000000';
// Pricing access fixtures. UNKNOWN_GROUP is deliberately absent from
// STORED_GROUPS so it exercises the "registry has never seen this group" path.
const SAFE_GROUP = 'Csafe000000000000000000000000000';
const DISABLED_GROUP = 'Cdisabled00000000000000000000000';
const UNKNOWN_GROUP = 'Cunknown000000000000000000000000';

// Every group is known, command-enabled and capture-mode, so any suppression the
// tests observe comes from event-type scoping rather than from a fail-closed policy.
const STORED_GROUPS: Record<string, unknown>[] = [
  {
    group_id: GENERIC_GROUP,
    joined_at: '2026-01-01T00:00:00Z',
    command_mode: 'enabled',
    intake_mode: 'capture',
    routing_mode: 'none',
  },
  {
    group_id: DOC_GROUP,
    joined_at: '2026-01-01T00:00:00Z',
    command_mode: 'enabled',
    intake_mode: 'capture',
    routing_mode: 'none',
  },
  {
    group_id: PDF_GROUP,
    joined_at: '2026-01-01T00:00:00Z',
    command_mode: 'enabled',
    intake_mode: 'capture',
    routing_mode: 'none',
  },
  {
    group_id: SAFE_GROUP,
    joined_at: '2026-01-01T00:00:00Z',
    command_mode: 'customer_safe',
    intake_mode: 'none',
    routing_mode: 'none',
  },
  {
    group_id: DISABLED_GROUP,
    joined_at: '2026-01-01T00:00:00Z',
    command_mode: 'disabled',
    intake_mode: 'none',
    routing_mode: 'none',
  },
];

// Rows the stubbed price RPC returns for the next request. The router is the
// subject here, so the RPC result is a fixture; the SQL matching rules are
// proved separately against the seeded migration further down.
let priceFixture: Record<string, unknown>[] = [];

const ROUTER_SOURCE = await Deno.readTextFile(new URL('./index.ts', import.meta.url));

// ---------- assertions (kept local so the harness has no remote dependency) ----

function assertEquals(actual: unknown, expected: unknown, message: string): void {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new Error(`${message}\n  expected: ${b}\n  actual:   ${a}`);
}

function assertTrue(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

// ---------- handler capture ---------------------------------------------------

async function loadHandler(): Promise<Handler> {
  let captured: Handler | null = null;
  // deno-lint-ignore no-explicit-any
  const denoAny = Deno as any;
  const realServe = denoAny.serve;
  denoAny.serve = (handler: Handler) => {
    captured = handler;
    return {
      finished: Promise.resolve(),
      shutdown: () => Promise.resolve(),
      ref() {},
      unref() {},
      addr: { transport: 'tcp', hostname: '127.0.0.1', port: 0 },
    };
  };
  try {
    await import('./index.ts');
  } finally {
    denoAny.serve = realServe;
  }
  const found = captured as Handler | null;
  if (!found) throw new Error('index.ts did not register a Deno.serve handler');
  return found;
}

const handler = await loadHandler();

// ---------- environment and outbound stubs ------------------------------------

function setEnv(): void {
  const values: Record<string, string> = {
    SUPABASE_URL,
    SUPABASE_SERVICE_ROLE_KEY: SERVICE_KEY,
    LINE_CHANNEL_SECRET: CHANNEL_SECRET,
    LINE_CHANNEL_ACCESS_TOKEN: CHANNEL_TOKEN,
    MITANG_COMMAND_MODE: 'all_groups',
    LINE_DOCINBOX_GROUP_IDS: DOC_GROUP,
    LINE_PDF_HELPER_GROUP_IDS: PDF_GROUP,
    LINE_AI_EXCEL_HELPER_URL: HELPER_URL,
  };
  for (const [key, value] of Object.entries(values)) Deno.env.set(key, value);
  for (const key of ['PDF_ALLOWED_GROUP_IDS', 'LINE_AI_CONTROL_GROUP_ID', 'LINE_OPS_ALERT_GROUP_ID']) {
    Deno.env.delete(key);
  }
}

function jsonResponse(value: unknown): Response {
  return new Response(JSON.stringify(value), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
}

function stubResponse(url: string, method: string): Response {
  const decoded = decodeURIComponent(url);
  if (decoded.includes('/rest/v1/rpc/app_lookup_line_price')) {
    return jsonResponse(priceFixture);
  }
  if (method === 'GET' && decoded.includes('/rest/v1/line_bot_groups')) {
    return jsonResponse(STORED_GROUPS.filter((row) => decoded.includes(String(row.group_id))));
  }
  if (decoded.includes('/rest/v1/line_file_inbox')) {
    return new Response(null, { status: 200, headers: { 'content-range': '0-0/0' } });
  }
  if (decoded.includes('api.line.me') && decoded.includes('/summary')) {
    return jsonResponse({ groupName: 'test group', pictureUrl: null });
  }
  return jsonResponse({});
}

function installFetch(calls: RecordedCall[]): () => void {
  const realFetch = globalThis.fetch;
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = typeof input === 'string'
      ? input
      : input instanceof URL
      ? input.toString()
      : input.url;
    const method = (init?.method || 'GET').toUpperCase();
    calls.push({ method, url, body: typeof init?.body === 'string' ? init.body : null });
    return Promise.resolve(stubResponse(url, method));
  }) as typeof fetch;
  return () => {
    globalThis.fetch = realFetch;
  };
}

async function signBody(body: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(CHANNEL_SECRET),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign('HMAC', key, enc.encode(body));
  return btoa(String.fromCharCode(...new Uint8Array(signature)));
}

interface RunResult {
  status: number;
  calls: RecordedCall[];
  rawBody: string;
}

async function deliver(events: unknown[]): Promise<RunResult> {
  setEnv();
  const rawBody = JSON.stringify({ destination: 'Udestination', events });
  const signature = await signBody(rawBody);
  const calls: RecordedCall[] = [];
  const restore = installFetch(calls);
  try {
    const res = await handler(
      new Request('https://edge.test/functions/v1/line-webhook-router', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-line-signature': signature },
        body: rawBody,
      }),
    );
    await res.text();
    return { status: res.status, calls, rawBody };
  } finally {
    restore();
  }
}

// ---------- event builders ----------------------------------------------------

let seq = 0;

// messageEdited events deliberately carry a replyToken and message.type 'text',
// so nothing but the event-type gate itself can stop command dispatch.
function textEvent(
  opts: { groupId: string; text: string; type?: string; messageId?: string },
): Record<string, unknown> {
  seq++;
  return {
    type: opts.type ?? 'message',
    replyToken: `reply-token-${seq}`,
    webhookEventId: `webhook-event-${seq}`,
    timestamp: 1_760_000_000_000 + seq,
    source: { type: 'group', groupId: opts.groupId, userId: 'Usender00000000000000000000000' },
    message: { id: opts.messageId ?? `M-${seq}`, type: 'text', text: opts.text },
  };
}

function unsendEvent(groupId: string, messageId: string): Record<string, unknown> {
  seq++;
  return {
    type: 'unsend',
    webhookEventId: `webhook-event-${seq}`,
    timestamp: 1_760_000_000_000 + seq,
    source: { type: 'group', groupId, userId: 'Usender00000000000000000000000' },
    unsend: { messageId },
  };
}

// ---------- call selectors ----------------------------------------------------

const replies = (calls: RecordedCall[]) =>
  calls.filter((call) => call.url.includes('api.line.me/v2/bot/message/reply'));

const intakeInserts = (calls: RecordedCall[]) =>
  calls.filter((call) => call.method === 'POST' && call.url.includes('/rest/v1/line_intake_events'));

const intakeWrites = (calls: RecordedCall[]) =>
  calls.filter((call) =>
    call.url.includes('/rest/v1/line_intake_events') && call.method !== 'GET' && call.method !== 'HEAD'
  );

const unsendRpcs = (calls: RecordedCall[]) =>
  calls.filter((call) => call.url.includes('/rest/v1/rpc/app_unsend_line_intake_event'));

const docForwards = (calls: RecordedCall[]) =>
  calls.filter((call) => call.url.includes('/functions/v1/line-doc-inbox'));

const pdfForwards = (calls: RecordedCall[]) => calls.filter((call) => call.url === HELPER_URL);

const priceLookups = (calls: RecordedCall[]) =>
  calls.filter((call) => call.url.includes('/rest/v1/rpc/app_lookup_line_price'));

function replyText(calls: RecordedCall[]): string {
  const sent = replies(calls);
  if (sent.length === 0) return '';
  const body = JSON.parse(String(sent[0].body)) as { messages: { text: string }[] };
  return body.messages[0].text;
}

function priceQuerySent(calls: RecordedCall[]): string | null {
  const sent = priceLookups(calls);
  if (sent.length === 0) return null;
  return (JSON.parse(String(sent[0].body)) as { p_query: string }).p_query;
}

// ---------- static guards (Phase 5) -------------------------------------------

Deno.test('static: event-type guards are present and no global messageEdited skip exists', () => {
  assertTrue(
    /function buildIntakeCandidate[\s\S]{0,400}?ev\.type !== 'message'/.test(ROUTER_SOURCE),
    'buildIntakeCandidate must still require ev.type === "message"',
  );
  assertTrue(
    /function buildUnsendCandidate[\s\S]{0,400}?ev\.type !== 'unsend'/.test(ROUTER_SOURCE),
    'buildUnsendCandidate must still require ev.type === "unsend"',
  );
  assertTrue(
    /meetangCommandMode === 'all_groups'[\s\S]{0,200}?ev\.type === 'message'/.test(ROUTER_SOURCE),
    'command dispatch must require ev.type === "message"',
  );
  assertTrue(
    !/ev\.type === 'messageEdited'/.test(ROUTER_SOURCE),
    'no branch may key off messageEdited; the patch scopes commands instead of dropping events',
  );
  assertTrue(
    !/continue;[\s\S]{0,40}messageEdited/.test(ROUTER_SOURCE),
    'no global messageEdited skip may exist at the top of the event loop',
  );
});

// ---------- required cases 1-10 -----------------------------------------------

Deno.test('1. normal message "มีตัง สถานะ" still becomes a command candidate', async () => {
  const { calls } = await deliver([textEvent({ groupId: GENERIC_GROUP, text: 'มีตัง สถานะ' })]);
  assertEquals(replies(calls).length, 1, 'expected exactly one Mitang reply for an original message');
});

Deno.test('2. messageEdited "มีตัง สถานะ" produces zero Mitang command candidates', async () => {
  const { calls } = await deliver([
    textEvent({ type: 'messageEdited', groupId: GENERIC_GROUP, text: 'มีตัง สถานะ' }),
  ]);
  assertEquals(replies(calls).length, 0, 'an edited message must never execute a Mitang command');
});

Deno.test('3. messageEdited ordinary text produces zero generic intake candidates', async () => {
  const { calls } = await deliver([
    textEvent({ type: 'messageEdited', groupId: GENERIC_GROUP, text: 'ข้อความทั่วไปที่ถูกแก้ไข' }),
  ]);
  assertEquals(intakeWrites(calls).length, 0, 'an edited message must not create or replace an intake row');
});

Deno.test('4. normal ordinary text keeps existing generic intake behavior', async () => {
  const { calls } = await deliver([
    textEvent({ groupId: GENERIC_GROUP, text: 'ข้อความทั่วไป', messageId: 'M-plain' }),
  ]);
  const inserts = intakeInserts(calls);
  assertEquals(inserts.length, 1, 'expected exactly one intake insert for an original text message');
  assertTrue(String(inserts[0].body).includes('ข้อความทั่วไป'), 'intake insert must carry the original text');
  assertTrue(String(inserts[0].body).includes('M-plain'), 'intake insert must carry the original message id');
  assertTrue(
    inserts[0].url.includes('on_conflict=line_message_id'),
    'intake insert must keep its insert-only conflict target',
  );
});

Deno.test('5. unsend still becomes an unsend candidate', async () => {
  const { calls } = await deliver([unsendEvent(GENERIC_GROUP, 'M-unsend')]);
  const rpcs = unsendRpcs(calls);
  assertEquals(rpcs.length, 1, 'expected exactly one unsend RPC');
  assertTrue(String(rpcs[0].body).includes('M-unsend'), 'unsend RPC must name the retracted message');
});

Deno.test('6. same-payload unsend suppression semantics remain unchanged', async () => {
  const { calls } = await deliver([
    textEvent({ groupId: GENERIC_GROUP, text: 'ข้อความที่จะถูกยกเลิก', messageId: 'M-same' }),
    unsendEvent(GENERIC_GROUP, 'M-same'),
  ]);
  assertEquals(unsendRpcs(calls).length, 1, 'the unsend must still reach the RPC');
  assertEquals(
    intakeWrites(calls).length,
    0,
    'a message unsent in the same payload must never be persisted',
  );
});

Deno.test('7. document/PDF specialized event selection remains unchanged', async () => {
  const doc = await deliver([textEvent({ groupId: DOC_GROUP, text: 'เอกสารแนบ', messageId: 'M-doc' })]);
  const docCalls = docForwards(doc.calls);
  assertEquals(docCalls.length, 1, 'document group events must still reach line-doc-inbox');
  assertTrue(String(docCalls[0].body).includes('M-doc'), 'doc route must receive the event');
  assertEquals(intakeWrites(doc.calls).length, 0, 'document groups never generic-capture');

  const pdf = await deliver([textEvent({ groupId: PDF_GROUP, text: 'ไฟล์ PDF', messageId: 'M-pdf' })]);
  const pdfCalls = pdfForwards(pdf.calls);
  assertEquals(pdfCalls.length, 1, 'PDF group events must still reach the helper');
  assertEquals(pdfCalls[0].body, pdf.rawBody, 'helper must still receive the raw body unchanged');
  assertEquals(intakeWrites(pdf.calls).length, 0, 'PDF groups never generic-capture');
});

Deno.test('8. messageEdited in a specialized group is NOT globally dropped', async () => {
  const doc = await deliver([
    textEvent({ type: 'messageEdited', groupId: DOC_GROUP, text: 'แก้ไขในกลุ่มเอกสาร', messageId: 'M-doc-edit' }),
  ]);
  const docCalls = docForwards(doc.calls);
  assertEquals(docCalls.length, 1, 'doc route must still run for a messageEdited event');
  assertTrue(String(docCalls[0].body).includes('messageEdited'), 'doc route must still see the edited event type');
  assertTrue(String(docCalls[0].body).includes('M-doc-edit'), 'doc route must still see the edited event');

  const pdf = await deliver([
    textEvent({ type: 'messageEdited', groupId: PDF_GROUP, text: 'แก้ไขในกลุ่ม PDF', messageId: 'M-pdf-edit' }),
  ]);
  const pdfCalls = pdfForwards(pdf.calls);
  assertEquals(pdfCalls.length, 1, 'PDF forward must still run for a messageEdited event');
  assertEquals(pdfCalls[0].body, pdf.rawBody, 'PDF helper must still receive the raw body unchanged');
});

Deno.test('9. no new intake UPDATE path exists', async () => {
  const { calls } = await deliver([
    textEvent({ groupId: GENERIC_GROUP, text: 'ข้อความเดิม', messageId: 'M-orig' }),
    textEvent({ type: 'messageEdited', groupId: GENERIC_GROUP, text: 'ข้อความที่แก้แล้ว', messageId: 'M-orig' }),
  ]);
  const writes = intakeWrites(calls);
  assertEquals(writes.length, 1, 'only the original message may write to line_intake_events');
  assertEquals(writes[0].method, 'POST', 'line_intake_events may only be written by insert');
  assertTrue(
    !String(writes[0].body).includes('ข้อความที่แก้แล้ว'),
    'the edited text must never be written',
  );

  const marker = 'rest/v1/line_intake_events';
  const occurrences = ROUTER_SOURCE.split(marker).length - 1;
  assertEquals(occurrences, 1, 'the router must reference the line_intake_events endpoint exactly once');
  const region = ROUTER_SOURCE.slice(ROUTER_SOURCE.indexOf(marker), ROUTER_SOURCE.indexOf(marker) + 400);
  assertTrue(region.includes(`method: 'POST'`), 'the only line_intake_events call must be a POST');
  assertTrue(
    !/'(PATCH|PUT|DELETE)'/.test(region),
    'no PATCH, PUT or DELETE may target line_intake_events',
  );
});

Deno.test('10. no new DB mutation path exists for edited text', async () => {
  const sentinel = 'SENTINEL-edited-8f2a1c';
  const { calls } = await deliver([
    textEvent({ type: 'messageEdited', groupId: GENERIC_GROUP, text: sentinel, messageId: 'M-sent-1' }),
    textEvent({ type: 'messageEdited', groupId: DOC_GROUP, text: sentinel, messageId: 'M-sent-2' }),
    textEvent({ type: 'messageEdited', groupId: PDF_GROUP, text: sentinel, messageId: 'M-sent-3' }),
  ]);

  const dbWrites = calls.filter((call) =>
    call.url.startsWith(`${SUPABASE_URL}/rest/v1/`) && call.method !== 'GET' && call.method !== 'HEAD'
  );
  for (const write of dbWrites) {
    assertTrue(
      !String(write.body ?? '').includes(sentinel),
      `edited text reached a database write: ${write.method} ${write.url}`,
    );
  }
  assertEquals(intakeWrites(calls).length, 0, 'edited events must write nothing to line_intake_events');
  assertEquals(unsendRpcs(calls).length, 0, 'edited events must trigger no unsend RPC');
  assertEquals(replies(calls).length, 0, 'edited events must trigger no Mitang reply');
});

// =============================================================
// Pricing V1
//
// Two independent layers are proved below.
//
//   Router layer  — the real handler with a stubbed price RPC: event-type
//                   gating, command-mode access control, query forwarding,
//                   reply shape, and the absence of any AI/n8n/intake effect.
//
//   Catalog layer — the alias and location rules simulated in TypeScript over
//                   the ACTUAL seed rows parsed out of the migration file. This
//                   proves the seeded data resolves each required query the way
//                   the RPC specifies. It is NOT PostgreSQL execution: no
//                   database was available locally, so the SQL itself is still
//                   unexecuted.
// =============================================================

const PRICE_MIGRATION = await Deno.readTextFile(
  new URL('../../migrations/20260824_line_price_catalog_foundation.sql', import.meta.url),
);

// Executable SQL only. The header prose legitimately names the things the file
// must not do ("no AI", "Myanmar ('MM')"), so negative checks run against the
// code with full-line comments removed.
const PRICE_MIGRATION_CODE = PRICE_MIGRATION
  .split('\n')
  .filter((line) => !line.trimStart().startsWith('--'))
  .join('\n');

// ---------- router layer ------------------------------------------------------

// A confirmed single-cost service, as the RPC would return it.
const FIXTURE_VISA = [{
  service_key: 'global-06',
  service_name: 'ตีวีซ่า',
  variant_name: null,
  cost_status: 'confirmed',
  location_name: null,
  cost_amount: '1200.00',
  sale_price_min: '2000.00',
  sale_price_max: '2000.00',
  note: null,
}];

Deno.test('P1. price command reaches the RPC and replies in an enabled group', async () => {
  priceFixture = FIXTURE_VISA;
  const { calls } = await deliver([
    textEvent({ groupId: GENERIC_GROUP, text: 'มีตัง ราคาตีวีซ่า' }),
  ]);
  assertEquals(priceLookups(calls).length, 1, 'expected exactly one price lookup');
  assertEquals(
    priceQuerySent(calls),
    'ราคาตีวีซ่า',
    'the text after the Mitang prefix must be forwarded verbatim',
  );
  assertEquals(replies(calls).length, 1, 'expected exactly one reply');
  assertEquals(
    replyText(calls),
    'ตีวีซ่า\nทุน: 1,200 บาท\nราคาขาย: 2,000 บาท',
    'single confirmed cost with an exact sale price',
  );
});

Deno.test('P2. price command runs only for ev.type === "message"', async () => {
  priceFixture = FIXTURE_VISA;
  const { calls } = await deliver([
    textEvent({ type: 'messageEdited', groupId: GENERIC_GROUP, text: 'มีตัง ราคาตีวีซ่า' }),
  ]);
  assertEquals(priceLookups(calls).length, 0, 'an edited message must not query pricing');
  assertEquals(replies(calls).length, 0, 'an edited message must not receive a price reply');
});

Deno.test('P3. customer_safe group cannot access pricing or cost data', async () => {
  priceFixture = FIXTURE_VISA;
  const { calls } = await deliver([
    textEvent({ groupId: SAFE_GROUP, text: 'มีตัง ราคาตีวีซ่า' }),
  ]);
  assertEquals(priceLookups(calls).length, 0, 'customer_safe must never query pricing');
  assertEquals(replies(calls).length, 0, 'customer_safe must receive no reply');
  for (const call of calls) {
    assertTrue(!String(call.body ?? '').includes('1200'), 'no cost figure may leave the router');
  }
});

Deno.test('P4. disabled group cannot access pricing', async () => {
  priceFixture = FIXTURE_VISA;
  const { calls } = await deliver([
    textEvent({ groupId: DISABLED_GROUP, text: 'มีตัง ราคาตีวีซ่า' }),
  ]);
  assertEquals(priceLookups(calls).length, 0, 'disabled must never query pricing');
  assertEquals(replies(calls).length, 0, 'disabled must receive no reply');
});

Deno.test('P5. unknown group cannot access pricing even though other commands default open', async () => {
  priceFixture = FIXTURE_VISA;
  const price = await deliver([textEvent({ groupId: UNKNOWN_GROUP, text: 'มีตัง ราคาตีวีซ่า' })]);
  assertEquals(priceLookups(price.calls).length, 0, 'pricing requires an explicitly enabled group');
  assertEquals(replies(price.calls).length, 0, 'no price reply for an unknown group');

  // The historical default-open behavior of the other command families is unchanged.
  const status = await deliver([textEvent({ groupId: UNKNOWN_GROUP, text: 'มีตัง สถานะ' })]);
  assertEquals(replies(status.calls).length, 1, 'status must still answer in an unknown group');
});

Deno.test('P6. ordinary chatter never invokes the price path', async () => {
  priceFixture = FIXTURE_VISA;
  for (const text of ['ราคาเท่าไหร่ครับ', 'ตีวีซ่าราคา', 'วันนี้ราคาทุนเท่าไหร่']) {
    const { calls } = await deliver([textEvent({ groupId: GENERIC_GROUP, text })]);
    assertEquals(priceLookups(calls).length, 0, `chatter must not query pricing: ${text}`);
    assertEquals(replies(calls).length, 0, `chatter must not be answered: ${text}`);
  }
});

Deno.test('P7. price commands never enter generic intake', async () => {
  priceFixture = FIXTURE_VISA;
  const { calls } = await deliver([
    textEvent({ groupId: GENERIC_GROUP, text: 'มีตัง ราคาตีวีซ่า', messageId: 'M-price' }),
  ]);
  assertEquals(intakeWrites(calls).length, 0, 'a price command must not be captured as intake');
});

Deno.test('P8. no AI, n8n or unexpected host is contacted on the price path', async () => {
  priceFixture = FIXTURE_VISA;
  const { calls } = await deliver([
    textEvent({ groupId: GENERIC_GROUP, text: 'มีตัง ราคาตีวีซ่า' }),
  ]);
  const allowed = [
    `${SUPABASE_URL}/rest/v1/line_bot_groups`,
    `${SUPABASE_URL}/rest/v1/rpc/app_lookup_line_price`,
    'https://api.line.me/v2/bot/message/reply',
  ];
  for (const call of calls) {
    assertTrue(
      allowed.some((prefix) => call.url.startsWith(prefix)),
      `unexpected outbound call on the price path: ${call.method} ${call.url}`,
    );
  }
  assertTrue(
    !/n8n|openai|anthropic|gemini|generativelanguage/i.test(PRICE_MIGRATION_CODE),
    'the price migration must contain no AI or n8n reference',
  );
});

Deno.test('P9. reply shapes: unknown cost, multi-location, note, variants, no match', async () => {
  priceFixture = [{
    service_key: 'global-07',
    service_name: 'ขึ้นทะเบียนใหม่',
    variant_name: null,
    cost_status: 'unknown',
    location_name: null,
    cost_amount: null,
    sale_price_min: '6500.00',
    sale_price_max: '8500.00',
    note: null,
  }];
  const unknownCost = await deliver([
    textEvent({ groupId: GENERIC_GROUP, text: 'มีตัง ราคาขึ้นทะเบียนใหม่' }),
  ]);
  assertEquals(
    replyText(unknownCost.calls),
    'ขึ้นทะเบียนใหม่\nทุน: ยังไม่ยืนยัน\nราคาขาย: 6,500–8,500 บาท',
    'unknown cost must never print a number',
  );

  const locationRow = (location_name: string, cost_amount: string) => ({
    service_key: 'global-02',
    service_name: 'แจ้งเข้า (แจ้งออกตาย)',
    variant_name: null,
    cost_status: 'confirmed',
    location_name,
    cost_amount,
    sale_price_min: '3500.00',
    sale_price_max: '4500.00',
    note: null,
  });
  priceFixture = [
    locationRow('ปทุมธานี', '860.00'),
    locationRow('กรุงเทพฯ', '2510.00'),
    locationRow('นนทบุรี', '1460.00'),
  ];
  const multi = await deliver([
    textEvent({ groupId: GENERIC_GROUP, text: 'มีตัง ราคาแจ้งเข้าแจ้งออกตาย' }),
  ]);
  assertEquals(
    replyText(multi.calls),
    'แจ้งเข้า (แจ้งออกตาย)\nทุน:\n- ปทุมธานี 860 บาท\n- กรุงเทพฯ 2,510 บาท\n' +
      '- นนทบุรี 1,460 บาท\nราคาขาย: 3,500–4,500 บาท',
    'every cost variant must be listed when no province is named',
  );

  priceFixture = [{
    service_key: 'global-08',
    service_name: 'ต่ออายุ มติ 11',
    variant_name: null,
    cost_status: 'confirmed',
    location_name: null,
    cost_amount: '4300.00',
    sale_price_min: '5500.00',
    sale_price_max: '7500.00',
    note: 'มีประกัน ลดได้ / ไม่เอาวีซ่า 5500',
  }];
  const noted = await deliver([
    textEvent({ groupId: GENERIC_GROUP, text: 'มีตัง ราคาต่ออายุ มติ 11' }),
  ]);
  assertEquals(
    replyText(noted.calls),
    'ต่ออายุ มติ 11\nทุน: 4,300 บาท\nราคาขาย: 5,500–7,500 บาท\n' +
      'หมายเหตุ: มีประกัน ลดได้ / ไม่เอาวีซ่า 5500',
    'the note must be preserved verbatim',
  );

  priceFixture = [
    {
      service_key: 'la-03',
      service_name: 'Passport ลาว ปกติ',
      variant_name: '45–60 วัน',
      cost_status: 'confirmed',
      location_name: null,
      cost_amount: '5000.00',
      sale_price_min: '6000.00',
      sale_price_max: '6500.00',
      note: null,
    },
    {
      service_key: 'la-04',
      service_name: 'Passport ลาว ด่วนพิเศษ',
      variant_name: '15–20 วัน',
      cost_status: 'confirmed',
      location_name: null,
      cost_amount: '6500.00',
      sale_price_min: '7000.00',
      sale_price_max: '7500.00',
      note: null,
    },
  ];
  const variants = await deliver([
    textEvent({ groupId: GENERIC_GROUP, text: 'มีตัง ราคาพาสลาว' }),
  ]);
  assertEquals(
    replyText(variants.calls),
    'Passport ลาว ปกติ 45–60 วัน\nทุน: 5,000 บาท\nราคาขาย: 6,000–6,500 บาท\n\n' +
      'Passport ลาว ด่วนพิเศษ 15–20 วัน\nทุน: 6,500 บาท\nราคาขาย: 7,000–7,500 บาท',
    'both variants must be rendered as separate blocks',
  );

  priceFixture = [];
  const miss = await deliver([
    textEvent({ groupId: GENERIC_GROUP, text: 'มีตัง ราคาอะไรก็ไม่รู้' }),
  ]);
  assertEquals(replyText(miss.calls), 'ไม่พบราคากลางรายการนี้', 'a miss must be deterministic');
});

Deno.test('P10. specialized document/PDF routes are unaffected by the price command', async () => {
  priceFixture = FIXTURE_VISA;
  const doc = await deliver([
    textEvent({ groupId: DOC_GROUP, text: 'มีตัง ราคาตีวีซ่า', messageId: 'M-doc-price' }),
  ]);
  assertEquals(docForwards(doc.calls).length, 1, 'the document route must still receive the event');
  assertEquals(intakeWrites(doc.calls).length, 0, 'document groups still never generic-capture');

  const pdf = await deliver([
    textEvent({ groupId: PDF_GROUP, text: 'มีตัง ราคาตีวีซ่า', messageId: 'M-pdf-price' }),
  ]);
  assertEquals(pdfForwards(pdf.calls).length, 1, 'the PDF helper must still receive the payload');
  assertEquals(
    pdfForwards(pdf.calls)[0].body,
    pdf.rawBody,
    'the helper still receives the raw body unchanged',
  );
});

// ---------- catalog layer: seeded data + documented matching rules ------------

interface SeedService {
  key: string;
  name: string;
  variant: string | null;
  scope: string;
  countryCode: string | null;
  saleMin: number;
  saleMax: number;
  costStatus: string;
}

interface SeedCost {
  key: string;
  location: string | null;
  tokens: string[];
  amount: number;
}

// Seeds are fail-closed, so a statement now ends at its own semicolon rather
// than at an ON CONFLICT clause. No seed value contains a semicolon.
function sqlBlock(marker: string): string {
  const start = PRICE_MIGRATION.indexOf(marker);
  if (start < 0) throw new Error(`migration block not found: ${marker}`);
  const end = PRICE_MIGRATION.indexOf(';', start);
  if (end < 0) throw new Error(`migration block unterminated: ${marker}`);
  return PRICE_MIGRATION.slice(start, end);
}

function parseServices(): SeedService[] {
  const block = sqlBlock('insert into public.line_price_services (');
  const re =
    /\('((?:global|la)-\d+)',\s*'([^']*)',\s*(null|'[^']*'),\s*'(global|country)',\s*(null|'[A-Z]{2}'),\s*(null|'[^']*'),\s*(\d+),\s*(\d+),\s*'(confirmed|unknown)'/g;
  const out: SeedService[] = [];
  for (const m of block.matchAll(re)) {
    out.push({
      key: m[1],
      name: m[2],
      variant: m[3] === 'null' ? null : m[3].slice(1, -1),
      scope: m[4],
      countryCode: m[5] === 'null' ? null : m[5].slice(1, -1),
      saleMin: Number(m[7]),
      saleMax: Number(m[8]),
      costStatus: m[9],
    });
  }
  return out;
}

function parseCosts(): SeedCost[] {
  const single = sqlBlock(
    'insert into public.line_price_service_costs (service_id, cost_amount, sort_order)',
  );
  const out: SeedCost[] = [];
  for (const m of single.matchAll(/\('((?:global|la)-\d+)',\s*(\d+)::numeric\)/g)) {
    out.push({ key: m[1], location: null, tokens: [], amount: Number(m[2]) });
  }
  const located = sqlBlock(
    'service_id, location_key, location_name, location_match_norms, cost_amount, sort_order',
  );
  const re =
    /\('((?:global|la)-\d+)',\s*'[a-z]+',\s*'([^']*)',\s*array\[([^\]]*)\],\s*(\d+)::numeric/g;
  for (const m of located.matchAll(re)) {
    out.push({
      key: m[1],
      location: m[2],
      tokens: m[3].split(',').map((token) => token.trim().replace(/^'|'$/g, '')),
      amount: Number(m[4]),
    });
  }
  return out;
}

function parseAliases(): { key: string; alias: string }[] {
  const block = sqlBlock('insert into public.line_price_service_aliases (service_id, alias_norm)');
  const out: { key: string; alias: string }[] = [];
  for (const m of block.matchAll(/\('((?:global|la)-\d+)',\s*'([^']*)'\)/g)) {
    out.push({ key: m[1], alias: m[2] });
  }
  return out;
}

const SEED_SERVICES = parseServices();
const SEED_COSTS = parseCosts();
const SEED_ALIASES = parseAliases();

// Mirrors public.line_price_normalize: fold case, keep only digits, latin
// letters and Thai characters U+0E01..U+0E59 (the SQL class 'ก-๙').
function normalizeQuery(text: string): string {
  return text.toLowerCase().replace(/[^0-9a-zก-๙]/gu, '');
}

// Mirrors the RPC: keep every alias literally contained in the normalized query,
// then keep only those tied for the longest alias.
function matchServices(query: string): string[] {
  const norm = normalizeQuery(query);
  if (norm === '') return [];
  const hits = SEED_ALIASES
    .filter((entry) => norm.includes(entry.alias))
    .map((entry) => ({ key: entry.key, len: [...entry.alias].length }));
  if (hits.length === 0) return [];
  const best = Math.max(...hits.map((hit) => hit.len));
  return [...new Set(hits.filter((hit) => hit.len === best).map((hit) => hit.key))].sort();
}

// Mirrors the RPC's location rule: if the query names any priced location for
// this service, return only those; otherwise return every cost row.
function matchCosts(serviceKey: string, query: string): SeedCost[] {
  const norm = normalizeQuery(query);
  const rows = SEED_COSTS.filter((cost) => cost.key === serviceKey);
  const located = rows.filter((cost) => cost.location !== null);
  if (located.length === 0) return rows;
  const named = located.filter((cost) => cost.tokens.some((token) => norm.includes(token)));
  return named.length > 0 ? named : located;
}

function serviceByKey(key: string): SeedService {
  const found = SEED_SERVICES.find((svc) => svc.key === key);
  if (!found) throw new Error(`seed service not found: ${key}`);
  return found;
}

Deno.test('C1. exactly 12 services are seeded: 8 global, 4 Laos, no MM or KH', () => {
  assertEquals(SEED_SERVICES.length, 12, 'the catalog must seed exactly 12 services');
  assertEquals(SEED_SERVICES.filter((s) => s.scope === 'global').length, 8, 'expected 8 global services');
  assertEquals(SEED_SERVICES.filter((s) => s.scope === 'country').length, 4, 'expected 4 country services');
  for (const svc of SEED_SERVICES) {
    if (svc.scope === 'global') {
      assertEquals(svc.countryCode, null, `${svc.key}: global rows must have a null country_code`);
    } else {
      assertEquals(svc.countryCode, 'LA', `${svc.key}: only Laos may be seeded in V1`);
    }
    assertTrue(svc.saleMax >= svc.saleMin, `${svc.key}: sale max must not be below sale min`);
  }
  assertTrue(!/'MM'|'KH'/.test(PRICE_MIGRATION_CODE), 'Myanmar and Cambodia must not be seeded yet');
});

Deno.test('C2. the unknown cost stays non-numeric and every other service has a cost', () => {
  const unknown = SEED_SERVICES.filter((svc) => svc.costStatus === 'unknown');
  assertEquals(unknown.length, 1, 'exactly one service has an unconfirmed cost');
  assertEquals(unknown[0].key, 'global-07', 'ขึ้นทะเบียนใหม่ is the unconfirmed one');
  assertEquals(
    SEED_COSTS.filter((cost) => cost.key === 'global-07').length,
    0,
    'an unconfirmed cost must have no cost row at all',
  );
  for (const svc of SEED_SERVICES) {
    if (svc.costStatus !== 'confirmed') continue;
    assertTrue(
      SEED_COSTS.some((cost) => cost.key === svc.key),
      `${svc.key}: a confirmed cost must have at least one cost row`,
    );
  }
});

Deno.test('C3. generic พาสลาว returns both Laos passport variants', () => {
  assertEquals(matchServices('ราคาพาสลาว'), ['la-03', 'la-04'], 'generic alias is intentionally ambiguous');
  assertEquals(matchServices('พาสลาวราคาเท่าไหร่'), ['la-03', 'la-04'], 'word order must not matter');
  assertEquals(matchServices('ราคาพาสปอร์ตลาว'), ['la-03', 'la-04'], 'the spelled-out form behaves the same');
});

Deno.test('C4. พาสลาวด่วน returns only the express variant', () => {
  assertEquals(matchServices('ราคาพาสลาวด่วน'), ['la-04'], 'the longer alias must win');
  assertEquals(matchServices('ราคาพาสปอร์ตลาวด่วนพิเศษ'), ['la-04'], 'full express wording resolves alone');
});

Deno.test('C5. พาสปอร์ตลาว 45-60 วัน returns only the normal variant', () => {
  assertEquals(matchServices('ราคาพาสปอร์ตลาว 45-60 วัน'), ['la-03'], 'punctuation is normalized away');
  assertEquals(matchServices('ราคาพาสลาว 15–20 วัน'), ['la-04'], 'the express window resolves to express');
});

Deno.test('C6. global ตีวีซ่า resolves to cost 1200 and sale 2000', () => {
  assertEquals(matchServices('ราคาตีวีซ่า'), ['global-06'], 'ตีวีซ่า is unambiguous');
  const svc = serviceByKey('global-06');
  assertEquals(svc.saleMin, 2000, 'sale min');
  assertEquals(svc.saleMax, 2000, 'sale max is the same figure: an exact price');
  const costs = matchCosts('global-06', 'ราคาตีวีซ่า');
  assertEquals(costs.length, 1, 'one cost row');
  assertEquals(costs[0].amount, 1200, 'cost 1200');
});

Deno.test('C7. ขึ้นทะเบียนใหม่ resolves to an unknown cost and sale 6500-8500', () => {
  assertEquals(matchServices('ราคาขึ้นทะเบียนใหม่'), ['global-07'], 'the specific alias wins');
  const svc = serviceByKey('global-07');
  assertEquals(svc.costStatus, 'unknown', 'cost is not confirmed');
  assertEquals([svc.saleMin, svc.saleMax], [6500, 8500], 'sale range');
  assertEquals(matchCosts('global-07', 'ราคาขึ้นทะเบียนใหม่').length, 0, 'no cost figure exists');
});

Deno.test('C8. แจ้งเข้าแจ้งออกตาย without a province returns all three cost variants', () => {
  const query = 'ราคาแจ้งเข้าแจ้งออกตาย';
  assertEquals(matchServices(query), ['global-02'], 'the compound alias beats แจ้งเข้า and แจ้งออก');
  const costs = matchCosts('global-02', query);
  assertEquals(costs.length, 3, 'all three provinces are returned rather than one being guessed');
  assertEquals(costs.map((cost) => cost.amount), [860, 2510, 1460], 'ปทุมธานี, กรุงเทพฯ, นนทบุรี');
  const svc = serviceByKey('global-02');
  assertEquals([svc.saleMin, svc.saleMax], [3500, 4500], 'sale range');
});

Deno.test('C9. naming a province narrows แจ้งเข้าแจ้งออกตาย to exactly one cost', () => {
  const cases: [string, string, number][] = [
    ['ปทุม', 'ปทุมธานี', 860],
    ['ปทุมธานี', 'ปทุมธานี', 860],
    ['กทม', 'กรุงเทพฯ', 2510],
    ['กรุงเทพ', 'กรุงเทพฯ', 2510],
    ['กรุงเทพมหานคร', 'กรุงเทพฯ', 2510],
    ['นนทบุรี', 'นนทบุรี', 1460],
  ];
  for (const [token, location, amount] of cases) {
    const query = `ราคาแจ้งเข้าแจ้งออกตาย ${token}`;
    assertEquals(matchServices(query), ['global-02'], `${token}: still the same service`);
    const costs = matchCosts('global-02', query);
    assertEquals(costs.length, 1, `${token}: exactly one cost variant`);
    assertEquals(costs[0].location, location, `${token}: location`);
    assertEquals(costs[0].amount, amount, `${token}: amount`);
  }
});

Deno.test('C10. ต่ออายุ มติ 11 resolves with its note preserved', () => {
  assertEquals(matchServices('ราคาต่ออายุ มติ 11'), ['global-08'], 'the compound alias wins over มติ11');
  const svc = serviceByKey('global-08');
  assertEquals([svc.saleMin, svc.saleMax], [5500, 7500], 'sale range');
  assertEquals(matchCosts('global-08', 'ราคาต่ออายุ มติ 11')[0].amount, 4300, 'cost 4300');
  assertTrue(
    PRICE_MIGRATION.includes('มีประกัน ลดได้ / ไม่เอาวีซ่า 5500'),
    'the note must be seeded verbatim from the source data',
  );
});

Deno.test('C11. every documented example query resolves to exactly the intended services', () => {
  const expected: [string, string[]][] = [
    ['ราคาแจ้งเข้า', ['global-01']],
    ['แจ้งเข้าราคาเท่าไหร่', ['global-01']],
    ['ราคาทุนแจ้งเข้า', ['global-01']],
    ['ราคาขายแจ้งออก', ['global-03']],
    ['ราคาตีวีซ่า', ['global-06']],
    ['ราคาขึ้นทะเบียนใหม่', ['global-07']],
    ['ราคาต่ออายุ มติ 11', ['global-08']],
    ['ราคาพาสลาว', ['la-03', 'la-04']],
    ['ราคาพาสปอร์ตลาว', ['la-03', 'la-04']],
    ['พาสลาวราคาเท่าไหร่', ['la-03', 'la-04']],
    ['ราคาพาสลาวด่วน', ['la-04']],
    ['ราคาพาสปอร์ตลาว 45-60 วัน', ['la-03']],
    ['ราคา MOU ลาว', ['la-01']],
    ['ราคาต่อ MOU ลาว', ['la-02']],
    ['ราคารายงานตัว 90 วัน ไม่ปรับ', ['global-04']],
    ['ราคารายงานตัว 90 วัน ปรับ', ['global-05']],
  ];
  for (const [query, want] of expected) {
    assertEquals(matchServices(query), want, `query: ${query}`);
  }
  assertEquals(matchServices('ราคาอะไรก็ไม่รู้'), [], 'an unmatched query resolves to nothing');
});

Deno.test('C12. migration structure: expected objects, security posture, no foreign coupling', () => {
  const count = (re: RegExp) => (PRICE_MIGRATION.match(re) || []).length;
  assertEquals(count(/^create table /gm), 3, 'exactly three pricing tables');
  assertEquals(count(/^create function /gm), 2, 'exactly two functions');
  assertEquals(count(/^create unique index /gm), 3, 'three unique indexes');
  assertEquals(count(/^create index /gm), 3, 'three supporting indexes');
  assertEquals(count(/enable row level security/g), 3, 'RLS on every pricing table');
  assertEquals(count(/create policy/g), 0, 'zero RLS policies');
  assertEquals(count(/grant .* on table/g), 0, 'no direct table privilege for any role');
  assertEquals(count(/^security definer$/gm), 1, 'only the lookup RPC is SECURITY DEFINER');
  assertEquals(count(/^set search_path = ''$/gm), 2, 'both functions pin an empty search_path');
  assertEquals(
    count(/grant execute on function public\.app_lookup_line_price\(text\) to service_role;/g),
    1,
    'service_role may execute the lookup RPC and nothing else',
  );
  assertTrue(
    !/public\.customers|public\.line_bot_groups|public\.groups|public\.cases|public\.documents/
      .test(PRICE_MIGRATION_CODE),
    'the pricing migration must not depend on customer or registry tables',
  );
  assertTrue(
    !/\bcron\b|pg_net|vault|http/i.test(PRICE_MIGRATION_CODE),
    'no scheduler, HTTP or secret access',
  );
  assertTrue(
    !/^\s*(delete|drop|truncate|alter table public\.(customers|line_bot_groups))/im
      .test(PRICE_MIGRATION_CODE),
    'no destructive statement and no change to existing tables',
  );
});

// ---------- revision gate: MOU Laos, help discoverability, fail-closed --------

Deno.test('C13. MOU Laos: new versus renewal resolves in both word orders', () => {
  // A renewal wording must never fall back to LA-01 (new MOU).
  assertEquals(matchServices('ราคา MOU ลาว'), ['la-01'], 'A: bare MOU ลาว is the new MOU');
  assertEquals(matchServices('ราคาต่อ MOU ลาว'), ['la-02'], 'B: ต่อ before MOU is a renewal');
  assertEquals(matchServices('ราคาต่ออายุ MOU ลาว'), ['la-02'], 'C: ต่ออายุ before MOU is a renewal');
  assertEquals(matchServices('ราคา MOU ลาว ต่อ'), ['la-02'], 'D: ต่อ after MOU is a renewal');
  assertEquals(matchServices('ราคา MOU ลาว ต่ออายุ'), ['la-02'], 'E: ต่ออายุ after MOU is a renewal');

  // The two services stay distinct in cost and sale range.
  const fresh = serviceByKey('la-01');
  assertEquals([fresh.saleMin, fresh.saleMax], [15000, 17000], 'LA-01 sale range');
  assertEquals(matchCosts('la-01', 'ราคา MOU ลาว')[0].amount, 9600, 'LA-01 cost');
  const renewal = serviceByKey('la-02');
  assertEquals([renewal.saleMin, renewal.saleMax], [6500, 8500], 'LA-02 sale range');
  assertEquals(matchCosts('la-02', 'ราคาต่อ MOU ลาว')[0].amount, 4100, 'LA-02 cost');

  // Structural guarantee behind the fix: LA-01 has exactly one alias and every
  // LA-02 alias is strictly longer, so longest-match can never pick LA-01 for a
  // renewal phrasing.
  const fresh01 = SEED_ALIASES.filter((entry) => entry.key === 'la-01');
  assertEquals(fresh01.length, 1, 'LA-01 carries a single generic alias');
  assertEquals(fresh01[0].alias, 'mouลาว', 'LA-01 alias');
  const renewalAliases = SEED_ALIASES.filter((entry) => entry.key === 'la-02');
  assertEquals(renewalAliases.length, 4, 'LA-02 carries both word orders, short and long form');
  for (const entry of renewalAliases) {
    assertTrue(
      [...entry.alias].length > [...fresh01[0].alias].length,
      `renewal alias ${entry.alias} must outrank the generic LA-01 alias`,
    );
  }
});

Deno.test('C14. migration is fail-closed: preflight present, no silent tolerance', () => {
  const count = (re: RegExp) => (PRICE_MIGRATION_CODE.match(re) || []).length;

  assertEquals(count(/if not exists/gi), 0, 'no CREATE ... IF NOT EXISTS may remain');
  assertEquals(count(/or replace/gi), 0, 'no CREATE OR REPLACE may remain');
  assertEquals(count(/on conflict/gi), 0, 'no ON CONFLICT clause may remain: seeds must insert exactly');

  assertTrue(/do \$preflight\$/.test(PRICE_MIGRATION_CODE), 'an explicit preflight block must exist');
  assertTrue(
    PRICE_MIGRATION_CODE.indexOf('do $preflight$') < PRICE_MIGRATION_CODE.indexOf('create function'),
    'the preflight must run before anything is created',
  );

  // The preflight must name every intended pricing object.
  const preflight = PRICE_MIGRATION_CODE.slice(
    PRICE_MIGRATION_CODE.indexOf('do $preflight$'),
    PRICE_MIGRATION_CODE.indexOf('$preflight$;') + '$preflight$;'.length,
  );
  for (
    const object of [
      'public.line_price_services',
      'public.line_price_service_costs',
      'public.line_price_service_aliases',
      'public.line_price_normalize(text)',
      'public.app_lookup_line_price(text)',
    ]
  ) {
    assertTrue(preflight.includes(object), `preflight must check ${object}`);
  }
  assertTrue(/raise exception/.test(preflight), 'the preflight must raise, not warn');
  // Statement-level check: the hint text legitimately contains the word "drop"
  // while telling the operator not to drop anything.
  assertTrue(
    !/\b(drop|alter|truncate)\s+(table|function|index|schema|extension)\b/i.test(preflight),
    'the preflight must never drop or alter an object',
  );
  assertTrue(!/\bdelete\s+from\b/i.test(preflight), 'the preflight must never delete rows');
  assertTrue(!/\b(insert|update)\s+(into|public\.)/i.test(preflight), 'the preflight must not write');

  // Nothing destructive anywhere in the migration.
  assertEquals(count(/^\s*drop /gim), 0, 'no DROP statement');
  assertEquals(count(/^\s*delete /gim), 0, 'no DELETE statement');
  assertEquals(count(/^\s*truncate /gim), 0, 'no TRUNCATE statement');
  assertEquals(count(/^\s*alter table (?!public\.line_price_)/gim), 0, 'no ALTER of a non-pricing table');

  // Still no AI, no n8n, no customer coupling, no environment branching.
  assertTrue(
    !/n8n|openai|anthropic|gemini|generativelanguage/i.test(PRICE_MIGRATION_CODE),
    'no AI or n8n reference',
  );
  assertTrue(
    !/public\.customers|public\.line_bot_groups|public\.groups|public\.cases|public\.documents/
      .test(PRICE_MIGRATION_CODE),
    'no customer or registry dependency',
  );
  assertTrue(
    !/staging|production|bzwtknqvhvdmatangzqf|magwqolbjmwymqxelizl/i.test(PRICE_MIGRATION_CODE),
    'no environment-specific logic or project ref',
  );
});

Deno.test('P11. help now makes the price command discoverable without listing prices', async () => {
  priceFixture = [];
  const { calls } = await deliver([
    textEvent({ groupId: GENERIC_GROUP, text: 'มีตัง ช่วยอะไรได้บ้าง' }),
  ]);
  const help = replyText(calls);

  assertTrue(help.includes('มีตัง ราคาตีวีซ่า'), 'help must show a global price example');
  assertTrue(help.includes('มีตัง ราคาพาสลาว'), 'help must show a country price example');

  // Existing help content is preserved.
  assertTrue(help.includes('มีตัง สถานะ'), 'the status command must still be listed');
  assertTrue(help.includes('มีตัง จำนวนเอกสาร'), 'the document command must still be listed');
  assertTrue(
    help.includes('ตอนนี้ยังไม่ใช้ AI และจะไม่ตอบข้อความทั่วไปในกลุ่ม'),
    'the no-AI / no-chatter wording must be preserved',
  );

  // Help is not a catalog: no figure and no service inventory leaks through it.
  assertEquals(priceLookups(calls).length, 0, 'help must not query the price catalog');
  for (const amount of ['1,200', '9,600', '15,000', '4,300', '860', '2,510']) {
    assertTrue(!help.includes(amount), `help must not contain the price figure ${amount}`);
  }
  assertTrue(help.split('\n').length <= 12, 'help must stay short');
});

// ---------- command prefix forms: space / no-space / colon --------------------

// Every command family must answer identically whether the body is separated by
// a space, a colon, or nothing at all.
const PREFIX_FORMS = (body: string) => [`มีตัง ${body}`, `มีตัง${body}`, `มีตัง:${body}`];

Deno.test('P12. help works with space, no-space and colon', async () => {
  for (const text of PREFIX_FORMS('ช่วยอะไรได้บ้าง')) {
    priceFixture = [];
    const { calls } = await deliver([textEvent({ groupId: GENERIC_GROUP, text })]);
    assertEquals(replies(calls).length, 1, `expected one reply for: ${text}`);
    assertTrue(replyText(calls).includes('คำสั่งที่ใช้ได้:'), `help body for: ${text}`);
  }
});

Deno.test('P13. status works with space, no-space and colon', async () => {
  for (const text of PREFIX_FORMS('สถานะ')) {
    priceFixture = [];
    const { calls } = await deliver([textEvent({ groupId: GENERIC_GROUP, text })]);
    assertEquals(replies(calls).length, 1, `expected one reply for: ${text}`);
    assertTrue(replyText(calls).includes('มีตังพร้อมใช้งาน'), `status body for: ${text}`);
  }
});

Deno.test('P14. document count works with space, no-space and colon', async () => {
  for (const text of PREFIX_FORMS('จำนวนเอกสาร')) {
    priceFixture = [];
    const { calls } = await deliver([textEvent({ groupId: GENERIC_GROUP, text })]);
    assertEquals(replies(calls).length, 1, `expected one reply for: ${text}`);
    assertTrue(replyText(calls).includes('จำนวนเอกสารของกลุ่มนี้'), `document body for: ${text}`);
  }
});

Deno.test('P15. pricing works with space, no-space and colon, forwarding the same body', async () => {
  for (const text of PREFIX_FORMS('ราคาพาสลาว')) {
    priceFixture = FIXTURE_VISA;
    const { calls } = await deliver([textEvent({ groupId: GENERIC_GROUP, text })]);
    assertEquals(priceLookups(calls).length, 1, `expected one price lookup for: ${text}`);
    assertEquals(
      priceQuerySent(calls),
      'ราคาพาสลาว',
      `the forwarded body must be identical regardless of delimiter: ${text}`,
    );
  }
});

Deno.test('P16. joined pricing phrasings forward the exact body after มีตัง', async () => {
  const cases: [string, string][] = [
    ['มีตังราคาแจ้งเข้าเท่าไหร่', 'ราคาแจ้งเข้าเท่าไหร่'],
    ['มีตัง ราคาแจ้งเข้าเท่าไหร่', 'ราคาแจ้งเข้าเท่าไหร่'],
    ['มีตังขอราคาตีวีซ่า', 'ขอราคาตีวีซ่า'],
    ['มีตัง ขอราคาตีวีซ่า', 'ขอราคาตีวีซ่า'],
    ['มีตังทุนต่ออายุ มติ 11', 'ทุนต่ออายุ มติ 11'],
    ['มีตัง ทุนต่ออายุ มติ 11', 'ทุนต่ออายุ มติ 11'],
  ];
  for (const [text, expected] of cases) {
    priceFixture = FIXTURE_VISA;
    const { calls } = await deliver([textEvent({ groupId: GENERIC_GROUP, text })]);
    assertEquals(priceLookups(calls).length, 1, `expected a price lookup for: ${text}`);
    assertEquals(priceQuerySent(calls), expected, `forwarded body for: ${text}`);
  }
});

Deno.test('P17. joined form is strict; the delimiter form keeps its unknown behavior', async () => {
  // Ordinary words that merely begin with มีตัง must stay chatter: no reply, no
  // price lookup, and still eligible for ordinary intake capture.
  for (const text of ['มีตังใจทำงาน', 'มีตังนิดหน่อย', 'มีตังแล้วหรือยัง', 'มีตังแมวอยู่ไหน']) {
    priceFixture = FIXTURE_VISA;
    const { calls } = await deliver([
      textEvent({ groupId: GENERIC_GROUP, text, messageId: `M-${text}` }),
    ]);
    assertEquals(replies(calls).length, 0, `must not be answered: ${text}`);
    assertEquals(priceLookups(calls).length, 0, `must not query pricing: ${text}`);
    assertEquals(intakeInserts(calls).length, 1, `must be treated as ordinary text: ${text}`);
  }

  // The delimiter form is unchanged, including its unknown-command reply.
  priceFixture = [];
  const delimited = await deliver([
    textEvent({ groupId: GENERIC_GROUP, text: 'มีตัง อะไรก็ไม่รู้' }),
  ]);
  assertEquals(replies(delimited.calls).length, 1, 'a delimited unknown command still answers');
  assertTrue(
    replyText(delimited.calls).includes('มีตังยังไม่รู้จักคำสั่งนี้'),
    'the existing unknown-command reply is preserved',
  );
  assertEquals(intakeWrites(delimited.calls).length, 0, 'a delimited command still never enters intake');
});

Deno.test('P18. a joined command cannot execute from a messageEdited event', async () => {
  priceFixture = FIXTURE_VISA;
  const status = await deliver([
    textEvent({ type: 'messageEdited', groupId: GENERIC_GROUP, text: 'มีตังสถานะ' }),
  ]);
  assertEquals(replies(status.calls).length, 0, 'edited joined status must not answer');

  const price = await deliver([
    textEvent({ type: 'messageEdited', groupId: GENERIC_GROUP, text: 'มีตังราคาพาสลาว' }),
  ]);
  assertEquals(priceLookups(price.calls).length, 0, 'edited joined price must not query pricing');
  assertEquals(replies(price.calls).length, 0, 'edited joined price must not answer');
});

Deno.test('P19. joined pricing never enters generic intake', async () => {
  priceFixture = FIXTURE_VISA;
  const { calls } = await deliver([
    textEvent({ groupId: GENERIC_GROUP, text: 'มีตังราคาตีวีซ่า', messageId: 'M-joined-price' }),
  ]);
  assertEquals(priceLookups(calls).length, 1, 'the joined price command still runs');
  assertEquals(intakeWrites(calls).length, 0, 'a joined price command must not be captured as intake');
});

Deno.test('P20. joined pricing still obeys command_mode', async () => {
  for (const group of [SAFE_GROUP, DISABLED_GROUP, UNKNOWN_GROUP]) {
    priceFixture = FIXTURE_VISA;
    const { calls } = await deliver([textEvent({ groupId: group, text: 'มีตังราคาตีวีซ่า' })]);
    assertEquals(priceLookups(calls).length, 0, `pricing must stay closed for group ${group}`);
    assertEquals(replies(calls).length, 0, `no reply for group ${group}`);
  }
});
