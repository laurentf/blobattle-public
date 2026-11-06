import { AIMING_TICK, OP, arrive, connect, join, openRoom, send, sleep, stream, untilTick, waitFor } from '../lib.mjs';

export const title = 'tranche 17 — snapshot, reconnection, absence played by a bot (§6.6, §6.7, D-08)';

async function whoIsActive(host, guest, teamOf) {
  const marks = [host.inbox.length, guest.inbox.length];
  await Promise.all([host, guest].map((p) => send(p, OP.input, { kind: 'move', direction: 0 })));
  const refused = await Promise.all(
    [host, guest].map((p, i) => waitFor(p, OP.refused, () => true, 1500, marks[i])),
  );
  const index = refused.findIndex((r) => r === null);
  if (index < 0 || refused[1 - index]?.code !== 'not_your_turn') return null;
  const active = [host, guest][index];
  return { active, other: [host, guest][1 - index], team: teamOf[active.session.user_id] };
}

export async function run(t) {
  const { host, code } = await openRoom('Away Host');
  const guest = await arrive('Away Guest', code);
  await send(host, OP.lobby_settings, { teams: 2, cats_per_team: 1, seed: 4 });
  await waitFor(guest, OP.lobby_state, (s) => s.seats?.length === 2 && s.seed === 4);
  await send(host, OP.start, {});
  const started = await waitFor(guest, OP.game_start);
  const teamOf = Object.fromEntries((started?.roster ?? []).map((r) => [r.user, r.team]));
  await untilTick(guest, AIMING_TICK);

  const turn = await whoIsActive(host, guest, teamOf);
  t.check('one human is active, the other is refused', turn !== null);
  if (turn === null) return;
  const { active: away, other, team } = turn;

  const leftAt = stream(other).last;
  away.socket.disconnect(false);
  const botPlayed = await waitFor(
    other,
    OP.ticks,
    (m) => (Array.isArray(m.inputs) ? m.inputs : []).some((e) => e.input.team === team && ['fire', 'skip'].includes(e.input.kind)),
    20000,
  );
  t.check('a bot plays the turn of the human who left', botPlayed !== null, `left at tick ${leftAt}`);

  away.inbox = [];
  await connect(away);
  const current = stream(other).last;
  const rejoined = await join(away, away.matchId);
  t.check('the same account joins the game in progress again', rejoined.ok, JSON.stringify(rejoined.error));
  const snapshot = await waitFor(away, OP.snapshot, () => true, 5000);
  t.check(
    'it receives a snapshot of the world at the current tick',
    snapshot !== null && snapshot.tick >= current && snapshot.tick <= stream(other).last + 2 && snapshot.state?.version === 11 && Array.isArray(snapshot.state?.cats),
    `tick ${snapshot?.tick} (stream at ${current}), ${JSON.stringify(snapshot ?? {}).length} bytes`,
  );
  const early = away.inbox.length;
  await send(away, OP.input, { kind: 'move', direction: 1 });
  const held = await waitFor(away, OP.refused, () => true, 2000, early);
  t.check('back during the bot turn, the human is refused until the next turn starts', held?.code === 'not_your_turn', JSON.stringify(held));

  let back = null;
  const deadline = Date.now() + 60000;
  while (back === null && Date.now() < deadline) {
    const mark = stream(other).ticks.length;
    await send(away, OP.input, { kind: 'move', direction: 0 });
    await send(other, OP.skip, {});
    await sleep(400);
    back = stream(other).ticks.slice(mark).flatMap((m) => (Array.isArray(m.inputs) ? m.inputs : [])).find((e) => e.input.team === team && e.input.kind === 'move') ?? null;
  }
  t.check('the human takes back control on a later turn', back !== null && back.at > (botPlayed?.to ?? Infinity), JSON.stringify(back));

  away.socket.disconnect(false);
  other.socket.disconnect(false);
}
