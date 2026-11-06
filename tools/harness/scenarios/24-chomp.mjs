import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { AIMING_TICK, OP, list, openRoom, send, stream, untilTick, waitFor } from '../lib.mjs';

export const title = 'tranche 24f — the Chomp online: a meal down into the ground, a snapshot mid-meal, every checksum replayed (§8.2, §6.4)';

const SEED = 244;
const DOWN = 768;
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
  const { host } = await openRoom('Chomp Host');
  await send(host, OP.lobby_settings, { teams: 2, cats_per_team: 1, seed: SEED });
  await waitFor(host, OP.lobby_state, (s) => s.seed === SEED && s.seats?.length === 2);
  await send(host, OP.start, {});
  const started = await waitFor(host, OP.game_start, () => true, 10000);
  const team = (started?.roster ?? []).find((r) => r.user === host.session.user_id)?.team;
  t.check('the human plays team 1, against a bot', team === 1 && started.roster[1].kind === 'bot', JSON.stringify(started?.roster?.map((r) => r.kind)));
  await untilTick(host, AIMING_TICK);

  const at = async (ticks) => untilTick(host, stream(host).last + ticks);
  await send(host, OP.fire, { weapon: 'chomp', angle: DOWN, power: 1 });
  await at(20);
  const asked = host.inbox.length;
  await send(host, OP.snapshot_request, {});
  const snapshot = await waitFor(host, OP.snapshot, () => true, 5000, asked);
  await at(480);

  const refused = of(host, OP.refused);
  t.check('the Chomp is accepted', refused.length === 0, JSON.stringify(refused));
  const all = list(stream(host).inputs).map((e) => e.input);
  const mine = all.filter((i) => i.team === team);
  t.check('it reaches the stream as a regular fire', mine.length === 1 && mine[0].kind === 'fire' && mine[0].weapon === 'chomp' && mine[0].angle === DOWN, JSON.stringify(mine));
  const eater = snapshot?.state?.cats?.find((c) => c.team === team);
  t.check(
    'a snapshot taken mid-meal carries it, at version 11',
    snapshot?.state?.version === 11 && eater?.dig > 0 && eater.dig < 60 && eater.dig_angle === DOWN && snapshot.state.turn.state === 'flight',
    JSON.stringify(eater && { dig: eater.dig, dig_angle: eater.dig_angle, y: eater.y, state: snapshot.state.turn.state }),
  );
  t.check('the meal ends the turn by itself: the bot plays next', all.some((i) => i.team !== team && i.kind === 'fire'), JSON.stringify(all));

  const recording = {
    game_start: of(host, OP.game_start)[0],
    game_end: of(host, OP.game_end)[0],
    ticks: of(host, OP.ticks).map((m) => ({ to: m.to, inputs: list(m.inputs) })),
    checksums: of(host, OP.checksum),
    snapshots: of(host, OP.snapshot),
  };
  mkdirSync(`${ROOT}tmp/harness`, { recursive: true });
  const file = 'tmp/harness/chomp.json';
  writeFileSync(`${ROOT}${file}`, JSON.stringify(recording));
  for (const engine of ['luajit', 'lua5.1']) {
    const result = replay(engine, file);
    t.check(`every checksum received is found again by the ${engine} replay, the snapshot mid-meal included`, result.ok && / 1 snapshots/.test(result.out), result.out.trim().split('\n').slice(-3).join(' | '));
  }

  host.socket.disconnect(false);
}
