import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { OP, arrive, list, openRoom, send, sleep, waitFor } from '../lib.mjs';

export const title = 'tranche 18 — a complete game, 2 simulated humans + 2 bots, every checksum replayed in Lua (§10.3)';

const SEED = 4;
const ROOT = new URL('../../..', import.meta.url).pathname;

function accepted(p, team, kind, from) {
  const messages = p.inbox.filter((e) => e.op === OP.ticks);
  for (let i = from; i < messages.length; i += 1) {
    if (list(messages[i].data.inputs).some((e) => e.input.team === team && e.input.kind === kind)) return true;
  }
  return false;
}

async function play(p, team, direction, stop) {
  const plan = [
    { kind: 'move', op: OP.input, message: { kind: 'move', direction } },
    { kind: 'jump', op: OP.input, message: { kind: 'jump', direction } },
    { kind: 'fire', op: OP.fire, message: { weapon: 'grenade', angle: 256, power: 1, fuse: 1 } },
  ];
  let step = 0;
  while (!stop.done) {
    const { kind, op, message } = plan[step];
    const from = p.inbox.filter((e) => e.op === OP.ticks).length;
    await send(p, op, message);
    await sleep(250);
    if (accepted(p, team, kind, from)) step = (step + 1) % plan.length;
  }
}

const of = (p, op) => p.inbox.filter((e) => e.op === op).map((e) => e.data);

function recording(p) {
  return {
    game_start: of(p, OP.game_start)[0],
    ticks: of(p, OP.ticks).map((m) => ({ to: m.to, inputs: list(m.inputs) })),
    checksums: of(p, OP.checksum),
    snapshots: of(p, OP.snapshot),
    game_end: of(p, OP.game_end)[0],
  };
}

function replay(engine, file) {
  try {
    return { ok: true, out: execFileSync(engine, ['tools/harness/check.lua', file], { cwd: ROOT, encoding: 'utf8', timeout: 300000 }) };
  } catch (error) {
    return { ok: false, out: `${error.stdout ?? ''}${error.stderr ?? ''}` };
  }
}

export async function run(t) {
  const { host, code } = await openRoom('Full Host');
  const guest = await arrive('Full Guest', code);
  await send(host, OP.lobby_settings, { teams: 4, cats_per_team: 1, bot_level: 'hard', seed: SEED });
  await waitFor(guest, OP.lobby_state, (s) => s.seats?.length === 4 && s.seed === SEED);
  await send(host, OP.start, {});
  const started = await waitFor(host, OP.game_start, () => true, 10000);
  const kinds = (started?.roster ?? []).map((r) => r.kind).join(',');
  t.check('the game starts with 2 humans and 2 bots', kinds === 'human,human,bot,bot', kinds);

  const began = Date.now();
  const stop = { done: false };
  const teamOf = Object.fromEntries((started?.roster ?? []).map((r) => [r.user, r.team]));
  const humans = [
    play(host, teamOf[host.session.user_id], 1, stop),
    play(guest, teamOf[guest.session.user_id], -1, stop),
  ];
  const ended = await waitFor(host, OP.game_end, () => true, 12 * 60 * 1000);
  stop.done = true;
  await Promise.all(humans);
  await waitFor(guest, OP.game_end, () => true, 5000);
  const minutes = ((Date.now() - began) / 60000).toFixed(1);
  t.check('the game is played to its end', ended !== null, `winner ${ended?.winner} after ${minutes} min`);

  const mine = recording(host);
  const theirs = recording(guest);
  t.check(
    'both humans received the same stream',
    mine.ticks.length > 0 && JSON.stringify(mine.ticks) === JSON.stringify(theirs.ticks) && JSON.stringify(mine.checksums) === JSON.stringify(theirs.checksums),
    `${mine.ticks.length} ticks messages, ${mine.checksums.length} checksums`,
  );
  const inputs = mine.ticks.flatMap((m) => m.inputs);
  const humanTeams = new Set((started?.roster ?? []).filter((r) => r.kind === 'human').map((r) => r.team));
  for (const team of humanTeams) {
    const kinds = new Set(inputs.filter((e) => e.input.team === team).map((e) => e.input.kind));
    t.check(`human team ${team} moved, jumped and fired through the regular path`, ['move', 'jump', 'fire'].every((k) => kinds.has(k)), [...kinds].join(','));
  }
  const byBots = inputs.filter((e) => !humanTeams.has(e.input.team) && e.input.kind === 'fire');
  t.check('the bots fired through the same stream', byBots.length >= 2, `${byBots.length} bot shots`);

  mkdirSync(`${ROOT}tmp/harness`, { recursive: true });
  const file = 'tmp/harness/full-game.json';
  writeFileSync(`${ROOT}${file}`, JSON.stringify(mine));
  for (const engine of ['luajit', 'lua5.1']) {
    const result = replay(engine, file);
    t.check(`every checksum received is found again by the ${engine} replay`, result.ok, result.out.trim().split('\n').slice(-3).join(' | '));
  }

  host.socket.disconnect(false);
  guest.socket.disconnect(false);
}
