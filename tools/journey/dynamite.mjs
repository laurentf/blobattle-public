import { connect, css, openPage, reporter, sleep, steady } from './lib.mjs';

const BASE = 'http://127.0.0.1:5373/?test=1';
const SEED = 376;
const RED = [0.86, 0.14, 0.12];
const t = reporter();
const browser = await connect();

const errorsOf = (s) => Object.keys(s?.errors || {});
const activeCat = (s) => s?.game?.sim?.cats?.[s.game.sim.cat - 1];
const stickOf = (s) => Object.values(s?.game?.shots ?? {}).find((shot) => shot.weapon === 'dynamite');

function redShape(image, at) {
  const [cx, cy] = [Math.round(at.x), Math.round(image.height - at.y)];
  let count = 0;
  let [x0, y0, x1, y1] = [Infinity, Infinity, -Infinity, -Infinity];
  for (let y = Math.max(0, cy - 90); y < Math.min(image.height, cy + 90); y += 1) {
    for (let x = Math.max(0, cx - 60); x < Math.min(image.width, cx + 60); x += 1) {
      const o = (y * image.width + x) * 4;
      const [r, g, b] = [image.pixels[o], image.pixels[o + 1], image.pixels[o + 2]];
      if (r > 120 && r > 3 * g && r > 3 * b) {
        count += 1;
        [x0, y0, x1, y1] = [Math.min(x0, x), Math.min(y0, y), Math.max(x1, x), Math.max(y1, y)];
      }
    }
  }
  return { count, w: count ? x1 - x0 + 1 : 0, h: count ? y1 - y0 + 1 : 0 };
}

async function launch(page) {
  const home = await page.waitFor((s) => s.screen === 'home' && s.profile && s.targets?.home?.nickname, 90000);
  if (home?.profile?.fresh) {
    await page.type('home', 'nickname', 'Fuse');
    await page.type('home', 'team', 'Blasters');
    await page.waitFor((s) => s.profile.nickname === 'Fuse', 5000);
  }
  await page.press('home', 'training');
  await page.waitFor((s) => s.screen === 'training' && s.targets?.training, 10000);
  for (let i = 0; i < 2; i += 1) await page.press('training', 'teams_minus');
  await page.press('training', 'map_cycle');
  await page.press('training', 'launch');
  await page.waitFor((s) => s.screen === 'game' && s.game, 30000);
  return page.waitFor((s) => s.game && s.game.team === s.game.me && s.game.state === 'aiming' && s.game.blob && s.targets?.hud?.weapon, 120000);
}

t.section('tranche 24t — the dynamite: the sixth cell of the grid, placed at the feet, a red stick whose fuse sparks, a walk away while the clock counts its 5 s, then the blast (§8.2, §7.3, §7.4)');
const page = await openPage(browser, { url: `${BASE}&seed=${SEED}`, cpu: 4 });
const aiming = await launch(page);
await page.press('hud', 'weapon');
const grid = await page.waitFor((s) => s.game.grid && s.targets.hud.grid_6, 5000);
await sleep(300);
const labels = (await page.state()).game.hud.shown.weapon_labels ?? {};
await page.shot('tmp/journey/grid-6.png');
await page.press('hud', 'grid_6');
const picked = await page.waitFor((s) => s.game.weapon === 'dynamite' && !s.game.grid, 5000);
t.check(
  'the grid shows six cells, the sixth reads "Dynamite x1" and fits its cell, and picks the dynamite (tmp/journey/grid-6.png)',
  aiming !== null && grid !== null && labels.grid_6?.text === 'Dynamite x1' && labels.grid_6.fits && picked !== null,
  JSON.stringify({ grid_6: labels.grid_6, picked: picked?.game?.weapon }),
);

const start = activeCat(await page.state());
const away = start && start.x < (await page.state()).game.width / 2 ? 'right' : 'left';
await steady(page);
const from = await css(page, (await page.state()).game.blob);
await page.touch('touchStart', [from]);
for (let i = 1; i <= 10; i += 1) {
  await sleep(30);
  await page.touch('touchMove', [[from[0] - 6 * i, from[1] + 3 * i]]);
}
await sleep(200);
const dragging = await page.state();
await page.touch('touchEnd', []);
const placed = await page.waitFor((s) => s.game.state === 'retreat' && stickOf(s), 3000, 50);
const first = stickOf(placed);
const bang = placed ? placed.game.tick + first.fuse : null;
await sleep(250);
const seen = stickOf(await page.state());
const image = await page.shot('tmp/journey/dynamite.png');
const drawn = seen ? redShape(image, seen.screen) : null;
const at = await page.target('hud', away);
await page.touch('touchStart', [at]);
const samples = [];
const deadline = Date.now() + 9000;
let after = null;
while (Date.now() < deadline) {
  const s = await page.state();
  const stick = stickOf(s);
  const c = activeCat(s);
  if (stick && s.game.state === 'retreat') {
    if (samples.length === 0 || samples[samples.length - 1].tick !== s.game.tick) samples.push({ tick: s.game.tick, fuse: stick.fuse, seconds: s.game.hud.seconds, sparks: stick.sparks, made: stick.cubes_made, resting: stick.resting, stick: stick.x, blob: c?.x, camera: s.game.camera.x, kind: s.game.camera.kind, hp: c?.hp });
  } else if (!stick && samples.length > 0) {
    after = s;
    break;
  }
  await sleep(60);
}
await page.touch('touchEnd', []);
const blast = after && (await page.waitFor((s) => s.game.camera.kind === 'blast', 2000, 30));
await page.shot('tmp/journey/dynamite-blast.png');

const last = samples[samples.length - 1];
const seconds = [...new Set([placed?.game?.hud?.seconds, ...samples.map((x) => x.seconds)])];
t.check(
  'placed by the slingshot, with no aim line and no fuse button while dragging, it stands at the blob\'s feet as a red stick with a fuse, seen on screen in front of the blob, taller than wide, and the turn goes straight to the retreat (tmp/journey/dynamite.png)',
  dragging.game.aim == null && !dragging.game.hud.shown.aim && !dragging.targets?.hud?.fuse && placed !== null && first.placed && first.stick && samples.some((x) => x.resting) && Math.abs(first.x - start.x) <= 1.5 && first.tint.every((v, i) => Math.abs(v - RED[i]) < 0.02) && drawn?.count >= 200 && drawn.h >= 1.8 * drawn.w,
  JSON.stringify({ first, from: start && start.x, aim: dragging.game.aim, shownAim: dragging.game.hud.shown.aim, fuseButton: Boolean(dragging.targets?.hud?.fuse), drawn }),
);
t.check(
  'its fuse sparks all along: at every moment published after the placing, at least 4 spark cubes are in flight, and the cubes of the sparks that go out are used again (40 at most made for the whole fuse, about 150 without)',
  samples.length >= 4 && samples.every((x) => x.tick === placed.game.tick || x.sparks >= 4) && last.made <= 40,
  JSON.stringify({ placed: placed?.game?.tick, sparks: samples.map((x) => [x.tick, x.sparks]), made: last?.made }),
);
t.check(
  'the clock counts the fuse down, 5, 4, 3, 2, 1, while the fuse burns at the sim\'s pace',
  [5, 4, 3, 2, 1].every((n) => seconds.includes(n)) && samples.every((x) => x.tick + x.fuse === bang),
  JSON.stringify({ seconds, bang, drift: samples.filter((x) => x.tick + x.fuse !== bang).slice(0, 3) }),
);
const walked = last && Math.abs(last.blob - start.x);
const following = samples.slice(Math.floor(samples.length / 2));
t.check(
  `holding ${away === 'right' ? '▶' : '◀'} walks the blob away, and the camera stays on it, not on the stick`,
  walked >= 40 && following.every((x) => x.kind !== 'projectile') && Math.abs(last.camera - last.blob) < Math.abs(last.camera - last.stick),
  JSON.stringify({ walked, kinds: [...new Set(samples.map((x) => x.kind))], camera: last?.camera, blob: last?.blob, stick: last?.stick }),
);
const end = await page.state();
const mine = placed ? end.game.sim.cats[placed.game.sim.cat - 1] : null;
t.check(
  'it goes off 5 s after it was placed: the stick, its fuse and every spark are gone, the camera goes to the blast, the blob that walked away is unhurt (tmp/journey/dynamite-blast.png)',
  after !== null && after.game.tick >= bang && end.game.stick_objects === 0 && blast !== null && mine?.alive && mine.hp === 100 && end.game.divergences === 0 && errorsOf(end).length === 0,
  JSON.stringify({ gone: after?.game?.tick, bang, objects: end.game.stick_objects, blast: blast !== null, hp: mine?.hp, divergences: end.game.divergences, errors: end.errors }),
);
await page.close();

const desk = await openPage(browser, { url: `${BASE}&seed=${SEED}`, touch: false });
await launch(desk);
await desk.mouse('mousePressed', 5, 5);
await desk.mouse('mouseReleased', 5, 5);
await desk.key('keyDown', '6', 'Digit6', 54);
await sleep(100);
await desk.key('keyUp', '6', 'Digit6', 54);
const deskPicked = await desk.waitFor((s) => s.game.weapon === 'dynamite', 3000);
await desk.key('keyDown', ' ', 'Space', 32);
const deskPlaced = await desk.waitFor((s) => s.game.state === 'retreat' && stickOf(s), 800, 50);
await sleep(100);
await desk.key('keyUp', ' ', 'Space', 32);
const deskEnd = await desk.state();
t.check(
  'on a computer: 6 picks the dynamite, Space places it at once',
  deskPicked !== null && deskPlaced !== null && deskEnd.game.divergences === 0 && errorsOf(deskEnd).length === 0,
  JSON.stringify({ picked: deskPicked !== null, placed: deskPlaced !== null, divergences: deskEnd.game.divergences }),
);
await desk.close();

browser.ws.close();
process.exit(t.failed === 0 ? 0 : 1);
