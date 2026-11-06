import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { Client } from '@heroiclabs/nakama-js';

const HOST = process.env.NAKAMA_HOST ?? 'blobattle-nakama';
const PORT = process.env.NAKAMA_PORT ?? '7350';
const KEY = process.env.NAKAMA_SERVER_KEY;

const lua = (expression) =>
  JSON.parse(
    execFileSync(
      'luajit',
      ['-e', `package.path = "./?.lua;" .. package.path; print(require("dkjson").encode(${expression}))`],
      { cwd: new URL('../..', import.meta.url).pathname, encoding: 'utf8' },
    ),
  );

export const OP = lua('require("shared.protocol").OPS');

export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export async function eventually(probe, timeoutMs = 3000, stepMs = 100) {
  const deadline = Date.now() + timeoutMs;
  let last = await probe();
  while (!last?.ok && Date.now() < deadline) {
    await sleep(stepMs);
    last = await probe();
  }
  return last;
}

export function checker() {
  const t = { failures: 0, checks: 0 };
  t.check = (label, ok, detail = '') => {
    t.checks += 1;
    console.log(`${ok ? '✅' : '❌'} ${label}${detail ? ` — ${detail}` : ''}`);
    if (!ok) t.failures += 1;
    return ok;
  };
  return t;
}

async function failure(error) {
  if (typeof error?.json === 'function') {
    const body = await error.json().catch(() => ({}));
    return { status: error.status, message: body.message ?? body.error, code: body.code };
  }
  return { status: 0, message: String(error?.message ?? error) };
}

export async function player(nickname) {
  if (!KEY) throw new Error('NAKAMA_SERVER_KEY is not set');
  const client = new Client(KEY, HOST, PORT, false);
  const session = await client.authenticateDevice(`harness-${randomUUID()}`, true);
  const p = { client, session, nickname, inbox: [], socket: null };
  if (nickname) await client.updateAccount(session, { display_name: nickname });
  return p;
}

export async function attempt(promise) {
  try {
    return { ok: true, value: await promise };
  } catch (error) {
    return { ok: false, error: await failure(error) };
  }
}

export async function rpc(p, id, payload) {
  const result = await attempt(p.client.rpc(p.session, id, payload));
  if (result.ok) result.value = result.value.payload;
  return result;
}

const decoder = new TextDecoder();

export async function connect(p) {
  p.socket = p.client.createSocket(false, false);
  p.socket.onmatchdata = (md) => {
    const text = md.data?.length ? decoder.decode(md.data) : '{}';
    p.inbox.push({ op: md.op_code, data: JSON.parse(text), at: Date.now() });
  };
  p.closed = false;
  p.socket.ondisconnect = () => {
    p.closed = true;
  };
  await p.socket.connect(p.session, true);
  return p;
}

export async function join(p, matchId) {
  if (!p.socket) await connect(p);
  p.matchId = matchId;
  return attempt(p.socket.joinMatch(matchId));
}

export function send(p, op, message) {
  return p.socket.sendMatchState(p.matchId, op, JSON.stringify(message));
}

export async function waitFor(p, op, predicate = () => true, timeoutMs = 5000, from = 0) {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    for (let i = from; i < p.inbox.length; i += 1) {
      const entry = p.inbox[i];
      if (entry.op === op && predicate(entry.data)) return { ...entry.data, index: i };
    }
    if (Date.now() > deadline) return null;
    await sleep(20);
  }
}

export async function openRoom(nickname, settings = {}) {
  const host = await player(nickname);
  const created = await rpc(host, 'room_create', { settings });
  if (!created.ok) throw new Error(`room_create: ${JSON.stringify(created.error)}`);
  const joined = await join(host, created.value.match_id);
  if (!joined.ok) throw new Error(`join: ${JSON.stringify(joined.error)}`);
  return { host, code: created.value.code, matchId: created.value.match_id };
}

export async function arrive(nickname, code) {
  const guest = await player(nickname);
  const found = await eventually(() => rpc(guest, 'room_find', { code }));
  if (!found.ok) throw new Error(`room_find: ${JSON.stringify(found.error)}`);
  const joined = await join(guest, found.value.match_id);
  if (!joined.ok) throw new Error(`join: ${JSON.stringify(joined.error)}`);
  return guest;
}

export const list = (value) => (Array.isArray(value) ? value : []);

export function stream(p) {
  const ticks = p.inbox.filter((e) => e.op === OP.ticks).map((e) => e.data);
  const sums = p.inbox.filter((e) => e.op === OP.checksum).map((e) => e.data);
  const inputs = ticks.flatMap((t) => list(t.inputs));
  return { ticks, sums, inputs, last: ticks.length ? ticks[ticks.length - 1].to : 0 };
}

export const AIMING_TICK = 70;

export async function untilTick(p, tick, timeoutMs = 20000) {
  return waitFor(p, OP.ticks, (t) => t.to >= tick, timeoutMs);
}
