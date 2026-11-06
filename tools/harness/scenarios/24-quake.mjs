import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { OP, arrive, list, openRoom, send, sleep, stream, untilTick, waitFor } from '../lib.mjs';

export const title = 'tranche 24o — the forest quake online: from the 8th round, shakes and cracks, snapshots mid-quake, every checksum replayed (§5.3, §5.9)';

const SEED = 2;
const FROM = 8;
const ROOT = new URL('../../..', import.meta.url).pathname;

const of = (p, op) => p.inbox.filter((e) => e.op === op).map((e) => e.data);

function replay(engine, file) {
  try {
    return { ok: true, out: execFileSync(engine, ['tools/harness/check.lua', file], { cwd: ROOT, encoding: 'utf8', timeout: 300000 }) };
  } catch (error) {
    return { ok: false, out: `${error.stdout ?? ''}${error.stderr ?? ''}` };
  }
}

const summary = (state) =>
  state && {
    version: state.version,
    state: state.turn?.state,
    ticks: state.turn?.ticks,
    rounds: state.rounds,
    cracks: list(state.cracks).map((c) => [c.x, c.width, c.top, list(c.path).length]),
    wells: list(state.wells).map((w) => [w.x, w.width]),
  };

export async function run(t) {
  const { host, code } = await openRoom('Quake Host');
  const guest = await arrive('Quake Guest', code);
  await send(host, OP.lobby_settings, { teams: 2, cats_per_team: 2, map: 'forest', seed: SEED });
  await waitFor(host, OP.lobby_state, (s) => s.seed === SEED && s.settings?.map === 'forest' && list(s.seats).every((seat) => seat.user));
  await send(host, OP.start, {});
  const started = await waitFor(host, OP.game_start, () => true, 10000);
  t.check(
    'a forest game starts between two humans',
    started?.settings?.map === 'forest' && list(started.roster).every((r) => r.kind === 'human'),
    JSON.stringify(started?.roster?.map((r) => r.kind)),
  );

  const skips = () => list(stream(host).inputs).filter((e) => e.input.kind === 'skip').length;
  const skipUntil = async (count) => {
    const deadline = Date.now() + 3 * 60 * 1000;
    while (skips() < count && Date.now() < deadline) {
      await send(host, OP.skip, {});
      await send(guest, OP.skip, {});
      await sleep(200);
    }
    return skips();
  };
  const snapshotOf = async (p) => {
    const asked = p.inbox.length;
    await send(p, OP.snapshot_request, {});
    return (await waitFor(p, OP.snapshot, () => true, 5000, asked))?.state ?? null;
  };

  const before = await skipUntil(2 * (FROM - 1));
  const calm = await snapshotOf(guest);
  t.check(
    'after 7 rounds, no quake yet: no crack, the generated wells in the state',
    before === 2 * (FROM - 1) && calm?.version === 11 && calm.rounds === FROM - 1 && list(calm.cracks).length === 0 && list(calm.wells).length >= 1,
    JSON.stringify(summary(calm)),
  );

  await skipUntil(2 * FROM);
  const first = await snapshotOf(host);
  t.check(
    'the 8th round over, a snapshot mid-quake shows its first crack, 4 px wide, from the surface down',
    first?.turn?.state === 'quake' && first.rounds === FROM && list(first.cracks).length === 1 && first.cracks[0].width === 4 && first.cracks[0].path?.[0] === 0,
    JSON.stringify(summary(first)),
  );

  await sleep(5200);
  await skipUntil(2 * FROM + 2);
  const second = await snapshotOf(host);
  const widened = list(second?.cracks)[0];
  t.check(
    'the 9th round over, the next quake has widened the first crack by 2 px and opened another',
    second?.turn?.state === 'quake' && second.rounds === FROM + 1 && list(second.cracks).length === 2 && widened?.width === 6 && widened.x === first?.cracks?.[0]?.x - 1,
    JSON.stringify(summary(second)),
  );

  await skipUntil(2 * FROM + 4);
  await untilTick(host, stream(host).last + 120);

  const refused = [...new Set(of(host, OP.refused).concat(of(guest, OP.refused)).map((r) => r.code))];
  t.check('the skips are only ever refused as not your turn, or not now while the ground shakes', refused.every((code) => code === 'not_your_turn' || code === 'not_now'), JSON.stringify(refused));

  const recording = {
    game_start: of(host, OP.game_start)[0],
    ticks: of(host, OP.ticks).map((m) => ({ to: m.to, inputs: list(m.inputs) })),
    checksums: of(host, OP.checksum),
    snapshots: of(host, OP.snapshot),
    game_end: of(host, OP.game_end)[0],
  };
  mkdirSync(`${ROOT}tmp/harness`, { recursive: true });
  const file = 'tmp/harness/quake.json';
  writeFileSync(`${ROOT}${file}`, JSON.stringify(recording));
  for (const engine of ['luajit', 'lua5.1']) {
    const result = replay(engine, file);
    t.check(`every checksum received is found again by the ${engine} replay, three quakes and two snapshots mid-quake included`, result.ok, result.out.trim().split('\n').slice(-3).join(' | '));
  }

  host.socket.disconnect(false);
  guest.socket.disconnect(false);
}
