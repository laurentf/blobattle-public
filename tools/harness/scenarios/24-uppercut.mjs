import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { AIMING_TICK, OP, list, openRoom, send, stream, untilTick, waitFor } from '../lib.mjs';

export const title = 'tranche 24e — the uppercut online: a walk, a punch, the blob in front sent flying, every checksum replayed (§8.2, §6.4)';

const SEED = 148;
const WALK_TICKS = 44;
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
  const { host } = await openRoom('Punch Host');
  await send(host, OP.lobby_settings, { teams: 2, cats_per_team: 4, seed: SEED });
  await waitFor(host, OP.lobby_state, (s) => s.seed === SEED && s.seats?.length === 2);
  await send(host, OP.start, {});
  const started = await waitFor(host, OP.game_start, () => true, 10000);
  const team = (started?.roster ?? []).find((r) => r.user === host.session.user_id)?.team;
  t.check('the human plays team 1, against a bot', team === 1 && started.roster[1].kind === 'bot', JSON.stringify(started?.roster?.map((r) => r.kind)));
  await untilTick(host, AIMING_TICK);

  const at = async (ticks) => untilTick(host, stream(host).last + ticks);
  await send(host, OP.input, { kind: 'move', direction: 1 });
  await at(WALK_TICKS);
  await send(host, OP.input, { kind: 'move', direction: 0 });
  await send(host, OP.fire, { weapon: 'uppercut', angle: 0, power: 1 });
  await at(12);
  const asked = host.inbox.length;
  await send(host, OP.snapshot_request, {});
  const snapshot = await waitFor(host, OP.snapshot, () => true, 5000, asked);
  await at(480);

  const refused = of(host, OP.refused);
  t.check('the walk and the punch are accepted', refused.length === 0, JSON.stringify(refused));
  const mine = list(stream(host).inputs).filter((e) => e.input.team === team).map((e) => e.input);
  const kinds = mine.map((i) => i.kind).join(',');
  t.check('they reach the stream as regular inputs, the uppercut as a fire', kinds === 'move,move,fire' && mine[2].weapon === 'uppercut', kinds);
  const cats = snapshot?.state?.cats ?? [];
  const hit = cats.find((c) => c.team !== team && c.hp === 70);
  t.check(
    'a snapshot just after the punch shows a bot blob 30 HP down and flying up and forward',
    hit !== undefined && hit.vy < 0 && hit.vx > 0 && hit.grounded === false && cats.filter((c) => c.hp < 100).length === 1,
    JSON.stringify(cats.map((c) => ({ team: c.team, hp: c.hp, vx: c.vx, vy: c.vy }))),
  );
  const all = list(stream(host).inputs).map((e) => e.input);
  const punched = all.findIndex((i) => i.team === team && i.kind === 'fire');
  const after = all.slice(punched + 1);
  t.check('the punch ends the turn by itself: the bot plays next, the human sends nothing more', punched >= 0 && after.some((i) => i.team !== team && i.kind === 'fire') && after.every((i) => i.team !== team), JSON.stringify(after));

  const recording = {
    game_start: of(host, OP.game_start)[0],
    game_end: of(host, OP.game_end)[0],
    ticks: of(host, OP.ticks).map((m) => ({ to: m.to, inputs: list(m.inputs) })),
    checksums: of(host, OP.checksum),
    snapshots: of(host, OP.snapshot),
  };
  mkdirSync(`${ROOT}tmp/harness`, { recursive: true });
  const file = 'tmp/harness/uppercut.json';
  writeFileSync(`${ROOT}${file}`, JSON.stringify(recording));
  for (const engine of ['luajit', 'lua5.1']) {
    const result = replay(engine, file);
    t.check(`every checksum received is found again by the ${engine} replay, the snapshot after the punch included`, result.ok && / 1 snapshots/.test(result.out), result.out.trim().split('\n').slice(-3).join(' | '));
  }

  host.socket.disconnect(false);
}
