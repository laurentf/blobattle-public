import { AIMING_TICK, OP, arrive, openRoom, send, stream, untilTick, waitFor } from '../lib.mjs';

export const title = 'tranche 16 — the game: start, ticks clock, checksum, validation (§6.5, §6.8)';

export async function run(t) {
  const { host, code } = await openRoom('Game Host');
  const guest = await arrive('Game Guest', code);
  await send(host, OP.lobby_settings, { teams: 2, cats_per_team: 1, seed: 4 });
  await waitFor(guest, OP.lobby_state, (s) => s.seats?.length === 2 && s.seed === 4);
  await send(host, OP.start, {});

  const started = await waitFor(guest, OP.game_start);
  t.check('the guest receives game_start with the seed and both humans', started?.seed === 4 && started.roster?.filter((r) => r.kind === 'human').length === 2, JSON.stringify(started?.roster));
  const teamOf = Object.fromEntries((started?.roster ?? []).map((r) => [r.user, r.team]));

  await untilTick(guest, AIMING_TICK);
  const shot = { weapon: 'bazooka', angle: 300, power: 60 };
  await Promise.all([send(host, OP.fire, shot), send(guest, OP.fire, shot)]);
  const refusals = await Promise.all([host, guest].map((p) => waitFor(p, OP.refused, () => true, 3000)));
  const idleIndex = refusals.findIndex((r) => r?.code === 'not_your_turn');
  t.check('exactly one of the two humans is refused with not_your_turn', idleIndex >= 0 && refusals.filter((r) => r !== null).length === 1, JSON.stringify(refusals));
  const idle = [host, guest][idleIndex] ?? host;
  const idleTeam = teamOf[idle.session.user_id];

  await untilTick(guest, 200);
  const { ticks, sums, inputs } = stream(guest);
  t.check('ticks arrive every two ticks without a gap', ticks.length >= 100 && ticks.every((m, i) => m.to === 2 * (i + 1)), `${ticks.length} messages, first ${ticks[0]?.to}`);
  t.check('a checksum arrives every 30 ticks', sums.length >= 6 && sums.every((m, i) => m.tick === 30 * (i + 1) && m.sum.length === 2), JSON.stringify(sums.slice(0, 2)));
  const fired = inputs.filter((e) => e.input.kind === 'fire');
  t.check('the active human fire is broadcast once, stamped with its tick', fired.length === 1 && fired[0].input.team !== idleTeam && fired[0].at >= 30, JSON.stringify(fired));
  t.check('nothing from the idle human reaches the stream', inputs.every((e) => e.input.team !== idleTeam));
  const same = ticks.length >= 100 && JSON.stringify(stream(host).ticks.slice(0, 100)) === JSON.stringify(ticks.slice(0, 100));
  t.check('both humans receive the same stream', same);

  host.socket.disconnect(false);
  guest.socket.disconnect(false);
}
