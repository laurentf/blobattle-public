import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { OP, list, openRoom, send, sleep, waitFor } from '../lib.mjs';

export const title = 'tranche 24h — the volcano online: the lava rises 2 px at the end of every round, every checksum replayed (§5.3, §5.9)';

const SEED = 7;
const START = 256 - 24;
const RISE = 2;
const FROM = 1;
const ROOT = new URL('../../..', import.meta.url).pathname;

const of = (p, op) => p.inbox.filter((e) => e.op === op).map((e) => e.data);

function replay(engine, file) {
  try {
    return { ok: true, out: execFileSync(engine, ['tools/harness/check.lua', file], { cwd: ROOT, encoding: 'utf8', timeout: 300000 }) };
  } catch (error) {
    return { ok: false, out: `${error.stdout ?? ''}${error.stderr ?? ''}` };
  }
}

export async function run(t) {
  const { host } = await openRoom('Lava Host');
  await send(host, OP.lobby_settings, { teams: 2, cats_per_team: 2, bot_level: 'easy', map: 'volcano', seed: SEED });
  await waitFor(host, OP.lobby_state, (s) => s.seed === SEED && s.settings?.map === 'volcano');
  await send(host, OP.start, {});
  const started = await waitFor(host, OP.game_start, () => true, 10000);
  t.check('a volcano game starts, a human against a bot', started?.settings?.map === 'volcano' && started.roster?.some((r) => r.kind === 'bot'), JSON.stringify(started?.settings));

  const stop = { done: false };
  const skipping = (async () => {
    while (!stop.done) {
      await send(host, OP.skip, {});
      await sleep(250);
    }
  })();
  let risen = null;
  const early = [];
  const deadline = Date.now() + 5 * 60 * 1000;
  while (Date.now() < deadline && risen === null) {
    await sleep(4000);
    const asked = host.inbox.length;
    await send(host, OP.snapshot_request, {});
    const snapshot = await waitFor(host, OP.snapshot, () => true, 5000, asked);
    const state = snapshot?.state;
    if (!state) continue;
    if (state.rounds < FROM) early.push({ rounds: state.rounds, level: state.liquid.level });
    if (state.rounds >= FROM + 1) risen = state;
  }
  stop.done = true;
  await skipping;

  t.check(
    'before the first round ends, the lava stays where it was',
    early.length > 0 && early.every((s) => s.level === START),
    JSON.stringify(early),
  );
  t.check(
    'from the first round on, it has risen 2 px at the end of each round, in a snapshot at version 11',
    risen !== null && risen.version === 11 && risen.rounds === Math.min(...risen.teams.map((team) => team.turns)) && risen.liquid.level === START - RISE * (risen.rounds - FROM + 1) && risen.liquid.kind === 'lava',
    JSON.stringify(risen && { version: risen.version, rounds: risen.rounds, turns: risen.teams.map((team) => team.turns), level: risen.liquid.level }),
  );

  const recording = {
    game_start: of(host, OP.game_start)[0],
    ticks: of(host, OP.ticks).map((m) => ({ to: m.to, inputs: list(m.inputs) })),
    checksums: of(host, OP.checksum),
    snapshots: of(host, OP.snapshot),
    game_end: of(host, OP.game_end)[0],
  };
  mkdirSync(`${ROOT}tmp/harness`, { recursive: true });
  const file = 'tmp/harness/lava.json';
  writeFileSync(`${ROOT}${file}`, JSON.stringify(recording));
  for (const engine of ['luajit', 'lua5.1']) {
    const result = replay(engine, file);
    t.check(`every checksum received is found again by the ${engine} replay, the rising lava included`, result.ok, result.out.trim().split('\n').slice(-3).join(' | '));
  }

  host.socket.disconnect(false);
}
