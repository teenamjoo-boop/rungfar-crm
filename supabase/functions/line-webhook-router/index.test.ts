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
];

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
