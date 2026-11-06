# Run B — serveur · **fait**

Conservé pour mémoire : ce run est terminé (tranches 13 à 18, puis
la revue de clôture). Le prompt et les avertissements qui suivent ont servi à le conduire ; le bilan
est en fin de fichier.

Tranches 13 à 18 du plan TDD de `SPEC.md` §10.6.

**Avant de lancer** : `/clear`. Ce qui n'est pas sur le disque n'existe plus après : l'état du run A,
ses mesures et ses pièges sont écrits dans `docs/runs/run-a-socle-simulation.md` (bilan).

**Ce run n'a pas besoin de Defold.** Le serveur se teste contre un vrai Nakama en conteneur et un
harnais Node (`@heroiclabs/nakama-js`) qui ne part jamais dans un build du jeu.

---

## Le prompt

```
Lis SPEC.md, CLAUDE.md et V0.md à la racine, puis docs/conventions.md,
docs/runs/run-a-socle-simulation.md (le bilan du run A : mesures et pièges) et
docs/runs/run-b-serveur.md (ce fichier : ce qui est tranché et les pièges).

Le run A est fait : shared/ (sim, bots) est complet et déterministe sous LuaJIT, Lua 5.1 et
Nakama. Tout tourne en conteneur :
  make test         (busted sous LuaJIT puis Lua 5.1)
  make lint         (luacheck + stylua --check)
  make bench N=…    (parties bots contre bots)
  make conformance  (vecteurs rejoués dans Nakama)

/goal Les tranches 13 à 18 de SPEC.md §10.6 sont faites : `make up` démarre Postgres et
Nakama sains avec le module room chargé, un code inconnu rend room_not_found, un invité
qui règle le salon reçoit refused, un fire du joueur inactif est jeté et compté, un joueur
déconnecté pendant son tour est joué par un bot puis reprend la main, et `make harness`
joue une partie complète à 2 humains simulés + 2 bots dont toutes les sommes de contrôle
reçues correspondent au rejeu Lua. `make test`, `make lint` et `make conformance` restent
verts. Respecte CLAUDE.md, en particulier D-03 (le serveur diffuse des entrées numérotées,
jamais l'état hors snapshot), D-08 (une place n'est jamais vide) et D-14 (tout message
validé : forme, bornes, expéditeur, taille, débit). Chaque tranche : test rouge vu échouer,
code, vert, lint, relecture du diff par un sous-agent contre SPEC.md, commit en français
sans trailer Co-Authored-By. À la fin : revue de clôture de V0.md §4, mise à jour de ce
fichier en « fait » avec les mesures (durée d'un tick serveur, plus gros snapshot, budget
des bots dans Nakama) et les pièges, report des hypothèses H-06 et H-07 dans SPEC §3, et
écriture de docs/runs/run-c-client.md. Ou stop après 60 tours.
```

## Ce qui est déjà tranché et ne se rediscute pas dans ce run

- **L'infrastructure Nakama se reprend de clinch et telegraph** (compose Postgres + Nakama, fichier
  de configuration `local.yml`, console sur `127.0.0.1`, profil `tunnel` plus tard). Une différence :
  Blobattle utilise le **runtime Lua**, donc ni bundle rollup ni correctif goja. Les modules sont des
  fichiers `.lua` montés tels quels.
- **Montages** : `shared/` → `modules/shared` (lecture seule), `server/` → `modules/server`. Rien
  d'autre : Nakama exécute chaque `.lua` qu'il trouve, un script posé là tournerait au démarrage.
- **Images** : les mêmes digests que le profil `conformance` (Nakama 3.41.0, Postgres 16-alpine).
  La conformance tourne dans son propre projet Compose (`-p blobattle-conformance`) : son `down -v` ne
  touche jamais la pile de développement.
  Services par défaut `blobattle-postgres` et `blobattle-nakama`, ports hôte de V0.md §3 : 5438 (Postgres,
  `127.0.0.1`), 7550 (API et socket), 7551 (console, `127.0.0.1`). La base du jeu a un volume nommé
  **sans** clé `name:` (qui traverserait les projets Compose) ; la conformance garde sa pile sans
  volume.
- **Configuration** : clé serveur, clé HTTP, clés de session et mot de passe de la console par `.env`,
  jamais dans le dépôt. ~~`socket.max_message_size_bytes` à 262144~~ : **abandonné à la tranche 13**,
  ce réglage ne borne que ce que le serveur lit d'un client (SPEC §6.6, H-06) ; il reste à 4 Kio.
- **Harnais** : `tools/harness/`, Node 24 et `@heroiclabs/nakama-js`, épinglés par
  `package-lock.json`, lancés dans l'image d'outils (ajouter Node au `Dockerfile`, épinglé). Il
  enregistre le flux `ticks` reçu, puis un script Lua (même principe que
  `tools/conformance/runner.lua`) rejoue ces entrées et vérifie chaque `checksum`.
- **Bots côté serveur** : le pilote de `shared/bots/driver.lua` tourne dans la boucle du match, avec
  une enveloppe réglée par le serveur. `BOT_STEPS_PER_TICK` (1500 en local) se règle ici sur la mesure
  dans Nakama.

## Ce que le run A laisse en place et qui sert ici

- `world.new(seed, settings)` refuse une graine ou un réglage hors bornes avec une raison précise
  (`nil, "invalid_seed"`, `nil, "invalid_teams"`…) : le RPC `room_create` les renvoie tels quels.
- `world.step(w, inputs)` ignore toute entrée invalide sans lever d'erreur ; la validation du serveur
  (D-14) vient **en plus**, pour compter et refuser avant la sim.
- `world.checksum(w)` rend deux entiers (`a`, `b`) : le message `checksum` les porte tous les deux.
- `world.snapshot(w)` rend des données simples qui passent par JSON ; `world.restore(s)` vérifie
  version, terrain et hachage des cellules.
- `driver.inputs(d, w)` rend l'entrée d'un bot à appliquer au tick courant ; une décision prise ne
  change plus du tour (§9).

## Pièges déjà rencontrés, à ne pas redécouvrir

- **Le runtime Lua de Nakama n'a pas `coroutine`.** Tout code de `shared/` qui tourne dans Nakama doit
  passer `make conformance` ; la suite seule ne le prouve pas.
- **Le nom de nœud Nakama (`--name`) est limité à 16 caractères.**
- **Nakama coupe un RPC HTTP au-delà d'environ 10 s.**
- **Générer la plus grande carte prend 1,7 à 2,4 s dans Nakama** : le faire dans la boucle du match
  bloque ce match pendant ce temps. Mesurer, et décider où la génération a lieu (au passage `lobby` →
  `playing`, avant d'annoncer `game_start`), la spec d'abord.
- **Un candidat de bot coûte 11 à 13 ms dans Nakama.** À 8 ms par tick et 3 s de décision, il reste
  environ 60 candidats, contre 64 / 320 / 640 au §9 : les niveaux doivent être réécrits d'après la
  mesure (moins de candidats, ou une évaluation moins chère), la spec d'abord.
- **SPEC §14 Q-03 (la durée des parties) est ouverte** : 70,5 % des parties du banc s'arrêtent à la
  limite des 30 rondes. Ne pas régler les dégâts ou les PV dans ce run sans décision de
  l'utilisateur.
- **Un volume Compose avec `name:`** est partagé par tous les projets : une copie de vérification
  lancée avec `-p autre` écrirait dans la base du dépôt.

## Bilan

Run conduit dans une seule session, avec une relecture par un sous-agent à chaque tranche, sur un
export de l'index git. Quand une relecture revenait alors que la tranche suivante avançait déjà dans
l'arbre de travail, la suite était mise de côté (`git diff` et fichiers nouveaux), la tranche relue
corrigée et commitée, puis la suite réappliquée (`git apply -3`).

### Ce qui a été mesuré

| Mesure | Valeur |
|---|---|
| Tick serveur, partie à 4 équipes d'un chat (2 humains, 2 bots difficiles) | 0,7 à 0,8 ms en moyenne, 7,2 ms au pire |
| Tick serveur, 4 parties simultanées à 8 équipes de 6 chats (1 humain, 7 bots difficiles) | 1,9 à 2,2 ms en moyenne, 12,4 à 13,0 ms au pire, sur ~3 770 ticks chacune |
| Rythme de ces 4 parties vu des clients (H-07) | 30,00 ticks/s chacune sur 60 s ; au pire 77 ms entre deux `ticks` (67 nominaux) |
| Plus gros snapshot (H-06) | 17 496 octets en JSON (8 équipes de 6, après 15 600 ticks de bots), écrit dans un test ; 16 574 octets reçus d'une partie en cours par nakama-js, en un message, sans réglage |
| Génération de la carte dans le match | 330 à 450 ms (4 équipes d'un chat), 0,9 à 1,1 s (8 équipes de 6, 4 à la fois) ; 1,4 à 2,5 s pour la plus grande dans le RPC de mesure |
| Un tick de sim de la plus grande partie dans Nakama | 1,7 à 2,2 ms (vecteur `brawl`) |
| Un snapshot de la plus grande carte dans Nakama | 125 à 141 ms après un cratère (encodage et hachage des 262 144 cellules), 0,7 ms depuis le cache, plus 0,8 ms d'encodage JSON |
| Budget des bots dans Nakama | 300 unités de travail par tick ; une unité ~8 µs sur un cœur performant de l'i9-13900KF, 20 à 28 µs sur un cœur économe ; un appel 2 à 8 ms en moyenne, ~24 ms au pire |
| Travail d'une recherche complète (LuaJIT, déterministe) | facile 5 500 à 9 300 unités, moyen 10 000 à 18 300, difficile 15 600 à 30 200 (46 000 au pire sur 2 700 recherches) |
| Banc, 200 parties (niveaux réduits) | 0 erreur, 35 s au lieu de 152 ; 79,5 % à la limite des rondes (70,5 % au run A) ; 11,2 / 12,5 / 14,2 dégâts par tir |
| Partie complète du harnais (2 humains simulés + 2 bots, graine 12) | 1,5 à 2,5 min, 91 à 153 sommes de contrôle, toutes retrouvées par le rejeu sous LuaJIT et sous Lua 5.1 |

- **Suite** : 307 tests, verts sous LuaJIT et Lua 5.1 (201 au run A) ; `luacheck` et
  `stylua --check` propres sur 83 fichiers. `make conformance` : sommes inchangées sous les trois
  moteurs, et les mesures de Nakama (carte, tick, snapshot, bots). `make harness` : 6 scénarios
  contre le vrai Nakama, de `room_not_found` à la charge, en 5 à 7 minutes.

### Ce que les relectures ont trouvé

Chaque tranche a eu sa relecture ; toutes ont trouvé quelque chose de réel, corrigé avant son commit
(le détail est dans chaque message). Les plus lourds :

1. **Les logs de Nakama en DEBUG écrivaient le contenu de chaque message reçu** (contraire à D-14) ;
   les secrets passaient en arguments, lisibles par tous dans `/proc` (tranche 13).
2. **D'autres chemins de Nakama écrivaient des données d'identité** (nom d'utilisateur choisi,
   profils Google ou Facebook, liaisons de compte) : refusés par des hooks (tranche 14, D-15).
3. **Une place réservée à la tentative d'entrée restait prise pour toujours** si l'entrée
   n'aboutissait pas : n'importe qui avec le code pouvait bloquer un salon. Une reconnexion dont
   l'ancienne session partait en retard laissait l'humain sans place ni hôte (tranche 15).
4. **La fenêtre de débit fixe laissait passer 40 messages en deux ticks** (tranche 15).
5. **« Même graine, mêmes tirs en ligne et hors ligne » était faux dans de rares cas**, et la règle
   D-03 « un message couvre les ticks après le `to` précédent » n'avait pas de test : un décalage
   d'un message survivait (tranche 16).
6. **Un bot qui reprenait un tour après 3 s de visée tirait au hasard au tick suivant** : son attente
   et sa limite de décision se comptaient depuis le début de la visée — le cas le plus courant d'un
   téléphone qui décroche. **Un snapshot coûtait 100 à 265 ms dans Nakama** à chaque entrée, hors des
   durées de tick mesurées, et un humain parti en marchant laissait son chat marcher seul vers le
   liquide (tranche 17).
7. **Une divergence faisait pendre le rejeu du harnais** au lieu de le faire échouer, et le « 2
   humains » était vide pour l'invité, mort avant son premier tour (tranche 18).
8. Beaucoup de règles écrites ne pouvaient pas faire échouer les tests ; comme au run A, les
   relectures ont muté le code et chaque mutant survivant a reçu son test (crédit d'une mort en fin
   de tour, match nul à 0, drapeau de clôture, phase `ended`…).

### Pièges rencontrés

- **Le compilateur de gopher-lua fusionne un `LOADNIL` avec le précédent sans voir le saut qui le
  contourne** (`AddLoadNil`) : `x = a and b or nil` suivi de `x == nil` compare à un registre jamais
  écrit, et le match tombe sur un `panic` Go. LuaJIT et Lua 5.1 n'ont pas ce défaut : seule la
  partie jouée contre le vrai Nakama l'a montré. `or nil` est interdit par un test d'architecture
  dans `shared/`, `server/` et `tools/conformance/`.
- **Nakama arrête un match dont `match_join_attempt` rend un `nil` final** (`return state, true,
  nil`) : il lit les retours par la fin. Rendre `state, true` ou `state, false, raison`.
- **Nakama indexe les labels de match par lots** : un salon n'est trouvable par son code qu'environ
  1 s après sa création.
- **`socket.max_message_size_bytes` ne borne que ce que le serveur lit** ; un message sortant n'a pas
  de borne en octets. H-06 était sans objet.
- **Nakama n'appelle ni `match_join` ni `match_leave` pour une entrée qui n'aboutit pas** : rien ne se
  réserve à la tentative.
- **L'encodeur JSON de Nakama rend `{}` pour une liste vide.**
- **Un RPC HTTP de plus de ~10 s est coupé** : les mesures de la conformance sont un appel chacune.
- **Le processeur de l'hôte est hybride** (8 cœurs performants, 16 économes) : le même travail
  déterministe y coûte du simple au triple selon le cœur où Go place le match. Mesurer plusieurs fois,
  lire les distributions, pas un chiffre.
- **Un bot qui reprend un tour ne part pas du début** : tout ce qui se compte en ticks de visée
  (attente, limite de décision) se compte depuis la reprise, et le temps de tour peut finir avant.
- **Un pas de recherche de bot n'est pas une unité de temps** : un tick de chat projeté coûte trois
  fois un tick de projectile, et l'examen des chats en enchaînait jusqu'à 48 dans un seul « pas ».
- **La dépendance `@scarf/scarf` de nakama-js envoie de la télémétrie à l'installation** : le harnais
  s'installe avec `--ignore-scripts` (et un `.npmrc`).
- **Un test de fin de partie doit produire le cas voulu** : l'hôte qui se fait sauter se noyait
  souvent (mort immédiate) au lieu de mourir par les PV en fin de tour ; la graine se choisit par une
  sonde hors ligne, puis le test vérifie qu'il a bien obtenu ce cas.

### Ce qui reste ouvert

- **Q-03, la durée des parties** (79,5 % à la limite) et **Q-04, le style de rendu** : à l'utilisateur.
- **`room_create` n'a pas de limite** par compte : n'importe qui avec la clé serveur (qui est dans le
  client) peut créer des salons en boucle. Pas d'exigence écrite ; à trancher avant le tunnel (run D).
- **Les specs de `server/ended.lua`, `snapshots.lua`, `players.lua`, `phase.lua` et `log.lua`** ne
  sont pas des fichiers miroirs (§10.1) : ces modules se testent par le match, dans `playing_spec`,
  `lobby_spec` et `guard_spec`.

### La revue de clôture

Elle a rejoué la suite (305 tests sous les deux moteurs, lint propre) et les enregistrements du
harnais (153 sommes de la partie complète, les 4 parties de charge, le snapshot comparé champ par
champ), relu tout le diff du run contre SPEC, CLAUDE.md et V0, et n'a rien trouvé de sérieux dans
`server/`, `shared/` ni `tools/`. Ses constats, corrigés dans le commit `revue de clôture` :

1. **D-15 n'était tenue que sur les chemins du compte** : stockage, discussion, groupes, amis,
   statut, matchs relayés et matchmaker restaient ouverts à toute session et auraient gardé ce qu'un
   joueur y tape, publics dès le tunnel. Ils rendent `unsupported` (`server/closed.lua`, vérifié
   contre le vrai Nakama : stockage, discussion, match relayé).
2. Trois raisons envoyées manquaient au §6 (`game_in_progress`, `room_code_unavailable`, `malformed`
   de `room_create`), et le §6.4 ne disait pas qu'une place hors de 1 à 8 rend `malformed`.
3. `dkjson`, utilisé par les specs et le harnais, n'était pas nommé dans la spec (§10.1).
4. Les modules de phase n'ont pas de spec miroir (laissé ouvert, ci-dessus).

