import { connect, openPage, reporter, sleep } from './lib.mjs';
import { centroid, changed, colours, share } from './png.mjs';

const BASE = 'http://127.0.0.1:5373/?test=1';
const SKY = [158, 214, 242];
const INK = [41, 33, 51];
const BUTTON = [250, 168, 107];
const PAPER = [255, 247, 235];
const GRASS = [86, 158, 64];
const LEAVES = [43, 120, 56];
const ROCK = [107, 105, 107];
const EMBER_SKY = [158, 51, 36];
const ASH = [120, 118, 118];
const BASALT = [45, 40, 42];
const CLOUD = [236, 238, 240];
const STUDIO = [12, 12, 11];
const PARCHMENT = [198, 168, 114];
const LOGO_BLUE = [20, 160, 240];
const t = reporter();
const browser = await connect();

const errorsOf = (s) => Object.keys(s?.errors || {});
const box = (image, x0, y0, x1, y1) => [
  Math.round(image.width * x0),
  Math.round(image.height * y0),
  Math.round(image.width * x1),
  Math.round(image.height * y1),
];

const LETTERS = 'ABCDEFGH';

function hudMatchesSim(s) {
  const g = s?.game;
  const hud = g?.hud;
  const sim = g?.sim;
  if (!hud || !sim || g.state === 'ended') return null;
  const teamHp = [];
  for (const c of sim.cats) teamHp[c.team - 1] = (teamHp[c.team - 1] ?? 0) + (c.alive ? c.hp : 0);
  const alive = sim.cats.map((c, i) => ({ ...c, label: hud.labels[i] })).filter((c) => c.alive && c.label && c.label.x !== undefined);
  const active = sim.cats[sim.cat - 1];
  return {
    team: hud.shown.team === sim.team_name && hud.shown.letter === LETTERS[sim.team - 1],
    hp: hud.teams.length === teamHp.length && hud.teams.every((line, i) => line.shown === String(teamHp[i] ?? 0)),
    timer: hud.shown.timer === String(sim.seconds),
    wind: hud.shown.wind === `Wind ${Math.abs(sim.wind)}` && hud.shown.wind_direction === Math.sign(sim.wind),
    labels: alive.length > 0 && hud.shown.labels === alive.length && alive.every((c) => c.label.name_shown === c.name && c.label.shown === `${LETTERS[c.team - 1]} ${c.hp}`),
    marker: hud.shown.marker === Boolean(active?.alive && g.state !== 'turn_end' && hud.labels[sim.cat - 1]?.x !== undefined),
    gauge: gaugeMatches(hud, sim),
  };
}

const GAUGE = 3000;
const GAUGE_PIXELS = 32;

function gaugeMatches(hud, sim) {
  const onActive = hud.labels[sim.cat - 1]?.gauge_shown;
  const elsewhere = hud.labels.some((l, i) => i !== sim.cat - 1 && l.gauge_shown !== undefined);
  if (elsewhere) return false;
  if (!hud.shown.marker) return onActive === undefined;
  return onActive !== undefined && Math.abs(onActive - sim.cats[sim.cat - 1].gauge / GAUGE) <= 1 / GAUGE_PIXELS;
}

function gaugeOf(s) {
  const sim = s?.game?.sim;
  return { sim: sim?.cats[sim.cat - 1]?.gauge, shown: s?.game?.hud?.labels[sim.cat - 1]?.gauge_shown };
}

const allTrue = (seen) => seen !== null && Object.values(seen).every(Boolean);

async function css(page, p) {
  const ratio = await page.eval('window.devicePixelRatio');
  const height = await page.eval("document.querySelector('canvas').height");
  return [p.x / ratio, (height - p.y) / ratio];
}

async function launch(page, settings = null) {
  await page.waitFor((s) => s.screen === 'home' && s.profile && !s.profile.fresh, 90000);
  await page.press('home', 'training');
  await page.waitFor((s) => s.screen === 'training' && s.targets?.training, 10000);
  for (const [button, times] of settings ?? []) {
    for (let i = 0; i < times; i += 1) {
      await page.press('training', button);
    }
  }
  await page.press('training', 'launch');
  return page.waitFor((s) => s.screen === 'game' && s.game, 30000);
}

async function myAimingTurn(page, timeout = 120000) {
  return page.waitFor(
    (s) => s.game && s.game.team === s.game.me && s.game.state === 'aiming' && s.game.blob && s.targets?.hud?.weapon,
    timeout,
  );
}

async function sling(page, from, dx, dy, hold = 300) {
  await page.touch('touchStart', [from]);
  for (let i = 1; i <= 12; i += 1) {
    await sleep(35);
    await page.touch('touchMove', [[from[0] + (dx * i) / 12, from[1] + (dy * i) / 12]]);
  }
  await sleep(hold);
  const aiming = await page.state();
  const shot = await page.shot('tmp/journey/aim.png');
  await page.touch('touchEnd', []);
  return { aiming, shot };
}

t.section('tranche 20 — the HTML5 build loads in Chromium and shows Home (§7.2, §10.5)');
const page = await openPage(browser, { url: BASE });
const intro = { first: null, shakes: [], peak: 0, gap: false, logo: false, seconds: 0 };
let introStart = null;
let studioShot = null;
let logoShot = null;
const introUntil = Date.now() + 90000;
while (Date.now() < introUntil) {
  const s = await page.state();
  const i = s?.intro;
  if (i && i.phase !== 'over') {
    intro.first ??= s.screen;
    introStart ??= Date.now();
    if (i.studio) intro.shakes.push(i.shake);
    if (i.logo) intro.logo = true;
    intro.peak = i.peak;
    intro.gap = i.gap;
    if (i.phase === 'studio' && i.t >= 2.2 && i.t <= 2.7 && studioShot === null) studioShot = await page.shot('tmp/journey/intro-studio.png');
    if (i.phase === 'logo' && i.t >= 4.1 && i.t <= 5.4 && logoShot === null) logoShot = await page.shot('tmp/journey/intro-logo.png');
  }
  if (s?.screen === 'home') {
    intro.seconds = (Date.now() - (introStart ?? Date.now())) / 1000;
    break;
  }
  await sleep(50);
}
const introColours = {
  dark: studioShot && share(studioShot, STUDIO, 12),
  parchment: studioShot && share(studioShot, PARCHMENT, 30),
  logoDark: logoShot && share(logoShot, STUDIO, 12),
  logoBlue: logoShot && share(logoShot, LOGO_BLUE, 40),
};
t.check(
  'the game opens on the Panis Vult studio, shaking harder and harder, then the Blobattle logo over black, then Home (tmp/journey/intro-studio.png, intro-logo.png)',
  intro.first === 'intro' && intro.shakes[0] < 4 && intro.peak >= 13 && intro.gap && intro.logo && intro.seconds >= 5 && introColours.dark > 0.4 && introColours.parchment > 0.005 && introColours.logoDark > 0.4 && introColours.logoBlue > 0.02,
  JSON.stringify({ ...intro, shakes: intro.shakes.slice(0, 3), colours: introColours }),
);
const home = await page.waitFor((s) => s.screen === 'home' && s.profile, 90000);
t.check('the page reaches the Home screen at 844×390', home !== null, JSON.stringify(home?.profile));
const gl = await page.eval(
  "(() => { const c = document.querySelector('canvas'); const g = c && (c.getContext('webgl2') || c.getContext('webgl')); return c ? [c.width, c.height, g ? g.getParameter(g.VERSION) : 'no context'].join(' ') : null; })()",
);
t.check('the canvas fills the landscape screen at the device pixel ratio', gl !== null && gl.startsWith('2532 1170'), gl);
await page.waitFor((s) => s.backdrop_loaded && s.backdrop && s.intro?.phase === 'over', 30000);
await sleep(500);
const image = await page.shot('tmp/journey/home.png');
const fields = share(image, PAPER, 12, box(image, 0.35, 0.2, 0.95, 0.6));
const ink = share(image, INK, 20);
t.check('Home is drawn over the sky and asks for a nickname and a team (tmp/journey/home.png)', share(image, SKY, 16) > 0.08 && fields > 0.15 && ink > 0.004, `fields ${fields.toFixed(2)}, ink ${ink.toFixed(4)}, ${colours(image)} colours`);
await page.resize(390, 844);
await sleep(800);
const portrait = await page.shot('tmp/journey/home-portrait.png');
const upright = share(portrait, PAPER, 12, box(portrait, 0.05, 0.25, 0.95, 0.5));
const portraitInk = share(portrait, INK, 20, box(portrait, 0, 0, 1, 0.6));
t.check('Home keeps its layout and its texts in portrait at 390×844 (tmp/journey/home-portrait.png)', upright > 0.15 && portraitInk > 0.004, `fields ${upright.toFixed(2)}, ink ${portraitInk.toFixed(4)}`);
await page.resize(844, 390);
await sleep(500);
const brand = await page.eval(`(async () => {
  const icon = document.querySelector('link[rel=icon]');
  const touch = document.querySelector('link[rel=apple-touch-icon]');
  const html = await fetch(location.pathname).then((r) => r.text());
  const fetched = await Promise.all([icon.href, touch.href, 'splash.png'].map((u) => fetch(u).then((r) => r.status)));
  return JSON.stringify({ title: document.title, splash: html.includes('url("splash.png")') && !html.includes('defold-logo'), fetched });
})()`);
const branded = JSON.parse(brand ?? '{}');
t.check('the page is called Blobattle, loads behind the studio logo on black instead of Defold\'s, and has its icons', branded.title === 'Blobattle' && branded.splash === true && branded.fetched?.every((code) => code === 200), brand);
t.check('no Lua error and no exception in the page', errorsOf(await page.state()).length === 0 && browser.logs.filter((l) => l.startsWith('exception')).length === 0, JSON.stringify((await page.state()).errors) + ' ' + browser.logs.join(' | '));

t.section('the Home screen: Blobattle in voxels over a living backdrop (§7.2)');
const TEAMS = [[247, 97, 107], [82, 163, 250], [252, 204, 69], [107, 214, 117], [186, 133, 245], [255, 153, 66], [77, 214, 214], [245, 143, 204]];
const top = box(image, 0.1, 0, 0.9, 0.3);
const lit = TEAMS.filter((rgb) => share(image, rgb, 40, top) > 0.002).length;
const drawn = (await page.state()).backdrop;
const spanFits = ([left, right]) => left > 0.01 && right < 0.99 && left < right;
t.check('the title BLOBATTLE is built in voxels at the top, a team colour per letter, within the screen', drawn.title === 9 && lit >= 5 && spanFits(drawn.title_span), JSON.stringify({ letters: drawn.title, colours: lit, span: drawn.title_span }));
const EYES = [31, 26, 41];
const EYES_UNDER_PANEL = EYES.map((v, i) => Math.round(v * 0.65 + PAPER[i] * 0.35));
const darkAround = (shot, at) => {
  const around = box(shot, at.x - 0.04, 1 - at.y - 0.06, at.x + 0.04, 1 - at.y + 0.06);
  return share(shot, EYES, 30, around) + share(shot, EYES_UNDER_PANEL, 20, around);
};
const onScreen = (b, i) => b.moods[i] === 'scared' && b.faces[i].x > 0.06 && b.faces[i].x < 0.94;
const faceTrials = [];
let boomsSeen = 0;
let angrySeen = false;
let scaredShot = null;
for (let round = 0; round < 4 && !faceTrials.some((f) => f.ratio > 1.4); round += 1) {
  const boomed = await page.waitFor((s) => s.backdrop?.booms > boomsSeen && s.backdrop.moods.some((_, i) => onScreen(s.backdrop, i)), 20000);
  if (!boomed) break;
  boomsSeen = boomed.backdrop.booms;
  angrySeen ||= boomed.backdrop.moods.includes('angry');
  const at = boomed.backdrop.moods.findIndex((_, i) => onScreen(boomed.backdrop, i));
  await sleep(900);
  const shot = await page.shot('tmp/journey/home-scared.png');
  const during = (await page.state()).backdrop;
  const scared = during.moods[at] === 'scared' ? darkAround(shot, during.faces[at]) : 0;
  scaredShot ??= shot;
  await page.waitFor((s) => s.backdrop.moods[at] === 'calm', 5000);
  await sleep(600);
  const calmShot = await page.shot('tmp/journey/home-calm.png');
  const calm = darkAround(calmShot, (await page.state()).backdrop.faces[at]);
  faceTrials.push({ blob: at, scared: Number(scared.toFixed(4)), calm: Number(calm.toFixed(4)), ratio: calm > 0 ? Number((scared / calm).toFixed(2)) : 0 });
}
const moved = scaredShot ? changed(image, scaredShot, 24, box(image, 0, 0.3, 1, 1)) : 0;
t.check('shells fall among the blobs: a scared face is drawn, darker than the same blob calm, another blob gets angry, and the scene moves (tmp/journey/home-scared.png, home-calm.png)', faceTrials.some((f) => f.ratio > 1.4) && angrySeen && moved > 0.01, JSON.stringify({ faceTrials, angrySeen, moved: moved.toFixed(3) }));
t.check('the backdrop draws under 30 000 vertices', drawn.vertices > 1000 && drawn.vertices < 30000, JSON.stringify({ vertices: drawn.vertices }));
await page.resize(390, 844);
await sleep(1200);
const uprightDrawn = (await page.state()).backdrop;
const uprightShot = await page.shot('tmp/journey/home-title-portrait.png');
const uprightLit = TEAMS.filter((rgb) => share(uprightShot, rgb, 40, box(uprightShot, 0, 0, 1, 0.25)) > 0.001).length;
t.check('in portrait the title still fits the screen, at the top (tmp/journey/home-title-portrait.png)', spanFits(uprightDrawn.title_span) && uprightLit >= 5, JSON.stringify({ span: uprightDrawn.title_span, colours: uprightLit }));
await page.resize(844, 390);
await sleep(500);
const heavy = await openPage(browser, { url: BASE, cpu: 4 });
await heavy.waitFor((s) => s.screen === 'home' && s.backdrop?.ms?.n > 60, 90000);
await sleep(4000);
const cost = (await heavy.state()).backdrop.ms;
t.check('at CPU ×4, the backdrop script stays under 2 ms a frame (p95)', cost.p95 < 2, JSON.stringify(cost));
await heavy.close();

t.section('tranche 23 — first launch: nickname, team, Solo (§6.1, §7.2, D-11)');
await page.press('home', 'training');
await sleep(300);
t.check('Solo waits for a valid nickname', (await page.state()).screen === 'home');
await page.type('home', 'nickname', 'x');
t.check('a nickname outside the rules is refused', (await page.state()).profile.nickname == null, JSON.stringify((await page.state()).profile));
await page.type('home', 'nickname', 'Journey');
const named = await page.waitFor((s) => s.profile.nickname === 'Journey', 5000);
await page.type('home', 'team', 'Blobble Crew');
const teamed = await page.waitFor((s) => s.profile.team_name === 'Blobble Crew', 5000);
t.check('the nickname and the team are typed in fields on the screen, no dialog', named !== null && teamed !== null && page.dialogs.length === 0, JSON.stringify({ profile: (await page.state()).profile, dialogs: page.dialogs }));
await page.press('home', 'training');
const training = await page.waitFor((s) => s.screen === 'training' && s.settings, 5000);
t.check('Training opens and the profile is kept', training !== null && training.profile.fresh === false, JSON.stringify(training?.profile));
for (let i = 0; i < 3; i += 1) await page.press('training', 'teams_minus');
for (let i = 0; i < 4; i += 1) await page.press('training', 'cats_minus');
await page.press('training', 'bots_cycle');
await page.press('training', 'map_cycle');
const set = await page.state();
const wanted = { teams: 2, cats_per_team: 1, bot_level: 'hard', map: 'forest' };
t.check('the steppers and choices stay within §5.2', Object.entries(wanted).every(([k, v]) => set.settings[k] === v), JSON.stringify(set.settings));
const trainingShot = await page.shot('tmp/journey/training.png');
t.check('Training is drawn with its buttons (tmp/journey/training.png)', share(trainingShot, BUTTON, 16) > 0.05 && share(trainingShot, INK, 20) > 0.004);
await page.resize(390, 844);
await sleep(800);
const trainingPortrait = await page.shot('tmp/journey/training-portrait.png');
t.check('Training keeps its layout in portrait (tmp/journey/training-portrait.png)', share(trainingPortrait, BUTTON, 16, box(trainingPortrait, 0, 0.1, 1, 0.9)) > 0.05);
await page.resize(844, 390);
await sleep(300);
await page.press('training', 'back');
t.check('Back returns Home, the profile already chosen', (await page.waitFor((s) => s.screen === 'home', 5000)) !== null);
await page.type('home', 'nickname', 'x', { enter: false });
await page.press('home', 'training');
await sleep(800);
const refusedTap = await page.state();
t.check('a name refused as it is typed keeps Solo closed', refusedTap.screen === 'home' && refusedTap.profile.nickname === 'Journey', JSON.stringify({ screen: refusedTap.screen, profile: refusedTap.profile }));
await page.type('home', 'team', 'Blob Squad', { enter: false });
await page.press('home', 'training');
const renamed = await page.waitFor((s) => s.screen === 'training' && s.profile.team_name === 'Blob Squad' && s.profile.fresh === false, 5000);
t.check('the team can be renamed later from Home, and Solo takes the new name at once, Enter or not', renamed !== null, JSON.stringify((await page.state()).profile));
await page.press('training', 'back');
await page.waitFor((s) => s.screen === 'home', 5000);
await page.type('home', 'team', 'Blobble Crew');
await page.close();
const office = await openPage(browser, { url: BASE, width: 1920, height: 1080, scale: 1, touch: false });
await office.waitFor((s) => s.intro?.phase === 'studio' && s.targets?.intro?.skip, 90000);
await office.press('intro', 'skip');
const skipped = await office.waitFor((s) => s.screen === 'home', 1500, 50);
t.check('a click on the intro skips it to Home', skipped !== null && skipped.intro?.phase !== 'studio', JSON.stringify(skipped?.intro));
const desktopHome = await office.waitFor((s) => s.screen === 'home' && s.ui_factor, 90000);
await office.shot('tmp/journey/home-desktop.png');
t.check('on a large desktop window the interface keeps its size in points instead of stretching (tmp/journey/home-desktop.png)', desktopHome && desktopHome.ui_factor < 0.7, JSON.stringify({ ui_factor: desktopHome?.ui_factor }));
t.check('the renamed team was saved and is found again on the next visit', desktopHome?.profile?.team_name === 'Blobble Crew' && desktopHome.profile.nickname === 'Journey', JSON.stringify(desktopHome?.profile));
await office.close();

t.section('tranche 21 — the voxel world of a training game (§7.4, D-09)');
const game = await openPage(browser, { url: `${BASE}&seed=4242` });
const menuFirst = await game.waitFor((s) => s.screen === 'home' && s.backdrop_loaded === true, 90000);
const playing = await launch(game);
t.check('Launch starts a game against the bots', playing !== null, JSON.stringify(playing?.game?.tick));
t.check('the menu backdrop, loaded behind Home, is unloaded during a game', menuFirst !== null && (await game.waitFor((s) => s.backdrop_loaded === false, 5000)) !== null);
const cratered = await game.waitFor((s) => s.game && s.game.rebuild_ms.n > 0, 120000);
t.check('a crater is rebuilt in slices of at most 4 ms', cratered !== null && cratered.game.rebuild_ms.max <= 4, JSON.stringify(cratered?.game?.rebuild_ms));
const world = await game.shot('tmp/journey/world.png');
const volcanic = cratered?.game?.biome === 'volcano';
const worldGround = share(world, volcanic ? ASH : GRASS, 40);
const heaven = share(world, volcanic ? EMBER_SKY : SKY, 24);
t.check('the voxel terrain is drawn in the colours of its map, under its sky (tmp/journey/world.png)', worldGround > 0.002 && heaven > 0.05, `${cratered?.game?.biome}: ground ${worldGround.toFixed(4)}, sky ${heaven.toFixed(3)}`);
const now = (await game.waitFor((s) => s.game && s.game.checked > 3, 30000)) || (await game.state());
t.check('the client replays the stream without a divergence', now.game.checked > 3 && now.game.divergences === 0 && now.game.tick <= now.game.confirmed, JSON.stringify({ checked: now.game.checked, divergences: now.game.divergences, tick: now.game.tick, confirmed: now.game.confirmed }));
t.check('no Lua error during the game', errorsOf(now).length === 0, JSON.stringify(now.errors));
await game.close();
const slow = await openPage(browser, { url: `${BASE}&seed=4242`, cpu: 4 });
await launch(slow);
let measured = null;
const slowUntil = Date.now() + 240000;
while (Date.now() < slowUntil && measured === null) {
  const st = await slow.state();
  if (st.game && st.game.crater_s.n >= 2) {
    measured = st;
  } else if (st.game && st.game.team === st.game.me && st.game.state === 'aiming' && st.game.blob) {
    await sling(slow, await css(slow, st.game.blob), 0, -80, 100);
  }
  await sleep(500);
}
const m = measured?.game;
t.check('at CPU ×4, craters are rebuilt in slices of 4 ms (p95) and before the explosion flash ends', m && m.rebuild_ms.p95 <= 4 && m.crater_s.max < m.flash_s, JSON.stringify({ rebuild_ms: m?.rebuild_ms, crater_s: m?.crater_s, flash_s: m?.flash_s, sim_ms: m?.sim_ms, authority_ms: m?.authority_ms }));
await slow.close();

t.section('tranche 22 — the slingshot, the thumbs and the camera (§7.3, D-04)');
const aimPage = await openPage(browser, { url: `${BASE}&seed=4242` });
await launch(aimPage);
const myTurn = await myAimingTurn(aimPage);
t.check('the player gets the hand with the thumb controls shown', myTurn !== null && myTurn.targets.hud.left && myTurn.targets.hud.right && myTurn.targets.hud.jump, JSON.stringify(myTurn?.targets?.hud));
await aimPage.press('hud', 'weapon');
const grid = await aimPage.waitFor((s) => s.game.grid && s.targets.hud.grid_2, 3000);
await aimPage.press('hud', 'grid_2');
const grenade = await aimPage.waitFor((s) => s.game.weapon === 'grenade' && s.game.fuse === 3 && s.targets.hud.fuse, 3000);
await aimPage.press('hud', 'fuse');
const fused = await aimPage.waitFor((s) => s.game.fuse === 4, 3000);
t.check('the weapon button opens the grid; the grenade shows its fuse pill, 3 → 4 s', grid !== null && grenade !== null && fused !== null);
const cam0 = (await aimPage.state()).game.camera;
await aimPage.drag([430, 70], [300, 70]);
const panned = await aimPage.waitFor((s) => Math.abs(s.game.camera.x - cam0.x) > 5 && s.game.camera.auto === false, 3000);
const d0 = (await aimPage.state()).game.camera.distance;
await aimPage.touch('touchStart', [[380, 110], [480, 110]]);
for (let i = 1; i <= 8; i += 1) {
  await sleep(40);
  await aimPage.touch('touchMove', [[380 - 12 * i, 110], [480 + 12 * i, 110]]);
}
await aimPage.touch('touchEnd', []);
const pinched = await aimPage.waitFor((s) => s.game.camera.distance < d0 - 5, 3000);
await sleep(500);
await aimPage.tap(430, 70);
await aimPage.tap(430, 70);
const recentred = await aimPage.waitFor((s) => s.game.camera.auto === true, 3000);
t.check('one finger pans, two fingers pinch, a double tap recenters', panned !== null && pinched !== null && recentred !== null, JSON.stringify({ cam0, panned: panned?.game?.camera, pinched: pinched?.game?.camera?.distance }));
await sleep(1500);
let st = await aimPage.state();
let blob = await css(aimPage, st.game.blob);
await aimPage.tap(blob[0] + 30, blob[1]);
await sleep(700);
t.check('a tap next to the blob sends nothing', (await aimPage.state()).game.state === 'aiming');
st = await aimPage.state();
blob = await css(aimPage, st.game.blob);
await aimPage.touch('touchStart', [blob]);
for (let i = 1; i <= 6; i += 1) {
  await sleep(40);
  await aimPage.touch('touchMove', [[blob[0] + 14 * i, blob[1] + 9 * i]]);
}
for (let i = 5; i >= 0; i -= 1) {
  await sleep(40);
  await aimPage.touch('touchMove', [[blob[0] + 14 * i, blob[1] + 9 * i]]);
}
await aimPage.touch('touchEnd', []);
await sleep(700);
t.check('bringing the finger back on the blob cancels', (await aimPage.state()).game.state === 'aiming');
st = await aimPage.state();
blob = await css(aimPage, st.game.blob);
const beforeAim = await aimPage.shot('tmp/journey/before-aim.png');
const { aiming, shot } = await sling(aimPage, blob, 84, 60);
const aim = aiming.game.aim;
const cancel = Math.max(20, aiming.game.cancel);
const wantAngle = Math.round(((Math.atan2(60, -84) / (2 * Math.PI)) * 1024 + 1024) % 1024);
const wantPower = Math.max(1, Math.min(100, Math.round(((Math.hypot(84, 60) - cancel) / 130) * 100)));
t.check('the aim follows the finger: the angle and power the drag says, as integers', aim && Number.isInteger(aim.angle) && Math.abs(aim.angle - wantAngle) <= 4 && Math.abs(aim.power - wantPower) <= 3, JSON.stringify({ aim, wantAngle, wantPower }));
const hue = [0.42 + (0.97 - 0.42) * (aim?.power ?? 0) / 100, 0.84 + (0.3 - 0.84) * (aim?.power ?? 0) / 100, 0.46 + (0.3 - 0.46) * (aim?.power ?? 0) / 100].map((v) => Math.round(v * 255));
const lineGain = share(shot, hue, 20) - share(beforeAim, hue, 20);
t.check('the aim line is drawn in the colour of its power (tmp/journey/aim.png)', aim != null && lineGain > 0.0008, `${hue} +${lineGain.toFixed(4)}`);
const flying = await aimPage.waitFor((s) => s.game && s.game.team === s.game.me && s.game.state === 'flight', 3000);
t.check('releasing fires through the authority', flying !== null, JSON.stringify(flying?.game?.state));
const nextTurn = await myAimingTurn(aimPage);
const startX = nextTurn.game.cat.x;
await aimPage.touch('touchStart', [await css(aimPage, nextTurn.targets.hud.left)]);
await sleep(900);
await aimPage.touch('touchEnd', []);
const walked = await aimPage.waitFor((s) => s.game && s.game.cat.x <= startX - 2, 5000);
await sleep(300);
const stopA = (await aimPage.state()).game.cat.x;
await sleep(700);
const stopB = (await aimPage.state()).game.cat.x;
t.check('holding ◀ walks the blob to the left, letting go stops it', walked !== null && stopA === stopB, `${startX.toFixed(1)} → ${stopA.toFixed(1)} → ${stopB.toFixed(1)}`);
const ground = (await aimPage.state()).game.cat.y;
await aimPage.press('hud', 'jump');
const jumped = await aimPage.waitFor((s) => s.game && s.game.cat.y < ground - 2, 3000);
t.check('the jump button jumps', jumped !== null, `${ground.toFixed(1)} → ${jumped?.game?.cat?.y?.toFixed(1)}`);
const walkedPixels = Math.round(startX - stopB);
const drained = await aimPage.waitFor((s) => s.game && s.game.state === 'aiming' && gaugeOf(s).sim === GAUGE - 20 * walkedPixels - 200 && gaugeOf(s).shown !== undefined, 3000);
const gauge = gaugeOf(drained ?? (await aimPage.state()));
t.check('the bar under the blob is its gauge: 20 a pixel walked, 200 for the jump (§5.4, §7.4)', drained !== null && Math.abs(gauge.shown - gauge.sim / GAUGE) <= 1 / GAUGE_PIXELS, JSON.stringify({ walkedPixels, gauge }));

const desk = await openPage(browser, { url: `${BASE}&seed=4242`, touch: false });
await launch(desk);
const deskTurn = await myAimingTurn(desk);
await desk.mouse('mousePressed', 5, 5);
await desk.mouse('mouseReleased', 5, 5);
const deskX = deskTurn.game.cat.x;
await desk.key('keyDown', 'ArrowLeft', 'ArrowLeft', 37);
await sleep(800);
await desk.key('keyUp', 'ArrowLeft', 'ArrowLeft', 37);
const deskWalked = await desk.waitFor((s) => s.game.cat.x <= deskX - 2, 3000);
await desk.key('keyDown', '2', 'Digit2', 50);
await sleep(100);
await desk.key('keyUp', '2', 'Digit2', 50);
const deskGrenade = await desk.waitFor((s) => s.game.weapon === 'grenade', 3000);
await desk.key('keyDown', 'ArrowUp', 'ArrowUp', 38);
await sleep(400);
await desk.key('keyUp', 'ArrowUp', 'ArrowUp', 38);
const deskAim = await desk.waitFor((s) => s.game.aim && s.game.aim.angle !== undefined, 3000);
await desk.key('keyDown', ' ', 'Space', 32);
await sleep(600);
const deskCharge = (await desk.state()).game.aim;
await desk.key('keyUp', ' ', 'Space', 32);
const deskShot = await desk.waitFor((s) => s.game.team === s.game.me && s.game.state === 'flight', 3000);
const deskAgain = await myAimingTurn(desk);
await sleep(1500);
const deskBlob = await css(desk, (await desk.state()).game.blob);
await desk.mouse('mouseMoved', deskBlob[0], deskBlob[1]);
await sleep(30);
await desk.mouse('mousePressed', deskBlob[0], deskBlob[1]);
for (let i = 1; i <= 10; i += 1) {
  await sleep(40);
  await desk.mouse('mouseMoved', deskBlob[0] + 9 * i, deskBlob[1] + 6 * i);
}
await sleep(150);
const deskDrag = (await desk.state()).game.aim;
await desk.mouse('mouseReleased', deskBlob[0] + 90, deskBlob[1] + 60);
const deskFired = await desk.waitFor((s) => s.game.team === s.game.me && s.game.state === 'flight', 3000);
const toward = Math.round(((Math.atan2(-60, 90) / (2 * Math.PI)) * 1024 + 1024) % 1024);
t.check('with the mouse, the aim points toward the cursor, not away from it', deskDrag && Number.isInteger(deskDrag.angle) && Math.abs(deskDrag.angle - toward) <= 4, JSON.stringify({ aim: deskDrag, toward }));
t.check('on a computer: ← walks, 2 picks the grenade, ↑ aims, Space charges and fires, a mouse drag fires', deskWalked !== null && deskGrenade !== null && deskAim !== null && deskCharge?.charging === true && deskCharge.power > 10 && deskShot !== null && deskAgain !== null && deskFired !== null, JSON.stringify({ walked: deskWalked !== null, grenade: deskGrenade !== null, aim: deskAim?.game?.aim, charge: deskCharge, shot: deskShot !== null, fired: deskFired !== null }));
t.check('no Lua error while aiming, on touch and on a computer', errorsOf(await aimPage.state()).length === 0 && errorsOf(await desk.state()).length === 0, JSON.stringify([(await aimPage.state()).errors, (await desk.state()).errors]));

t.section('tranche 23 — a clear HUD, and a game that goes on in portrait (§7.4, D-10)');
const hudState = await aimPage.waitFor((s) => s.game?.state === 'aiming' && s.game.sim.seconds > 0 && allTrue(hudMatchesSim(s)), 60000);
const hudLast = hudState ?? (await aimPage.state());
t.check('the HUD shows what the sim says: the team playing, its HP per team, the time, the wind, a name and HP over each blob, the marker and the active blob\'s gauge', hudState !== null, JSON.stringify({ seen: hudMatchesSim(hudLast), shown: hudLast?.game?.hud?.shown }));
const deskFit = (await desk.state()).game?.hud?.shown?.fit;
await desk.resize(1600, 900);
await sleep(1500);
const deskShown = (await desk.state()).game?.hud?.shown;
t.check('on a computer, a resized window refits the HP list and the labels with the rest of the HUD', deskShown && Math.abs(deskShown.fit - deskFit) > 0.1 && deskShown.row_fit === deskShown.fit && deskShown.label_fit === deskShown.fit, JSON.stringify({ before: deskFit, fit: deskShown?.fit, rows: deskShown?.row_fit, labels: deskShown?.label_fit }));
t.check('no Lua error after the resize', errorsOf(await desk.state()).length === 0, JSON.stringify((await desk.state()).errors));
await desk.close();
const before = (await aimPage.state()).game.tick;
await aimPage.resize(390, 844);
const turned = await aimPage.waitFor((s) => s.rotate === true, 5000);
await sleep(1500);
const rotateShot = await aimPage.shot('tmp/journey/rotate.png');
const during = (await aimPage.state()).game.tick;
t.check('in portrait the game shows the rotate screen (tmp/journey/rotate.png)', turned !== null && share(rotateShot, INK, 30) > 0.5, `veil ${share(rotateShot, INK, 30).toFixed(2)}`);
t.check('and goes on meanwhile', during >= before + 30, `${before} → ${during}`);
await aimPage.resize(844, 390);
const back = await aimPage.waitFor((s) => s.rotate === false, 5000);
t.check('back in landscape, the game is shown again', back !== null);
t.check('no Lua error while playing', errorsOf(await aimPage.state()).length === 0, JSON.stringify((await aimPage.state()).errors));
await aimPage.close();

t.section('tranche 24 — a whole training game at 844×390, to the End screen (§10.5)');
const full = await openPage(browser, { url: `${BASE}&seed=${process.env.JOURNEY_SEED || 922}` });
await launch(full, [['teams_minus', 2], ['cats_minus', 3], ['bots_cycle', 1]]);
const sampled = { frames: 0, matched: 0, mine: 0, theirs: 0, ahead: 0, aim: false, misses: {}, tick: -1, faces: {} };
let shots = 0;
let ended = null;
const deadline = Date.now() + 10 * 60 * 1000;
while (Date.now() < deadline) {
  const s = await full.state();
  if (s.screen === 'end') {
    ended = s;
    break;
  }
  const g = s.game;
  const matches = hudMatchesSim(s);
  if (g && matches && g.tick !== sampled.tick) {
    sampled.tick = g.tick;
    for (const c of g.sim.cats) if (c.face) sampled.faces[c.face] = (sampled.faces[c.face] ?? 0) + 1;
    if (g.tick > g.confirmed) sampled.ahead += 1;
    sampled.frames += 1;
    if (allTrue(matches)) {
      sampled.matched += 1;
      if (g.team === g.me) sampled.mine += 1;
      else sampled.theirs += 1;
    } else {
      for (const [k, v] of Object.entries(matches)) if (!v) sampled.misses[k] = (sampled.misses[k] ?? 0) + 1;
    }
  }
  if (g && g.team === g.me && g.state === 'aiming' && g.blob && s.targets?.hud?.weapon) {
    const enemy = g.hud.labels.find((l) => l.alive && l.team !== g.team && l.x !== undefined);
    const from = await css(full, g.blob);
    let dx = 70;
    let dy = 70;
    if (enemy) {
      const to = await css(full, { x: enemy.x, y: enemy.y });
      const len = Math.hypot(to[0] - from[0], to[1] - from[1]) || 1;
      dx = ((from[0] - to[0]) / len) * 90;
      dy = ((from[1] - to[1]) / len) * 90 + 40;
    }
    const { aiming: a } = await sling(full, from, dx, dy, 150);
    sampled.aim ||= a.game.hud.shown.aim === true && Number.isInteger(a.game.aim?.angle);
    shots += 1;
    await full.waitFor((st) => st.screen === 'end' || (st.game && st.game.state !== 'aiming'), 5000);
  }
  await sleep(250);
}
t.check('the game is played to its end and the End screen shows', ended !== null, `${shots} shots by the player`);
t.check('all along, the HUD showed what the sim says (team, HP per team, time, wind, names and HP, marker, gauge), on the player\'s turns and the bot\'s, and the aim line', sampled.frames >= 20 && sampled.matched >= 0.9 * sampled.frames && sampled.mine > 0 && sampled.theirs > 0 && sampled.aim, JSON.stringify(sampled));
const endShot = await full.shot('tmp/journey/end.png');
const result = ended?.result;
const last = ended?.game;
const standing = [...new Set((last?.sim?.cats ?? []).filter((c) => c.alive).map((c) => c.team))];
const winnerRight = result && last && last.state === 'ended' && (standing.length === 1 ? result.winner === standing[0] : result.winner === 0 || standing.includes(result.winner));
const endShows = result?.shown && result.shown.winner === (result.winner ? `${result.teams[result.winner - 1]} wins` : 'Draw') && result.shown.rows.length === result.stats.length && result.stats.length === 2 && result.shown.rows.every((r, i) => r.enabled && r.name === result.teams[result.stats[i].team - 1] && r.damage === String(result.stats[i].damage) && r.kills === String(result.stats[i].kills));
t.check('End names the team left standing and shows each team\'s damage and kills (tmp/journey/end.png)', winnerRight && endShows && share(endShot, INK, 20) > 0.004, JSON.stringify({ standing, result }));
t.check('in the game, a blob that is hit makes an angry face (§7.4)', (sampled.faces.angry ?? 0) > 0, JSON.stringify(sampled.faces));
t.check('the client never went past the confirmed tick, never diverged, and checked every checksum', last && sampled.ahead === 0 && last.tick === last.confirmed && last.divergences === 0 && last.checked >= Math.floor(last.tick / 30) - 1, JSON.stringify({ ahead: sampled.ahead, tick: last?.tick, confirmed: last?.confirmed, checked: last?.checked, divergences: last?.divergences }));
t.check('the backdrop comes back behind the End screen', (await full.waitFor((s) => s.backdrop_loaded === true, 10000)) !== null);
await full.press('end', 'quit');
t.check('Quit returns Home', (await full.waitFor((s) => s.screen === 'home', 5000)) !== null);
t.check('no Lua error in the whole game', errorsOf(await full.state()).length === 0, JSON.stringify((await full.state()).errors));
const second = await launch(full, [['teams_plus', 1]]);
const fresh = await full.waitFor((s) => s.game && s.game.tick > 0 && s.game.tick < ended.game.tick && s.game.sim?.cats?.length === 3 && allTrue(hudMatchesSim(s)), 30000);
const secondSampled = { frames: 0, matched: 0, tick: -1, misses: {} };
for (let i = 0; i < 40; i += 1) {
  const s = await full.state();
  const matches = hudMatchesSim(s);
  if (matches && s.game.tick !== secondSampled.tick) {
    secondSampled.tick = s.game.tick;
    secondSampled.frames += 1;
    if (allTrue(matches)) secondSampled.matched += 1;
    else for (const [k, v] of Object.entries(matches)) if (!v) secondSampled.misses[k] = (secondSampled.misses[k] ?? 0) + 1;
  }
  await sleep(250);
}
const again = await full.state();
t.check('a second game in the same session, with 3 teams, shows its blobs as the sim says, without an error or a divergence', second !== null && fresh !== null && again.game.tick > fresh.game.tick && secondSampled.frames >= 5 && secondSampled.matched >= 0.9 * secondSampled.frames && again.game.checked > 0 && again.game.divergences === 0 && errorsOf(again).length === 0, JSON.stringify({ secondSampled, checked: again.game?.checked, divergences: again.game?.divergences, errors: again.errors }));
await full.close();

t.section('closing review — the small phone at 667×375 and 1280×720 (V0 §2)');
async function targetsFit(page, screen) {
  const s = await page.state();
  const ratio = await page.eval('window.devicePixelRatio');
  const width = await page.eval('window.innerWidth');
  const height = await page.eval('window.innerHeight');
  const list = Object.entries(s.targets?.[screen] ?? {}).map(([name, r]) => ({ name, x: r.x / ratio, y: r.y / ratio, w: r.w / ratio, h: r.h / ratio }));
  const small = list.filter((r) => r.w < 44 || r.h < 44).map((r) => `${r.name} ${r.w.toFixed(1)}×${r.h.toFixed(1)}`);
  const out = list.filter((r) => r.x - r.w / 2 < 0 || r.x + r.w / 2 > width || r.y - r.h / 2 < 0 || r.y + r.h / 2 > height).map((r) => r.name);
  const overlap = [];
  for (let i = 0; i < list.length; i += 1) {
    for (let j = i + 1; j < list.length; j += 1) {
      const [a, b] = [list[i], list[j]];
      if (Math.abs(a.x - b.x) < (a.w + b.w) / 2 && Math.abs(a.y - b.y) < (a.h + b.h) / 2) overlap.push(`${a.name}/${b.name}`);
    }
  }
  return { count: list.length, small, out, overlap };
}
const fits = (r, least) => r.count >= least && r.small.length === 0 && r.out.length === 0 && r.overlap.length === 0;
for (const [width, height, scale] of [[667, 375, 2], [1280, 720, 1]]) {
  const sized = await openPage(browser, { url: `${BASE}&seed=4242`, width, height, scale });
  await sized.waitFor((s) => s.screen === 'home' && s.targets?.home?.training, 90000);
  await sleep(500);
  const home = await targetsFit(sized, 'home');
  await sized.shot(`tmp/journey/home-${width}.png`);
  await sized.press('home', 'training');
  await sized.waitFor((s) => s.screen === 'training' && s.targets?.training?.launch, 10000);
  await sleep(300);
  const solo = await targetsFit(sized, 'training');
  for (let i = 0; i < 2; i += 1) await sized.press('training', 'teams_minus');
  for (let i = 0; i < 3; i += 1) await sized.press('training', 'cats_minus');
  await sized.press('training', 'launch');
  const turn = await myAimingTurn(sized);
  await sleep(500);
  const hud = await targetsFit(sized, 'hud');
  await sized.shot(`tmp/journey/game-${width}.png`);
  t.check(`at ${width}×${height}, every target of Home, Solo and the game is 44 points or more, on screen and apart from the others (tmp/journey/home-${width}.png, game-${width}.png)`, turn !== null && fits(home, 4) && fits(solo, 8) && fits(hud, 4) && errorsOf(await sized.state()).length === 0, JSON.stringify({ home, solo, hud, errors: (await sized.state()).errors }));
  await sized.close();
}

t.section('tranches 24c and 24q — the tentacle: thrown, climbed and lowered with the cross, swung, let go with Jump, and back on the ground (§5.4, §7.3, §7.4)');
const ROPE_SEED = 244;
const ROPE_ANGLE = 176;
const RED = [247, 97, 107];
const activeCat = (s) => s?.game?.sim?.cats?.[s.game.sim.cat - 1];
const armOnAnchor = (s) => {
  const c = activeCat(s);
  const arm = s?.game?.arm;
  return Boolean(c?.anchor && arm && arm.mode === 'hooked' && arm.shown > 0 && arm.tip.x === c.anchor.x + 0.5 && arm.tip.y === arm.height - c.anchor.y - 0.5);
};
async function holdTarget(page, name, until, timeout) {
  const at = await page.target('hud', name);
  if (!at) return null;
  await page.touch('touchStart', [at]);
  const reached = await page.waitFor(until, timeout, 50);
  await page.touch('touchEnd', []);
  return reached;
}
const rope = await openPage(browser, { url: `${BASE}&seed=${ROPE_SEED}`, cpu: 4 });
await launch(rope, [['teams_minus', 2], ['cats_minus', 3]]);
await myAimingTurn(rope);
await rope.press('hud', 'weapon');
await rope.waitFor((s) => s.game.grid && s.targets.hud.grid_3, 5000);
await rope.press('hud', 'grid_3');
const picked = await rope.waitFor((s) => s.game.weapon === 'tentacle' && !s.game.grid, 5000);
const greyed = (st) => st?.game?.hud?.shown?.climb_arrow < st?.game?.hud?.shown?.live_arrow;
const greyBefore = Boolean(picked?.targets?.hud?.climb_up && picked?.targets?.hud?.climb_down && greyed(picked));
const idle = activeCat(picked);
await holdTarget(rope, 'climb_up', () => false, 400);
const afterGrey = await rope.state();
const inert = activeCat(afterGrey)?.y === idle?.y && !activeCat(afterGrey)?.hanging && (afterGrey.game.trace?.counts?.climb ?? 0) === (picked.game.trace?.counts?.climb ?? 0);
await sleep(500);
const beforeRope = await rope.shot('tmp/journey/rope-before.png');
const ropeFrom = await css(rope, (await rope.state()).game.blob);
const throwAngle = (ROPE_ANGLE / 1024) * 2 * Math.PI;
const { aiming: ropeAim } = await sling(rope, ropeFrom, -Math.cos(throwAngle) * 90, Math.sin(throwAngle) * 90, 150);
const hooked = await rope.waitFor((s) => activeCat(s)?.hanging === true && armOnAnchor(s), 5000);
t.check(
  'the tentacle is picked in the weapon grid and thrown by the slingshot, its angle only: it hooks the slope above',
  picked !== null && hooked !== null && Math.abs((ropeAim.game.aim?.angle ?? -99) - ROPE_ANGLE) <= 4 && ropeAim.game.aim.weapon === 'tentacle' && hooked.game.state === 'aiming',
  JSON.stringify({ aim: ropeAim.game.aim, anchor: activeCat(hooked)?.anchor, state: hooked?.game?.state }),
);
await sleep(300);
const hanging = await rope.state();
const ropeShot = await rope.shot('tmp/journey/rope-hooked.png');
const mid = hanging.game.arm?.mid ? await css(rope, hanging.game.arm.mid) : [0, 0];
const ratio = ropeShot.width / 844;
const around = [Math.round((mid[0] - 10) * ratio), Math.round((mid[1] - 10) * ratio), Math.round((mid[0] + 10) * ratio), Math.round((mid[1] + 10) * ratio)];
const armRed = share(ropeShot, RED, 40, around) - share(beforeRope, RED, 40, around);
t.check('its voxel arm is drawn from the blob to the anchor, in the team colour (tmp/journey/rope-hooked.png)', armOnAnchor(hanging) && armRed > 0.1, JSON.stringify({ arm: hanging.game.arm, red: armRed.toFixed(3) }));
const pads = await targetsFit(rope, 'hud');
const [leftPad, rightPad, up, down, jumpPad] = ['left', 'right', 'climb_up', 'climb_down', 'jump'].map((name) => hanging.targets?.hud?.[name]);
const screenWidth = await rope.eval("document.querySelector('canvas').width");
const cross = leftPad && rightPad && up && down && Math.abs(up.x - down.x) < 1 && Math.abs(up.x - (leftPad.x + rightPad.x) / 2) < 1 && up.y > leftPad.y && down.y < leftPad.y && Math.abs(leftPad.y - rightPad.y) < 1;
t.check(
  'a cross ◀ ▶ ▲ ▼ at the left thumb, ▲ ▼ grey and inert until the tentacle hooks, and Jump apart at the right thumb, with its word; 44 points or more, apart from the other targets',
  greyBefore && inert && !greyed(hanging) && hanging.game.hud.shown.climb_arrow === hanging.game.hud.shown.live_arrow && cross && jumpPad && jumpPad.x > screenWidth / 2 && hanging.game.hud.shown.jump === 'Jump' && fits(pads, 6),
  JSON.stringify({ greyBefore, inert, arrows: [hanging.game.hud.shown.climb_arrow, hanging.game.hud.shown.live_arrow], jump: hanging.game.hud.shown.jump, pads }),
);
const low = activeCat(hanging);
const climbed = await holdTarget(rope, 'climb_up', (s) => activeCat(s)?.hanging && activeCat(s).y <= low.y - 2 && !activeCat(s).grounded, 6000);
t.check('holding ▲ of the cross shortens the rope without letting go: the blob leaves the ground and rises', climbed !== null && activeCat(climbed).hanging && activeCat(climbed).rope < low.rope, JSON.stringify({ from: [low.x, low.y, low.rope], to: climbed && [activeCat(climbed).x, activeCat(climbed).y, activeCat(climbed).rope] }));
const short = activeCat(await rope.state());
const lowered = await holdTarget(rope, 'climb_down', (s) => activeCat(s)?.hanging && activeCat(s).rope >= short.rope + 256 * 2, 3000);
t.check('holding ▼ lengthens it, still hanging', lowered !== null && activeCat(lowered).hanging, JSON.stringify({ from: short.rope, to: lowered && activeCat(lowered).rope }));
const still = activeCat(await rope.state());
const swung = await holdTarget(rope, 'left', (s) => activeCat(s)?.hanging && !activeCat(s).grounded && Math.abs(activeCat(s).x - still.x) >= 3, 6000);
t.check('holding ◀ swings the blob on its rope', swung !== null, JSON.stringify({ from: still.x, to: swung && activeCat(swung).x }));
const letGoPads = [await rope.target('hud', 'right'), await rope.target('hud', 'jump')];
await rope.touch('touchStart', [letGoPads[0]]);
await sleep(60);
await rope.touch('touchStart', letGoPads);
const letGo = await rope.waitFor((s) => activeCat(s)?.hanging === false, 1500, 50);
await rope.touch('touchEnd', []);
const retracted = await rope.waitFor((s) => s.game.arm?.mode === 'idle' && s.game.arm?.shown === 0, 3000);
const landed = await rope.waitFor((s) => activeCat(s)?.grounded === true, 8000);
const greyAfter = greyed(landed);
t.check('Jump, with ▶ held, lets go toward the slope: the arm comes back, ▲ ▼ grey again, and the blob lands, alive', letGo !== null && retracted !== null && landed !== null && activeCat(landed).alive && greyAfter, JSON.stringify({ cat: landed && activeCat(landed), state: landed?.game?.state, greyAfter }));
const ropeAfter = await rope.state();
t.check(
  'all along, no divergence and no tick past the confirmed one, and no Lua error',
  ropeAfter.game.divergences === 0 && ropeAfter.game.tick <= ropeAfter.game.confirmed && ropeAfter.game.checked > 0 && errorsOf(ropeAfter).length === 0,
  JSON.stringify({ tick: ropeAfter.game.tick, confirmed: ropeAfter.game.confirmed, checked: ropeAfter.game.checked, divergences: ropeAfter.game.divergences, errors: ropeAfter.errors }),
);
t.check('at CPU ×4, a sim tick of this game with the tentacle stays well under a frame', ropeAfter.game.sim_ms.p95 < 4, JSON.stringify(ropeAfter.game.sim_ms));
await rope.close();

const deskRope = await openPage(browser, { url: `${BASE}&seed=${ROPE_SEED}`, touch: false });
await launch(deskRope, [['teams_minus', 2], ['cats_minus', 3]]);
await myAimingTurn(deskRope);
await deskRope.mouse('mousePressed', 5, 5);
await deskRope.mouse('mouseReleased', 5, 5);
await deskRope.key('keyDown', '3', 'Digit3', 51);
await sleep(100);
await deskRope.key('keyUp', '3', 'Digit3', 51);
const deskPicked = await deskRope.waitFor((s) => s.game.weapon === 'tentacle', 3000);
async function nudgeAim(page, key, code, keyCode) {
  await page.key('keyDown', key, code, keyCode);
  await sleep(20);
  await page.key('keyUp', key, code, keyCode);
  await sleep(120);
  return (await page.state()).game.aim?.angle ?? 0;
}
let deskAngle = await nudgeAim(deskRope, 'ArrowUp', 'ArrowUp', 38);
for (let i = 0; i < 40 && Math.abs(deskAngle - ROPE_ANGLE) > 3; i += 1) {
  deskAngle = deskAngle < ROPE_ANGLE ? await nudgeAim(deskRope, 'ArrowUp', 'ArrowUp', 38) : await nudgeAim(deskRope, 'ArrowDown', 'ArrowDown', 40);
}
const deskAimed = Math.abs(deskAngle - ROPE_ANGLE) <= 3 ? deskAngle : null;
await deskRope.key('keyDown', ' ', 'Space', 32);
const deskHooked = await deskRope.waitFor((s) => activeCat(s)?.hanging === true, 800, 50);
await sleep(100);
await deskRope.key('keyUp', ' ', 'Space', 32);
const deskLow = activeCat(await deskRope.state());
await deskRope.key('keyDown', 'ArrowUp', 'ArrowUp', 38);
const deskClimbed = await deskRope.waitFor((s) => activeCat(s)?.hanging && activeCat(s).rope < deskLow.rope - 256 * 3, 4000, 50);
await deskRope.key('keyUp', 'ArrowUp', 'ArrowUp', 38);
const deskStill = activeCat(await deskRope.state());
await deskRope.key('keyDown', 'ArrowLeft', 'ArrowLeft', 37);
const deskSwung = await deskRope.waitFor((s) => activeCat(s)?.hanging && Math.abs(activeCat(s).x - deskStill.x) >= 4, 5000, 50);
await deskRope.key('keyUp', 'ArrowLeft', 'ArrowLeft', 37);
const deskPads = Boolean((await deskRope.state()).targets?.hud?.climb_up);
await deskRope.key('keyDown', 'ArrowRight', 'ArrowRight', 39);
await sleep(60);
await deskRope.key('keyDown', 'Enter', 'Enter', 13);
const deskLetGo = await deskRope.waitFor((s) => activeCat(s)?.hanging === false, 1000, 50);
await deskRope.key('keyUp', 'Enter', 'Enter', 13);
await deskRope.key('keyUp', 'ArrowRight', 'ArrowRight', 39);
const deskLanded = deskLetGo && (await deskRope.waitFor((s) => activeCat(s)?.grounded, 8000));
const deskEnd = await deskRope.state();
t.check(
  'on a computer, without the thumb pads: 3 picks the tentacle, ↑ aims, Space throws it at once, ↑ climbs, ← swings, → and Enter let go',
  deskPicked !== null && deskAimed !== null && deskHooked !== null && deskClimbed !== null && deskSwung !== null && !deskPads && deskLetGo !== null && deskLanded && deskEnd.game.divergences === 0 && errorsOf(deskEnd).length === 0,
  JSON.stringify({ picked: deskPicked !== null, angle: deskAngle, hooked: deskHooked !== null, climbed: deskClimbed !== null, swung: deskSwung !== null, pads: deskPads, letGo: deskLetGo !== null, landed: Boolean(deskLanded), divergences: deskEnd.game.divergences }),
);
await deskRope.close();

t.section('tranche 24e — the uppercut: picked in the grid, a walk, a punch, the blob in front sent flying (§8.2, §7.3, §7.4)');
const PUNCH_SEED = 121;
const inReach = (s) => {
  const c = activeCat(s);
  if (!c) return null;
  const [cx, cy] = [Math.floor(c.x), Math.floor(c.y)];
  const near = (o) => o !== c && o.alive && o.team !== c.team && Math.floor(o.x) - cx >= 1 && Math.floor(o.x) - cx <= 12 && Math.abs(Math.floor(o.y) - cy) < 7;
  return s.game.sim.cats.findIndex(near);
};
const punch = await openPage(browser, { url: `${BASE}&seed=${PUNCH_SEED}`, cpu: 4 });
await launch(punch, [['teams_minus', 2]]);
await myAimingTurn(punch);
await punch.press('hud', 'weapon');
const punchGrid = await punch.waitFor((s) => s.game.grid && s.targets.hud.grid_4, 5000);
await sleep(300);
const gridFit = await targetsFit(punch, 'hud');
const gridLabels = (await punch.state()).game.hud.shown.weapon_labels ?? {};
await punch.shot('tmp/journey/grid.png');
await punch.press('hud', 'grid_4');
const punchPicked = await punch.waitFor((s) => s.game.weapon === 'uppercut' && !s.game.grid, 5000);
t.check(
  'the weapon grid shows its cells in two columns, 44 points or more, on screen and apart from the others; the fourth picks the uppercut (tmp/journey/grid.png)',
  punchGrid !== null && fits(gridFit, 8) && punchPicked !== null,
  JSON.stringify(gridFit),
);
const shownLabels = Object.values(gridLabels);
t.check(
  'each cell names its weapon with the ammunition left when it is counted (Bazooka x10, Chomp x3, Dynamite x1), the tentacle and the uppercut without a count, and every label fits its cell (§8.2)',
  shownLabels.length >= 7 && shownLabels.every((l) => l.fits) && ['Bazooka x10', 'Grenade x10', 'Tentacle', 'Uppercut', 'Chomp x3', 'Dynamite x1'].every((text) => shownLabels.some((l) => l.text === text)),
  JSON.stringify(gridLabels),
);
const walkedTo = await holdTarget(punch, 'right', (s) => inReach(s) >= 0, 6000);
await sleep(300);
const victim = inReach(await punch.state());
const victimBefore = victim >= 0 ? (await punch.state()).game.sim.cats[victim] : null;
const punchFrom = await css(punch, (await punch.state()).game.blob);
const { aiming: punchAiming } = await sling(punch, punchFrom, -60, 30, 150);
const struck = victimBefore && (await punch.waitFor((s) => s.game.sim.cats[victim].hp <= victimBefore.hp - 30, 3000, 50));
const flung = struck && (await punch.waitFor((s) => s.game.sim.cats[victim].y <= victimBefore.y - 20, 3000, 50));
if (flung) await punch.shot('tmp/journey/punch.png');
const handedOver = struck && (await punch.waitFor((s) => s.game.team !== s.game.me, 20000));
const punchEnd = await punch.state();
t.check(
  'holding ▶ walks up to a bot blob; the slingshot, with no aim line, punches it: 30 HP down, sent up in an arc, and the turn ends by itself (tmp/journey/punch.png)',
  walkedTo !== null && punchAiming.game.aim == null && !punchAiming.game.hud.shown.aim && struck && flung && handedOver && punchEnd.game.divergences === 0 && errorsOf(punchEnd).length === 0,
  JSON.stringify({ walked: walkedTo !== null, victim, before: victimBefore && { hp: victimBefore.hp, y: victimBefore.y }, aim: punchAiming.game.aim, struck: Boolean(struck), flung: Boolean(flung), handedOver: Boolean(handedOver), divergences: punchEnd.game.divergences }),
);
await punch.close();

const deskPunch = await openPage(browser, { url: `${BASE}&seed=${PUNCH_SEED}`, touch: false });
await launch(deskPunch, [['teams_minus', 2]]);
await myAimingTurn(deskPunch);
await deskPunch.mouse('mousePressed', 5, 5);
await deskPunch.mouse('mouseReleased', 5, 5);
await deskPunch.key('keyDown', '4', 'Digit4', 52);
await sleep(100);
await deskPunch.key('keyUp', '4', 'Digit4', 52);
const deskUppercut = await deskPunch.waitFor((s) => s.game.weapon === 'uppercut', 3000);
await deskPunch.key('keyDown', 'ArrowRight', 'ArrowRight', 39);
const deskNear = await deskPunch.waitFor((s) => inReach(s) >= 0, 6000, 50);
await deskPunch.key('keyUp', 'ArrowRight', 'ArrowRight', 39);
await sleep(300);
const deskVictim = inReach(await deskPunch.state());
const deskBefore = deskVictim >= 0 ? (await deskPunch.state()).game.sim.cats[deskVictim] : null;
await deskPunch.key('keyDown', ' ', 'Space', 32);
const deskStruck = deskBefore && (await deskPunch.waitFor((s) => s.game.sim.cats[deskVictim].hp <= deskBefore.hp - 30, 800, 50));
await sleep(100);
await deskPunch.key('keyUp', ' ', 'Space', 32);
const deskPunchEnd = await deskPunch.state();
t.check(
  'on a computer: 4 picks the uppercut, → walks up to the blob, Space punches at once',
  deskUppercut !== null && deskNear !== null && deskStruck && deskPunchEnd.game.divergences === 0 && errorsOf(deskPunchEnd).length === 0,
  JSON.stringify({ picked: deskUppercut !== null, near: deskNear !== null, victim: deskVictim, struck: Boolean(deskStruck), divergences: deskPunchEnd.game.divergences }),
);
await deskPunch.close();

t.section('tranche 24f — the Chomp: picked in the grid, aimed down, a tunnel eaten, the mouth munching (§8.2, §7.3, §7.4)');
const chompPage = await openPage(browser, { url: `${BASE}&seed=${ROPE_SEED}`, cpu: 4 });
await launch(chompPage, [['teams_minus', 2], ['cats_minus', 3]]);
await myAimingTurn(chompPage);
await chompPage.press('hud', 'weapon');
const fiveGrid = await chompPage.waitFor((s) => s.game.grid && s.targets.hud.grid_5, 5000);
await sleep(300);
const fiveFit = await targetsFit(chompPage, 'hud');
await chompPage.press('hud', 'grid_5');
const chompPicked = await chompPage.waitFor((s) => s.game.weapon === 'chomp' && !s.game.grid, 5000);
t.check(
  'the weapon grid shows six cells, two columns of three, 44 points or more, on screen and apart from the others; the fifth picks the Chomp',
  fiveGrid !== null && fits(fiveFit, 10) && chompPicked !== null,
  JSON.stringify(fiveFit),
);
await sleep(300);
const eaterBefore = activeCat(await chompPage.state());
const chompFrom = await css(chompPage, (await chompPage.state()).game.blob);
const { aiming: chompAiming } = await sling(chompPage, chompFrom, 0, -90, 150);
const faces = {};
let eating = null;
const mealDeadline = Date.now() + 8000;
while (Date.now() < mealDeadline) {
  const s = await chompPage.state();
  const c = activeCat(s);
  if (c?.dig > 0) {
    eating = eating ?? s;
    faces[c.face] = (faces[c.face] ?? 0) + 1;
    if (faces.munch && faces.chew && !faces.shot) {
      faces.shot = 1;
      await chompPage.shot('tmp/journey/chomp.png');
    }
  } else if (eating) break;
  await sleep(40);
}
const fed = await chompPage.waitFor((s) => activeCat(s)?.dig === 0 && activeCat(s)?.grounded, 5000);
const eaterAfter = activeCat(fed);
const chompMeasured = fed?.game;
const passedOn = fed && (await chompPage.waitFor((s) => s.game.team !== s.game.me, 20000));
const chompEnd = await chompPage.state();
t.check(
  'aimed down by the slingshot, the blob eats its way 40 px down, munching, and the turn ends by itself (tmp/journey/chomp.png)',
  chompAiming.game.aim?.weapon === 'chomp' && eating !== null && faces.munch > 0 && faces.chew > 0 && eaterAfter?.alive && eaterAfter.y - eaterBefore.y >= 38 && Math.abs(eaterAfter.x - eaterBefore.x) < 2 && passedOn && chompEnd.game.divergences === 0 && errorsOf(chompEnd).length === 0,
  JSON.stringify({ aim: chompAiming.game.aim, faces, from: [eaterBefore.x, eaterBefore.y], to: eaterAfter && [eaterAfter.x, eaterAfter.y], passedOn: Boolean(passedOn), divergences: chompEnd.game.divergences }),
);
t.check(
  'at CPU ×4, the tunnel is rebuilt in slices of 4 ms (p95), and a sim tick of the meal stays well under a frame',
  chompMeasured && chompMeasured.rebuild_ms.n > 0 && chompMeasured.rebuild_ms.p95 <= 4 && chompMeasured.sim_ms.p95 < 4,
  JSON.stringify({ rebuild_ms: chompMeasured?.rebuild_ms, sim_ms: chompMeasured?.sim_ms }),
);
await chompPage.close();

const deskChomp = await openPage(browser, { url: `${BASE}&seed=${ROPE_SEED}`, touch: false });
await launch(deskChomp, [['teams_minus', 2], ['cats_minus', 3]]);
await myAimingTurn(deskChomp);
await deskChomp.mouse('mousePressed', 5, 5);
await deskChomp.mouse('mouseReleased', 5, 5);
await deskChomp.key('keyDown', '5', 'Digit5', 53);
await sleep(100);
await deskChomp.key('keyUp', '5', 'Digit5', 53);
const deskChompPicked = await deskChomp.waitFor((s) => s.game.weapon === 'chomp', 3000);
await deskChomp.key('keyDown', ' ', 'Space', 32);
const deskEating = await deskChomp.waitFor((s) => activeCat(s)?.dig > 0, 800, 50);
await sleep(100);
await deskChomp.key('keyUp', ' ', 'Space', 32);
const deskFed = await deskChomp.waitFor((s) => activeCat(s)?.dig === 0 && s.game.state !== 'flight', 5000);
const deskChompEnd = await deskChomp.state();
const deskRebuild = deskFed?.game?.rebuild_ms;
t.check(
  'on a computer: 5 picks the Chomp, Space starts the meal at once, and the tunnel is rebuilt in slices of 4 ms at most',
  deskChompPicked !== null && deskEating !== null && deskFed !== null && deskRebuild?.n > 0 && deskRebuild.max <= 4 && deskChompEnd.game.divergences === 0 && errorsOf(deskChompEnd).length === 0,
  JSON.stringify({ picked: deskChompPicked !== null, eating: deskEating !== null, fed: deskFed !== null, rebuild_ms: deskRebuild, divergences: deskChompEnd.game.divergences }),
);
await deskChomp.close();

t.section('tranche 24g — two maps: a forest under a blue sky, a volcano under a glowing one (§5.3, §7.4)');
const BIOME_SEED = 4242;
async function biomeGame(settings, cpu) {
  const page = await openPage(browser, { url: `${BASE}&seed=${BIOME_SEED}`, touch: false, cpu });
  await launch(page, settings);
  const ready = await page.waitFor((s) => s.game && s.game.biome && s.game.vertices > 0, 60000);
  await sleep(1500);
  return { page, ready };
}
const forest = await biomeGame([['map_cycle', 1]]);
const forestShot = await forest.page.shot('tmp/journey/forest.png');
const forestTop = box(forestShot, 0, 0, 1, 0.3);
const forestColours = {
  sky: share(forestShot, SKY, 16),
  grass: share(forestShot, GRASS, 30),
  leaves: share(forestShot, LEAVES, 20),
  rock: share(forestShot, ROCK, 30),
  clouds: share(forestShot, CLOUD, 30, forestTop),
  grassAt: centroid(forestShot, GRASS, 30),
  rockAt: centroid(forestShot, ROCK, 30),
};
const forestState = await forest.page.state();
t.check(
  'Map set to Forest gives a forest: a blue sky with clouds, grass on top of the ground, grey rock under it, round green crowns (tmp/journey/forest.png)',
  forest.ready?.game?.biome === 'forest' && forestColours.sky > 0.1 && forestColours.grass > 0.002 && forestColours.leaves > 0.002 && forestColours.rock > 0.02 && forestColours.clouds > 0.0005 && forestColours.grassAt < forestColours.rockAt && forestState.game.bubbles === 0 && forestState.game.clouds > 0,
  JSON.stringify({ biome: forest.ready?.game?.biome, colours: forestColours, bubbles: forestState.game.bubbles, clouds: forestState.game.clouds }),
);
await forest.page.close();
const volcano = await biomeGame([['map_cycle', 2]]);
const volcanoShot = await volcano.page.shot('tmp/journey/volcano.png');
const volcanoColours = {
  sky: share(volcanoShot, EMBER_SKY, 24),
  ash: share(volcanoShot, ASH, 24),
  basalt: share(volcanoShot, BASALT, 25, box(volcanoShot, 0, 0.35, 1, 0.8)),
  blue: share(volcanoShot, SKY, 16),
};
const bubbling = await volcano.page.waitFor((s) => s.game.bubbles > 0, 5000, 50);
t.check(
  'Map set to Volcano gives a volcano: a glowing red sky, grey ash over black basalt, and bubbles on the lava (tmp/journey/volcano.png)',
  volcano.ready?.game?.biome === 'volcano' && volcanoColours.sky > 0.1 && volcanoColours.ash > 0.002 && volcanoColours.basalt > 0.02 && volcanoColours.blue < 0.01 && bubbling !== null,
  JSON.stringify({ biome: volcano.ready?.game?.biome, colours: volcanoColours, bubbles: bubbling?.game?.bubbles }),
);
await volcano.page.close();
const largest = await biomeGame([['map_cycle', 2], ['teams_plus', 4], ['cats_plus', 2]], 4);
t.check(
  'at CPU ×4, the texture of the materials of the largest map (1024 px) is painted once, at the start, in under a second',
  largest.ready?.game?.paint_ms > 0 && largest.ready.game.paint_ms < 1000 && errorsOf(largest.ready).length === 0,
  JSON.stringify({ paint_ms: largest.ready?.game?.paint_ms, cats: largest.ready?.game?.sim?.cats?.length }),
);
await largest.page.close();

t.section('tranche 24h — at the volcano, the lava rises at the end of every round and the drawn lava follows it (§5.3, §7.4)');
const LAVA_SEED = 6;
const lavaPage = await openPage(browser, { url: `${BASE}&seed=${LAVA_SEED}`, touch: false });
await launch(lavaPage, [['teams_minus', 2], ['cats_minus', 2], ['bots_cycle', 2], ['map_cycle', 2]]);
const lava = { start: null, lowest: null, followed: false, between: false, drawn: true, biome: null, samples: 0 };
const lavaUntil = Date.now() + 9 * 60 * 1000;
while (Date.now() < lavaUntil && !lava.followed) {
  const g = (await lavaPage.state())?.game;
  if (g && g.liquid !== undefined) {
    lava.samples += 1;
    lava.biome = g.biome;
    lava.start ??= g.liquid;
    lava.lowest = Math.min(lava.lowest ?? g.liquid, g.liquid);
    if (g.liquid < lava.start && Math.abs(g.liquid_shown - g.liquid) < 0.05) lava.followed = true;
    if (g.liquid_shown > g.liquid + 0.05 && g.liquid_shown < g.liquid + 2) lava.between = true;
    if (Math.abs(g.liquid_y - (g.liquid_start - g.liquid_shown)) > 0.01 || Math.abs(g.fog_top - (g.height - g.liquid_shown)) > 0.01) lava.drawn = false;
  }
  await sleep(100);
}
const lavaEnd = await lavaPage.state();
t.check(
  'the lava rises 2 px after the first round, and the drawn lava, its fog and its bubbles climb to it smoothly',
  lava.biome === 'volcano' && lava.lowest === lava.start - 2 && lava.followed && lava.between && lava.drawn && lavaEnd?.game?.divergences === 0 && errorsOf(lavaEnd).length === 0,
  JSON.stringify(lava),
);
await lavaPage.close();

browser.ws.close();
process.exit(t.failed === 0 ? 0 : 1);
