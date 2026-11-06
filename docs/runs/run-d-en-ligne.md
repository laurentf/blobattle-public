# Run D — en ligne · **fait**

Conservé pour mémoire : ce run est terminé (tranches 25, 26, 26b et 27, puis la
revue de clôture). Le prompt et les avertissements qui suivent ont
servi à le conduire ; le bilan est en fin de fichier.

Tranches 25 à 27 du plan TDD de `SPEC.md` §10.6 : la partie par code entre les téléphones et les
ordinateurs du réseau local. Le tunnel (tranche 28 : nginx, PWA, cloudflared) passe au run D2, qui
attend trois réponses de l'utilisateur (ci-dessous) ; rien du run D n'en dépend.

Demandé par l'utilisateur : « le goal multi avec partie par code, synchro pour tout le
monde quand un blob bouge, tire, réagit, etc. ; si un joueur quitte, un bot prend l'équipe et le
remplace (on voit quand même une icône à côté d'une équipe pilotée par un bot) ; sur le côté, avec la
vie globale par équipe, afficher le nom de l'équipe aussi ».

**Avant de lancer** : `/clear`. Ce qui n'est pas sur le disque n'existe plus après : l'état des runs A
à C4, leurs mesures et leurs pièges sont écrits dans `docs/runs/run-a-socle-simulation.md`,
`docs/runs/run-b-serveur.md`, `docs/runs/run-c-client.md`, `docs/runs/run-c2-tentacule.md`,
`docs/runs/run-c3-armes-cartes.md` et `docs/runs/run-c4-bots.md` (bilans).

**Préalables** : Docker, Internet pour le build Defold, les ports 5438, 7550, 7551 et 5373 libres
(V0.md §3). Le build est servi sur le réseau local par `make serve` et Nakama écoute sur le port 7550
de la même machine : le client en ligne trouve le serveur à l'adresse de la page, port 7550.

**Préalables du run D2 (le tunnel), à régler par l'utilisateur avant de le lancer** :

1. **Q-02, le domaine du tunnel** : un sous-domaine de `npc.fm` pour le build web et un pour Nakama,
   sur le modèle de npchero et telegraph, à confirmer. Un tunnel Cloudflare nommé créé
   (`cloudflared tunnel create blobattle`), ses identifiants dans `./cloudflared/` (ignoré par git).
2. **La limite de `room_create`** : aujourd'hui, n'importe qui avec la clé serveur (qui est dans le
   client) peut créer des salons en boucle. Sans gravité sur le réseau local ; à trancher avant
   d'ouvrir le tunnel (une limite par compte et par minute, ou un plafond de salons ouverts).
3. **Le nom technique** : le jeu s'affiche sous le nom de **Blobattle** depuis le run C3 ; le code,
   Compose, l'image d'outils, le dossier de sauvegarde et le domaine du tunnel gardent encore
   le nom de travail : renommer, ou le garder comme nom technique.

**Ce qui reste ouvert et ne se règle pas dans ce run** : Q-03 (la durée des parties : 39,0 % des
parties du banc atteignent la limite des rondes après 24i, 43,5 % au run C3, 41,0 % au run C2,
79,5 % au run B) ; Q-01 (la marche avec l'aller-retour réseau à travers le tunnel, sur le réseau
mobile) se mesure au run D2 ; ici, on mesure l'aller-retour sur le réseau local.

---

## Le prompt

```
Lis SPEC.md, CLAUDE.md et V0.md à la racine, puis docs/conventions.md,
docs/sonde/README.md (nakama-defold en HTML5, CDP), docs/runs/run-b-serveur.md (le
protocole, le match room, les absences, les pièges de Nakama), docs/runs/run-c-client.md
(le client, LocalAuthority, le parcours, les pièges de Defold) et docs/runs/run-d-en-ligne.md
(ce fichier : ce qui est tranché et les pièges). Lis aussi docs/runs/run-c2-tentacule.md,
docs/runs/run-c3-armes-cartes.md et docs/runs/run-c4-bots.md : les graines choisies pour
leurs propriétés et comment les re-sonder.

Les runs A à C4 sont faits : shared/ (sim, bots qui jouent tout, protocole, noms, les cinq
armes, la forêt et le volcan), server/ (le match room complet, absences comprises) et client/
(Defold : LocalAuthority, intro, rendu voxel, commandes, écrans, parcours).
Tout tourne en conteneur :
  make test         (busted sous LuaJIT puis Lua 5.1)
  make lint         (luacheck + stylua --check, scripts Defold compris)
  make conformance  (vecteurs et noms rejoués dans Nakama)
  make up           (Postgres + Nakama de développement)
  make harness      (clients Node contre le vrai Nakama, rejeu Lua des sommes)
  make web          (build HTML5 par bob.jar dans l'image d'outils)
  make journey      (Chromium sans interface piloté par CDP : le parcours)
  make serve        (le build out/web/Blobattle sur 0.0.0.0:5373, pour un téléphone du réseau local)

/goal Les tranches 25 à 27 de SPEC.md §10.6 sont faites. Depuis l'Accueil, Multi mène à
Créer (un code de 5 lettres, à partager) et à Rejoindre (saisir le code), et le lien
?room=CODE ouvre le même Salon ; deux contextes navigateur s'y retrouvent, chacun sous son
nom d'équipe, l'hôte règle la partie (places Ouverte ou Bot comprises) et lance. Pendant
toute une partie en ligne, chaque contexte voit les mêmes marches, sauts, tirs, coups,
repas, tentacules, projections, dégâts, visages et morts, aux mêmes ticks, sans aucune
divergence de somme de contrôle vérifiée côté client. Sur le côté, chaque ligne d'équipe
montre sa lettre, son nom et ses PV, avec une icône de bot quand un bot la joue, hors
ligne comme en ligne. Un contexte qui quitte en pleine partie voit son équipe prise par un
bot : l'autre contexte voit l'icône apparaître sur cette équipe en moins d'une seconde et le
bot jouer ses tours ; au retour du contexte, il reprend la main au tour suivant de son
équipe et l'icône s'en va. Une Revanche relance le salon. make test, make lint,
make conformance, make harness et make journey restent verts. Respecte CLAUDE.md, en
particulier D-03 (le client n'avance jamais au-delà du dernier tick confirmé), D-08 (une
place n'est jamais vide), D-14 (le serveur ne fait confiance à aucun client), D-15 (rien de
personnel, la console sur 127.0.0.1) et la couture unique de l'autorité (§7.1 :
NakamaAuthority a exactement l'interface de LocalAuthority). Chaque tranche : la spec
d'abord si une décision change, test rouge vu échouer, code, vert, lint, relecture du diff
par un sous-agent contre SPEC.md, commit en français sans trailer Co-Authored-By, push sur
origin main. À la fin : revue de clôture de V0.md §4, mise à jour de ce fichier en « fait »
avec les mesures (aller-retour d'une entrée sur le réseau local depuis le téléphone de
l'utilisateur, temps de reconnexion, taille d'un snapshot reçu par le client Defold) et les
pièges, report des hypothèses H-02 (en WS) et H-09 (sur le téléphone de l'utilisateur) dans
SPEC §3, et écriture de docs/runs/run-d2-tunnel.md. Ou stop après 60 tours.
```

## Ce qui est déjà tranché et ne se rediscute pas dans ce run

- **Multi, Créer, Rejoindre** (§7.2) : l'Accueil gagne « Multi », qui mène à Créer (le serveur rend
  un code de 5 lettres, qu'un bouton de partage copie ou partage, avec le lien `?room=CODE`) et à
  Rejoindre (le code saisi dans un vrai champ de texte, comme le pseudo). Le lien `?room=CODE` ouvre
  le Salon directement (HTML5), après l'intro.
- **Tout le monde voit la même partie** : c'est le modèle de D-03, déjà en place côté serveur — le
  serveur diffuse les entrées datées au tick (`ticks`), chaque client rejoue la même sim ; les
  mouvements, tirs, coups, repas, projections, dégâts et visages en découlent, rien d'autre n'est
  envoyé. Le parcours à deux contextes le vérifie par la somme de contrôle et par l'état publié en
  mode test des deux côtés, comparé tick à tick.
- **L'équipe d'un joueur qui part** (§6.7, déjà au serveur depuis le run B) : dès que la dernière
  présence du compte quitte le match, le pilote des bots du serveur prend l'équipe ; il la rend au
  premier `turn_started` qui suit le retour. Nouveau au run D : le serveur **dit à tous** qui pilote
  chaque équipe (message `pilots`, §6.4), à chaque prise et à chaque retour, et un client qui revient
  le reçoit avec son snapshot.
- **L'interface des équipes** (§7.4) : sur le côté, sous l'équipe qui joue, une ligne par équipe :
  sa lettre, son nom (coupé s'il le faut, jamais sous 12 points), ses PV restants, et une petite
  icône de bot quand un bot la joue — dès le lancement pour une place Bot, ou après le départ du
  joueur. Hors ligne, les équipes des bots la portent aussi. Elle vaut pour les 8 équipes à 844×390.
- **La couture** (§7.1) : `client/authority/local_authority.lua` fixe l'interface —
  `start()`, `update(dt)`, `send(name, body)` avec les noms d'opérations de
  `shared/protocol.lua`, `poll()` qui rend la liste des `{name, data}` reçus (`game_start`, `ticks`,
  `checksum`, `snapshot`, `game_end`, `refused`), une liste réutilisée qui ne vaut que jusqu'au
  `poll()` suivant, `team()` (l'équipe du joueur) et `stop()`. Hors de `client/authority/`, rien ne
  touche l'autorité autrement (`spec/architecture_spec.lua` le vérifie).
  `NakamaAuthority` l'implémente à l'identique ; `client/game/playback.lua`, le rendu et les
  commandes ne changent pas. `playback` ne sait pas encore restaurer un snapshot : c'est à écrire
  ici (restaurer, puis n'appliquer des `ticks` suivants que les entrées d'un `at` ≥ `tick`, §6.6),
  et à tester comme `tools/harness/replay.lua`.
- **La somme de contrôle vérifiée côté client** : `playback` compte déjà `checked` et
  `divergences` ; en ligne, une divergence envoie `snapshot_request {tick}` (au plus un toutes les
  5 s, `too_soon`), puis le snapshot remet le monde d'aplomb.
- **Les noms** (§6.1) : le profil local (`client/main/profile.lua` : pseudo, nom d'équipe, six
  membres tirés une fois) se dépose par `team_set` ; le serveur valide et garde ; `game_start`
  porte `team_name` et `members` pour chaque place, bots compris (`shared/names.lua` sur la
  graine). Le roster de `server/playing.lua` ne les porte pas encore.
- **Le client en ligne** : nakama-defold v3.4.0 et extension-websocket 4.2.4 sont déjà déclarés
  dans `client/game.project` et compilés dans le build ; la sonde (`docs/sonde/ref/client/net.script`)
  montre authentification, RPC, socket et match. L'Accueil a aujourd'hui « Solo » (contre les
  bots) ; il gagne « Multi », qui mène à Créer et Rejoindre (un code à partager), comme l'utilisateur
  l'a demandé en jouant le build du run C, et le lien `?room=ABCDE` ouvre le Salon (HTML5).
- **Le parcours à deux contextes** : deux cibles CDP dans le même Chromium, chacune avec son
  stockage (profil séparé, ou `Storage.clearDataForOrigin` entre les deux), contre le vrai Nakama
  de `make up`.

- **La couture et les pilotes** : au lancement, le client lit qui pilote chaque équipe dans le
  `roster` de `game_start` (`kind` = `human` ou `bot`) ; ensuite, le message `pilots` (§6.4) le met à
  jour. `LocalAuthority` n'en a pas besoin hors ligne (les bots ne changent pas), `NakamaAuthority` le
  rend par `poll()` comme les autres messages.

## Pièges déjà rencontrés, à ne pas redécouvrir

- **Nakama** (run B) : `or nil` interdit dans tout ce qui tourne sur le serveur (gopher-lua fusionne
  un `LOADNIL` à travers un saut) ; un `match_join_attempt` qui rend un `nil` final arrête le match ;
  un label de match n'est trouvable qu'environ 1 s après sa création ; l'encodeur JSON rend `{}` pour
  une liste vide (le client doit lire `{}` comme une liste vide) ; un RPC HTTP de plus de ~10 s est
  coupé.
- **Defold** (run C) : un build release avale les erreurs Lua — le mode test (`?test=1`) les publie
  dans `window.blobattle.errors` par `sys.set_error_handler`, et le parcours les vérifie ; HTML5 ne
  fabrique pas d'événement souris depuis le toucher (écouter `TOUCH_MULTI`, `client/ui/pointer.lua`) ;
  une scène `.gui` doit nommer ses deux dispositions (Landscape et Portrait), sinon Defold prend la
  mauvaise ; au changement de disposition, les textes posés par le script sont perdus (réappliquer
  sur `layout_changed`) ; `bob.jar` 1.13.1 exige Java 25 ; **une ressource créée par
  `resource.create_buffer` meurt avec la partie** (le proxy qui la charge) : la garder dans un module,
  qui survit, fait planter la partie suivante — elles se créent et se libèrent par partie
  (`client/game/models.lua`, `terrain_view.lua`), et le parcours joue une deuxième partie.
- **Le parcours** : les cibles se touchent par leur position publiée en mode test
  (`window.blobattle.targets`), en pixels d'écran à diviser par `devicePixelRatio` ; le pseudo et le
  nom d'équipe se saisissent dans de vrais `<input>` posés sur le canevas
  (`client/ui/text_fields.lua`), que le parcours remplit par `Input.insertText` ; au clic, la
  souris de CDP ne bouge qu'avec un `mouseMoved`, et un appui et un relâcher de touche dans la même
  image sont perdus ; la molette n'atteint pas Defold dans Chromium sans interface.
- **Mesurer le CPU dans Chromium, le GPU sur le téléphone** : SwiftShader rend en logiciel, ses
  images par seconde ne disent rien d'un téléphone (H-11).

---

## Bilan

Run conduit dans une seule session, une tranche après l'autre. Pour chaque tranche :
la spec d'abord quand une décision changeait, le test qui ouvre la tranche vu rouge, le code, puis
une relecture du diff par un sous-agent. Venaient ensuite la suite sous LuaJIT et Lua 5.1 et le lint,
puis le build HTML5, le parcours en ligne et, quand le serveur changeait, le harnais, tous rejoués
**sur un export de l'index** (`git checkout-index`). Enfin, un commit et un push. Les tranches ont
avancé ensemble dans l'arbre de travail : chacune a été indexée seule, les fichiers qu'elles
partageaient (`game.script`, `server/playing.lua` et sa spec, `SPEC.md`, le parcours) dans une
version dérivée écrite dans l'index par `git hash-object`.

**Un écart avec le prompt** : il disait les runs A à C4 faits. Du run C4, seules les tranches 24i (les
poutrelles) et 24n (l'intro) le sont. Les tranches 24j à 24m (les bots qui marchent, frappent,
mangent et lancent le tentacule) n'ont aucun commit, et SPEC §9 dit toujours que les bots ne tirent
qu'au bazooka et à la grenade. Rien du run D n'en dépend : en ligne, les bots tournent sur le
serveur avec le cerveau actuel.

### Ce qui a été mesuré

| Mesure | Valeur |
|---|---|
| Entrer dans un salon (appareil, pseudo, équipe, `room_create` ou `room_find`, socket, match), sur la machine | 0,12 à 0,17 s |
| L'icône du bot chez l'autre contexte, après la fermeture d'une page | 497 à 563 ms |
| Revenir par le lien `?room=` (page rechargée : chargement, intro passée, entrée, `game_start`, snapshot) | 8,0 à 9,1 s dans Chromium sans interface |
| Socket coupée en pleine partie, jusqu'à la partie remise d'aplomb | 2,5 à 2,9 s, dont les 2 s d'attente avant l'essai (`link.RETRY_SECONDS`) et 0,18 à 0,22 s de connexion |
| Snapshot reçu par le client Defold (3 équipes de 2, forêt), en un message | 7 996 à 10 287 octets |
| Aller-retour d'une entrée, envoyée puis revue dans `ticks` (Chromium de la machine, par le relais) | 32 à 91 ms, 52 à 91 ms en moyenne sur 8 à 12 selon la charge de la machine : le tick serveur (33 ms) et un `ticks` tous les 2 ticks en font l'essentiel |
| Aller-retour d'une entrée depuis le téléphone de l'utilisateur, sur le réseau local | **non mesuré** : l'utilisateur ne pouvait pas pendant le run et préfère passer par le tunnel (run D2) ; `?test=1` l'affiche en bas de l'écran |
| Snapshot d'une partie de 8 équipes de 6 reçu par le client Defold (page rechargée vers le tick 1 450), en un message | 24 668 à 26 332 octets, restauré, sans divergence |
| Une partie entière à deux contextes | 114 points de contrôle identiques sur 3 401 ticks, 640 sur 19 202 ; aucune divergence ; jamais un tick au-delà du confirmé |
| Build HTML5 | 4,65 Mo (4,65 avant le run : +8 Ko) ; 5,9 à 6,5 s dans un export neuf |
| Suite | 681 tests sous LuaJIT et Lua 5.1 (612 au début du run) ; lint propre sur 179 fichiers |
| Harnais | 79 contrôles, verts à chaque tranche qui touchait le serveur |
| Parcours (`make journey`) | 121 contrôles en fin de run (84 hors ligne, 37 en ligne), environ 65 min ; avec la revue de clôture, **124** (84 hors ligne, 40 en ligne : Multi et Salon à 390×844 et 667×375, snapshot de 8 × 6), environ 70 min |

### Ce que les relectures ont trouvé

Chaque tranche a eu sa relecture ; toutes ont trouvé quelque chose de réel, corrigé avant son commit
(le détail est dans chaque message). Les plus lourds :

1. **25 — Lancer plantait la partie** : le roster de `game_start` ne portait pas encore les noms, et
   `game.script` les lit au premier tick. Le roster avec `team_name` et `members` est passé dans la
   tranche 25.
2. **25 — La connexion pouvait rester coincée pour toujours** : une socket perdue pendant la
   recherche du salon faisait mourir la coroutine (l'état restait « connexion… », Retour ignoré), et
   un `match_join` sans réponse bloquait la reconnexion (nakama-defold n'a pas de délai sur les
   requêtes de socket). Remède : des générations (tout travail d'une génération dépassée
   s'arrête), un chien de garde de 25 s, la socket ouverte après la recherche, et Retour qui annule.
3. **25 — Sur une page `http:` du réseau local**, `navigator.share`, `navigator.clipboard` et
   `crypto.randomUUID` n'existent pas : le partage disait « copié » sans rien copier, et
   l'identifiant d'appareil tombait sur `math.random` (~20 bits, l'identifiant *est* le compte).
   `crypto.getRandomValues` existe en `http:` ; le partage essaie l'ancienne commande du
   presse-papiers, puis affiche le lien.
4. **25 — Deux onglets du même profil** (même compte) se volaient la socket en boucle avec
   `single_socket` : la connexion s'arrête après trois pertes de suite, chacune moins de 5 s après
   son entrée (`reason.elsewhere`).
5. **25 — La Revanche restait à un hôte parti** : hors du salon, rien ne disait que l'hôte avait
   changé. `game_end` porte l'hôte, et repart à tous quand il change pendant `ended` (§6.4).
6. **26 — Une vue restaurée gardait l'état d'avant** : des flaques pour des blobs vivants, des blobs
   pour des morts, un bras de tentacule sans corde. Et une spec de restauration passait sans
   restauration, parce que la fenêtre sourde du test ne portait aucune entrée.
7. **26b — Les lignes élargies passaient sous les pavés des pouces** à partir de 4 équipes : Saut,
   et ▲ ▼ au-dessus de lui. Les lignes montent et se resserrent, ▲ ▼ passent à droite de Saut
   (§7.3 réécrit), et une spec le vérifie.
8. **Partout, des mutants** (le jeton de session, une partie nouvelle au retour, la marque de
   coupure, `pilots` à chaque début de tour, les noms hors du hachage de la trace…) : tous tués. Et
   des contrôles du parcours qui promettaient plus qu'ils ne vérifiaient (« le bot joue son tour »
   passait sur un tour écoulé sans action) : resserrés.

### La revue de clôture (V0.md §4)

Un sous-agent a relu le diff complet du run et ses docs contre SPEC.md,
CLAUDE.md et V0.md : la couture, D-03, D-08, D-11, D-15 et les formes du §6.4 sont tenues, rien
n'est hors périmètre. Corrigé dans le commit de clôture :

- **Les visages suivaient l'horloge d'affichage** : la peur retenue tant qu'un blob est fâché
  dépendait du temps réel, si bien que deux contextes pouvaient montrer un visage différent au
  même tick (après un rattrapage). Ils suivent le temps de la sim.
- **D-14 sur `team_set`** : ni taille, ni écriture évitée ; un corps de plus de 1 Kio rend
  `too_large` (`room_create` aussi), et un dépôt identique n'écrit rien (§6.2).
- **V0 §2** : Multi et le Salon n'étaient vérifiés ni à 390×844 ni à 667×375. Ils le sont
  maintenant, et à 667×375 les places et les réglages du Salon se touchaient une fois mis à
  l'échelle (58 px entre deux rangées au lieu de 56).
- **H-06** n'était pas refermée pour le client Defold : un snapshot de 8 équipes de 6 passe
  maintenant par une page rechargée.
- **§7.1** décrivait l'ancienne couture : ses six fonctions et les messages de `poll()` y sont,
  l'écran Fin y est nommé comme lecteur de la connexion, et une spec vérifie que seul
  `client/net/` charge nakama-defold.
- **L'identifiant d'appareil hors HTML5** (l'APK du run E) tombait sur `math.random` : il vient
  de `/dev/urandom`.
- **L'ordre des messages** au retour dans une partie finie (`game_end` pouvait précéder
  `game_start`), et les docs (identifiant du commit, règle des éjections, écran allumé qui relève de
  la tranche 29, `make journey J=offline` qui ne redémarre plus Nakama, l'entrée C4 de V0 §4).

### Pièges rencontrés

- **`bob.jar --settings` avec un chemin relatif** le lit depuis `client/` et tombe sur une
  `NullPointerException` à la lecture des tâches : un chemin absolu.
- **Un corps d'erreur HTTP de Nakama porte `"error": {}`** (un objet vide) et la raison dans
  `message` ; une réponse d'erreur de socket la porte dans `error.message`. Nakama répond
  `Access-Control-Allow-Origin: *`, erreurs comprises : rien à régler pour une page servie ailleurs.
- **Le JSON de Defold rend `{}` pour une liste vide**, dans l'état publié en mode test aussi : le
  parcours lit tout tableau par `list()`.
- **`gui.get_text_metrics_from_node` n'existe plus dans Defold 1.13** : `resource.get_text_metrics`
  sur la ressource de la police du nœud (`gui.get_font_resource(gui.get_font(node))`). Le build
  release avale l'erreur ; seul le mode test du parcours l'a montrée.
- **Le contexte de script qui ouvre une WebSocket en reçoit les rappels** (comme `http.request`) :
  la connexion au salon vit dans `app.script`, qui l'entretient à chaque image, jamais dans la scène
  de la partie, déchargée à la fin.
- **Deux contextes CDP du même Chromium partagent leur stockage** : `Target.createBrowserContext`
  donne à chacun son profil, donc son compte. Dans un même contexte, un deuxième onglet est le même
  compte : fermer le premier avant de rouvrir le lien.
- **Dans l'image d'outils, `127.0.0.1:7550` n'est pas Nakama** : le parcours y ouvre un relais vers
  `blobattle-nakama:7350` (`tools/journey/forward.mjs`), pour que le client garde sa règle « l'adresse
  de la page, port 7550 ».
- **Viser pendant que la caméra glisse** : l'appui tombe loin du blob et déplace la vue. Le parcours
  attend que le blob ne bouge plus à l'écran. Accroché au tentacule, un blob ne tire pas : il faut
  lâcher avant le Chomp ou l'uppercut.
- **Une partie contre un bot difficile peut finir en un tour** : le parcours joue deux blobs par
  équipe et poursuit, tour après tour, les actions que la partie n'a pas encore montrées ; tout
  montré, les humains se tirent aux pieds pour la finir.
- **`docker ps` montre aussi le `make serve` de l'utilisateur** : arrêter les conteneurs d'outils
  « à la main » l'a arrêté une fois (relancé aussitôt).

### Ce qui reste ouvert

- **Le téléphone de l'utilisateur** : l'aller-retour depuis son téléphone et H-09 (le toucher à deux
  doigts et le paysage sur Chrome Android, en ligne) ne sont pas mesurés : il ne pouvait pas pendant
  le run, et a demandé à passer par le tunnel, en reprenant le conteneur `cloudflared` comme pour
  npchero (fait le jour même : `https://blobattle.npc.fm`). Il y a ensuite joué en ligne sur son
  téléphone : « super fluide même en multi sur le tel ». Un ressenti, pas une mesure : la ligne du
  mode test (`https://blobattle.npc.fm/?test=1`) donne les chiffres.
- **Les bots qui jouent tout** (tranches 24j à 24m du run C4) : pas faites (voir l'écart ci-dessus).
- **Le run D2** (`docs/runs/run-d2-tunnel.md`) : nginx, PWA, le tunnel, et ce qu'il attend de
  l'utilisateur (le domaine, la limite de `room_create`, le nom technique) ; Q-01 (l'aller-retour à
  travers le tunnel, sur le réseau mobile) s'y mesure.
- **Une page rechargée en pleine partie** construit la vue deux fois (le monde de la graine, puis
  celui du snapshot) et rejoue l'animation des flaques des blobs déjà morts : un écart de rendu,
  comme le fond des cratères peint en herbe (§7.4).
- **Deux onglets du même profil** sont un même compte : la connexion abandonne après trois pertes
  de suite, chacune moins de 5 s après son entrée (`reason.elsewhere`) ; les distinguer demanderait
  un identifiant de session à part, hors V0.
- **Q-03** (la durée des parties) reste à l'utilisateur.

