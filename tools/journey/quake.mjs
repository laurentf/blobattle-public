import { connect, newContext, openPage, pick, reporter, sleep, sling } from './lib.mjs';

const ORIGIN = process.env.JOURNEY_ORIGIN || 'http://127.0.0.1:5373';
const BASE = `${ORIGIN}/?test=1`;
const SEED = 4;
const QUAKES = 2;
const SHAKE_FRAMES = (31 / 30) * 60;
const t = reporter();
const browser = await connect();

const errorsOf = (s) => Object.keys(s?.errors || {});
const list = (value) => (Array.isArray(value) ? value : []);

async function player(nickname, team, url, cpu) {
  const context = await newContext(browser);
  const page = await openPage(browser, { url, context, cpu });
  const home = await page.waitFor((s) => s.screen === 'home' && s.profile && s.targets?.home?.nickname, 90000);
  if (home?.profile?.fresh) {
    await page.type('home', 'nickname', nickname);
    await page.type('home', 'team', team);
    await page.waitFor((s) => s.profile.nickname === nickname && s.profile.team_name === team, 5000);
  }
  await page.press('home', 'multi');
  await page.waitFor((s) => s.screen === 'multi' && s.targets?.multi?.create, 10000);
  return page;
}

t.section('tranche 24p — the forest quake online: the same quakes at the same ticks for both, the camera shakes, the cracks open on screen as in the sim, the dust flies (§5.3, §7.4)');
const fay = await player('Fay', 'Fault Line', `${BASE}&seed=${SEED}`, 1);
await fay.press('multi', 'create');
const room = await fay.waitFor((s) => s.screen === 'room' && s.room?.host === true && /^[A-HJ-NP-Z]{5}$/.test(s.room?.code ?? ''), 20000);
const code = room?.room?.code;
const gus = await player('Gus', 'Tremor Kids', BASE, 4);
await gus.type('multi', 'code', code ?? '');
await gus.press('multi', 'join');
await gus.waitFor((s) => s.screen === 'room' && s.room?.code === code, 20000);
for (const [button, times] of [['teams_minus', 2], ['cats_minus', 2], ['map_cycle', 1]]) {
  for (let i = 0; i < times; i += 1) {
    await fay.press('room', button);
    await sleep(250);
  }
}
const ready = await gus.waitFor((s) => s.room?.settings?.teams === 2 && s.room.settings.cats_per_team === 2 && s.room.settings.map === 'forest' && s.room.seats?.[1]?.team === 'Tremor Kids', 10000);
await fay.press('room', 'launch');
const started = await Promise.all([fay, gus].map((p) => p.waitFor((s) => s.screen === 'game' && s.game?.sim?.cats?.length === 4, 60000)));
t.check(
  'a forest game of two teams of two starts between two humans, on the seed the host asked for',
  ready !== null && started.every((s) => s && s.game.seed === SEED && s.game.biome === 'forest') && started[0].game.me === 1 && started[1].game.me === 2,
  JSON.stringify(started.map((s) => s && { seed: s.game.seed, biome: s.game.biome, me: s.game.me })),
);

const players = [fay, gus];
const seen = [new Map(), new Map()];
const played = { ahead: 0, samples: 0, punches: 0 };
const quaking = [[], []];
const dusty = [0, 0];
let states = [null, null];
const deadline = Date.now() + 8 * 60 * 1000;
const done = (s) => s && (s.screen === 'end' || (s.game?.quake?.quakes >= QUAKES && s.game.state !== 'quake' && list(s.game.quake.checks).length >= 2));
while (Date.now() < deadline && !states.every(done)) {
  for (let i = 0; i < 2; i += 1) {
    const s = await players[i].state();
    states[i] = s;
    for (const c of list(s?.game?.trace?.checkpoints)) seen[i].set(c.tick, c.sum);
    const g = s?.game;
    if (!g) continue;
    played.samples += 1;
    if (g.tick > g.confirmed) played.ahead += 1;
    if (g.state === 'quake') quaking[i].push(g.tick);
    dusty[i] = Math.max(dusty[i], g.quake?.dust_live ?? 0);
    if (g.team === g.me && g.state === 'aiming' && g.blob && s.targets?.hud?.weapon && !done(s)) {
      await pick(players[i], 'grid_4');
      await players[i].waitFor((st) => st.game?.weapon === 'uppercut' && !st.game.grid, 3000);
      await sleep(300);
      await sling(players[i], -60, 30);
      played.punches += 1;
      await players[i].waitFor((st) => st.screen === 'end' || (st.game && (st.game.team !== st.game.me || st.game.state !== 'aiming')), 8000);
    }
  }
  await sleep(150);
}
states = await Promise.all(players.map((p) => p.state()));
const [a, b] = states.map((s) => s?.game);
const counts = [a, b].map((g) => g?.trace?.counts ?? {});
const common = [...seen[0].keys()].filter((tick) => seen[1].has(tick));
const differ = common.filter((tick) => seen[0].get(tick) !== seen[1].get(tick));
t.check(
  'after the 8th round, both contexts go through the same quakes, shakes and cracks, at the same ticks',
  a && b && counts[0].quaked >= QUAKES && counts[0].shook >= 3 * QUAKES && counts[0].cracked >= 3 && ['quaked', 'shook', 'cracked'].every((k) => counts[0][k] === counts[1][k]) && common.length >= 20 && differ.length === 0 && quaking.every((ticks) => ticks.length > 0),
  JSON.stringify({ quaked: counts.map((c) => c.quaked), shook: counts.map((c) => c.shook), cracked: counts.map((c) => c.cracked), common: common.length, differ: differ.slice(0, 5), quaking: quaking.map((ticks) => ticks.slice(0, 3)), punches: played.punches }),
);
const peaks = [a, b].map((g) => list(g?.quake?.peaks));
t.check(
  'the camera shakes at each quake, harder at the second',
  peaks.every((p) => p.length >= QUAKES && p[0] > 0.3 && p[1] > p[0]),
  JSON.stringify(peaks),
);
const checks = [a, b].map((g) => list(g?.quake?.checks));
const opened = (list_) => list_.some((c) => c.width === 4) && list_.some((c) => c.width === 6);
const exact = (list_) => list_.length >= 2 && list_.every((c) => c.drawn === 0 && c.solid === 0 && c.edges > 0 && c.agree === c.edges);
t.check(
  'each crack opens on screen as in the sim: no voxel drawn where the sim opened it, its edges drawn exactly as the sim\'s cells, the first crack widened by the second quake',
  checks.every((list_) => exact(list_) && opened(list_)),
  JSON.stringify(checks),
);
t.check(
  'the dust flies from every crack that opens or widens: its cubes are seen in the air during the quakes',
  [a, b].every((g, i) => g && g.quake.dust >= 18 * counts[i].cracked && dusty[i] >= 18),
  JSON.stringify({ spawned: [a, b].map((g) => g?.quake?.dust), seen: dusty }),
);
const slow = b?.quake;
t.check(
  'at CPU ×4, the terrain of the cracks rebuilds in slices of 4 ms at most (p95), one per frame, in fewer frames than the shakes last at 60 per second',
  slow && slow.crack_ms?.n > 0 && slow.crack_ms.p95 < 4 && slow.crack_frames?.n >= 2 && slow.crack_frames.max < SHAKE_FRAMES,
  JSON.stringify({ crack_ms: slow?.crack_ms, crack_frames: slow?.crack_frames, crack_s: slow?.crack_s }),
);
console.log(`📏 crack rebuild at CPU ×4: slices ${JSON.stringify(slow?.crack_ms)}, frames ${JSON.stringify(slow?.crack_frames)}, whole in SwiftShader ${JSON.stringify(slow?.crack_s)}, a part ${slow?.part_ms?.toFixed?.(2)} ms, an upload ${slow?.upload_ms?.toFixed?.(2)} ms; at CPU ×1: ${JSON.stringify(a?.quake?.crack_s)}`);
await fay.shot('tmp/journey/quake.png');
t.check(
  'neither client went past the confirmed tick, nor diverged, and both checked their checksums',
  played.ahead === 0 && [a, b].every((g) => g && g.divergences === 0 && g.checked >= Math.floor(g.tick / 30) - 2 && g.tick <= g.confirmed),
  JSON.stringify({ ahead: played.ahead, games: [a, b].map((g) => g && { tick: g.tick, confirmed: g.confirmed, checked: g.checked, divergences: g.divergences }) }),
);
for (const [name, s] of [['Fay', states[0]], ['Gus', states[1]]]) {
  t.check(`no Lua error for ${name} through the quakes`, errorsOf(s).length === 0, JSON.stringify(s?.errors));
}

browser.ws.close();
process.exit(t.failed === 0 ? 0 : 1);
