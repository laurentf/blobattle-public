import { OP, arrive, openRoom, send, waitFor } from '../lib.mjs';

export const title = 'tranche 15 — the lobby: seats, host, settings, host transfer (§6.3, D-08)';

export async function run(t) {
  const { host, code } = await openRoom('Lobby Host');
  const guest = await arrive('Lobby Guest', code);
  const hostId = host.session.user_id;
  const guestId = guest.session.user_id;

  const seated = await waitFor(guest, OP.lobby_state, (s) => s.seats?.[1]?.user === guestId);
  const seen = await waitFor(host, OP.lobby_state, (s) => s.seats?.[1]?.user === guestId);
  t.check(
    'each human takes the first open seat and both see it',
    seated !== null && seen !== null && seated.seats[0].user === hostId && seated.seats[0].name === 'Lobby Host' && seated.host === hostId,
    JSON.stringify(seated?.seats),
  );

  await send(guest, OP.lobby_settings, { teams: 2 });
  const refused = await waitFor(guest, OP.refused);
  t.check('a guest who sends lobby_settings receives refused', refused?.code === 'not_host', JSON.stringify(refused));

  const before = host.inbox.length;
  await send(host, OP.lobby_settings, { teams: 3, map: 'volcano' });
  const changed = await waitFor(guest, OP.lobby_state, (s) => s.seats?.length === 3);
  t.check('the host changes the settings and the guest sees them', changed?.settings?.map === 'volcano');
  const hostRefused = await waitFor(host, OP.refused, () => true, 300, before);
  t.check('the host is not refused', hostRefused === null, JSON.stringify(hostRefused));

  await send(host, OP.lobby_slot, { seat: 2, kind: 'bot' });
  const taken = await waitFor(host, OP.refused, () => true, 3000, before);
  t.check('a seat a human holds cannot become a bot', taken?.code === 'seat_taken', JSON.stringify(taken));

  await host.socket.leaveMatch(host.matchId);
  const transferred = await waitFor(guest, OP.lobby_state, (s) => s.host === guestId);
  t.check(
    'when the host leaves, the guest becomes host and the seat is freed',
    transferred !== null && transferred.seats[0].user === undefined && transferred.seats[0].kind === 'open',
    JSON.stringify(transferred),
  );

  const mark = guest.inbox.length;
  await send(guest, OP.lobby_settings, { teams: 5 });
  const applied = await waitFor(guest, OP.lobby_state, (s) => s.seats?.length === 5, 5000, mark);
  t.check('the new host can change the settings', applied !== null);

  guest.socket.disconnect(false);
}
