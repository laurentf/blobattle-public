import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { AIMING_TICK, OP, list, openRoom, send, stream, untilTick, waitFor } from '../lib.mjs';

export const title = 'tranche 24b — the tentacle online: thrown, climbed, swung, let go, every checksum replayed (§5.4, §6.4, §6.8)';

const SEED = 244;
const ANGLE = 176;
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
  const { host } = await openRoom('Rope Host');
  await send(host, OP.lobby_settings, { teams: 2, cats_per_team: 1, seed: SEED });
  await waitFor(host, OP.lobby_state, (s) => s.seed === SEED && s.seats?.length === 2);
  await send(host, OP.start, {});
  const started = await waitFor(host, OP.game_start, () => true, 10000);
  const team = (started?.roster ?? []).find((r) => r.user === host.session.user_id)?.team;
  t.check('the human plays team 1, against a bot', team === 1 && started.roster[1].kind === 'bot', JSON.stringify(started?.roster?.map((r) => r.kind)));
  await untilTick(host, AIMING_TICK);

  const at = async (ticks) => untilTick(host, stream(host).last + ticks);
  await send(host, OP.fire, { weapon: 'tentacle', angle: ANGLE, power: 1 });
  await send(host, OP.input, { kind: 'climb', direction: -1 });
  await at(24);
  await send(host, OP.input, { kind: 'climb', direction: 0 });
  await send(host, OP.input, { kind: 'move', direction: -1 });
  await at(20);
  const asked = host.inbox.length;
  await send(host, OP.snapshot_request, {});
  const snapshot = await waitFor(host, OP.snapshot, () => true, 5000, asked);
  await at(20);
  await send(host, OP.input, { kind: 'move', direction: 0 });
  await send(host, OP.input, { kind: 'jump', direction: 1 });
  await at(60);
  await send(host, OP.skip, {});
  await at(240);

  const refused = of(host, OP.refused);
  t.check('the throw, the climb, the swing and the release are all accepted', refused.length === 0, JSON.stringify(refused));
  const mine = list(stream(host).inputs).filter((e) => e.input.team === team).map((e) => e.input);
  const kinds = mine.map((i) => i.kind).join(',');
  const thrown = mine.find((i) => i.kind === 'fire');
  t.check(
    'they reach the stream as regular inputs, the tentacle as a fire',
    kinds === 'fire,climb,climb,move,move,jump,skip' && thrown.weapon === 'tentacle' && thrown.angle === ANGLE,
    kinds,
  );
  const hanging = snapshot?.state?.cats?.find((c) => c.team === team);
  t.check(
    'a snapshot taken on the rope carries the tentacle',
    hanging?.hanging === true && hanging.rope >= 4 * 256 && hanging.anchor_y > 0 && snapshot.state.version === 11,
    JSON.stringify(hanging && { hanging: hanging.hanging, anchor: [hanging.anchor_x, hanging.anchor_y], rope: hanging.rope, climb: hanging.climb }),
  );

  const recording = {
    game_start: of(host, OP.game_start)[0],
    game_end: of(host, OP.game_end)[0],
    ticks: of(host, OP.ticks).map((m) => ({ to: m.to, inputs: list(m.inputs) })),
    checksums: of(host, OP.checksum),
    snapshots: of(host, OP.snapshot),
  };
  mkdirSync(`${ROOT}tmp/harness`, { recursive: true });
  const file = 'tmp/harness/tentacle.json';
  writeFileSync(`${ROOT}${file}`, JSON.stringify(recording));
  for (const engine of ['luajit', 'lua5.1']) {
    const result = replay(engine, file);
    t.check(`every checksum received is found again by the ${engine} replay, the snapshot on the rope included`, result.ok && / 1 snapshots/.test(result.out), result.out.trim().split('\n').slice(-3).join(' | '));
  }

  host.socket.disconnect(false);
}
