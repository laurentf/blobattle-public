import { connect, css, newContext, openPage, pick, reporter, sleep, sling } from './lib.mjs';
import { share } from './png.mjs';

const ORIGIN = process.env.JOURNEY_ORIGIN || 'http://127.0.0.1:5373';
const BASE = `${ORIGIN}/?test=1`;
const INK = [41, 33, 51];
const t = reporter();
const browser = await connect();

const errorsOf = (s) => Object.keys(s?.errors || {});
const list = (value) => (Array.isArray(value) ? value : []);

async function player(nickname, team, url = BASE) {
  const context = await newContext(browser);
  const page = await openPage(browser, { url, context });
  page.context = context;
  page.nickname = nickname;
  page.team = team;
  const home = await page.waitFor((s) => s.screen === 'home' && s.profile && s.targets?.home?.nickname, 90000);
  if (home?.profile?.fresh) {
    await page.type('home', 'nickname', nickname);
    await page.type('home', 'team', team);
    await page.waitFor((s) => s.profile.nickname === nickname && s.profile.team_name === team, 5000);
  }
  return page;
}

const SOCKETS = `(() => {
  const Native = window.WebSocket;
  window.__sockets = [];
  window.WebSocket = function (...args) {
    const socket = new Native(...args);
    window.__sockets.push(socket);
    return socket;
  };
  window.WebSocket.prototype = Native.prototype;
  Object.assign(window.WebSocket, { CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 });
})();`;

async function reopen(page, url, init) {
  const again = await openPage(browser, { url, context: page.context, init });
  again.context = page.context;
  again.nickname = page.nickname;
  again.team = page.team;
  return again;
}

async function toMulti(page) {
  await page.press('home', 'multi');
  return page.waitFor((s) => s.screen === 'multi' && s.targets?.multi?.create, 10000);
}

const inRoom = (code) => (s) => s.screen === 'room' && s.room?.code === code && s.room.seats?.length > 0;

function seatsOf(s) {
  return list(s?.room?.seats).map((seat) => seat && `${seat.team}|${seat.player}${seat.mine ? '|me' : ''}`);
}

t.section('tranche 25 — Multi: create a room, open its link, join it by its code (§6.1, §6.2, §7.2)');
const ann = await player('Ann', 'Gel Gang');
const multi = await toMulti(ann);
t.check('Home leads to Multi, with Create, a code field, Join and Back', multi !== null && ['create', 'code', 'join', 'back'].every((b) => multi.targets.multi[b]), JSON.stringify(multi?.targets?.multi));
await ann.press('multi', 'create');
const created = await ann.waitFor((s) => s.screen === 'room' && /^[A-HJ-NP-Z]{5}$/.test(s.room?.code ?? '') && s.room.seats?.length > 0, 20000);
const code = created?.room?.code;
t.check('Create opens the Salon of a new room, under a 5-letter code, its creator the host', created !== null && created.room.host === true && created.net?.status === 'joined', JSON.stringify({ room: created?.room, net: created?.net }));
const annShot = await ann.shot('tmp/journey/room-host.png');
t.check('the Salon is drawn (tmp/journey/room-host.png)', created !== null && share(annShot, INK, 20) > 0.004);
if (!code) {
  browser.ws.close();
  process.exit(1);
}

const bob = await player('Bob', 'Blob Squad', `${BASE}&room=${code}`);
const bobMulti = await toMulti(bob);
t.check('a first launch through the room link asks for a nickname and a team first, then Multi offers the link\'s code', bobMulti?.multi?.code === code, JSON.stringify(bobMulti?.multi));
await bob.press('multi', 'join');
const bobIn = await bob.waitFor(inRoom(code), 20000);
t.check('the room link leads into the same Salon', bobIn !== null, JSON.stringify(bobIn?.room ?? bobIn?.multi));

await bob.close();
const bobAgain = await reopen(bob, `${BASE}&room=${code}`);
const direct = await bobAgain.waitFor(inRoom(code), 60000);
t.check('with a profile already made, the room link opens the Salon right after the intro', direct !== null && direct.room.seats.filter((s) => s?.mine).length === 1, JSON.stringify(direct?.room));

const cid = await player('Cid', 'Jelly Crew');
await toMulti(cid);
await cid.type('multi', 'code', code.toLowerCase());
await cid.press('multi', 'join');
const cidIn = await cid.waitFor(inRoom(code), 20000);
t.check('Join with the code typed in the field leads into the same Salon', cidIn !== null, JSON.stringify(cidIn?.multi));

const expected = [`Gel Gang|Ann (host)`, `Blob Squad|Bob`, `Jelly Crew|Cid`, 'Open|'];
const views = [];
for (const [page, seat] of [[ann, 0], [bobAgain, 1], [cid, 2]]) {
  const s = await page.waitFor((st) => inRoom(code)(st) && st.room.seats.filter(Boolean).length === 4 && st.room.seats[2]?.team === 'Jelly Crew', 10000);
  const seats = seatsOf(s).map((v) => v?.replace('|me', ''));
  views.push({ seats, mine: seatsOf(s)[seat]?.endsWith('|me') });
}
t.check(
  'the three contexts see the same Salon: each seat under its team name and nickname, the host marked, each its own seat',
  views.every((v) => JSON.stringify(v.seats.slice(0, 4)) === JSON.stringify(expected) && v.mine),
  JSON.stringify(views),
);

await ann.press('room', 'share');
const shared = await ann.waitFor((s) => s.room?.shared, 5000);
t.check('Share gives the room link', shared?.room?.shared === `${ORIGIN}/?room=${code}`, shared?.room?.shared);

await cid.press('room', 'leave');
const left = await cid.waitFor((s) => s.screen === 'multi', 5000);
const freed = await ann.waitFor((s) => s.room?.seats?.[2]?.team === 'Open', 5000);
t.check('Leave goes back to Multi, and the seat is open again for the others', left !== null && freed !== null, JSON.stringify(freed?.room?.seats));

await cid.type('multi', 'code', 'ZZZZZ');
await cid.press('multi', 'join');
const unknown = await cid.waitFor((s) => s.screen === 'multi' && s.multi?.reason, 20000);
t.check('an unknown code says so on Multi', unknown?.multi?.reason === 'room_not_found' && unknown.multi.shown === 'No room with this code', JSON.stringify(unknown?.multi));

for (const [name, page] of [['Ann', ann], ['Bob', bobAgain], ['Cid', cid]]) {
  t.check(`no Lua error for ${name}`, errorsOf(await page.state()).length === 0, JSON.stringify((await page.state())?.errors));
}
await cid.close();
await sleep(100);

t.section('tranche 26 — the host sets the game up, and both contexts see the same game, tick for tick (§6.3–6.6, D-03)');
const bob2 = bobAgain;
const presses = [['teams_minus', 1], ['cats_minus', 2], ['turn_cycle', 1], ['map_cycle', 1], ['bots_cycle', 1], ['seat_3', 1]];
for (const [button, times] of presses) {
  for (let i = 0; i < times; i += 1) {
    await ann.press('room', button);
    await sleep(250);
  }
}
await bob2.press('room', 'teams_plus');
const WANTED = { teams: 3, cats_per_team: 2, turn_seconds: 60, map: 'forest', bot_level: 'hard' };
const sameSettings = (s) => s?.room?.settings && Object.entries(WANTED).every(([k, v]) => s.room.settings[k] === v);
const setUp = await bob2.waitFor((s) => sameSettings(s) && s.room.seats.length === 3 && s.room.seats[2]?.team === 'Bot', 10000);
t.check('the host sets teams, blobs, turn time, map, bot level and a Bot seat; the guest sees it all and cannot change it', setUp !== null && !setUp.room.host, JSON.stringify(setUp?.room ?? (await bob2.state())?.room));
const guestView = await bob2.state();
t.check('the guest has no Launch button, and is told the host launches', !guestView.targets?.room?.launch && guestView.room?.said === 'The host launches the game', JSON.stringify({ targets: guestView.targets?.room, said: guestView.room?.said }));

await ann.press('room', 'launch');
const inGame = await Promise.all([ann, bob2].map((p) => p.waitFor((s) => s.screen === 'game' && s.game?.sim?.cats?.length === 6, 60000)));
t.check(
  'Launch takes both contexts into the game, with a team each and the Bot seat played by a bot',
  inGame.every(Boolean) && inGame[0].game.me === 1 && inGame[1].game.me === 2 && inGame.every((s) => JSON.stringify(s.game.kinds) === JSON.stringify(['human', 'human', 'bot'])),
  JSON.stringify(inGame.map((s) => s && { me: s.game.me, kinds: s.game.kinds })),
);

async function hold(page, pad, ms) {
  const at = await page.target('hud', pad);
  if (!at) return;
  await page.touch('touchStart', [at]);
  await sleep(ms);
  await page.touch('touchEnd', []);
}

async function atEnemy(page) {
  const s = await page.state();
  const g = s.game;
  const enemy = g.hud.labels.find((l) => l.alive && l.team !== g.me && l.x !== undefined);
  let dx = 70;
  let dy = 70;
  if (enemy && g.blob) {
    const from = await css(page, g.blob);
    const to = await css(page, { x: enemy.x, y: enemy.y });
    const len = Math.hypot(to[0] - from[0], to[1] - from[1]) || 1;
    dx = ((from[0] - to[0]) / len) * 90;
    dy = ((from[1] - to[1]) / len) * 90 + 40;
  }
  await pick(page, 'grid_1');
  await sling(page, dx, dy);
}

const stillAiming = async (page) => {
  const g = (await page.state()).game;
  return g && g.team === g.me && g.state === 'aiming';
};

const misses = [];

async function use(page, who, cell, weapon, dx, dy) {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    if (!(await stillAiming(page))) return false;
    const counted = (st) => st.game?.trace?.counts?.[`fire:${weapon}`] ?? 0;
    const before = counted(await page.state());
    await pick(page, cell);
    const picked = await page.waitFor((st) => st.game?.weapon === weapon && !st.game.grid, 3000);
    await sleep(400);
    if (picked) await sling(page, dx, dy);
    const done = await page.waitFor((st) => counted(st) > before, 3000);
    if (done) return true;
    const st = (await page.state()).game;
    misses.push({ who, weapon, attempt, picked: Boolean(picked), shown: st?.weapon, grid: st?.grid, state: st?.state, blob: st?.blob });
  }
  return false;
}

const WANTED_COUNTS = ['walk', 'jump', 'fire:bazooka', 'fire:tentacle', 'fire:uppercut', 'fire:chomp', 'chomped', 'fired', 'exploded', 'damaged:explosion', 'face:angry', 'face:scared', 'died'];
const activeOf = (st) => st.game?.sim?.cats?.[st.game.sim.cat - 1];
const PLANS = [['tentacle', 'chomp', 'uppercut'], ['tentacle', 'uppercut', 'chomp']];
const MOVES = {
  tentacle: ['grid_3', 0, 90],
  uppercut: ['grid_4', -60, 30],
  chomp: ['grid_5', 0, -90],
};

async function playTurn(page, who, k) {
  const counts = (await page.state()).game?.trace?.counts ?? {};
  await hold(page, k % 2 ? 'right' : 'left', 250);
  if (!counts.jump) {
    await page.press('hud', 'jump');
    await page.waitFor((st) => activeOf(st)?.grounded, 3000);
  }
  for (const weapon of PLANS[who]) {
    if ((counts[`fire:${weapon}`] ?? 0) > 0) continue;
    const [cell, dx, dy] = MOVES[weapon];
    await use(page, who, cell, weapon, dx, dy);
    if (weapon !== 'tentacle') return;
    if (activeOf(await page.state())?.hanging) {
      await sleep(800);
      await page.press('hud', 'jump');
    }
    await page.waitFor((st) => !st.game || (activeOf(st)?.grounded && !activeOf(st)?.hanging), 5000);
  }
  if (!(await stillAiming(page))) return;
  const seenAll = WANTED_COUNTS.every((key) => key === 'died' || (counts[key] ?? 0) > 0);
  if (seenAll) {
    await pick(page, 'grid_1');
    await sling(page, 0, -90);
  } else {
    await atEnemy(page);
  }
}

const players = [ann, bob2];
const turns = [0, 0];
const seen = [new Map(), new Map()];
const played = { ahead: 0, samples: 0 };
const finished = [null, null];
const gameDeadline = Date.now() + 15 * 60 * 1000;
while (Date.now() < gameDeadline && finished.some((f) => f === null)) {
  for (let i = 0; i < 2; i += 1) {
    if (finished[i]) continue;
    const s = await players[i].state();
    for (const c of list(s.game?.trace?.checkpoints)) seen[i].set(c.tick, c.sum);
    if (s.screen === 'end') {
      finished[i] = s;
      continue;
    }
    const g = s.game;
    if (!g) continue;
    played.samples += 1;
    if (g.tick > g.confirmed) played.ahead += 1;
    if (g.team === g.me && g.state === 'aiming' && g.blob && s.targets?.hud?.weapon) {
      await playTurn(players[i], i, turns[i]);
      turns[i] += 1;
      await players[i].waitFor((st) => st.screen === 'end' || (st.game && (st.game.team !== st.game.me || st.game.state !== 'aiming')), 8000);
    }
  }
  await sleep(200);
}
const common = [...seen[0].keys()].filter((tick) => seen[1].has(tick));
const differ = common.filter((tick) => seen[0].get(tick) !== seen[1].get(tick));
const lastGames = finished.map((f) => f?.game);
const endTicks = lastGames.map((g) => g?.tick);
t.check('the game is played to its end in both contexts', finished.every(Boolean), JSON.stringify({ turns, screens: await Promise.all(players.map(async (p) => (await p.state()).screen)) }));
t.check(
  'every checkpoint both contexts traced (inputs, events, faces, positions) is the same, tick for tick',
  common.length >= 20 && differ.length === 0 && endTicks[0] === endTicks[1] && seen[0].get(endTicks[0]) !== undefined && seen[0].get(endTicks[0]) === seen[1].get(endTicks[1]),
  JSON.stringify({ common: common.length, differ: differ.slice(0, 5), a: seen[0].size, b: seen[1].size, end: endTicks }),
);
const counts = lastGames.map((g) => g?.trace?.counts ?? {});
const shown = WANTED_COUNTS.filter((k) => (counts[0][k] ?? 0) > 0);
const hurt = shown.length === WANTED_COUNTS.length;
t.check(
  'both saw the same walks, jumps, shots, punches, meals, tentacles, blasts that throw and hurt, angry and scared faces, and deaths',
  JSON.stringify(counts[0]) === JSON.stringify(counts[1]) && shown.length === WANTED_COUNTS.length && hurt,
  JSON.stringify({ counts, misses }),
);
t.check(
  'neither client went past the confirmed tick, nor diverged, and both checked every checksum',
  played.ahead === 0 && lastGames.every((g) => g && g.divergences === 0 && g.checked >= Math.floor(g.tick / 30) - 1 && g.tick === g.confirmed),
  JSON.stringify({ ahead: played.ahead, games: lastGames.map((g) => g && { tick: g.tick, checked: g.checked, divergences: g.divergences, restored: g.restored }) }),
);
const results = finished.map((f) => f?.result);
t.check(
  'both End screens name the same winner with the same damage and kills',
  results.every(Boolean) && JSON.stringify(results[0].stats) === JSON.stringify(results[1].stats) && results[0].winner === results[1].winner && results[0].shown.winner === results[1].shown.winner,
  JSON.stringify(results.map((r) => r && { winner: r.winner, stats: r.stats })),
);
t.check('on the End screen, Rematch is the host\'s', results[0]?.rematch === true && results[1]?.rematch === false, JSON.stringify(results.map((r) => r?.rematch)));
for (const [name, page] of [['Ann', ann], ['Bob', bob2]]) {
  t.check(`no Lua error for ${name} in the online game`, errorsOf(await page.state()).length === 0, JSON.stringify((await page.state())?.errors));
}

t.section('tranche 26b — each team line: letter, name, HP, and a bot icon when a bot plays it (§7.4, §6.4 pilots)');
const LETTERS = 'ABCDEFGH';
function linesOf(s) {
  return list(s?.game?.hud?.teams).map((l) => ({ team: l.team, name: l.name_shown, hp: l.shown, bot: l.bot_shown === true }));
}
function linesMatch(s) {
  const g = s?.game;
  if (!g?.sim || !g.hud?.teams?.length) return false;
  const hp = [];
  for (const c of g.sim.cats) hp[c.team - 1] = (hp[c.team - 1] ?? 0) + (c.alive ? c.hp : 0);
  return g.hud.teams.every((l, i) => l.shown === String(hp[i] ?? 0) && typeof l.name_shown === 'string' && l.name_shown.length > 0 && l.bot_shown === (g.pilots?.[i] === true));
}
const solo = await openPage(browser, { url: `${BASE}&seed=4242`, context: ann.context });
await solo.waitFor((s) => s.screen === 'home' && s.profile && !s.profile.fresh, 90000);
await solo.press('home', 'training');
await solo.waitFor((s) => s.screen === 'training' && s.targets?.training, 10000);
await solo.press('training', 'teams_minus');
await solo.press('training', 'launch');
const offline = await solo.waitFor((s) => s.screen === 'game' && linesMatch(s), 60000);
const offLines = linesOf(offline);
t.check(
  'offline, the player\'s line has no bot icon, the bots\' lines have one, each with its team name and HP',
  offline !== null && offLines.length === 3 && offLines[0].bot === false && offLines[0].name === 'Gel Gang' && offLines.slice(1).every((l) => l.bot) && offline.game.me === 1,
  JSON.stringify(offLines),
);
await solo.shot('tmp/journey/lines-offline.png');
await solo.close();

await ann.press('end', 'rematch');
const rematched = await Promise.all([ann, bob2].map((p) => p.waitFor((s) => s.screen === 'room' && s.room?.phase === 'lobby', 15000)));
t.check('the host\'s Rematch brings both contexts back to the same Salon', rematched.every(Boolean), JSON.stringify(rematched.map((s) => s?.room?.seats)));
await ann.press('room', 'launch');
const second = await Promise.all([ann, bob2].map((p) => p.waitFor((s) => s.screen === 'game' && linesMatch(s), 60000)));
const onLines = second.map(linesOf);
t.check(
  'online, both see every line with its letter\'s team name and HP, the bot icon on the Bot seat only',
  second.every(Boolean) && onLines.every((ls) => ls.length === 3 && ls[0].name === 'Gel Gang' && ls[1].name === 'Blob Squad' && !ls[0].bot && !ls[1].bot && ls[2].bot),
  JSON.stringify(onLines),
);
await ann.shot('tmp/journey/lines-online.png');

const bobTeam = second[1]?.game?.me;
const leftAt = Date.now();
await bob2.close();
const iconUp = await ann.waitFor((s) => linesOf(s)[bobTeam - 1]?.bot === true, 5000, 40);
const iconMs = Date.now() - leftAt;
t.check('when a context leaves, the other sees the bot icon on its team in under a second', iconUp !== null && iconMs < 1000, `${iconMs} ms`);
const firesOf = (st) => Object.entries(st?.game?.trace?.counts ?? {}).reduce((n, [k, v]) => (k.startsWith('fire:') ? n + v : n), 0);
let atTurnStart = null;
const botTurn = await ann.waitFor((st) => {
  const g = st.game;
  if (!g || g.team !== bobTeam) {
    atTurnStart = null;
    return false;
  }
  if (atTurnStart === null && (g.state === 'turn_start' || g.state === 'aiming')) atTurnStart = firesOf(st);
  return atTurnStart !== null && firesOf(st) > atTurnStart && linesOf(st)[bobTeam - 1]?.bot;
}, 120000, 100);
t.check('and the bot plays that team\'s turn: it shoots during it', botTurn !== null && linesMatch(botTurn), JSON.stringify({ state: botTurn?.game?.state, team: botTurn?.game?.team, fires: firesOf(botTurn), before: atTurnStart }));

t.section('tranche 27 — back in the game: the room link, a snapshot, the team handed back at its next turn (§6.6, §6.7)');
async function settled(page, from) {
  const later = await page.waitFor((st) => st.game && st.game.checked >= from.game.checked + 2, 10000, 100);
  return later ?? (await page.state());
}
const comingBack = Date.now();
const bob3 = await reopen(bob2, `${BASE}&room=${code}`, SOCKETS);
const back = await bob3.waitFor((s) => s.screen === 'game' && s.game?.restored >= 1 && s.game.me === bobTeam && linesMatch(s), 120000, 100);
const backSeconds = (Date.now() - comingBack) / 1000;
const annAtBack = await ann.state();
const backLater = back && (await settled(bob3, back));
t.check(
  'the room link brings the context back into the game in progress, set right by a snapshot, its team still shown as the bot\'s',
  back !== null && back.game.tick >= botTurn.game.tick && linesOf(back)[bobTeam - 1]?.bot === true && backLater.game.divergences === 0 && backLater.game.checked >= back.game.checked + 2,
  JSON.stringify({ seconds: backSeconds, net: back?.net, restored: back?.game?.restored, checked: [back?.game?.checked, backLater?.game?.checked], divergences: backLater?.game?.divergences }),
);
const handed = await Promise.all([ann, bob3].map((p) => p.waitFor((s) => linesOf(s)[bobTeam - 1]?.bot === false, 120000, 100)));
t.check(
  'at the first turn start after the return, the team is handed back, and its bot icon goes away for both',
  handed.every(Boolean) && handed[0].game.turns <= annAtBack.game.turns + 1,
  JSON.stringify({ turnsAtBack: annAtBack.game.turns, turnsHanded: handed.map((s) => s?.game?.turns), lines: handed.map((s) => s && linesOf(s)) }),
);
const bobAiming = await bob3.waitFor((s) => s.game?.team === s.game?.me && s.game.state === 'aiming' && s.targets?.hud?.left, 180000);
const walksBefore = (await ann.state()).game.trace.counts.walk ?? 0;
if (bobAiming) await hold(bob3, 'right', 700);
const annSaw = await ann.waitFor((s) => (s.game?.trace?.counts?.walk ?? 0) > walksBefore, 5000);
t.check(
  'on its team\'s next turn, the returning player plays again: the other context sees its blob walk',
  bobAiming !== null && annSaw !== null && bobAiming.game.turns - handed[1].game.turns <= bobAiming.game.sim.cats.length,
  JSON.stringify({ walksBefore, after: annSaw?.game?.trace?.counts?.walk, turns: [handed[1]?.game?.turns, bobAiming?.game?.turns] }),
);

const cut = await bob3.eval('window.__sockets.filter((w) => w.readyState === 1).length');
const cutAt = Date.now();
await bob3.eval('window.__sockets.forEach((w) => w.close()), 1');
const rejoinedAt = await bob3.waitFor((s) => s.net?.rejoins >= 1 && s.game?.restored >= 2, 30000, 100);
const rejoinSeconds = (Date.now() - cutAt) / 1000;
const rejoined = rejoinedAt && (await settled(bob3, rejoinedAt));
t.check(
  'a socket that drops in the middle of a game comes back by itself, set right by a snapshot, without a divergence',
  cut >= 1 && rejoinedAt !== null && rejoined.game.divergences === 0 && rejoined.game.checked >= rejoinedAt.game.checked + 2 && rejoined.screen === 'game' && rejoined.net.game === rejoinedAt.net.game,
  JSON.stringify({ open: cut, seconds: rejoinSeconds, net: rejoined?.net, screen: rejoined?.screen, game: rejoined?.game && { tick: rejoined.game.tick, confirmed: rejoined.game.confirmed, restored: rejoined.game.restored, rejected: rejoined.game.rejected, divergences: rejoined.game.divergences, resync: rejoined.game.resync } }),
);
const nets = await Promise.all([ann, bob3].map(async (p) => (await p.state()).net));
console.log(`📏 back through the link in ${backSeconds.toFixed(1)} s; socket back in ${rejoinSeconds.toFixed(1)} s (link ${rejoined?.net?.rejoined_s?.toFixed?.(2)} s); snapshot ${rejoined?.net?.snapshot_bytes} bytes; input round trip ${nets.map((n) => `${Math.round(n?.rtt_avg_ms ?? -1)} ms avg over ${n?.rtt_n ?? 0}`).join(', ')}`);
const finals = await Promise.all([ann, bob3].map((p) => p.state()));
t.check(
  'at the end, neither context has diverged, nor gone past its confirmed tick',
  finals.every((s) => s?.game && s.game.divergences === 0 && s.game.tick <= s.game.confirmed && s.game.checked > 0),
  JSON.stringify(finals.map((s) => s && { tick: s.game.tick, confirmed: s.game.confirmed, checked: s.game.checked, divergences: s.game.divergences })),
);
for (const [name, page] of [['Ann', ann], ['Bob', bob3]]) {
  t.check(`no Lua error for ${name} after the return`, errorsOf(await page.state()).length === 0, JSON.stringify((await page.state())?.errors));
}

t.section('closing review — Multi and the Salon at 390×844 and 667×375, and the largest snapshot through the Defold client (V0 §2, H-06)');
async function targetsFit(page, screen) {
  const s = await page.state();
  const ratio = await page.eval('window.devicePixelRatio');
  const width = await page.eval('window.innerWidth');
  const height = await page.eval('window.innerHeight');
  const rects = Object.entries(s.targets?.[screen] ?? {}).map(([name, r]) => ({ name, x: r.x / ratio, y: r.y / ratio, w: r.w / ratio, h: r.h / ratio }));
  const small = rects.filter((r) => r.w < 44 || r.h < 44).map((r) => `${r.name} ${r.w.toFixed(1)}×${r.h.toFixed(1)}`);
  const out = rects.filter((r) => r.x - r.w / 2 < 0 || r.x + r.w / 2 > width || r.y - r.h / 2 < 0 || r.y + r.h / 2 > height).map((r) => r.name);
  const overlap = [];
  for (let i = 0; i < rects.length; i += 1) {
    for (let j = i + 1; j < rects.length; j += 1) {
      const [a, b] = [rects[i], rects[j]];
      if (Math.abs(a.x - b.x) < (a.w + b.w) / 2 && Math.abs(a.y - b.y) < (a.h + b.h) / 2) overlap.push(`${a.name}/${b.name}`);
    }
  }
  return { count: rects.length, small, out, overlap };
}
const fits = (r, least) => r.count >= least && r.small.length === 0 && r.out.length === 0 && r.overlap.length === 0;
const dee = await player('Dee', 'Big Brawl');
await toMulti(dee);
const sizes = {};
for (const [width, height] of [[390, 844], [667, 375]]) {
  await dee.resize(width, height);
  await sleep(1200);
  sizes[`multi ${width}`] = await targetsFit(dee, 'multi');
  await dee.shot(`tmp/journey/multi-${width}.png`);
}
await dee.resize(844, 390);
await sleep(800);
await dee.press('multi', 'create');
const bigRoom = await dee.waitFor((s) => s.screen === 'room' && s.room?.host === true, 20000);
for (let i = 0; i < 4; i += 1) {
  await dee.press('room', 'teams_plus');
  await sleep(250);
}
for (let i = 0; i < 2; i += 1) {
  await dee.press('room', 'cats_plus');
  await sleep(250);
}
const eight = await dee.waitFor((s) => s.room?.settings?.teams === 8 && s.room.settings.cats_per_team === 6 && s.room.seats.length === 8, 10000);
for (const [width, height] of [[390, 844], [667, 375]]) {
  await dee.resize(width, height);
  await sleep(1200);
  sizes[`room ${width}`] = await targetsFit(dee, 'room');
  await dee.shot(`tmp/journey/room-${width}.png`);
}
await dee.resize(844, 390);
await sleep(800);
t.check(
  'at 390×844 and 667×375, every target of Multi and of the Salon with its 8 seats is 44 points or more, on screen and apart from the others (tmp/journey/multi-*.png, room-*.png)',
  bigRoom !== null && eight !== null && fits(sizes['multi 390'], 4) && fits(sizes['multi 667'], 4) && fits(sizes['room 390'], 16) && fits(sizes['room 667'], 16),
  JSON.stringify(sizes),
);
const bigCode = bigRoom?.room?.code;
await dee.press('room', 'launch');
const bigGame = await dee.waitFor((s) => s.screen === 'game' && s.game?.sim?.cats?.length === 48, 90000);
await dee.waitFor((s) => s.game && s.game.tick > 900, 120000, 500);
await dee.close();
const deeBack = await reopen(dee, `${BASE}&room=${bigCode}`);
const bigBack = await deeBack.waitFor((s) => s.screen === 'game' && s.game?.restored >= 1 && s.game.sim?.cats?.length === 48, 120000, 200);
const bigLater = bigBack && (await deeBack.waitFor((st) => st.game && st.game.checked >= bigBack.game.checked + 2, 15000, 200));
t.check(
  'the snapshot of a game of 8 teams of 6 reaches the Defold client in one message and sets it right (H-06)',
  bigGame !== null && bigBack !== null && bigLater !== null && bigLater.game.divergences === 0 && bigBack.net?.snapshot_bytes > 12000,
  JSON.stringify({ bytes: bigBack?.net?.snapshot_bytes, tick: bigBack?.game?.tick, checked: bigLater?.game?.checked, divergences: bigLater?.game?.divergences }),
);
console.log(`📏 snapshot of 8 teams of 6 received by the Defold client: ${bigBack?.net?.snapshot_bytes} bytes at tick ${bigBack?.game?.tick}`);
t.check('no Lua error for Dee', errorsOf(await deeBack.state()).length === 0, JSON.stringify((await deeBack.state())?.errors));
await deeBack.close();

browser.ws.close();
process.exit(t.failed === 0 ? 0 : 1);
