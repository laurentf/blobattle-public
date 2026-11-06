import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { OP, list, openRoom, send, sleep, waitFor } from '../lib.mjs';

export const title = 'H-07 — 4 simultaneous games of 8 teams × 6 cats hold 30 Hz on the host (§3)';

const ROOMS = 4;
const WINDOW_MS = 60000;
const ROOT = new URL('../../..', import.meta.url).pathname;

const of = (p, op) => p.inbox.filter((e) => e.op === op);
const lastTo = (p) => {
  const ticks = of(p, OP.ticks);
  return ticks.length ? ticks[ticks.length - 1].data.to : 0;
};

export async function run(t) {
  const hosts = [];
  for (let i = 0; i < ROOMS; i += 1) {
    const { host } = await openRoom(`Load Host ${i + 1}`);
    await send(host, OP.lobby_settings, { teams: 8, cats_per_team: 6, bot_level: 'hard', seed: 4242 + i });
    await waitFor(host, OP.lobby_state, (s) => s.seats?.length === 8 && s.seed === 4242 + i);
    hosts.push(host);
  }
  await Promise.all(hosts.map((h) => send(h, OP.start, {})));
  const started = await Promise.all(hosts.map((h) => waitFor(h, OP.game_start, () => true, 15000)));
  t.check('4 games of 8 teams × 6 cats start at once', started.every((s) => s?.roster?.length === 8));

  const stop = { done: false };
  const skipping = hosts.map(async (h) => {
    while (!stop.done) {
      await send(h, OP.skip, {});
      await sleep(400);
    }
  });
  await sleep(5000);
  const begin = hosts.map((h) => ({ at: Date.now(), to: lastTo(h), index: of(h, OP.ticks).length }));
  await sleep(WINDOW_MS);
  const end = hosts.map((h) => ({ at: Date.now(), to: lastTo(h) }));
  stop.done = true;
  await Promise.all(skipping);

  const rates = hosts.map((_, i) => (end[i].to - begin[i].to) / ((end[i].at - begin[i].at) / 1000));
  const gaps = hosts.map((h, i) => {
    const arrivals = of(h, OP.ticks).slice(begin[i].index).map((e) => e.at);
    let worst = 0;
    for (let k = 1; k < arrivals.length; k += 1) worst = Math.max(worst, arrivals[k] - arrivals[k - 1]);
    return worst;
  });
  t.check(
    'each game advances at 30 ticks per second, within 5 %, never stalling a quarter second',
    rates.every((r) => r >= 28.5 && r <= 31.5) && gaps.every((g) => g < 250),
    `${rates.map((r) => r.toFixed(2)).join(' / ')} ticks/s, worst gap between two ticks messages ${gaps.join(' / ')} ms`,
  );

  const asked = hosts[0].inbox.length;
  await send(hosts[0], OP.snapshot_request, {});
  const snapshot = await waitFor(hosts[0], OP.snapshot, () => true, 5000, asked);
  const bytes = JSON.stringify(snapshot ?? {}).length;
  t.check('a snapshot of an 8 × 6 game crosses Nakama in one message (H-06), checked by the replay below', snapshot !== null && bytes > 8000, `${bytes} bytes at tick ${snapshot?.tick}`);
  await sleep(500);

  mkdirSync(`${ROOT}tmp/harness`, { recursive: true });
  for (let i = 0; i < ROOMS; i += 1) {
    const h = hosts[i];
    const file = `tmp/harness/load-${i + 1}.json`;
    const checksums = of(h, OP.checksum).map((e) => e.data);
    const cut = checksums.length > 0 ? checksums[checksums.length - 1].tick : 0;
    writeFileSync(
      `${ROOT}${file}`,
      JSON.stringify({
        game_start: of(h, OP.game_start)[0].data,
        ticks: of(h, OP.ticks).filter((e) => e.data.to <= cut).map((e) => ({ to: e.data.to, inputs: list(e.data.inputs) })),
        checksums,
        snapshots: of(h, OP.snapshot).map((e) => e.data).filter((s) => s.tick < cut),
      }),
    );
    let result;
    try {
      result = { ok: true, out: execFileSync('luajit', ['tools/harness/check.lua', file], { cwd: ROOT, encoding: 'utf8', timeout: 300000 }) };
    } catch (error) {
      result = { ok: false, out: `${error.stdout ?? ''}${error.stderr ?? ''}` };
    }
    t.check(`game ${i + 1}: every checksum received under load is found again by the replay`, result.ok, result.out.trim().split('\n').pop());
  }
  hosts.forEach((h) => h.socket.disconnect(false));
}
