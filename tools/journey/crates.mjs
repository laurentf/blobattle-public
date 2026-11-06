import { connect, openPage, reporter, sleep } from './lib.mjs';

const BASE = 'http://127.0.0.1:5373/?test=1';
const t = reporter();
const browser = await connect();
const errorsOf = (s) => Object.keys(s?.errors || {});
const list = (v) => Object.values(v ?? {});
const KEY = {
  four: ['4', 'Digit4', 52],
  seven: ['7', 'Digit7', 55],
  eight: ['8', 'Digit8', 56],
  nine: ['9', 'Digit9', 57],
  zero: ['0', 'Digit0', 48],
  up: ['ArrowUp', 'ArrowUp', 38],
  enter: ['Enter', 'Enter', 13],
  space: [' ', 'Space', 32],
  left: ['ArrowLeft', 'ArrowLeft', 37],
  right: ['ArrowRight', 'ArrowRight', 39],
};

async function tap(page, key, hold = 80) {
  await page.key('keyDown', ...key);
  await sleep(hold);
  await page.key('keyUp', ...key);
  await sleep(150);
}

async function launch(page) {
  const home = await page.waitFor((s) => s.screen === 'home' && s.profile && s.targets?.home?.nickname, 90000);
  if (home?.profile?.fresh) {
    await page.type('home', 'nickname', 'Crates');
    await page.type('home', 'team', 'Droppers');
    await page.waitFor((s) => s.profile.nickname === 'Crates', 5000);
  }
  await page.press('home', 'training');
  await page.waitFor((s) => s.screen === 'training' && s.targets?.training, 10000);
  for (let i = 0; i < 2; i += 1) await page.press('training', 'teams_minus');
  await page.press('training', 'map_cycle');
  await page.press('training', 'launch');
  await page.waitFor((s) => s.screen === 'game' && s.game, 30000);
  return page.waitFor((s) => s.game && s.game.team === s.game.me && s.game.state === 'aiming' && s.targets?.hud?.weapon, 120000);
}

// Turn 1: an uppercut at nothing ends my turn; turn 2 is the bot's; turn 3 brings the crate down.
async function to_the_crate(page) {
  await tap(page, KEY.four);
  await tap(page, KEY.space);
  await page.waitFor((s) => s.game.team !== s.game.me, 20000);
  const falling = await page.waitFor((s) => list(s.game.crates).some((k) => k.chute) && s.game.team === s.game.me, 120000, 50);
  await sleep(700);
  const seen = await page.state();
  await page.shot(`tmp/journey/crate-falling-${seen.game.seed}.png`);
  const landed = await page.waitFor((s) => s.game.state === 'aiming' && list(s.game.crates).length > 0 && list(s.game.crates).every((k) => !k.chute), 30000, 50);
  return { falling, seen, landed };
}

async function walk_to(page, crate) {
  const side = crate.x > (await page.state()).game.cat.x ? KEY.right : KEY.left;
  await page.key('keyDown', ...side);
  const picked = await page.waitFor((s) => list(s.game.picked).length > 0, 15000, 50);
  await page.key('keyUp', ...side);
  await sleep(300);
  return picked;
}

async function crate_part(seed, weapon, use) {
  const page = await openPage(browser, { url: `${BASE}&seed=${seed}`, touch: false });
  await launch(page);
  const { falling, seen, landed } = await to_the_crate(page);
  const crate = list(landed?.game?.crates)[0];
  t.check(
    `seed ${seed}: on the 3rd turn a crate comes down under its parachute after a plane, the camera on it (tmp/journey/crate-falling-${seed}.png)`,
    falling !== null && list(seen.game.crates).some((k) => k.chute && k.chute_shown) && seen.game.planes.flown >= 1 && seen.game.camera.kind === 'crate',
    JSON.stringify({ crates: seen?.game?.crates, planes: seen?.game?.planes, camera: seen?.game?.camera?.kind }),
  );
  t.check(`seed ${seed}: it lands, folds its chute, and the turn starts`, crate !== undefined && !crate.chute_shown && landed.game.state === 'aiming', JSON.stringify(landed?.game?.crates));
  const picked = await walk_to(page, crate);
  const popped = await page.waitFor((s) => list(s.game.hud?.shown?.pops).length > 0, 3000, 50);
  const pops = list(popped?.game?.hud?.shown?.pops);
  t.check(
    `seed ${seed}: my blob walks onto it and gets a ${weapon}, "+1" rising above it`,
    picked !== null && list(picked.game.picked)[0] === weapon && pops.some((p) => p.startsWith('+1')),
    JSON.stringify({ picked: picked?.game?.picked, pops }),
  );
  await use(page);
  const end = await page.state();
  t.check(`seed ${seed}: no divergence, no error`, end.game.divergences === 0 && errorsOf(end).length === 0, JSON.stringify({ divergences: end.game.divergences, errors: end.errors }));
  await page.close();
}

t.section('tranche 24z — the crates on screen: the plane, the parachute, the pick-up, the cluster and the air strike (§5.10, §7.3, §7.4)');

if (!process.env.ONLY_STRIKE) await crate_part(120, 'cluster', async (page) => {
  await page.press('hud', 'weapon');
  const grid = await page.waitFor((s) => s.game.grid && Object.values(s.game.hud.shown.weapon_labels).some((l) => l.text === 'Cluster x1'), 5000, 50);
  await page.press('hud', 'weapon');
  t.check('the grid shows the cluster in a seventh cell, "Cluster x1"', grid !== null, JSON.stringify(grid?.game?.hud?.shown?.weapon_labels));
  await tap(page, KEY.seven);
  await page.key('keyDown', ...KEY.space);
  await sleep(700);
  await page.key('keyUp', ...KEY.space);
  const thrown = await page.waitFor((s) => s.game.state === 'flight', 5000, 50);
  const after = await page.waitFor((s) => s.game.state === 'retreat' || s.game.state === 'settling' || s.game.team !== s.game.me, 30000, 50);
  t.check('thrown, the cluster bursts into five mini-blobs of five colours', thrown !== null && after !== null && after.game.bit_colours === 5, JSON.stringify({ colours: after?.game?.bit_colours }));
});

await crate_part(29, 'airstrike', async (page) => {
  await tap(page, KEY.eight);
  const chosen = await page.waitFor((s) => s.game.weapon === 'airstrike', 3000, 50);
  await page.tap(422, 180);
  const aimed = await page.waitFor((s) => s.game.target !== undefined && s.game.target !== null && s.targets?.hud?.action, 3000, 50);
  await page.shot('tmp/journey/airstrike-target.png');
  t.check(
    'with the air strike chosen, a click on the map places a red cross, a Strike button shows, and no aim line (tmp/journey/airstrike-target.png)',
    chosen !== null && aimed !== null && aimed.game.hud.shown.target === true && aimed.game.hud.shown.action === 'Strike' && aimed.game.hud.shown.aim === false,
    JSON.stringify({ target: aimed?.game?.target, shown: aimed?.game?.hud?.shown?.action, aim: aimed?.game?.hud?.shown?.aim }),
  );
  const flown = aimed?.game?.planes?.flown ?? 0;
  await page.press('hud', 'action');
  const struck = await page.waitFor((s) => s.game.state === 'flight', 5000, 50);
  const after = await page.waitFor((s) => s.game.state !== 'flight', 30000, 50);
  t.check('Strike sends the plane over that column, and the shells fall', struck !== null && after !== null && after.game.planes.flown === flown + 1, JSON.stringify({ planes: after?.game?.planes }));
});

t.section('tranche 24z2 — the Waddler and the jetpack on screen and at the fingers (§7.3, §7.4)');

await crate_part(110, 'waddler', async (page) => {
  await tap(page, KEY.left, 40);
  await tap(page, KEY.nine);
  await tap(page, KEY.space);
  const walking = await page.waitFor((s) => s.game.state === 'flight' && s.targets?.hud?.action, 5000, 50);
  await sleep(500);
  await page.shot('tmp/journey/waddler.png');
  const seen = await page.state();
  t.check(
    'placed, the Waddler walks off as a little white blob, and a Boom button shows (tmp/journey/waddler.png)',
    walking !== null && seen.game.waddlers >= 1 && seen.game.state === 'flight' && seen.game.hud.shown.action === 'Boom',
    JSON.stringify({ waddlers: seen.game.waddlers, state: seen.game.state, action: seen.game.hud.shown.action }),
  );
  await page.press('hud', 'action');
  const boom = await page.waitFor((s) => s.game.state !== 'flight', 3000, 50);
  t.check('Boom sets it off before its 10 s are up', boom !== null && list(boom.game.shots).length === 0, JSON.stringify({ state: boom?.game?.state }));
});

await crate_part(48, 'jetpack', async (page) => {
  await tap(page, KEY.zero);
  await tap(page, KEY.space);
  const lit = await page.waitFor((s) => list(s.game.sim.cats).some((c) => c.jet > 0), 3000, 50);
  const y0 = lit?.game?.cat?.y;
  await page.key('keyDown', ...KEY.up);
  await sleep(900);
  const flying = await page.state();
  await page.shot('tmp/journey/jetpack.png');
  await page.key('keyUp', ...KEY.up);
  const marker = Object.values(flying.game.hud.labels ?? {}).find((l) => l.fuel_shown);
  t.check(
    'lit, ▲ held lifts the blob with flames under it, and the bar under its name shows the fuel in orange (tmp/journey/jetpack.png)',
    lit !== null && flying.game.cat.y < y0 - 10 && flying.game.flames > 0 && marker !== undefined && marker.gauge_shown < 1,
    JSON.stringify({ y0, y: flying.game.cat.y, flames: flying.game.flames, fuel: marker?.gauge_shown }),
  );
  await tap(page, KEY.enter);
  const cut = await page.waitFor((s) => list(s.game.sim.cats).every((c) => c.jet === 0), 3000, 50);
  const landed = await page.waitFor((s) => s.game.flames === 0, 5000, 50);
  t.check('Jump cuts the engine: the flames go out and the blob falls back', cut !== null && landed !== null, JSON.stringify({ flames: landed?.game?.flames }));
});

browser.ws.close();
process.exit(t.failed === 0 ? 0 : 1);
