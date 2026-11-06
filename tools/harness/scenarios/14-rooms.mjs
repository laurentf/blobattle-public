import { randomUUID } from 'node:crypto';
import { attempt, eventually, player, rpc } from '../lib.mjs';

export const title = 'tranche 14 — identity, room_create, room_find (§6.1–6.3)';

export async function run(t) {
  const host = await player('Harness Host');

  const unknown = await rpc(host, 'room_find', { code: 'ZZZZZ' });
  t.check(
    'an unknown code gives room_not_found',
    !unknown.ok && unknown.error.message === 'room_not_found' && unknown.error.status === 404,
    JSON.stringify(unknown.error ?? unknown.value),
  );

  const created = await rpc(host, 'room_create', { settings: { teams: 3 } });
  const code = created.value?.code;
  t.check('room_create returns a code and a match', created.ok && /^[A-HJ-NP-Z]{5}$/.test(code ?? '') && !!created.value.match_id, JSON.stringify(created));

  const found = await eventually(() => rpc(host, 'room_find', { code }));
  t.check('room_find returns that match once Nakama has indexed its label', found.ok && found.value.match_id === created.value?.match_id);
  const lower = await rpc(host, 'room_find', { code: code?.toLowerCase() });
  t.check('room_find accepts the code in lowercase', lower.ok && lower.value.match_id === created.value?.match_id);

  const listed = await attempt(host.client.listMatches(host.session, 10, true, '', 0, 100, ''));
  t.check('listing the matches is refused: nobody reads the codes of the open rooms', !listed.ok && listed.error.message === 'unsupported', JSON.stringify(listed.error ?? listed.value));

  for (const wildcard of ['*', '?????', 'A*', '*****']) {
    const probe = await rpc(host, 'room_find', { code: wildcard });
    t.check(`a wildcard code (${wildcard}) finds no room`, !probe.ok && probe.error.message === 'room_not_found', JSON.stringify(probe));
  }

  const refused = await rpc(host, 'room_create', { settings: { teams: 9 } });
  t.check('room_create returns the sim reason for a bad setting', !refused.ok && refused.error.message === 'invalid_teams' && refused.error.status === 400, JSON.stringify(refused.error));

  const badName = await attempt(host.client.updateAccount(host.session, { display_name: ' x' }));
  t.check('an invalid nickname is refused', !badName.ok && badName.error.message === 'invalid_nickname', JSON.stringify(badName.error));
  const otherField = await attempt(host.client.updateAccount(host.session, { location: 'Paris' }));
  t.check('another account field is refused', !otherField.ok && otherField.error.message === 'invalid_account', JSON.stringify(otherField.error));
  const account = await host.client.getAccount(host.session);
  t.check('the valid nickname is the display name', account.user.display_name === 'Harness Host');

  const named = await attempt(host.client.authenticateDevice(`harness-${randomUUID()}`, true, 'Jean Dupont'));
  t.check('a client-chosen username is refused at device authentication', !named.ok && named.error.message === 'invalid_account', JSON.stringify(named.error));
  const custom = await attempt(host.client.authenticateCustom(`harness-custom-${randomUUID()}`, true));
  t.check('custom authentication is refused', !custom.ok && custom.error.message === 'unsupported', JSON.stringify(custom.error));
  const email = await attempt(host.client.linkEmail(host.session, { email: 'cat@example.com', password: 'password123' }));
  t.check('linking an email is refused', !email.ok && email.error.message === 'unsupported', JSON.stringify(email.error));

  const stored = await attempt(host.client.writeStorageObjects(host.session, [{ collection: 'notes', key: 'me', value: { text: 'hello' } }]));
  t.check('writing to the storage is refused', !stored.ok && stored.error.message === 'unsupported', JSON.stringify(stored.error));
  const socket = host.client.createSocket(false, false);
  await socket.connect(host.session, false);
  const chat = await attempt(socket.joinChat('lobby', 1, false, false));
  t.check('joining a chat channel is refused', !chat.ok, JSON.stringify(chat.error));
  const relayed = await attempt(socket.createMatch());
  t.check('creating a relayed match is refused', !relayed.ok, JSON.stringify(relayed.error));
  socket.disconnect(false);
}

