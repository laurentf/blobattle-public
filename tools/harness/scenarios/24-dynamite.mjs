import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { AIMING_TICK, OP, list, openRoom, send, stream, untilTick, waitFor } from '../lib.mjs';

export const title = 'tranche 24s — the dynamite online: placed at the feet, a walk away while its fuse burns, it goes off 5 s later, a second one refused, every checksum replayed (§8.2, §5.6)';

const SEED = 7;
const FUSE = 150;
const TURN_START = 60;
const SPACING = 160;
const FP = 256;
const ROOT = new URL('../../..', import.meta.url).pathname;

const of = (p, op) => p.inbox.filter((e) => e.op === op).map((e) => e.data);

function replay(engine, file) {
  try {
    return { ok: true, out: execFileSync(engine, ['tools/harness/check.lua', file], { cwd: ROOT, encoding: 'utf8', timeout: 300000 }) };
  } catch (error) {
    return { ok: false, out: `${error.stdout ?? ''}${error.stderr ?? ''}` };
  }
}

async function snapshot(host) {
  const asked = host.inbox.length;
  await send(host, OP.snapshot_request, {});
  return (await waitFor(host, OP.snapshot, () => true, 5000, asked))?.state;
}

export async function run(t) {
  const { host } = await openRoom('Fuse Host');
  await send(host, OP.lobby_settings, { teams: 2, cats_per_team: 2, seed: SEED });
  await waitFor(host, OP.lobby_state, (s) => s.seed === SEED && s.seats?.length === 2);
  await send(host, OP.start, {});
  const started = await waitFor(host, OP.game_start, () => true, 10000);
  const before = await snapshot(host);
  const team = (started?.roster ?? []).find((r) => r.user === host.session.user_id)?.team;
  t.check('the human plays team 1, against a bot', team === 1 && started.roster[1].kind === 'bot', JSON.stringify(started?.roster?.map((r) => r.kind)));
  await untilTick(host, AIMING_TICK);

  const at = async (ticks) => untilTick(host, stream(host).last + ticks);
  const me = before?.cats?.[before.turn.cat - 1];
  const away = me && me.x < (before.terrain[0] * FP) / 2 ? 1 : -1;
  await send(host, OP.fire, { weapon: 'dynamite', angle: 0, power: 1 });
  await at(2);
  await send(host, OP.input, { kind: 'move', direction: away });
  await untilTick(host, (before?.tick ?? 0) + SPACING);
  const mid = await snapshot(host);
  await send(host, OP.input, { kind: 'move', direction: 0 });
  await at(FUSE);

  const refusedEarly = of(host, OP.refused);
  t.check('the placing and the walk during the retreat are accepted', refusedEarly.length === 0, JSON.stringify(refusedEarly));
  const mine = list(stream(host).inputs).filter((e) => e.input.team === team);
  const kinds = mine.map((e) => e.input.kind).join(',');
  const placed = mine[0]?.at;
  t.check('they reach the stream as regular inputs, the dynamite as a fire', kinds === 'fire,move,move' && mine[0].input.weapon === 'dynamite', kinds);
  const stick = list(mid?.projectiles).find((p) => p.weapon === 'dynamite');
  const walker = mid?.cats?.[before?.turn?.cat - 1];
  t.check(
    'a snapshot mid-fuse shows the dynamite resting where the blob stood, its fuse burning, the turn in its retreat counting the same fuse down, and the blob walked away from it',
    stick !== undefined && stick.resting === true && stick.vx === 0 && Math.abs(stick.x - me.x) <= FP && stick.fuse === FUSE - (mid.tick - placed) && mid.turn.state === 'retreat' && mid.turn.timer === stick.fuse && Math.abs(walker.x - stick.x) >= 20 * FP,
    JSON.stringify({ stick, placed, tick: mid?.tick, turn: mid?.turn, from: me?.x, walker: walker && { x: walker.x, hp: walker.hp } }),
  );
  let back = null;
  for (let i = 0; i < 12 && !back; i += 1) {
    await at(SPACING);
    const s = await snapshot(host);
    if (s?.turn?.team === team && s.turn.state === 'aiming') back = s;
  }
  const bot = list(stream(host).inputs).find((e) => e.input.team !== team && e.at > placed);
  t.check('the bot plays only once the fuse has burnt: its first input comes after the 5 s of the fuse and the 2 s start of its turn', bot !== undefined && bot.at - placed >= FUSE + TURN_START, JSON.stringify({ placed, bot }));
  const refusals = of(host, OP.refused).length;
  const mark = host.inbox.length;
  await send(host, OP.fire, { weapon: 'dynamite', angle: 0, power: 1 });
  const second = await waitFor(host, OP.refused, () => true, 3000, mark);
  t.check(
    'on its next turn, the team has no dynamite left: a second one is refused, not spent',
    back !== null && back.teams[team - 1].ammo[5] === 0 && second?.code === 'no_ammo' && of(host, OP.refused).length === refusals + 1,
    JSON.stringify({ ammo: back?.teams?.[team - 1]?.ammo, second }),
  );
  await send(host, OP.skip, {});
  await at(30);

  const recording = {
    game_start: of(host, OP.game_start)[0],
    game_end: of(host, OP.game_end)[0],
    ticks: of(host, OP.ticks).map((m) => ({ to: m.to, inputs: list(m.inputs) })),
    checksums: of(host, OP.checksum),
    snapshots: of(host, OP.snapshot),
  };
  mkdirSync(`${ROOT}tmp/harness`, { recursive: true });
  const file = 'tmp/harness/dynamite.json';
  writeFileSync(`${ROOT}${file}`, JSON.stringify(recording));
  const taken = recording.snapshots.length;
  for (const engine of ['luajit', 'lua5.1']) {
    const result = replay(engine, file);
    t.check(`every checksum received is found again by the ${engine} replay, the ${taken} snapshots included, the one mid-fuse among them`, result.ok && taken >= 3 && new RegExp(` ${taken} snapshots`).test(result.out), result.out.trim().split('\n').slice(-3).join(' | '));
  }

  host.socket.disconnect(false);
}
