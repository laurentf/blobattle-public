import { connect, newContext, openPage, reporter, sleep } from './lib.mjs';

const BASE = 'http://127.0.0.1:5373/?test=1';
const SEED = 376;
const COMMANDS = ['left', 'right', 'aim_up', 'aim_down', 'fire', 'jump', 'fuse', 'weapon_1', 'weapon_2', 'weapon_3', 'weapon_4', 'weapon_5', 'weapon_6', 'weapon_7', 'weapon_8', 'weapon_9', 'weapon_10'];
const X = ['x', 'KeyX', 88];
const ESCAPE = ['Escape', 'Escape', 27];
const SPACE = [' ', 'Space', 32];
const AZERTY_M = ['m', 'Semicolon', 77];
const t = reporter();
const browser = await connect();

const errorsOf = (s) => Object.keys(s?.errors || {});

async function hit(page, [key, code, keyCode], hold = 80) {
  await page.key('keyDown', key, code, keyCode);
  await sleep(hold);
  await page.key('keyUp', key, code, keyCode);
  await sleep(120);
}

async function home(page) {
  const shown = await page.waitFor((s) => s.screen === 'home' && s.profile && s.targets?.home?.nickname, 90000);
  if (shown?.profile?.fresh) {
    await page.type('home', 'nickname', 'Keys');
    await page.type('home', 'team', 'Rebinders');
    await page.waitFor((s) => s.profile.nickname === 'Keys', 5000);
  }
  return page.state();
}

async function choose(page, command, key) {
  await page.press('keys', command);
  const waiting = await page.waitFor((s) => s.keys?.waiting === command, 3000, 50);
  await hit(page, key);
  return { waiting, after: await page.waitFor((s) => !s.keys.waiting, 3000, 50) };
}

function laidOut(s, width, height) {
  const boxes = Object.entries(s?.targets?.keys ?? {}).map(([name, b]) => ({ name, x0: b.x - b.w / 2, x1: b.x + b.w / 2, y0: b.y - b.h / 2, y1: b.y + b.h / 2 }));
  const ratio = s?.ratio ?? 1;
  const inside = boxes.every((b) => b.x0 >= 0 && b.y0 >= 0 && b.x1 <= width * ratio + 1 && b.y1 <= height * ratio + 1);
  const overlaps = [];
  for (let i = 0; i < boxes.length; i += 1) {
    for (let j = i + 1; j < boxes.length; j += 1) {
      const [a, b] = [boxes[i], boxes[j]];
      if (a.x0 < b.x1 && b.x0 < a.x1 && a.y0 < b.y1 && b.y0 < a.y1) overlaps.push(`${a.name}/${b.name}`);
    }
  }
  const lowest = Math.min(...boxes.map((b) => (b.y1 - b.y0) / ratio));
  return { count: boxes.length, inside, overlaps, lowest: Math.round(lowest) };
}

async function geometry(page, width, height) {
  const s = await page.state();
  const ratio = await page.eval('window.devicePixelRatio');
  return laidOut({ ...s, ratio }, width, height);
}

t.section('tranche 24v — the Keys screen: each command on a key of one\'s choice, kept on the device across a reload, and played in a game (§7.2, §7.3)');
const context = await newContext(browser);
const desk = await openPage(browser, { url: `${BASE}&seed=${SEED}`, touch: false, context });
const first = await home(desk);
await sleep(600);
await desk.shot('tmp/journey/home-keys.png');
t.check('on a computer, Home shows a Keys button, bottom right after Multi (tmp/journey/home-keys.png)', Boolean(first?.targets?.home?.keys), JSON.stringify(Object.keys(first?.targets?.home ?? {})));

await desk.press('home', 'keys');
const opened = await desk.waitFor((s) => s.screen === 'keys' && s.keys && s.targets?.keys?.fire, 5000);
await sleep(300);
await desk.shot('tmp/journey/keys.png');
const shown = opened?.keys?.shown ?? {};
t.check(
  'Keys lists the seventeen commands with the keys of the spec: Fire on Space, Jump on Enter, ← → ↑ ↓, F, and 1 to 9 and 0 for the weapons (tmp/journey/keys.png)',
  COMMANDS.every((c) => shown[c]) && shown.fire === 'Space' && shown.jump === 'Enter' && shown.left === 'Left' && shown.aim_up === 'Up' && shown.fuse === 'F' && shown.weapon_1 === '1' && shown.weapon_9 === '9' && shown.weapon_10 === '0',
  JSON.stringify(shown),
);
const wide = await geometry(desk, 844, 390);
t.check('at 844×390, in four columns, its nineteen buttons sit inside the screen, none covers another, and each is at least 56 points high, 44 on a 667×375 phone (D-10)', wide.count === 19 && wide.inside && wide.overlaps.length === 0 && wide.lowest >= 56, JSON.stringify(wide));

await desk.press('keys', 'jump');
const waitingJump = await desk.waitFor((s) => s.keys.waiting === 'jump', 3000, 50);
await hit(desk, ESCAPE);
const cancelled = await desk.waitFor((s) => s.screen === 'keys' && !s.keys.waiting, 3000, 50);
t.check(
  'a click on a key asks for one ("Press a key"), and Escape cancels, leaving it as it was',
  waitingJump?.keys?.shown?.jump === 'Press a key' && cancelled?.keys?.shown?.jump === 'Enter',
  JSON.stringify({ waiting: waitingJump?.keys, cancelled: cancelled?.keys?.shown?.jump }),
);

const toX = await choose(desk, 'fire', X);
t.check('Fire passes to X', toX.waiting !== null && toX.after?.keys?.shown?.fire === 'X', JSON.stringify(toX.after?.keys?.shown));
const swap = await choose(desk, 'jump', X);
const swapped = swap.after?.keys?.shown;
const back = await choose(desk, 'fire', X);
const restored = back.after?.keys?.shown;
t.check(
  'a key already taken swaps: Jump on X gives Fire the Enter of Jump, and back',
  swapped?.jump === 'X' && swapped?.fire === 'Enter' && restored?.fire === 'X' && restored?.jump === 'Enter',
  JSON.stringify({ swapped, restored }),
);
const azerty = await choose(desk, 'fuse', AZERTY_M);
t.check(
  'the M of an AZERTY keyboard, which Defold reads as ";", shows as M',
  azerty.after?.keys?.shown?.fuse === 'M',
  JSON.stringify(azerty.after?.keys?.shown),
);

await desk.resize(390, 844);
await desk.waitFor((s) => s.targets?.keys?.fire && Math.abs(s.targets.keys.weapon_1.x - s.targets.keys.fire.x) < 5, 5000);
await sleep(400);
await desk.shot('tmp/journey/keys-portrait.png');
const tall = await geometry(desk, 390, 844);
await desk.resize(844, 390);
await sleep(400);
t.check('at 390×844 portrait, on two columns, the nineteen buttons sit inside the screen, none covers another, and each is at least 44 points high (tmp/journey/keys-portrait.png)', tall.count === 19 && tall.inside && tall.overlaps.length === 0 && tall.lowest >= 44, JSON.stringify(tall));

await hit(desk, ESCAPE);
const left = await desk.waitFor((s) => s.screen === 'home', 3000, 50);
t.check('Escape on Keys goes back to Home', left !== null);

await desk.s('Page.reload', {});
await sleep(1000);
await desk.waitFor((s) => s.screen === 'intro', 30000);
await hit(desk, SPACE);
const again = await home(desk);
await desk.press('home', 'keys');
const kept = await desk.waitFor((s) => s.screen === 'keys' && s.keys?.shown?.fire, 5000);
t.check(
  'after a reload of the page, Space still skips the intro, and the keys are the ones chosen: Fire on X, the fuse on M, Jump on Enter',
  again !== null && kept?.keys?.shown?.fire === 'X' && kept.keys.shown.fuse === 'M' && kept.keys.shown.jump === 'Enter',
  JSON.stringify(kept?.keys?.shown),
);

await desk.press('keys', 'back');
await desk.waitFor((s) => s.screen === 'home', 3000, 50);
await desk.press('home', 'training');
await desk.waitFor((s) => s.screen === 'training' && s.targets?.training, 10000);
for (let i = 0; i < 2; i += 1) await desk.press('training', 'teams_minus');
await desk.press('training', 'map_cycle');
await desk.press('training', 'launch');
await desk.waitFor((s) => s.screen === 'game' && s.game, 30000);
const turn = await desk.waitFor((s) => s.game && s.game.team === s.game.me && s.game.state === 'aiming' && s.game.blob, 120000);
await desk.mouse('mousePressed', 5, 5);
await desk.mouse('mouseReleased', 5, 5);
await desk.key('keyDown', ...SPACE);
await sleep(600);
const space = await desk.state();
await desk.key('keyUp', ...SPACE);
await sleep(300);
await desk.key('keyDown', ...X);
const charging = await desk.waitFor((s) => s.game.aim?.charging === true && s.game.aim.power > 10, 2000, 50);
await desk.key('keyUp', ...X);
const fired = await desk.waitFor((s) => s.game.team === s.game.me && s.game.state === 'flight', 3000, 50);
const end = await desk.state();
t.check(
  'in a game, Space no longer charges nor fires, and X charges and fires',
  turn !== null && space.game.state === 'aiming' && space.game.aim?.charging !== true && charging !== null && fired !== null && end.game.divergences === 0 && errorsOf(end).length === 0,
  JSON.stringify({ space: { state: space.game.state, aim: space.game.aim }, charging: charging?.game?.aim, fired: fired !== null, divergences: end.game.divergences, errors: end.errors }),
);
await desk.close();

const phone = await openPage(browser, { url: BASE, context: await newContext(browser) });
const onPhone = await home(phone);
t.check('on a touch phone, Home has no Keys button', onPhone !== null && !onPhone.targets.home.keys, JSON.stringify(Object.keys(onPhone?.targets?.home ?? {})));
await phone.close();

browser.ws.close();
process.exit(t.failed === 0 ? 0 : 1);
