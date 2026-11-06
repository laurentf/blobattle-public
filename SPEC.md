# SPEC — Blobattle : artillerie au tour par tour, multijoueur, pensée pour le téléphone

Statut : spec V0, à exécuter en TDD, run par run (`V0.md`).
Stack : Defold 1.13 (Lua) · Nakama 3 (runtime Lua) · PostgreSQL · Docker Compose · tunnel Cloudflare ou
Caddy.
Le choix de la stack et ses raisons : `docs/adr-001-defold-lua.md`.

---

## 1. Contexte et objectif

**Blobattle** est un Worms-like (le nom de la fenêtre, de la page, de l'application, du dépôt et du
code ; le build HTML5 charge derrière le logo rond du jeu, `client/brand/`, au lieu de celui de
Defold, avec son icône d'onglet et d'écran d'accueil ; le dossier de sauvegarde s'appelle aussi
`blobattle`, et ce renommage repart de profils vierges, choix de l'utilisateur) : 2 à 8 équipes de chats s'affrontent
sur une carte générée au hasard, au tour par tour, au bazooka et à la grenade, sur un terrain qui se
creuse à chaque explosion. Les places qu'aucun humain ne prend sont jouées par des bots.

On y joue entre amis, **d'abord sur téléphone** : un lien ouvert dans le navigateur, servi depuis la
machine de l'utilisateur à travers un tunnel Cloudflare, ou un APK Android. iOS et Steam viennent
après la V0, sans rien réécrire.

Deux propriétés traversent toute la spec :

1. **La simulation est une, et elle est déterministe.** Les mêmes fichiers Lua calculent la partie
   sur le serveur et sur chaque client, et doivent donner le même état au bit près. Le serveur fait
   autorité ; un client ne décide jamais d'un résultat, il le recalcule.
2. **Le téléphone est la cible, pas une adaptation.** Tout se joue aux pouces, en paysage, sur un
   téléphone de milieu de gamme. Un écran qui ne marche pas à 844×390 n'est pas fini, quel que soit
   son rendu sur un écran de bureau.

## 2. Périmètre

### Dans la V0

- La simulation complète (§5) : carte générée (relief, grottes, liquide à gauche et à droite, puits),
  chats (marche, saut, chute, noyade), vent, bazooka, grenade, explosions, tours, fin de partie.
- Des armes extensibles (§8) : deux armes livrées, la grammaire pour en ajouter ; et le tentacule, un
  grappin à balancier qui ne termine pas le tour (§5.4, §8.2), avec une jauge de déplacement par tour.
  Puis, à la demande de l'utilisateur (run C3) : l'uppercut au corps à corps, le Chomp qui creuse,
  des chocs entre blobs projetés (§5.4), et deux cartes, la forêt et le volcan, dont la lave monte
  (§5.3).
- Des bots à trois niveaux (§9), qui jouent par le même chemin d'entrées qu'un humain.
- Le serveur Nakama (§6) : salon rejoint par un code ou un lien, places ouvertes ou bots, partie qui
  fait autorité, reconnexion, un bot qui remplace l'absent, revanche.
- Le client Defold (§7) : entraînement hors ligne contre des bots, partie en ligne, commandes
  tactiles, paysage imposé en partie, textes en anglais (D-11).
- Le build HTML5 servi par nginx derrière le tunnel, ou derrière un reverse proxy : le Caddy du dépôt
  (profil `https`) ou celui de qui héberge le jeu (`docs/heberger.md`) ; et un APK Android
  installable à la main.
- Un rendu 3D en voxels (§7.4) : terrain qui se creuse voxel par voxel, « chats » dessinés en blobs
  gélatineux aux couleurs de leur équipe, le tout généré par le code, sans modèle ni sprite importé.
- Des noms : chaque équipe et chacun de ses membres ont le leur (§6.1), affichés en partie (§7.4).
- La mort subite de la forêt : dès la 8e ronde, un séisme à chaque fin de ronde, de plus en plus
  fort, qui secoue les blobs et ouvre des failles jusqu'à l'eau (§5.3, demandé par l'utilisateur) ;
  la lave du volcan joue déjà ce rôle.
- La dynamite, qu'on pose et qui explose 5 s plus tard, et des munitions comptées par partie
  (§8.2), demandées par l'utilisateur (run C6).
- Des caisses lâchées par avion, qui descendent en parachute un tour sur trois (§5.10), et quatre
  armes qu'on ne trouve que dedans (§8.2) : le Waddler, un mini-blob qui marche seul et qu'on fait
  sauter quand on veut, le jetpack, la grappe et l'appui aérien. Demandés par l'utilisateur
  (run C8).
- Un panneau d'administration local, en lecture seule (§11.1), et le journal des salons et des
  parties que le serveur tient pour lui (§6.9) : demandé par l'utilisateur, sur le
  modèle du panneau de telegraph.

### Hors V0, explicitement

- Sons et musique, d'autres armes que celles de §8.2 ; une mort subite pour les cartes à venir.
- Des caisses posées à la génération, des caisses de soins ou d'outils, une roue de choix des armes,
  d'autres cartes que la forêt et le volcan (la planche de référence en montre d'autres : ville en ruine, mine, hiver).
- Skins, statistiques et hauts faits par membre d'équipe, médailles, hall of fame ; renommer ses
  membres (le nom de l'équipe et le pseudo, eux, se changent dès la V0 depuis l'Accueil).
- Le français : le mécanisme de catalogues est là (D-11), seul l'anglais est livré.
- Voir la visée des autres joueurs en direct, prédiction du déplacement avec retour en arrière.
- Bots qui se déplacent avant de tirer.
- iOS, Steam, publication sur les stores, authentification autre qu'anonyme.
- Matchmaking public, classement, profils, amis, discussion.
- Spectateurs, plusieurs humains dans une même équipe.

## 3. Contraintes externes et hypothèses

### Trois moteurs Lua exécutent la même simulation

| Où | Moteur | Particularités qui comptent |
|---|---|---|
| Serveur Nakama | gopher-lua (Lua 5.1, en Go) | pas de LuaJIT, pas de FFI ; `math` en Go |
| Client Defold natif (Linux, Android, iOS) | LuaJIT | `math` en C ; module `bit` |
| Client Defold HTML5 | Lua 5.1 compilé en WebAssembly | pas de JIT ; le plus lent des trois |

Les trois représentent les nombres en `double` IEEE 754. Les additions, soustractions,
multiplications et comparaisons **d'entiers inférieurs à 2^53** y sont exactes et identiques. Les
fonctions `math.sin`, `math.cos`, `math.atan2`, `math.pow`, `math.exp`, `math.log` ne le sont pas
garanties. L'ordre de parcours de `pairs()` diffère d'un moteur à l'autre. D'où D-02.

### Hypothèses

À vérifier avant de coder dessus. Chaque run reporte ici ce qu'il a vérifié ou démenti.

La sonde (`docs/sonde/README.md`) en a vérifié cinq avant l'écriture de cette spec.

| # | Hypothèse | Statut |
|---|---|---|
| H-01 | `bob.jar` 1.13.1 construit les builds HTML5 et Linux sans éditeur | **vérifiée au run C dans l'image d'outils** (`make web`) : `bob.jar` 1.13.1 exige Java 25 (JRE Temurin), et AWT freetype et fontconfig pour lire une police ; HTML5 25,0 à 35,1 s à froid, dont 21 à 31 s de compilation de l'extension WebSocket sur `build.defold.com` (selon sa charge), 2,8 à 3,9 s à chaud, 2,89 Mo. Le build Linux au run E |
| H-02 | nakama-defold + extension-websocket fonctionnent avec Defold 1.13 en HTML5 | vérifiée : v3.4.0 + 4.2.4, HTML5 et Linux natif, sans modification. **Run D, en WS sur le réseau local** : le build HTML5 contre Nakama 3.41.0, par l'adresse de la page et le port 7550, sans réglage CORS (Nakama répond `*`, erreurs comprises) : authentification par appareil, pseudo, `team_set`, `room_create`/`room_find`, socket, salon, partie entière, coupure et retour dans le même match, revanche (`make journey J=online`). Pièges : le rappel d'une socket va au script qui l'a ouverte ; une erreur de socket porte sa raison dans `error.message`, une erreur HTTP dans `message` (`error` y vaut `{}`) ; un envoi sur une socket fermée par le navigateur lève une erreur avant l'événement de déconnexion. **WSS vérifiée** par le tunnel `blobattle.npc.fm` : le parcours en ligne entier (40 contrôles : Salon, partie comparée tick par tick, départ, retour, coupure, revanche, snapshot de 8 × 6) joué par l'adresse publique ; depuis la machine, aller-retour d'une entrée de 61 à 70 ms en moyenne, socket revenue en 2,8 s |
| H-03 | le runtime Lua de Nakama charge les fichiers de `shared/` sans copie ni modification | vérifiée : `shared/` monté en `modules/shared`, `require "shared.sim.x"` des deux côtés (D-01) |
| H-04 | une même sim donne la même somme de contrôle sous LuaJIT, Lua 5.1 et gopher-lua | **vérifiée au run A** sur la vraie sim : 3 vecteurs (2 à 8 équipes, marche, sauts, bazooka, grenades, 2400 ticks) donnent 27 sommes identiques sous les trois moteurs (`make conformance`) ; ré-enregistrés au run C pour les cartes à ciel ouvert, puis pour la poussée du bazooka à 1920, puis pour la tolérance de 2 px en l'air, le début de tour de 2 s et les rebonds des blobs projetés (le duel finit au tick 749 : 22 sommes en tout), puis pour la jauge de déplacement et le tentacule (run C2 : six champs de plus par chat et une troisième arme dans les munitions ; même script, mêmes fins), avec les noms des équipes et des membres, identiques aussi ; `sin`/`cos`/`exp`/`atan2` et `bit` divergent (sonde, D-02) **Run C3** : les vecteurs ré-enregistrés à chaque changement de la somme (champs du repas, cinquième munition, matériaux du terrain, niveau du liquide et rondes), chaque fois après avoir vérifié qu'ils rejouent les mêmes parties (sans les entrées nouvelles, les sommes d'avant reviennent) ; le duel passe à la graine 1240 (fini au tick 1555) ; mêmes sommes sous les trois moteurs après chaque tranche. **Run C5** : un quatrième vecteur, `quake` (graine 4), traverse trois séismes. **Run C6** : les vecteurs ré-enregistrés pour les munitions comptées, puis pour la sixième munition et `timer` qui compte le repli, scripts d'entrées inchangés ; un cinquième, `dynamite` (graine 42), pose la dynamite au deuxième tour de l'équipe 1, ré-enregistré seul quand la pose a rempli la jauge ; mêmes sommes sous les trois moteurs. **Run C8** : les vecteurs ré-enregistrés à 24w et 24x, scripts inchangés (des munitions puis `jet` et `facing` de plus dans la somme) ; à 24y, les caisses changent les parties dès le 3e tour : tous ré-enregistrés avec de nouveaux scripts, `quake` passé à la graine 10 (4 600 ticks, deux séismes), et un sixième, `crates` (graine 105, 3 équipes de 3, 6 000 ticks), où les blobs marchent vers les caisses et jouent les quatre armes qu'ils y trouvent (le script d'enregistrement a un mode `crates`) ; mêmes sommes sous les trois moteurs. |
| H-05 | reconstruire le rendu du terrain autour d'un cratère ne fait pas chuter les 60 images par seconde sur téléphone | pixel art (sonde) : 0,5 ms de creusage + 0,8 ms d'envoi en HTML5 à CPU ×4. **Voxel** (prototype, `docs/sonde-voxel/`) : 5 ms de maillage par cratère à CPU ×1, 39 ms à ×4, étalés en tranches de 2 à 4 ms par image sous le flash de l'explosion, 60 i/s tenues dans Chromium. **Run C**, dans le build HTML5 à CPU ×4 : tranches de 2,8 ms en moyenne, 3,6 ms au p95 (une à 5,0 ms sur 76 sur la plus grande partie), un cratère reconstruit en 0,12 à 0,27 s sous le flash de 0,3 s, en ne recalculant que les rangées et les bandes de 32 rangées qu'il touche. **Run C3** : les cartes à surplombs, arbres et grottes coûtent plus de faces ; cratère en 0,27 à 0,31 s en moyenne, 0,29 à 0,35 s au pire, sous un flash porté à 0,4 s, en tranches de 3,0 à 3,4 ms au p95 (4,1 ms une fois, mesuré pendant qu'un autre conteneur tournait ; au pire, une image isolée de 4,2 à 4,9 ms, comme au run C) ; le tunnel du Chomp, une bouchée par tick, en tranches de 3,1 à 3,2 ms au p95. **Run C5** : une faille du séisme (une centaine de rangées sur un ou deux morceaux) se reconstruit à CPU ×4 en tranches de 3,5 ms au p95, en 22 images au plus pour deux failles, loin des 62 que durent les secousses à 60 i/s (0,68 à 0,87 s dans SwiftShader, qui n'atteint pas 60 i/s). Pour cela, `build_row` lit les cases directement : 3,4 fois plus vite sous Lua 5.1 natif. Le GPU du téléphone reste à voir (H-11) : le build est servi sur le réseau local (`make serve`, `http://192.168.0.21:5373/`) pour que l'utilisateur l'ouvre sur son téléphone |
| H-06 | la taille maximale d'un message Nakama se règle assez haut pour un snapshot (§6.6) | **sans objet** (run B) : `socket.max_message_size_bytes` ne borne que ce que le serveur lit d'un client (4 Kio par défaut, gardés) ; un message sortant n'a pas de borne en octets. Mesuré : le plus gros snapshot fait 17 496 octets en JSON au run B, 16 571 avec les cartes à ciel ouvert du run C, 16 932 avec la poussée du bazooka à 1920 et le budget des bots hors ligne à 300, 17 090 avec la tolérance de saut (un champ de plus par chat), 20 854 avec la jauge et le tentacule du run C2 (six champs de plus par chat), 25 606 avec le repas du Chomp et les cartes du run C3 (matériaux, arbres, surplombs, stalactites, poutrelles) (8 équipes de 6 après 15 600 ticks de bots, écrit dans un test, entre 24 000 et 27 000) ; un snapshot de 16 574 octets d'une partie en cours arrive à nakama-js en un message et restaure exactement le monde (`make harness`). **Run D, le client Defold** : un snapshot de 24 668 à 26 332 octets (8 équipes de 6, page rechargée vers le tick 1 450) lui arrive en un message et le remet d'aplomb sans divergence ; 8,0 à 10,3 Ko pour 3 équipes de 2. **Run C5** : les failles découpent les rangées du terrain en plus de plages ; une forêt de 8 équipes de 6 fait 30 784 octets après 20 rondes et 10 failles (graine 29) ; **run C6**, avec les munitions comptées : 31 654 octets après 18 rondes et 11 failles ; **run C8**, avec `jet` et les quatre munitions des caisses : 32 117 octets, puis, avec les caisses, qui changent la partie, 31 011 octets après 19 rondes, 10 failles et 3 caisses sur la carte (graine 2, borné par un test entre 29 000 et 34 000) |
| H-07 | gopher-lua tient la sim à 30 Hz pour 4 parties simultanées sur la machine hôte | **vérifiée au run B** (`make harness`) : 4 parties simultanées à 8 équipes de 6 chats (1 humain, 7 bots difficiles) avancent chacune à 30,00 ticks/s sur 60 s, 78 ms au pire entre deux `ticks` ; côté serveur, 1,9 à 2,2 ms par tick en moyenne, 13 ms au pire, bots compris (i9-13900KF : 8 cœurs performants, 16 économes, sur lesquels le même travail coûte jusqu'à trois fois plus) |
| H-08 | le tunnel Cloudflare transporte la WebSocket de Nakama | vérifiée (npchero, telegraph). **Pour Blobattle** : tunnel `blobattle`, un seul hôte `blobattle.npc.fm`, partagé par chemin entre nginx (le build) et Nakama (`/v2/`, `/ws`, `/healthcheck`) ; le parcours en ligne joué par l'adresse publique, en WSS (voir H-02) |
| H-09 | Defold HTML5 gère le multi-touch et le paysage sur Chrome Android et Safari iOS | **run C, dans Chromium avec le toucher émulé** : les doigts arrivent par `TOUCH_MULTI` (Defold HTML5 ne fabrique pas d'événement souris depuis le toucher), deux doigts à la fois (marcher et pincer) ; paysage et portrait par les dispositions des scènes, écran de rotation en partie. Sur Chrome Android et Safari iOS : le build est servi sur le réseau local (`http://192.168.0.21:5373/`), à ouvrir par l'utilisateur ; au plus tard au run E **Run D** : non vérifiée sur son téléphone (l'utilisateur ne pouvait pas pendant le run, et passera par le tunnel du run D2) ; en ligne, le mode test (`?test=1`) affiche en bas de l'écran l'aller-retour d'une entrée, la dernière reconnexion et la taille du dernier snapshot ; **par le tunnel**, l'utilisateur a joué en ligne sur son téléphone : « super fluide même en multi sur le tel » (un ressenti ; le toucher à deux doigts et l'aller-retour mesuré restent à relever) |
| H-10 | une taille de registre Lua relevée suffit à gopher-lua pour les tableaux de la sim | **inutile** (run A) : la sim, les vecteurs et les bots passent avec la taille par défaut (512) ; seul un `table.concat` de 256 éléments échouait dans la sonde, et la sim n'en fait pas. À retenir aussi : **le runtime Lua de Nakama n'a pas la bibliothèque `coroutine`** |
| H-11 | le GPU d'un téléphone de milieu de gamme tient le rendu voxel à 60 i/s en HTML5 (terrain d'environ 26 000 sommets, jusqu'à 48 blobs d'environ 1 500 sommets) | **non vérifiée au run C** : Chromium sans interface rend avec SwiftShader (~25 ms par image à CPU ×4, sans valeur pour un téléphone) ; terrain mesuré de 22 800 à 40 000 sommets. Le build est servi sur le réseau local (`make serve`, `http://192.168.0.21:5373/?test=1` montre les mesures dans `window.blobattle`) pour le téléphone de l'utilisateur ; au plus tard au run E (tranche 30) ; **en ligne par le tunnel**, « super fluide » sur le téléphone de l'utilisateur, à l'œil, sans mesure des images par seconde |

### Versions épinglées

Defold et `bob.jar` **1.13.1** (JRE Temurin **25.0.4.1**) · Chrome for Testing **154.0.8037.57**
(*headless shell*, parcours) · Nakama **3.41.0** (`registry.heroiclabs.com/heroiclabs/nakama:3.41.0`)
· nakama-defold **v3.4.0** · extension-websocket **4.2.4** · Postgres **16-alpine** · Caddy
**2.10.2-alpine** (le HTTPS sans tunnel, certificat Let's Encrypt automatique). Les images sont
épinglées par digest dans `compose.yaml` ; une montée de version est un commit à part
(`docs/conventions.md` §7).

### Le téléphone

- Safari sur iPhone n'autorise pas le plein écran d'une page : le build HTML5 est une **PWA**
  installable (manifeste, icônes), qui s'ouvre sans barre d'adresse depuis l'écran d'accueil.
- L'écran doit rester allumé pendant une partie (Wake Lock en HTML5, `window.set_dim_mode` en natif).
- Un téléphone passe en arrière-plan, se verrouille, perd le réseau : la reconnexion est un parcours
  normal (D-08), pas une erreur.
- Taille de texture maximale sûre sur mobile : 4096 px de côté.

## 4. Décisions d'architecture

Numérotées, citables en revue et en commit. Une décision ne se contredit pas dans le code : elle se
réécrit ici d'abord.

- **D-01 — Une seule simulation, en Lua pur, partagée.** `shared/` est exécuté tel quel par le runtime
  Lua de Nakama et par le client Defold. Il n'appelle aucune API de moteur : ni `nk`, ni `go`, `gui`,
  `msg`, `vmath`, `sys`, `json`. Seul `server/` connaît `nk` ; seul `client/` connaît Defold. Un test
  d'architecture le fait respecter.
  - **Organisation** : `shared/` est à la racine du dépôt. Nakama le monte en lecture seule comme
    `modules/shared` ; le projet Defold `client/` y accède par le lien symbolique
    `client/shared → ../shared`. Des deux côtés : `require "shared.sim.world"`.
  - **Aucun effet de bord au chargement** : Nakama exécute chaque fichier `.lua` de son dossier de
    modules au démarrage. Un module de `shared/` définit et renvoie sa table, rien d'autre.
- **D-02 — Déterministe au bit près.** Dans `shared/` :
  - tout nombre est un **entier** ; les positions et vitesses sont en virgule fixe, **256 unités par
    pixel d'art** (`FP = 256`) ; aucun littéral décimal (`0.5`) ;
  - division entière par une fonction dédiée (`fixed.div`, arrondi vers le bas, défini pour les
    négatifs) ; racine carrée entière (`fixed.isqrt`) ; trigonométrie par une table d'entiers
    générée une fois et versionnée ;
  - interdits : `math.sin`, `math.cos`, `math.tan`, `math.atan`, `math.atan2`, `math.pow`,
    `math.exp`, `math.log`, `math.sqrt`, `math.random`, `math.randomseed`, `os.*`, `io.*`,
    `pairs`, `next`, `bit`, `string.format` sur un nombre, `tostring` sur un nombre ;
  - on ne parcourt que des tableaux indexés (`ipairs` ou `for i = 1, #t`), et un tableau n'a jamais
    de trou : `#t` n'est défini de la même façon partout que sans `nil` au milieu ;
  - `table.sort` seulement avec un comparateur qui départage tout (par identifiant en dernier
    recours) : l'algorithme de tri diffère d'un moteur à l'autre ;
  - le hasard vient d'un générateur à graine (§5.1) ; aucune horloge ;
  - toute valeur intermédiaire reste sous 2^50 en valeur absolue : à cette taille, `math.floor(a / b)`
    et `%` donnent le résultat exact sous les trois moteurs. Les bornes sont écrites dans
    `shared/sim/rules.lua` et vérifiées par un test.
  Un test lit les sources de `shared/` et échoue sur tout ce qui précède. Il fonctionne par **liste
  blanche** (`spec/support/determinism.lua`) : un global ou un champ de `math`, `string` ou
  `table` qui n'y figure pas est refusé, et les opérateurs `/`, `%` et `^` n'existent que dans
  `shared/sim/fixed.lua`.
- **D-03 — Le serveur fait autorité, les clients rejouent.** La partie tourne dans un match Nakama à
  30 Hz. Le serveur diffuse **les entrées numérotées par tick**, pas l'état. Chaque client applique les
  mêmes entrées aux mêmes ticks et n'avance jamais au-delà du dernier tick confirmé par le serveur. Le
  serveur envoie une somme de contrôle chaque seconde ; un écart, une arrivée ou une reconnexion
  déclenche un snapshot (§6.6).
- **D-04 — La visée est locale, seul le tir voyage.** Le geste de visée (angle, puissance) ne quitte
  pas le téléphone tant qu'on n'a pas tiré. Le tir part avec `{arme, angle, puissance, minuterie}`.
  Marcher et sauter partent comme des changements d'état (appuyé, relâché) appliqués au tick suivant
  côté serveur, sans prédiction côté client en V0 (question Q-01).
- **D-05 — Une arme est un fichier.** Une arme = un module `shared/sim/weapons/<id>.lua` (données +
  fonctions de rappel) + une ligne dans le registre + ses textes + son icône. Rien dans le cœur de la
  sim ne nomme une arme. Un test de contrat commun passe chaque arme enregistrée.
- **D-06 — Un bot est un joueur sans mains.** Un bot produit les mêmes entrées qu'un humain, par le
  même chemin, et ne lit que ce qu'un humain voit (l'état public de la sim, vent compris). En ligne,
  les bots tournent **uniquement sur le serveur** ; leurs entrées sont diffusées comme les autres.
  Hors ligne, le client les fait tourner lui-même. Le cerveau d'un bot ne modifie jamais le monde
  qu'il évalue.
- **D-07 — Un match « room », trois phases.** Un salon et sa partie sont le même match Nakama :
  `lobby` → `playing` → `ended` → `lobby` (revanche). Personne ne change de match entre le salon et
  la partie.
- **D-08 — Une place n'est jamais vide.** Chaque équipe est Ouverte ou Bot. Au lancement, toute place
  ouverte sans humain devient un bot. Tant qu'un humain est déconnecté, un bot joue les tours de son
  équipe, y compris celui en cours ; l'humain reprend la main au premier début de tour qui suit son
  retour (§6.7). Un humain qui quitte la partie laisse son équipe au bot jusqu'à la fin.
- **D-09 — Le monde est une grille, rendue en voxels.** Une cellule de terrain = un voxel du rendu,
  extrudé en profondeur ; le terrain est un tableau plat de cellules et les liquides ne sont pas des
  cellules mais un niveau (§5.3). Le rendu est en 3D (§7.4), mais tout ce qui compte pour le jeu vient
  de la grille 2D de la sim : rien de ce qui n'existe qu'à l'écran (profondeur, débris, déformation
  des blobs) n'influence la partie.
- **D-10 — Paysage pour jouer, tout aux pouces.** Une partie se joue en paysage ; en portrait, un
  écran demande de tourner le téléphone, et la partie continue sans attendre. Toute action est
  atteignable aux pouces, chaque cible tactile fait au moins 44 points. Sur ordinateur, la même
  interface répond au clavier et à la souris, sans les pavés des pouces, que le clavier remplace
  (§7.3).
- **D-11 — Aucun texte en dur.** Identifiants en anglais, un catalogue par langue ; la V0 ne livre que
  le catalogue anglais (`en`), le français viendra sans toucher au code. Le serveur envoie des
  identifiants et des paramètres, jamais une phrase. Les noms (pseudo, équipes, membres) ne se
  traduisent pas. Seule exception : les messages de secours du gabarit HTML5 de Defold
  (`client/brand/engine_template.html` : page ouverte en fichier local, WebGL absent), affichés avant
  que le moteur et ses catalogues ne démarrent.
- **D-12 — La somme de contrôle fait foi.** Tout état de sim a une somme de contrôle canonique. Des
  vecteurs de conformité versionnés (graine + réglages + script d'entrées → sommes attendues à des
  ticks donnés) passent sous LuaJIT, sous Lua 5.1 et dans le runtime de Nakama. Une divergence fait
  échouer la suite.
- **D-13 — Tout tourne en Docker, sauf l'éditeur.** L'hôte n'a besoin que de Docker. Lua 5.1,
  LuaJIT, busted, luacheck et StyLua vivent dans l'image `blobattle-tools` dès le run A ; Node (harnais,
  run B), un JRE Java 25 (Temurin, qu'exige `bob.jar` 1.13.1), `bob.jar` et Chromium sans interface
  (le *headless shell* de Chrome for Testing, avec SwiftShader) pour les builds et le parcours (run C)
  s'y ajoutent au run qui en a besoin, chacun épinglé par sa somme. L'éditeur Defold
  est facultatif, pour regarder et retoucher des scènes à la main.
- **D-14 — Le serveur ne fait confiance à aucun client.** Chaque message est validé à l'entrée du
  match : forme, bornes, expéditeur (seul le joueur actif agit sur la partie, seul l'hôte règle le
  salon), taille maximale, débit. Un message invalide est jeté et compté, jamais appliqué.
- **D-15 — Rien de personnel.** Un identifiant d'appareil, un pseudo, le nom de son équipe et ceux de
  ses membres (§6.1), rien d'autre. Pas
  d'analytics, pas d'adresse IP dans les logs applicatifs. Le tunnel (ou le reverse proxy) n'expose
  que le build web et l'API de Nakama ; la console Nakama et Postgres restent sur `127.0.0.1`, nginx
  aussi par défaut (`WEB_BIND`).

## 5. La simulation

`shared/sim/` — Lua pur (D-01, D-02). Toutes les valeurs de réglage vivent dans
`shared/sim/rules.lua`, pas dans les modules qui les utilisent. Les nombres ci-dessous sont les
valeurs de départ ; le banc (§10.4) dit s'ils tiennent.

### 5.1 Unités, temps, hasard

- **Tick** : 30 par seconde. Tout temps de jeu se compte en ticks.
- **Positions et vitesses** : virgule fixe, `FP = 256` unités par pixel d'art. Axe `y` vers le bas.
- **Angles** : entiers de `0` à `1023` (`ANGLES = 1024`) ; `0` = droite, `256` = haut. La table
  `shared/sim/trig.lua` donne `sin` et `cos` à l'échelle `trig.SCALE = 16384`. Elle est produite par
  `tools/gen_trig.lua` (qui a le droit d'utiliser `math.sin`) et versionnée ; la sim ne la recalcule
  jamais. Elle est symétrique par construction (un quart calculé, trois recopiés).
- **Arrondis** : une division qui ramène une grandeur orientée à l'échelle — une vitesse décomposée
  par la table trigonométrique, une direction de poussée — s'arrondit **au plus proche, à mi-chemin en
  s'éloignant de zéro** (`fixed.round_div`), pour qu'un tir à gauche soit l'exact miroir du même tir
  à droite. Toute autre division entière arrondit vers le bas (`fixed.div`). Diviser par zéro lève une
  erreur ; aucune fonction de `fixed` ne rend `-0`.
- **Hasard** : générateur de Lehmer modulo `2147483647` (famille Park–Miller), exact en double.
  Quatre flux indépendants dérivés de la graine de partie `g` : `map` (génération ; multiplicateur
  48271, état initial `g`), `sim` (vent ; 69621, `g + 1000003`), `bots` (bruit des bots ; 16807,
  `g + 2000006`), `names` (noms générés des équipes de bots et de leurs membres ; 39373,
  `g + 3000009`), chaque état ramené dans `[1, 2147483646]`. Le flux `bots` d'une équipe `e` part de
  la graine `g + e` (ramenée dans les bornes). Un tirage d'un flux ne décale jamais les autres. Seul
  `sim` fait partie de l'état du monde ; `map` ne sert qu'à la génération, `bots` appartient au pilote
  des bots (§9) et `names` aux noms (§6.1).
- **Somme de contrôle** : deux hachages polynomiaux modulo `2147483647` (multiplicateurs distincts),
  sur les champs canoniques de l'état, dans un ordre fixé par le code (§5.9).

### 5.2 La partie

| Réglage | Défaut | Bornes |
|---|---|---|
| équipes | 4 | 2 à 8 |
| chats par équipe | 4 | 1 à 6 |
| points de vie d'un chat | 100 | fixe en V0 |
| durée d'un tour | 45 s | 30, 45, 60, 90 s |
| repli après le tir | 3 s ; après une arme posée, sa mèche (5 s pour la dynamite) | fixe |
| carte | au hasard | forêt, volcan, au hasard (le liquide en découle : eau, lave) |
| niveau des bots | moyen | facile, moyen, difficile |
| graine | au hasard | entier de 1 à 2147483646 (une graine = un état du générateur) |

- **Ordre** : les équipes jouent dans l'ordre des places, à partir d'une équipe tirée au sort (flux
  `map`). Une équipe sans chat vivant est sautée. Chaque équipe fait tourner ses chats vivants dans
  l'ordre de leur numéro.
- **Fin** : quand il reste au plus une équipe avec un chat vivant. Une équipe : elle gagne. Aucune :
  match nul.
- **Limite** : après 30 rondes (chaque équipe encore en vie a joué 30 fois), la partie s'arrête et
  l'équipe qui a le plus de points de vie cumulés gagne ; égalité = match nul. C'est une protection,
  pas une règle de jeu : le banc (§10.4) mesure combien de parties l'atteignent.

### 5.3 La carte

Générée depuis la graine (flux `map`), identique sur le serveur et sur chaque client. Un client ne
reçoit jamais le terrain d'une partie qui commence, il le génère ; il ne le reçoit que dans un
snapshot.

- **Taille** : hauteur `H = 256`. Largeur `W = clamp(320 + 18 × chats_total, 384, 1024)` : 2 équipes
  de 4 = 464 ; 8 équipes de 4 = 896.
- **Relief** : une ligne de surface par bruit de valeur 1D à trois octaves, entre 35 % et 75 % de `H`
  depuis le haut. Sous la surface, le terrain est plein jusqu'en bas.
- **Grottes** : un bruit de valeur 2D à deux octaves, évalué sur des grilles grossières (une valeur
  tous les 32 px, puis tous les 8 px, interpolation entière lissée) ; sous seuil, la cellule est
  vidée, seulement dans la bande entre la surface +12 px et le niveau du liquide −8 px. Les amas de
  terrain de moins de 64 cellules non reliés au bas de la carte sont supprimés (remplissage par
  diffusion) ; les amas plus gros restent, suspendus.
- **Liquide** : un niveau `L = H − 24`. Toute cellule vide sous `L` est du liquide. Sur les 72 px de
  chaque bord, la surface descend en pente jusqu'à 20 px sous `L`, atteints à 32 px du bord : **les
  32 derniers pixels de chaque côté sont un bassin de liquide, visible à gauche et à droite**. Sortir
  de la carte par un côté, c'est tomber dans le liquide. Le liquide vient de la carte (eau à la forêt,
  lave au volcan) ; « au hasard » se tire sur le flux `map`.
- **Deux cartes** (run C3, sur le modèle de la planche « Forêt » de
  `docs/planche_maps_worms_like.pdf`), tirées de la même graine par le même
  générateur, qui ajoute par biome :
  - **des surplombs**, dans les deux : des creux horizontaux sous le rebord des pentes, qui laissent
    une lèvre de terrain en porte-à-faux ;
  - **la forêt** : des arbres (un tous les ~60 px de surface à ciel ouvert : tronc de 2 px sur 10 à
    16 px, houppier rond de 5 à 8 px de rayon), en terrain destructible, qui servent de couverture ;
    de l'eau qui ne monte pas ; et, **dès la fin de la 8e ronde, un séisme à chaque fin de ronde**
    (ci-dessous) ;
  - **le volcan** : plus de cavernes, des stalactites (pointes de 3 à 10 px sous les plafonds et les
    surplombs), des poutrelles d'acier en travers du ciel comme dans Worms (à la demande de
    l'utilisateur), de la lave qui **monte de 2 px à chaque fin de ronde, dès la première** (dès la 5e
    au run C3, dès la 1re à la demande de l'utilisateur au run C4 ; une ronde finit
    quand chaque équipe en vie a joué une fois de plus) et noie qui elle atteint, sur-le-champ : les
    blobs noyés meurent à la fin du tour, avant la fin de partie, la limite des rondes et le tour
    suivant.
  - **le séisme de la forêt** (la mort subite de la forêt, demandé par l'utilisateur :
    « quand la partie dure trop longtemps, des tremblements de terre […] ça créé des failles ça
    s'écarte et les blobs peuvent alors tomber dans l'eau ») : à la fin de chaque ronde à partir de
    la 8e (`QUAKE_FROM`), là où la lave du volcan monte, le n-ième séisme (n = rondes finies − 7)
    passe entre la fin du tour et le tour suivant, dans un état à lui, `quake` (§5.6), et non pendant
    le début du tour suivant : un bot cherche son tir dès le `turn_start` (§9), sur un terrain et des
    blobs qui ne bougent plus. Si la partie s'arrête à cette fin de ronde (une équipe au plus, ou la
    limite des rondes), il n'y a pas de séisme ;
    - **la secousse** : trois secousses, aux ticks 1, 16 et 31 de l'état `quake` (espacées de
      15 ticks) ; chacune donne à chaque blob vivant posé au sol, dans l'ordre du tableau des chats,
      une poussée tirée sur le flux `sim`, de côté entre −P et +P et vers le haut de `256` FP/tick,
      avec P = `192 + 64 × n` FP/tick, borné à `704`. Au-delà de `384` de côté, le blob est projeté
      (§5.4 : rebonds, glissade, chocs). La secousse ne blesse pas : seules comptent la chute (§5.4,
      ~40 px) et l'eau ; ces dégâts et ces morts, hors de tout tour, ne comptent pour aucune équipe
      (§6.4) ;
    - **les failles** : à la première secousse, avant la poussée, chaque faille déjà ouverte s'écarte
      de 2 px (un de chaque côté : un blob qui tient sur son bord y tombe), puis une faille nouvelle
      s'ouvre : une colonne `x` tirée sur le flux `sim` dans les 60 % centraux de la largeur (de 20 %
      à 80 % de `W`, moins sa largeur, comme les puits), à plus de 24 px de tout puits et de toute
      faille (l'écart entre leurs bords ; 8 tirages au plus, sinon pas de faille nouvelle). Large de
      4 px, elle descend de la surface (la première rangée où l'une de ses 4 colonnes a de la terre,
      son `haut`) jusqu'à 4 px sous `L`, donc remplie d'eau, en zigzag : par tranches de 4 rangées
      depuis son haut, la première à `x`, chaque suivante décalée de −1, 0 ou +1 pixel de la
      précédente (tiré), sans jamais s'écarter de plus d'un pixel de `x` ; au-dessus de son haut,
      elle reste à `x`. Une faille est un enregistrement de l'état (colonne, largeur, haut,
      décalages) ; elle se creuse case par case, de la rangée 0 jusqu'à son bas, sur toute sa
      largeur à l'ouverture et sur ses deux nouveaux bords quand elle s'écarte (un bord sur une pente
      se creuse depuis sa propre surface) : chaque case pleine est un disque de rayon 0 du journal du
      terrain (§5.9), comme les cratères ; une case déjà vide n'y entre pas ;
    - **le tour qui suit** : l'état `quake` dure jusqu'à ce que tout soit immobile après la troisième
      secousse (300 ticks au plus, comme `settling`) ; puis les morts s'appliquent, la fin de partie
      se teste, et le tour suivant commence par son `turn_start` : on ne vise jamais pendant que le
      sol bouge ;
    - les bots ne prévoient pas le séisme : ils évaluent le terrain courant (§9) ;
    - chiffres de départ. Au banc du run C5, la part des parties de forêt qui atteignent la limite
      des rondes tombe de 44,9 % à 5,6 % (Q-03).
  Les garanties de la carte (liquide aux deux bords, puits, apparition à ciel ouvert, loin des
  bords et des puits) valent pour les deux ; l'apparition exclut d'elle-même le dessous d'un
  houppier, d'un surplomb ou d'une poutrelle. Le détail, tout sur le flux `map` :
  - l'ordre : relief, remplissage, **placement des puits**, surplombs, grottes, creusement des
    puits, îlots, puis arbres (forêt) ou stalactites et poutrelles (volcan), puis apparitions ;
  - **un surplomb** se tente tous les 8 à 24 px dans les collines (entre les rives, pas sur leurs
    pentes), à plus de 16 px d'un puits : un creux elliptique de 9 à 14 px de demi-largeur et 3 à 5 px
    de demi-hauteur, sous une lèvre de 4 px au bord de la pente (le relief des collines reste
    au-dessus du fond des grottes, le creux aussi) ; il n'est creusé que si, d'un côté, le relief passe sous le haut du creux à un
    pixel du bout de sa demi-largeur (le creux s'ouvre sur la pente) et si, de l'autre, il remonte au-dessus
    du bas de la lèvre juste derrière lui (la lèvre reste accrochée à la colline) ; après un creux,
    l'essai suivant part de son bout ;
  - **un arbre** se plante tous les 45 à 75 px sur le sol à ciel ouvert entre les rives : deux
    colonnes au même niveau, leurs voisines pas plus hautes, au moins 8 px au-dessus de `L`, houppier
    dans la carte et à plus de 1 px d'un puits ; tronc en bois (`2`), houppier en feuillage (`3`)
    centré entre les deux colonnes du tronc, qu'il chevauche de 2 px, posés seulement sur du vide ;
    aucun chat n'apparaît sur un arbre (il se pose sur la terre ou sur une poutrelle) ;
  - **une stalactite** se tente tous les 8 à 16 px, sous chaque plafond de la colonne (terrain au-dessus,
    vide au-dessous, sous la surface, au-dessus de `L`) qui laisse au moins 4 px de vide sous sa pointe : 3 px de
    large en haut, 1 px à la pointe ;
  - **le volcan** vide ses grottes sous un seuil de 390 au lieu de 300 ;
  - **une poutrelle** (volcan, après les stalactites, avant les apparitions) se tente entre les
    rives, 40 à 90 px après la précédente (un essai qui ne peut pas se poser glisse d'une colonne) :
    une barre horizontale d'acier (`4`) de 16 à 32 px de long et 3 px d'épaisseur, posée à une hauteur
    tirée entre 12 et 56 px au-dessus du plus haut sol sous elle, dans la carte et à plus de 16 px d'un
    puits ; un chat peut apparaître dessus (plus nombreuses et à des hauteurs variées à la demande de
    l'utilisateur, run C4) ; elle flotte (elle n'est pas un îlot à retirer) et se creuse comme le
    reste ;
  - mesuré sur 200 graines, 4 équipes de 4 : 3,5 surplombs par carte (6 cartes sur 200 sans),
    7,1 arbres en forêt, 28 stalactites et 4,7 poutrelles au volcan (1,8 au run C3), où 24,5 % des
    blobs apparaissent sur une poutrelle, 6 % de vide en plus au volcan.
- **Puits** : `1 + floor(W / 400)` puits (1 à 3), de 8 à 12 px de large, creusés de la surface
  jusqu'au liquide, dans les 60 % centraux de la largeur, espacés d'au moins 96 px. Une tentative qui
  n'arrive pas à les placer tous est une tentative ratée.
- **Points d'apparition** : **à ciel ouvert** (aucune cellule de terrain au-dessus de la boîte du
  chat, dans aucune de ses colonnes : la surface ou le dessus d'un îlot, à n'importe quelle hauteur ;
  personne ne commence dans une grotte). Pour chaque colonne, le chat se pose sur le sol le plus haut
  sous les six colonnes de sa boîte : un candidat par colonne, au moins 8 px au-dessus de `L`, à au
  moins 16 px d'un puits et d'un bord. Les points se tirent au hasard parmi les candidats (flux
  `map`), à au moins 24 px de tout autre chat. Les équipes sont intercalées.
  Si le tirage n'en place pas assez, un balayage de gauche à droite les place au plus serré à la même
  distance ; s'il en manque encore, la distance se relâche de 4 px par passe (jusqu'à 12 px), puis la
  génération recommence avec la sous-graine suivante (8 essais au plus, puis erreur explicite).
  Mesuré au run C sur 200 graines : toutes les parties gardent 24 px, sauf 8 équipes de 6 (48 chats
  sur la plus grande carte) : 20 px, ou 16 px pour 13 graines sur 200.
- **Coût** : la plus grande carte (1024×256) se génère en moins de 150 ms sous LuaJIT, moins de 1 s
  sous Lua 5.1 et moins de 3 s dans Nakama (le serveur la génère aussi, avant `game_start`). Mesuré
  au run A et écrit dans un test de performance ; si Nakama dépasse, le bruit des grottes devient
  plus grossier, la spec d'abord.
- **Stockage** : un tableau Lua plat de `W × H` entiers, ligne par ligne (`0` vide ; une case pleine
  porte son matériau : `1` terre ou roche, `2` bois, `3` feuillage, `4` acier ; la sim ne regarde que « vide ou
  non », le rendu colore par matériau, la somme des cellules et le snapshot les couvrent). La
  sonde l'a mesuré plus rapide qu'un buffer ou qu'une grille empaquetée sur les trois moteurs.

### 5.4 Les chats

- **Boîte de collision** : 6 px de large, 7 px de haut, ancrée en bas au centre.
- **Marche** : 1 px tous les 2 ticks (15 px/s). Monte une marche de 3 px au plus, descend de 3 px au
  plus ; au-delà, le chat tombe.
- **Saut** : vitesse initiale `(±256, −614)` en FP par tick, soit environ 14 px de haut et 24 px de
  long sur sol plat.
- **Gravité** : `+51` FP par tick². Vitesse limitée à `3072` FP par tick sur chaque axe.
- **En l'air, une tolérance de 2 px par vol** (`AIR_NUDGE`), pour qu'un voxel isolé n'arrête pas
  un saut : quand la boîte heurte le terrain de côté, le chat passe s'il le peut en montant de 1 puis
  2 px, sinon en descendant de 1 puis 2 px ; sinon sa vitesse horizontale tombe à zéro. Quand il se
  cogne la tête en montant, il passe s'il le peut en glissant de 1 puis 2 px de côté ; sinon sa
  vitesse verticale tombe à zéro. Ces décalages puisent dans une réserve de 2 px, remplie quand le
  chat quitte le sol (saut, poussée, chute) et gardée dans son état (`nudge`, dans la somme de
  contrôle et le snapshot, version 2) : un escalier ou une pente ne se gravit pas en l'air, et un mur
  ou un plafond plus épais que 2 px l'arrête comme avant.
- **Projeté, il rebondit et glisse**, comme dans Worms : un chat qui file de côté à plus de `384`
  FP/tick (un saut va à 256, il n'est pas concerné) rebondit sur un mur en repartant en sens inverse
  à 50 % de sa vitesse ; s'il touche le sol à plus de `700` FP/tick en filant ainsi, il rebondit à
  30 % de sa vitesse verticale et garde 70 % de sa vitesse horizontale (événement `rebounded`). Quand
  il se pose en filant ainsi, il glisse avec 50 % de sa vitesse horizontale, freinée de `128` FP par
  tick, en suivant le sol comme la marche (une marche de 3 px au plus, une descente de 3 px au plus) ;
  arrêté par un mur, il s'arrête ; au bord d'un vide, il repart en l'air. Les pourcentages
  s'arrondissent au plus proche, symétriquement (§5.1).
- **Atterrissage** : un chat qui se pose sans filer ainsi (saut, chute) pose sa vitesse horizontale à
  zéro. À chaque choc au sol, rebond compris, si la vitesse verticale d'impact dépasse `1024` FP/tick
  (une chute d'environ 40 px ; un saut retombe jusqu'à ~30 px plus bas sans dommage), dégâts =
  `floor((v − 1024) × 20 / 256)`. Le seuil était de `794` (24 px) jusqu'au run D : un saut qui
  retombait 12 px plus bas blessait déjà et finissait le tour, ce que l'utilisateur a relevé en
  jouant (« on prend des dégâts de hauteur beaucoup trop rapidement »), et il a choisi ~40 px. Une chute qui blesse le chat
  actif termine son tour.
- **Liquide** : un chat dont le centre de la boîte passe sous `L` meurt, cause `liquid`. Un chat qui
  sort par un côté meurt aussi, cause `liquid`.
- Les chats ne se bloquent pas entre eux en marchant. **Un chat projeté** (plus de `384` FP/tick de
  côté, en vol ou en glissade) dont la boîte en touche une autre pendant son déplacement pixel par
  pixel, en s'en rapprochant, lui transmet `60` % de leur écart de vitesse et en garde le reste
  (quantité de mouvement conservée, arrondis symétriques) ; le touché décolle (au moins `256` FP
  vers le haut) et rebondit ou glisse à son tour. Sans dégâts : la chute compte comme d'habitude.
  Deux chats ne se cognent qu'en se rapprochant (un choc les éloigne ; un chat cogné qui rebondit sur
  un mur peut revenir cogner le premier, dans le même tick), dans l'ordre du tableau des chats ; un
  chat qui en cogne un autre en glissant et y gagne une vitesse verticale décolle. Un chat qui mange
  (Chomp) ne se cogne pas : un chat projeté le traverse comme un chat qui marche. Le fantôme des
  bots ne voit pas les autres chats (il évalue un tir, pas les chocs en chaîne).
- **Jauge de déplacement** : au début de son tour, le chat actif a une jauge pleine de `3000` points
  (`GAUGE`). Marcher coûte `20` par pixel, un saut `200`, lancer le tentacule `300` posé et `100` en
  l'air (`GAUGE_TENTACLE_AIR`, pour enchaîner les prises), rester accroché `3` par tick. Un pas, un
  saut ou un lancer que la jauge ne couvre pas n'a pas lieu ; accroché, une jauge vide lâche le
  tentacule. Jauge vide, le chat vise et tire encore. Poser une arme (la dynamite) **remplit la
  jauge** : le repli qui suit laisse toujours de quoi s'éloigner, même après avoir marché jusqu'à
  l'ennemi (run C6, « on a le temps de bouger au moins 5 sec » ; Worms n'a pas de jauge). La jauge
  fait partie de l'état du chat (`gauge`).
- **Le tentacule** (le grappin, genre `utility`, §8.2) : le blob tend un tentacule selon l'angle de la
  visée (la puissance est ignorée), depuis le centre de sa boîte, pixel par pixel sur la table
  trigonométrique, jusqu'à `120` px (`TENTACLE_RANGE`) ; un point du rayon qui tombe exactement entre
  deux colonnes compte dans celle vers laquelle va le rayon (celle du regard du chat s'il monte droit),
  pour qu'un lancer à gauche soit le miroir du même lancer à droite. Au premier pixel de terre, il s'y
  accroche :
  le point d'accroche est ce pixel, la longueur de la corde la distance entière (`isqrt`) du centre
  de la boîte à ce point, bornée entre `4` et `120` px (on remonte jusqu'à l'ancre). S'il ne touche rien, il se rétracte : seul le
  lancer est décompté (`tentacle_missed`, avec le pixel où il s'arrête). Accroché (`hanging`), à chaque
  tick, celui du lancer compris :
  1. la jauge perd 3 points ; vide, le tentacule lâche ;
  2. la corde se raccourcit ou s'allonge de `256` FP selon l'entrée `climb`, dans ses bornes ; tendue,
     la part de la vitesse qui tourne autour de l'ancre (perpendiculaire à la corde) est multipliée par
     l'ancienne longueur sur la nouvelle (`round_div`) : remonter en se balançant accélère, comme sur
     une balançoire ;
  3. la gravité s'ajoute à la vitesse ; une direction tenue (`move`) ajoute une poussée tangente de
     `64` FP/tick dans son sens (la tangente dont la composante horizontale a ce signe), arrondie
     symétriquement ;
  4. la corde tendue, la vitesse perd ce qui tirerait sur elle (sa composante qui s'éloigne du point
     d'accroche, `round_div`) ; puis le centre visé (position + vitesse) est ramené sur le cercle s'il
     en sort (`round_div` sur l'écart au point d'accroche), et la vitesse perd de nouveau ce qui
     tirerait sur la corde au point atteint (sans quoi, en laissant filer la corde, la gravité
     s'empilait dans une vitesse que le blob ne prenait pas). Le
     balancier garde ainsi son élan : une fois lancé, il perd 3 à 10 % de sa hauteur par
     demi-oscillation (d'autant plus que la corde est courte et l'amplitude grande ; davantage au
     premier passage s'il part corde molle), et n'en gagne pas (au run C2, la vitesse devenait le
     déplacement obtenu, et le balancier perdait 22 à 30 % de sa hauteur à chaque passage) ;
  5. le chat va vers ce point pixel par pixel comme en vol, horizontalement puis verticalement. Une
     case pleine l'arrête sur cet axe ; si sa vitesse y allait vers la terre, elle repart en sens
     inverse à `90` % (`ROPE_BOUNCE`, arrondi symétrique ; ni décalage de 2 px) : il rebondit sur
     une paroi pour reprendre de l'élan, et tiré contre une pente, il la longe au lieu de s'y coller.
     L'autre axe finit son pas. Dès qu'un axe a été arrêté, tout axe qui n'a pas rebondi prend pour
     vitesse le déplacement qu'il a fait : un chat retenu par la terre n'accumule pas de vitesse qu'il
     ne prend pas. Enfin la vitesse est bornée à `3072` FP/tick par axe, comme en vol. Il peut finir
     au-delà du cercle de sa corde : de moins d'un pixel le long d'une pente, et beaucoup plus quand
     il remonte la corde contre de la terre qui le retient (il y reste, sans prendre de vitesse,
     jusqu'à ce qu'il laisse filer ou saute).
  Un saut (`jump`) lâche le tentacule : le chat part avec sa vitesse, augmentée de l'élan d'un saut
  (`±256`, `−614`) si la jauge couvre ses `200` points (sinon il lâche seulement, sans rien payer),
  et §5.4 s'applique (rebonds, glissade, réserve de 2 px remplie). Remonter jusqu'à l'ancre, sauter
  depuis la corde et relancer en l'air font grimper une paroi : une falaise de 60 px se gravit en
  quatre lancers (écrit dans un test). Une explosion qui le pousse, ou la sortie de l'état `aiming`
  (temps écoulé, dégâts), le lâche aussi. En l'air, il peut relancer le tentacule. Accroché, il ne
  tire pas ; posé, il vise et tire comme d'habitude. Le tentacule ne s'enroule pas autour des coins.
- **Le jetpack** (run C8, genre `utility`, §8.2) : l'allumer remplit son carburant (`jet`, 150
  ticks, `JET_FUEL`) et fait décoller le chat (vitesse verticale `−256`, `JET_LIFT`). Tant que
  `jet > 0`, le chat vole comme en l'air (gravité, tolérance de 2 px, chute), et avant chaque pas :
  ▲ tenu (`climb = −1`) retire `96` FP/tick à sa vitesse verticale (`JET_UP`), sans passer sous
  `−512` (`JET_MAX_UP`) ; une direction de marche tenue ajoute `±32` à l'horizontale (`JET_SIDE`)
  sans la porter au-delà de `±320` (`JET_MAX_SIDE`, sous `THROWN_VX` : il ne bouscule personne),
  et sans freiner un blob déjà lancé plus vite dans ce sens, et le tourne. Un tick
  où il pousse, d'un côté ou de l'autre, coûte 1 de carburant. ▼ ne fait rien. Le moteur se coupe
  (`jet = 0`, `jet_ended{cat}`) quand le carburant est vide, quand le chat se pose, sur un saut
  (`jump`), quand il tire et quand il quitte `aiming` ; il retombe alors comme d'habitude, dégâts de
  chute compris. Le jetpack ne puise pas dans la jauge. Il s'allume au sol ou en l'air ; accroché ou
  déjà allumé, il est refusé, sans munition dépensée.
- **Mort** : un chat à 0 PV ou moins meurt à la fin de la résolution du tour (§5.6), pas pendant ;
  un chat noyé meurt immédiatement.

### 5.5 Projectiles et explosions

- **Lancement** : vitesse = `MAX_SPEED × puissance / 100`, `MAX_SPEED = 2304` FP/tick (9 px/tick,
  une portée d'environ 400 px à 45° sans vent), puissance de 1 à 100, direction = angle.
- **Vent** : un entier de `−wind_max` à `wind_max` tiré à chaque début de tour (flux `sim`) ;
  `wind_max` vaut 10, et 0 seulement dans les tests (il n'est pas proposé dans le salon). Accélération horizontale
  = `vent × 1` FP/tick², multipliée par la sensibilité au vent de l'arme (en pourcentage).
- **Intégration** : à chaque tick, gravité puis vent sur la vitesse, puis déplacement **par pas d'au
  plus 1 px**, en testant le terrain et les chats à chaque pas. Un pas qui change de colonne et de
  ligne à la fois teste aussi les deux cellules qu'il frôle. Un projectile ne traverse jamais un mur
  d'un pixel, droit ou en diagonale, à aucune vitesse. Positions intermédiaires, vent et rebond
  s'arrondissent symétriquement (§5.1).
- **Tireur** : le projectile ignore la boîte du chat qui l'a tiré pendant ses 6 premiers ticks.
- **Sortie** : un projectile qui passe sous `L` ou à plus de 64 px d'un bord disparaît sans exploser
  (événement `vanished`).
- **Chats touchés** : un projectile qui ne rebondit pas explose au premier chat dont la boîte contient
  le pixel où il arrive ; une arme qui rebondit (la grenade) ne heurte que le terrain.
- **Explosion** `(x, y, rayon_creusé, rayon_dégâts, dégâts_max, poussée_max)` :
  - vide toutes les cellules telles que `dx² + dy² ≤ rayon_creusé²` ;
  - pour chaque chat vivant à distance `d` du centre de sa boîte, avec `d < rayon_dégâts` : dégâts
    = `floor(dégâts_max × (rayon_dégâts − d) / rayon_dégâts)`, et une poussée dans la direction
    centre → chat, d'intensité `poussée_max × (rayon_dégâts − d) / rayon_dégâts`, avec un minimum
    de 64 FP vers le haut ; le chat décolle. Les distances se mesurent en **demi-pixels**, entre le
    centre du pixel de l'explosion et le centre exact de la boîte (qui tombe entre deux pixels), pour
    qu'une explosion à gauche d'un chat fasse exactement ce que fait son miroir à droite ;
  - le tireur n'est pas épargné.

### 5.6 Le tour

États, dans l'ordre. Toute transition hors de cette table est une erreur.

| État | Durée | Ce qui s'y passe | Sortie |
|---|---|---|---|
| `turn_start` | 60 ticks ; sur un tour de largage, tant qu'une caisse descend sous son parachute (§5.10), 300 ticks au plus | la caméra finit de montrer le tour précédent, suit la caisse qui descend, puis rejoint le chat ; vent tiré, puis la caisse lâchée ; aucune entrée | → `aiming` |
| `aiming` | durée du tour | marcher, sauter, lancer le tentacule et s'y balancer, voler au jetpack, choisir l'arme, tirer | tir d'une arme → `flight` (le tentacule n'en sort pas ; une arme posée, la dynamite, mène droit au repli) ; temps écoulé → `settling` ; dégâts subis → `settling` |
| `flight` | jusqu'à ce qu'aucun projectile ne reste et qu'aucun blob ne mange (Chomp) | la caméra suit le projectile ; aucune entrée, sauf `fire`, qui fait sauter le Waddler (§8.1) | → `retreat` |
| `retreat` | 90 ticks après un tir ; après une arme posée, autant que sa mèche (150 ticks pour la dynamite), jauge pleine | marcher et sauter seulement ; la mèche d'une arme posée brûle | temps écoulé ou dégâts subis → `settling` |
| `settling` | jusqu'à l'immobilité, 300 ticks au plus | tout retombe, caisses comprises (§5.10) ; une arme posée dont le repli a été coupé par des dégâts finit de brûler et explose ; aucune entrée | → `turn_end` |
| `turn_end` | 1 tick | morts appliquées, fin de partie testée ; la ronde qui finit en forêt dès la 8e déclenche le séisme (§5.3) | → `turn_start`, `quake` ou `ended` |
| `quake` | jusqu'à l'immobilité après la 3e secousse, 300 ticks au plus | le séisme de la forêt : trois secousses, les failles à la première ; tout retombe ; aucune entrée | morts appliquées, fin de partie testée → `turn_start` ou `ended` |
| `ended` | — | état final : plus aucune entrée, plus aucun tick | — |

Pendant le repli, `timer` (le temps du tour, §5.9) compte les ticks qui lui restent. Un chat est
immobile quand il est au sol avec une vitesse nulle. Au bout de 300 ticks en `settling`
ou en `quake`, tout ce qui bouge encore est posé où il est, et les projectiles restants disparaissent. Quitter
`aiming` ou `retreat` relâche la direction de marche du chat actif et coupe son jetpack. Un chat actif mort (noyé) compte
comme blessé : son tour s'arrête.

### 5.7 Entrées

Une entrée est une table `{team, kind, ...}` appliquée au tick où la sim la reçoit. La sim ignore
toute entrée d'une équipe qui n'est pas l'équipe active, qui n'est pas permise dans l'état courant
(§5.6), ou dont un champ sort de ses bornes : elle ne lève jamais d'erreur sur une entrée.

| Genre | Champs | Effet |
|---|---|---|
| `move` | direction `-1`, `0` ou `1` | direction tenue jusqu'à la prochaine entrée `move` ; accroché, le sens du balancier ; au jetpack, la poussée de côté |
| `jump` | direction `-1` ou `1` | un saut si le chat est au sol ; accroché, lâche le tentacule ; au jetpack, coupe le moteur |
| `climb` | direction `-1`, `0` ou `1` | accroché : raccourcit (−1), allonge (1) ou tient (0) la corde ; au jetpack, −1 pousse vers le haut |
| `fire` | arme, angle, puissance, minuterie, colonne | tire si l'arme a des munitions ; le tentacule se lance au sol ou en l'air, jamais accroché ; l'uppercut frappe dans le sens du regard (angle et puissance, bornés comme pour un tir, n'y comptent pas) ; la dynamite et le Waddler se posent aux pieds du blob, le jetpack s'allume, sans visée non plus ; l'appui aérien vise une colonne de la carte (`target`, de 0 à la largeur − 1). Pendant `flight`, `fire` fait sauter le Waddler de l'équipe active, sans munition (§8.1) |
| `skip` | — | passe le tour |

### 5.8 Événements

Chaque tick renvoie la liste des événements survenus, dans l'ordre. Le client s'en sert pour les
effets, les tests pour leurs vérifications ; ils n'entrent pas dans la somme de contrôle.

`turn_started{team, cat, wind}` · `fired{cat, weapon}` · `bounced{projectile}` ·
`vanished{projectile, x, y}` · `exploded{x, y, radius}` · `damaged{cat, amount, cause}`
(`explosion`, `fall`, `melee`) ·
`landed{cat}` · `rebounded{cat}` ·
`died{cat, cause}` (`hp`, `liquid`) · `turn_ended{}` · `game_ended{winner}` (`nil` = nul) ·
`chomped{cat, x, y, radius}` (le Chomp mange un disque) · `liquid_rose{level}` (la lave monte) ·
`tentacle_hooked{cat, x, y}` · `tentacle_missed{cat, x, y}` · `tentacle_released{cat}` ·
`quaked{n}` (le n-ième séisme de la forêt commence : l'entrée dans `quake`) · `shook{n}` (une
secousse du n-ième séisme) · `cracked{x, width, top}` (une faille s'ouvre ou s'écarte : sa colonne
et sa largeur, après, et la plus haute rangée qu'elle a creusée cette fois, ou son haut si elle n'a
rien creusé plus haut : le rendu reconstruit le terrain de là jusqu'à son bas) ·
`crate_dropped{crate, x}` (une caisse est lâchée au-dessus de cette colonne, sans dire son contenu) ·
`crate_landed{crate}` · `crate_picked{crate, cat, weapon}` · `crate_destroyed{crate}` (avant son
`exploded`) · `crate_lost{crate}` · `jet_started{cat}` · `jet_ended{cat}`. Un lancer de
tentacule n'émet pas `fired` : il émet `tentacle_hooked` ou `tentacle_missed`. Un uppercut émet
`fired`, puis un `damaged` (`melee`) par blob touché.

La liste rendue par `world.step` est réutilisée d'un tick à l'autre : elle est valable jusqu'au pas
suivant, qui la vide. Qui veut garder un événement le recopie.

### 5.9 L'état et sa somme de contrôle

Le monde regroupe : tick, flux de hasard, réglages résolus, terrain, niveau et type de liquide,
équipes, chats, projectiles, caisses (§5.10), tour, vent, munitions, le nombre de rondes finies
(`rounds`), les puits de la génération (`wells` : colonne et largeur, dont dépend la place des
failles) et les failles du séisme (`cracks` : colonne, largeur, haut et décalages, §5.3).

- Un chat porte, en plus de sa position, de sa vitesse et de ses PV : sa jauge (`gauge`), sa réserve
  de décalage en l'air (`nudge`), son tentacule (`hanging`, point d'accroche `anchor_x`,
  `anchor_y` en pixels, longueur `rope` en FP, `climb`), son repas de Chomp (`dig`, `dig_angle`) et
  le carburant de son jetpack (`jet`). Un projectile porte son sens de marche (`facing`, le
  Waddler). Le snapshot est à la version 11 (la 4 a ajouté le repas, la 5 les matériaux du terrain,
  la 6 les rondes finies, la 7 les puits et les failles, la 8 la munition de la dynamite et `timer`,
  qui compte aussi le repli, la 9 les munitions de la grappe et de l'appui aérien, la 10 `jet`,
  `facing` et les munitions du Waddler et du jetpack, la 11 les caisses).
- **Somme de contrôle** : tick, flux `sim`, niveau du liquide, champs de chaque chat, de chaque
  projectile et de chaque caisse dans l'ordre des tableaux, tour, vent, munitions, rondes finies, puits et failles (chaque champ, décalages
  compris), et le **journal du terrain** : la carte ne change que
  par des disques creusés (explosions, bouchées du Chomp et cases des failles), donc le hachage du terrain est la suite des `(x, y, rayon_creusé)` appliqués
  depuis la génération. Le hachage complet des cellules n'est calculé que dans les tests et à la
  vérification d'un snapshot.
- **Snapshot** : l'état complet en données simples (tables, entiers, chaînes, booléens : de quoi
  passer par JSON sans perte), le terrain compressé par plages (RLE) ligne par ligne, chaque plage
  écrite `longueur × 8 + matériau`, avec son journal
  de creusages, et le hachage complet des cellules. Restaurer un snapshot vérifie sa version, son
  terrain et ce hachage (`nil, "snapshot_version" | "snapshot_terrain" | "snapshot_cells"`), puis
  donne un monde de même somme de contrôle, aux cellules identiques, qui continue exactement comme
  l'original.

### 5.10 Les caisses

Demandées par l'utilisateur (run C8) : « quelques largages avec des trucs forts […]
1 largage au 3eme 6eme etc tour », « une boite larguée par avion qui tombe parachute sur la map, on
peut ensuite aller dessus pour drop une arme ».

- **Le largage** : au début de chaque tour dont le numéro, compté sur toute la partie, toutes
  équipes confondues (la somme des tours joués par les équipes, plus un), est un multiple de 3
  (`CRATE_EVERY`), une caisse est lâchée s'il y en a moins de 3 sur la carte (`CRATE_MAX`). Après le
  vent, le flux `sim` tire sa colonne, à au moins 24 px des bords (`CRATE_EDGE`), jusqu'à 8 fois
  (`CRATE_TRIES`), jusqu'à une colonne dont la première case pleine en descendant est au-dessus du
  liquide ; sans colonne, pas de caisse. Puis il tire son contenu parmi les armes des caisses
  (`CRATE_WEAPONS` : Waddler, jetpack, grappe, appui aérien), à chances égales.
- **La caisse** : une boîte de 6 × 6 px, ancrée en bas au centre comme un chat (`crate` : id, arme,
  position et vitesse en FP, `chute`, `fuse`, `alive`). Elle part du haut de la carte, sa boîte juste
  au-dessus de la rangée 0, sous son parachute : elle descend à vitesse constante, 384 FP/tick
  (`CRATE_FALL`, 1,5 px par tick), et dérive avec le vent de `vent × 8` FP/tick (`CRATE_DRIFT`), par
  pas d'au plus 1 px. Une case pleine sous sa boîte la pose (`crate_landed`) et le parachute se
  replie ; une case pleine de côté arrête sa dérive. Posée, si le terrain disparaît sous elle, elle
  retombe sans parachute ni dérive, avec la gravité, et se repose sans rebond.
- **Le début du tour l'attend** : sur un tour de largage, `turn_start` dure ses 60 ticks puis tant
  qu'une caisse descend sous son parachute, 300 ticks au plus (§5.6) : la caméra la suit, puis
  rejoint le blob.
- **Ramasser** : dès que la boîte du blob actif touche celle d'une caisse, à tout moment de son
  tour (en marchant, en sautant, au tentacule, au jetpack, projeté), la caisse disparaît et son
  équipe gagne une munition de l'arme qu'elle contenait (`crate_picked`). Les autres blobs, les
  projectiles et le Waddler passent à travers. Une caisse qu'une explosion vient de toucher ne se
  ramasse plus.
- **Détruite** : une explosion dont le rayon de dégâts atteint le centre de sa boîte (même mesure
  que pour un chat, §5.5) la fait exploser au tick suivant (`fuse`), comme un petit baril : creuse
  10 px, rayon 20 px, 30 dégâts, poussée 1280 FP/tick (`CRATE_BLAST`), `crate_destroyed` puis
  `exploded`. Une caisse peut en faire sauter une autre.
- **Perdue** : une caisse dont le centre passe sous le niveau du liquide, ou à plus de 64 px d'un
  bord, disparaît (`crate_lost`) ; la lave qui monte la prend aussitôt, comme les blobs, et elle ne
  compte plus pour les 3 du largage qui suit.
- **Au repos** : une caisse qui tombe ou va exploser retient `settling` et `quake` comme un blob qui
  bouge ; au bout de leurs 300 ticks, elle est posée où elle est, et une caisse qui allait exploser
  disparaît.
- Les bots ne vont pas chercher les caisses et ne jouent pas leurs armes (§9).

## 6. Le serveur

`server/` — modules du runtime Lua de Nakama. Ils utilisent `shared/` et `nk`, rien d'autre.

### 6.1 Identité

Authentification par identifiant d'appareil. Le pseudo (2 à 16 caractères ASCII : lettres,
chiffres, espace, `_`, `-`, sans espace au début ni à la fin) est le nom d'affichage du compte. Aucune
autre donnée : une mise à jour du compte qui touche un autre champ est refusée (`invalid_account`),
un pseudo hors de ces règles aussi (`invalid_nickname`), comme un nom d'utilisateur choisi à
l'authentification (`invalid_account`). Toute autre façon de s'authentifier ou de lier un compte est
refusée (`unsupported`), comme les API de Nakama que le jeu n'utilise pas et où un joueur écrirait
quelque chose : stockage, groupes, amis, discussion, statut, matchs relayés, matchmaker et groupes de
joueurs (*parties*) ; et la liste des matchs, qui donnerait à n'importe qui le code de chaque salon
ouvert (le code est la seule clé d'un salon ; `room_find` cherche côté serveur). Rejoindre un salon demande un pseudo valide.

Chaque joueur a une **équipe** : un nom qu'il choisit au premier lancement (un nom généré lui est
proposé ; ce nom proposé, l'identifiant d'appareil et ce que le joueur tape sont gardés aussitôt, si
bien qu'un rechargement de la page ne change rien), aux règles du pseudo, qu'il peut changer ensuite depuis l'Accueil, comme son pseudo, et
six noms de membres tirés au hasard à ce moment-là (le générateur ci-dessous), puis fixes ; les chats
de son équipe prennent ces noms dans l'ordre. Le client les garde localement, pour l'entraînement
hors ligne, et les dépose sur son compte par `team_set` (§6.2) ; le serveur les valide
(`invalid_team_name`, `invalid_member_name`, chaque nom aux règles du pseudo) et les garde dans son
stockage, que seul ce RPC écrit. Un humain qui n'a rien déposé joue sous des noms générés, comme un
bot. Renommer ses membres viendra plus tard (§13).

Les équipes de bots reçoivent un nom et des noms de membres **générés** : des mots-valises anglais
composés à partir d'un dictionnaire (`shared/names.lua`, du genre « Purrnado » ou « Snugglebytes »,
16 caractères au plus), tirés sur le flux `names` de la partie (§5.1). Une même graine donne les
mêmes noms sur le serveur et sur chaque client.

### 6.2 RPC

- `room_create {settings}` → `{code, match_id}` : crée le match `room`, l'appelant en devient l'hôte.
  Seuls les réglages du salon (§5.2) sont lus ; un réglage hors bornes rend la raison de la sim
  (`invalid_teams`…), un corps qui n'est pas un objet JSON `malformed`, un corps de plus de 1 Kio
  `too_large`, et 8 tirages de code tous pris `room_code_unavailable`.
- `team_set {name, members}` → `{name, members}` : dépose l'équipe du joueur, son nom et ses six noms
  de membres (§6.1) ; `malformed`, `too_large` comme `room_create`. Le client le rappelle à chaque
  connexion : un dépôt identique au dernier n'écrit rien.
- `room_find {code}` → `{match_id}` ou l'erreur `room_not_found`, y compris pour un code mal formé.
  Les minuscules sont acceptées et ramenées en majuscules.
- Un appel sans session (clé HTTP de serveur à serveur) est refusé (`unauthenticated`).

### 6.3 Le match `room`

- **Code** : 5 lettres prises dans `ABCDEFGHJKLMNPQRSTUVWXYZ`, unique parmi les matchs ouverts
  (vérifié par une requête sur le label, nouveau tirage sinon, 8 tirages au plus). Nakama indexe les
  labels par lots (`match.label_update_interval_ms`, 1 s) : un salon n'est trouvable par son code
  qu'environ 1 s après sa création, et l'unicité ne vaut qu'à cette seconde près (24⁵ codes).
- **Label** : `{"code": "ABCDE", "phase": "lobby"}`, mis à jour à chaque changement de phase.
- **`lobby`** : l'hôte règle la partie (§5.2) et bascule chaque place entre Ouverte et Bot ; un
  joueur qui arrive prend la première place ouverte ; l'hôte lance quand il veut — l'hôte
  seul contre des bots est une partie valide. Si l'hôte part, le rôle passe à l'humain arrivé le plus
  tôt. Un humain qui quitte le salon libère sa place. Une place tenue par un humain ne devient pas
  Bot, et le nombre d'équipes ne descend pas sous elle (`seat_taken`). Rejoindre est refusé sans
  pseudo valide (`nickname_required`) ou sans place ouverte libre (`room_full`). La place se prend
  quand l'entrée dans le match aboutit, pas à la tentative (Nakama ne signale pas une entrée qui
  n'aboutit pas) ; deux humains admis pour la dernière place : le second est expulsé. L'hôte se
  choisit après chaque entrée et chaque départ : un salon dont le créateur n'est jamais venu a
  pour hôte le premier humain arrivé.
- **`playing`** : seul un joueur déjà inscrit peut rejoindre (reconnexion ; les autres reçoivent
  `game_in_progress`, en `ended` aussi) ; la sim avance à 30 Hz.
- **`ended`** : le résultat reste affiché ; l'hôte peut relancer (retour à `lobby`, mêmes places :
  chaque place retrouve son genre du salon, les humains encore présents gardent la leur, celle d'un
  humain parti redevient libre).
- Le match se ferme après 60 s sans aucun humain présent.

### 6.4 Messages

Encodés en JSON. Les codes et la forme de chaque message vivent dans `shared/protocol.lua`, partagé
par le client et le serveur ; l'encodage JSON reste propre à chaque côté.

| Sens | Code | Message |
|---|---|---|
| client → serveur | 1 | `lobby_settings` (hôte) |
| | 2 | `lobby_slot` (hôte : Ouverte ↔ Bot) |
| | 3 | `start` (hôte) |
| | 10 | `input` : `move`, `jump` ou `climb` |
| | 11 | `fire` |
| | 12 | `skip` |
| | 13 | `snapshot_request` |
| | 20 | `rematch` (hôte) |
| serveur → clients | 100 | `lobby_state` |
| | 101 | `game_start {seed, settings, roster}` |
| | 102 | `ticks {to, inputs}` |
| | 103 | `checksum {tick, sum}` |
| | 104 | `snapshot {tick, state}` |
| | 105 | `game_end {winner, stats, host}` |
| | 106 | `refused {code}` |
| | 107 | `pilots {bots}` |

Formes des messages du salon :

- `lobby_settings {teams?, cats_per_team?, turn_seconds?, map?, bot_level?, seed?}` : les champs
  présents remplacent les réglages courants, validés comme à `room_create` ; `seed` est un entier de
  0 à 2147483646, 0 voulant dire « au hasard » (tirée au lancement).
- `lobby_slot {seat, kind}` : `seat` de 1 au nombre d'équipes, `kind` = `open` ou `bot` ; une place
  hors de 1 à 8 rend `malformed`, au-delà du nombre d'équipes `invalid_seat`.
- `lobby_state {code, host, settings, seed, seats}` : envoyé à tous après chaque changement ;
  `seats` liste pour chaque place `{kind, user?, name?, team?}` (l'identifiant du compte, le pseudo et
  le nom d'équipe de l'humain qui la tient).
- `refused {code}` : au seul expéditeur, `code` étant la raison du refus : `malformed` (forme),
  `too_large`, `rate_limited`, `unknown_op`, `wrong_phase`, `not_host`, `not_your_turn`,
  `seat_taken`, `invalid_seat`, ou la raison de la sim (`invalid_teams`, `invalid_seed`…). Pour
  `rate_limited`, une seule réponse par seconde.

Formes des messages de la partie :

- `start {}` (hôte, salon) : toute place Ouverte sans humain devient un bot (D-08) ; la graine est
  tirée si elle vaut 0 ; le serveur génère la carte, passe en `playing` et envoie
  `game_start {seed, settings, roster}`, `roster` listant pour chaque équipe (dans l'ordre des
  places) `{team, kind, user?, name?, team_name, members}` avec `kind` = `human` ou `bot`, `team_name`
  le nom de l'équipe et `members` les noms de ses membres, dans l'ordre de ses chats (§6.1).
- `input {kind, direction}` : `move` avec `direction` −1, 0 ou 1 ; `jump` avec −1 ou 1 ; `climb` avec
  −1, 0 ou 1.
- `fire {weapon, angle, power, fuse?, target?}` : bornes du §6.8 ; `fuse` seulement pour une arme à
  minuterie, `target` seulement pour l'appui aérien.
- `skip {}`.
- `ticks {to, inputs}` : `inputs` liste, dans l'ordre d'application, `{at, input}` où `input` est
  l'entrée de la sim (§5.7, équipe comprise) et `at` le tick où elle s'applique (le pas qui mène de
  `at` à `at + 1`). Un message couvre les ticks après le `to` du précédent, jusqu'à `to` compris.
- `checksum {tick, sum}` : `sum` = `[a, b]`, les deux entiers de la somme de contrôle au tick `tick`.
- `pilots {bots}` : `bots` liste les équipes qu'un bot joue en ce moment, places Bot comprises, dans
  l'ordre des places (une liste vide peut arriver comme `{}`). Envoyé à tous à chaque prise d'une
  équipe par le pilote des bots et à chaque retour à son joueur (§6.7), et à un client qui revient,
  après son snapshot. Au lancement, `roster` le dit déjà (`kind`).
- `game_end {winner, stats, host}` : `winner` = l'équipe gagnante, 0 pour un match nul ; `host`
  l'identifiant du compte de l'hôte, le seul qui peut lancer la revanche (l'hôte change sans
  `lobby_state` hors du salon : `game_end` est renvoyé à tous quand il change pendant `ended`) ;
  `stats` liste pour chaque équipe `{team, damage, kills}` : les dégâts infligés aux chats des
  autres équipes (les montants des événements `damaged`, sans plafond aux PV qui restaient) et leurs
  morts, comptés pendant les tours de l'équipe ; ceux du séisme de la forêt (§5.3), hors de tout
  tour, ne comptent pour personne. Un blob encore en l'air au bout des 300 ticks de `settling` ou
  de `quake` est posé où il est, puis retombe au début du tour suivant : sa chute compte alors pour
  l'équipe qui joue (le banc n'a jamais vu un séisme atteindre ce plafond).

L'encodeur JSON de Nakama ne distingue pas un tableau vide d'un objet vide : une liste vide (des
`inputs` sans entrée, des projectiles absents d'un snapshot) peut arriver comme `{}`. Un client la lit
comme une liste vide.

Refus propres à la partie : `not_your_turn` (l'expéditeur ne joue pas l'équipe active, ou un bot la
joue), `not_now` (l'état du tour n'accepte pas cette entrée, §5.6), `no_ammo`, `invalid_target`
(une colonne hors de la carte, §6.8), `invalid_weapon`,
`invalid_angle`, `invalid_power`, `invalid_fuse`, `invalid_direction`, `too_soon` (§6.6).

### 6.5 Un tick de partie

1. Le serveur valide les messages reçus depuis le tick précédent (D-14) et les convertit en entrées
   pour le tick `t`.
2. Les bots (§9) ajoutent les leurs.
3. La sim avance d'un tick, jusqu'à `t + 1`.
4. Quand le tick atteint est pair, `ticks {to, inputs}` part à tous les clients, même vide : c'est
   l'horloge des clients (15 Hz).
5. Quand il est multiple de 30, `checksum {tick, sum}`.
6. Quand la partie se termine : le dernier `ticks` part aussitôt (même à un tick impair), puis la
   somme de contrôle du tick final, puis `game_end` ; le match passe en `ended`.

La carte se génère au lancement, dans la boucle du match, avant `game_start` : jusqu'à ~2,3 s pour
la plus grande (mesuré au run A), pendant lesquelles Nakama met les ticks en file (128 au plus) puis
les rattrape d'affilée. Le tour de départ commence par ses 60 ticks de `turn_start` : ce rattrapage
ne mange que le début de la première visée.

Le client avance sa sim jusqu'à `to`, jamais au-delà, et affiche en interpolant entre les deux
derniers états.

### 6.6 Snapshot

`snapshot {tick, state}` : l'état du monde au tick `tick` (`world.snapshot`, §5.9). Le client le
restaure, puis n'applique, des `ticks` qui suivent, que les entrées d'un `at` au moins égal à `tick`
(les précédentes y sont déjà). `snapshot_request {tick?}` en demande un, au plus un toutes les 5 s par
présence (`too_soon`) ; `tick` est celui de la somme de contrôle qui ne correspondait pas : le serveur
l'écrit en `warn` (§11), seulement pour une demande acceptée.

Encoder le terrain et hacher ses cellules parcourt toute la carte : c'est l'essentiel du coût d'un
snapshot dans Nakama. Le terrain ne changeant qu'aux explosions, le match garde cet encodage tant que
le journal des cratères n'a pas bougé : seul le premier snapshot après un cratère le recalcule, dans
la boucle du match. Mesuré au run B dans Nakama (`make conformance`), pour la plus grande carte : 125
à 141 ms après un cratère, 0,7 ms depuis le cache, plus 0,8 ms d'encodage JSON (16 Ko).

Envoyé à un joueur qui rejoint une partie en cours, qui le demande, ou dont la somme de contrôle a
divergé (le client le demande lui-même quand `checksum` ne correspond pas). Il part en un seul
message. La limite de Nakama (`socket.max_message_size_bytes`) ne porte que sur ce que le serveur
**lit** d'un client : elle reste à sa valeur par défaut (4 Kio), qui coupe la connexion d'un client
au-delà, et le §6.8 jette déjà tout message de plus de 1 Kio. Un message sortant n'y est pas soumis
(H-06) ; le plus gros snapshot mesuré au run B est écrit dans un test.

### 6.7 Absences

Un joueur dont la présence quitte le match est marqué absent : si c'est son tour, un bot le joue ;
sinon, le bot jouera son prochain tour. À son retour (même compte), il reçoit `game_start` (le même
qu'au lancement : un client qui a rechargé sa page n'a plus ni la graine ni le roster), un snapshot,
puis `pilots`, et reprend la main au premier `turn_start` qui suit.

Le pilote des bots du serveur prend l'équipe dès le départ de la dernière présence du compte, en
relâchant d'abord la direction de marche par une entrée ordinaire (`move` 0), pour qu'un chat ne
marche pas seul vers le liquide, et le tentacule par un saut s'il est accroché, pour que le bot puisse
tirer ; le bot reprend le tour en cours là où il en est (§9, il reconnaît le tour au compteur de tours de l'équipe)
et le joue jusqu'au bout. Il rend l'équipe au premier `turn_started` qui suit le retour : entre les
deux, les entrées de l'humain sont refusées (`not_your_turn`). À la prise comme au retour, le serveur
envoie `pilots` à tous (§6.4) : chaque client montre l'icône de bot sur cette équipe (§7.4). Un joueur qui revient dans une partie
finie reçoit `game_start`, le snapshot final et `game_end`.

### 6.8 Validation et limites (D-14)

- Messages de plus de 1 Kio (client → serveur) jetés ; au-delà de 4 Kio, Nakama coupe lui-même la
  connexion avant que le match ne voie le message (§6.6).
- Au plus 20 messages par présence sur toute fenêtre d'une seconde (fenêtre glissante, en ticks du
  match) ; au-delà, jetés, sans lire ni leur taille ni leur forme. Un message arrivé d'une présence
  qui a déjà quitté le match est ignoré.
- `fire` : arme connue, qu'on choisit (jamais un éclat, §8.1) et disponible, angle entier 0–1023,
  puissance entière 1–100, minuterie entière 1–5 (grenade, grappe), colonne entière pour l'appui
  aérien seulement, de 0 à la largeur de la carte − 1 (`invalid_target` : au décodage, de 0 à
  1023, puis la largeur de la partie), seulement dans `aiming` et par le joueur actif. Le tentacule est une arme toujours disponible ; sa puissance, bornée comme les
  autres, est ignorée. Pendant `flight`, quand un Waddler de l'équipe active marche, le même `fire`
  le fait sauter : les munitions ne sont pas regardées.
- `input` `climb` : direction entière −1, 0 ou 1, seulement dans `aiming` et par le joueur actif
  (accroché au tentacule ou au jetpack ; sinon la sim l'ignore).
- Un `fire` ou un `skip` accepté clôt le tick pour la partie (en vol, celui qui fait sauter le
  Waddler aussi) : un autre message de jeu dans le même tick rend `not_now`. Un lancer de tentacule, qui ne termine pas le tour, ne le clôt pas.
- Tout refus est compté par code et par présence dans les logs, sans le contenu du message : chaque
  refus en `debug`, un `warn` quand une présence dépasse le débit, et le total par code de la
  présence en `info` quand elle quitte le match.

### 6.9 Le journal des salons et des parties

Le serveur garde une trace de ce qui s'est joué, pour le panneau d'administration (§11.1). Deux
collections du stockage de Nakama, écrites **par le match seul**, au nom du compte système
(`00000000-0000-0000-0000-000000000000`), permissions de lecture et d'écriture à 0 : aucun client ne
les lit ni ne les écrit (D-14, D-15). Rien n'y entre que ce que le jeu connaît déjà : le code, les
réglages, la graine, les identifiants des comptes, les pseudos, les noms d'équipes et de membres,
les résultats. Aucun identifiant d'appareil, aucune adresse.

- **`room`**, clé = l'identifiant du match : `{code, phase, created_at, updated_at, closed_at?,
  settings, seats, games}`. Écrit à la création du salon, à chaque changement de phase (`lobby`,
  `playing`, `ended`) et à sa fermeture ; `seats` recopie les places du `lobby_state` (genre, compte,
  pseudo, nom d'équipe), `games` le nombre de parties lancées. Pas d'écriture à chaque arrivée dans
  le salon : la phase suffit.
- **`game`**, clé = l'identifiant du match suivi du numéro de la partie dans le salon (`<match>:1`,
  `<match>:2` après une revanche) : `{match, code, number, started_at, ended_at, ticks, seed,
  settings, roster, winner, stats, rounds, round_limit, away}`. Écrit une fois, à la fin de la
  partie : `roster` est celui de `game_start` (§6.4), `winner` et `stats` ceux de `game_end`,
  `rounds` le nombre de rondes finies, `round_limit` vrai si la limite des rondes l'a arrêtée, `away`
  les équipes dont l'humain était parti à la fin (joué par un bot).
- Les instants (`*_at`) sont l'horloge de Nakama (`nk.time()`, en millisecondes) : le serveur a le
  droit d'avoir une horloge, la simulation non (D-02).
- Une écriture qui échoue est journalisée en `warn` (🏠) et n'arrête jamais le match.

## 7. Le client

`client/` — code Defold. Il utilise `shared/` et Defold ; il ne décide jamais d'un résultat en ligne.

### 7.1 L'autorité, une seule couture

Le client parle à une **autorité** par une seule interface, six fonctions : `start()`,
`update(dt)`, `send(nom, corps)` (les noms d'opérations de `shared/protocol.lua`), `poll()` (la liste
des `{name, data}` reçus depuis le dernier appel : `game_start`, `ticks`, `checksum`, `snapshot`,
`game_end`, `refused`, `pilots`), `team()` (l'équipe du joueur) et `stop()`. Hors de
`client/authority/`, rien ne la touche autrement (une spec le vérifie). Deux adaptateurs :

- `LocalAuthority` : fait tourner la sim et les bots dans le client (entraînement hors ligne) ;
- `NakamaAuthority` : parle au match `room`.

Tout le reste du client (rendu, caméra, commandes, interface) ignore lequel est branché.

En ligne (run D), `NakamaAuthority` passe par **la connexion au salon** (`client/net/`, la seule
partie du client qui connaît nakama-defold et la WebSocket : `link.lua` et sa construction pour
Defold, `nakama_link.lua`) : authentification par l'identifiant d'appareil,
pseudo déposé sur le compte, équipe déposée par `team_set` (§6.1), socket, entrée dans le match par
son code, et reconnexion. Le Salon lit et règle le salon par elle, l'écran Fin y lit qui est l'hôte
(la Revanche) ; au `game_start`, l'autorité en
ligne la reprend pour la partie. Elle vit aussi longtemps que l'application (le contexte de script
qui ouvre une socket reçoit ses rappels), pas dans la scène de la partie.

- **L'adresse du serveur** : sur une page en `http:` (le réseau local), Nakama à l'hôte de la
  page, port `7550` (`nakama.port` de `game.project`), sans TLS. Sur une page en `https:` (le
  tunnel, `https://blobattle.npc.fm`), Nakama **à l'origine même de la page** (même hôte, même
  port, 443 par défaut), en TLS : le tunnel, ou le reverse proxy de qui héberge le jeu, envoie à
  Nakama les chemins de son API et de sa socket (`/v2/`, `/ws`, `/healthcheck`) et tout le reste au
  nginx qui sert le build (`docs/heberger.md`). La clé serveur n'est
  pas dans le dépôt : `make web` la lit dans `.env` et la passe à `bob.jar` par `--settings`
  (`nakama.server_key`).
- **L'identifiant d'appareil** (D-15) : 128 bits tirés une fois au premier lancement
  (`crypto.getRandomValues` en HTML5, qui existe aussi sur une page en `http:` du réseau local),
  gardé dans le profil local avec le pseudo et l'équipe ; deux navigateurs, ou deux profils d'un
  même navigateur, sont deux comptes.

### 7.2 Écrans

| Écran | Orientation | Contenu |
|---|---|---|
| Intro | les deux | au lancement, sur fond noir : le logo du studio **Panis Vult**, qui tremble de plus en plus fort en grossissant (« Deus Vult intensifies ») puis s'efface ; le logo rond de **Blobattle** ; puis l'Accueil, en fondu. Un appui, un clic, Espace ou Entrée la passe |
| Accueil | les deux | pseudo et nom de l'équipe (demandés au premier lancement, modifiables ensuite), Solo, Multi (Créer, Rejoindre par code, run D) ; Touches, sur ordinateur (run C7) |
| Touches | les deux | chaque commande du clavier et sa touche ; un clic sur une touche, puis la touche voulue ; Par défaut ; Retour (§7.3) |
| Multi | les deux | Créer (un salon, dont on devient l'hôte) ; le code d'un salon, saisi dans un vrai champ de texte, et Rejoindre ; Retour ; la raison d'un refus (salon introuvable, complet, partie en cours, serveur injoignable) |
| Solo | les deux | l'entraînement contre les bots : équipes, chats par équipe, niveau des bots, carte ; Lancer |
| Salon | les deux | code et bouton de partage, places (Ouverte / Bot / équipe et pseudo), réglages (hôte), Lancer (hôte) |
| Partie | paysage | carte, commandes, interface de partie |
| Fin | les deux | l'équipe gagnante, dégâts et éliminations par équipe, Revanche (hôte), Quitter |

Un lien `?room=ABCDE` ouvre directement le Salon correspondant (HTML5), après l'intro. Au premier
lancement, l'Accueil demande d'abord le pseudo et l'équipe ; Multi propose alors le code du lien.
Le bouton de partage du Salon partage ce lien (`navigator.share`) ou, à défaut, le copie ; sur une
page en `http:` du réseau local, où le navigateur n'offre ni l'un ni l'autre, il le copie par
l'ancienne commande du presse-papiers ou, faute de mieux, l'affiche.

**L'intro** (run C4, demandée par l'utilisateur) : le studio d'abord, le jeu ensuite, comme d'usage.
Pendant le chargement de la page HTML5, le logo du studio est déjà là, immobile, à la taille où
l'intro le reprend, sur le même noir (la barre du navigateur aussi). Puis il tremble de plus en plus
fort jusqu'à 2,9 s : un décalage au hasard à chaque image, de 1 à 14 points (en carré du temps :
le quart du chemin à mi-temps), avec une légère rotation (3° au plus) et un zoom qui monte à 15 % ;
il s'efface de 2,9 à 3,3 s en tremblant encore. Le logo du jeu paraît de 3,5 à 4 s en rebondissant
comme un blob (de 75 % de sa taille à 115 %, puis 100 %), reste jusqu'à 5,7 s, s'efface ; l'Accueil
paraît à 6,1 s sous le noir, qui se lève en 0,4 s : 6,5 s en tout. Les deux logos viennent d'images
fournies (`panisvult.png`, et le logo rond de `logo-base.png`), réduites à 512 px dans un atlas du
client, les bords du logo du studio fondus dans le noir. Les champs du pseudo et de l'équipe
n'apparaissent qu'avec l'Accueil.

**Le décor des menus.** Derrière l'Accueil, Solo et Fin, une petite scène 3D en voxels, chargée avec les
menus et déchargée pendant une partie (rien de visible ne touche la sim, D-09) :

- trois plans à des profondeurs différentes (montagnes pâles au loin, collines, sol avec une bande
  d'eau devant) et des nuages de cubes qui dérivent ; la caméra glisse lentement de côté, ce qui fait
  la parallax. Un plan se génère d'une graine et d'un **aspect** (couleurs, reliefs, largeur) : une
  donnée, pour que d'autres aspects (des biomes) puissent venir plus tard ; la V0 n'en a qu'un ;
- cinq ou six blobs aux couleurs des équipes sur le sol, qui respirent par le ressort du rendu, chacun
  avec un visage en voxels : calme, apeuré (sourcils levés, grands yeux, bouche en O) ou en colère
  (sourcils en V, bouche tordue) ;
- toutes les 4 à 6 s, un obus traverse et explose près d'un blob (le flash et les débris du jeu) :
  ceux qui sont près sursautent et prennent peur, un autre se fâche et tremble ; au bout de 2 s ils
  reviennent au calme ;
- sur l'Accueil, le titre « Blobattle » (le texte `app.title` du catalogue, en capitales) est bâti en
  vrais cubes, lettre par lettre dans une police voxel de 5 × 7, chaque lettre dans une couleur
  d'équipe et qui rebondit comme un blob. Le titre tient dans l'écran en paysage comme en portrait.

Le décor coûte peu : moins de 30 000 sommets en tout, et son script reste sous 2 ms par image au p95
à CPU ×4 dans le build HTML5.

Le pseudo et le nom de l'équipe se saisissent dans de vrais champs de texte posés sur l'écran (en HTML5,
des champs du navigateur, qui font venir le clavier du téléphone), jamais par une boîte de dialogue.
L'interface garde la même taille en points sur un ordinateur que sur un téléphone : elle ne s'étire
pas avec une grande fenêtre.

### 7.3 Commandes

Référence : paysage 844×390 points. Les zones évitent les encoches (safe area).

- **Pouce gauche** : une croix de quatre pavés, ◀ ▶ ▲ ▼ (maintenus). ◀ ▶ marchent (accroché,
  balancent) ; ▲ ▼ raccourcissent ou allongent la corde du tentacule, et restent affichés grisés tant
  qu'on n'est pas accroché, pour que la croix ne change pas de forme.
- **Pouce droit** : un bouton **Saut** à part, marqué de son mot (`hud.jump`) et non d'une flèche,
  à côté du bouton d'arme : saut vers la direction du regard ; accroché, il lâche. Le bouton d'arme
  ouvre une grille d'armes avec leurs munitions ; pour la grenade, une pastille fait défiler la
  minuterie de 1 à 5 s. (Jusqu'au run D, Saut était au-dessus de ◀ ▶ et portait une flèche vers le
  haut, la même que ▲ : au téléphone, l'utilisateur prenait Saut pour « haut », lâchait la corde en
  voulant la remonter, et ne voyait pas ▲ ▼, apparus ailleurs une fois accroché. Il a demandé « un
  bouton dédié pour sauter et avoir gauche droite haut bas ».)
- **Viser et tirer** : un appui qui commence à moins de 48 points du chat actif et glisse vers
  l'arrière, comme un lance-pierre. La ligne de visée montre l'angle et la puissance ; relâcher tire ;
  revenir sur le chat annule. L'angle et la puissance sont arrondis aux entiers de §5.1 avant
  l'envoi : la sim ne reçoit jamais un décimal.
- **Le tentacule** : il se choisit dans la grille d'armes et se vise du même geste (seul l'angle
  compte) ; relâcher le lance. Accroché, ◀ ▶ de la croix balancent, ▲ ▼ raccourcissent ou allongent la
  corde, et Saut lâche. Au clavier : Espace lance ; accroché,
  ← → balancent, ↑ ↓ raccourcissent ou allongent la corde (au lieu de l'angle), Entrée lâche.
- **L'uppercut et le Chomp** (run C3) : la grille d'armes passe à cinq cases (deux colonnes), touches
  4 et 5. L'uppercut part du même geste que les autres armes (le lance-pierre au doigt, le glisser à
  la souris, Espace au clavier, qui frappe aussitôt) : seul le relâcher compte, le coup part dans le
  sens du regard (◀ ▶ ou ← → le tournent), et aucune ligne de visée ne s'affiche. Le Chomp se vise comme le tentacule (seul l'angle compte),
  et Espace le lance aussitôt.
- **La dynamite** (run C6) : la grille d'armes passe à six cases (deux colonnes de trois), touche 6.
  Elle se pose du même geste que l'uppercut (seul le relâcher compte, Espace la pose aussitôt), sans
  ligne de visée. Chaque case porte le nom de l'arme et, si elles sont comptées, ses munitions ; une
  arme épuisée quitte la grille.
- **Les armes des caisses** (run C8) : la grille passe à dix cases (deux colonnes de cinq), touches
  7 à 9 et 0, dans cet ordre : la grappe, l'appui aérien, le Waddler, le jetpack ; une arme des caisses n'y paraît que quand l'équipe en a. Le Waddler se pose du même
  geste que la dynamite ; tant qu'il marche, un bouton **Boom** (`hud.boom`) paraît au pouce droit,
  à gauche de Saut, et lui ou la touche Tirer le fait sauter. Le jetpack s'allume du même
  geste ; allumé, ▲ de la croix (ou la touche qui monte l'angle) pousse vers le haut, ◀ ▶ de côté,
  et Saut coupe le moteur ; ▲ n'est plus grisé tant qu'il brûle (▼, qui n'y fait rien, le reste),
  et au clavier la visée ne bouge pas pendant le vol. Boom ne part qu'une fois par Waddler. La grappe se vise et se règle comme
  la grenade. L'appui aérien n'a pas de ligne de visée : un appui ou un clic sur la carte, qui ne
  glisse pas, y pose une cible (une croix à l'écran, qu'un autre appui déplace ; un appui hors de
  la carte ou le doigt immobile d'un pincement ne la pose pas, et un double appui ne recentre pas
  la caméra tant qu'on vise) ; un bouton
  **Strike** (`hud.strike`) paraît alors à la même place, et lui ou la touche Tirer lâche les
  obus sur la colonne de la cible. Boom et Strike sont un seul bouton d'action, qui change de mot.
- **Caméra** : un doigt qui glisse ailleurs déplace la vue ; deux doigts pincent pour zoomer, entre
  une vue d'ensemble et un gros plan sur un blob ; un double appui recentre sur le chat actif. La
  caméra suit seule, comme dans Worms : le blob actif au début du tour, le projectile en vol (même
  après un déplacement de la vue), puis le point de l'explosion et les blobs qu'elle projette, jusqu'à
  la fin du tour. Une arme posée n'est pas suivie : pendant le repli qui suit la dynamite, la caméra
  reste sur le blob qui s'éloigne, puis va à l'explosion. Elle ne quitte pas l'action trop vite : elle reste au moins 1,2 s sur une explosion
  et sur un blob qui meurt, même quand le tour suivant commence, puis glisse en 0,8 s vers le blob
  suivant ; le début de tour dure 2 s pour que ce temps ne soit pas pris sur la visée. Le coup qui
  finit la partie se voit aussi : l'écran Fin attend la fin de ce maintien. **Sur ordinateur**, la
  caméra part de la vue d'ensemble, toute la carte centrée (largeur et hauteur), avec au-dessus
  d'elle 32 px de ciel où passent l'avion et les caisses (run C8) : la molette zoome
  pour suivre l'action de près, et revenir au plus loin redonne la vue d'ensemble, qui le reste
  quand la fenêtre change de taille (à la demande de l'utilisateur).
- **Ordinateur**, au clavier comme dans Worms, avec ces touches par défaut : ← → marcher, ↑ ↓ lever ou baisser l'angle (la ligne
  de visée reste affichée), Espace maintenu charge la puissance et relâché tire (à pleine puissance,
  le tir part seul), Entrée sauter, 1 à 9 et 0 pour les armes (3, le tentacule, qu'Espace lance aussitôt,
  sans charger), F pour la minuterie de la grenade. La
  souris vise **vers le curseur** : appuyer sur le blob, glisser vers la cible, relâcher tire ; la
  ligne part du blob vers le curseur et sa longueur, comptée depuis le bord du blob, dit la puissance
  (au doigt, le lance-pierre tire à l'opposé du glisser, comme on tend un élastique). Revenir sur le
  blob annule, comme au doigt. Molette pour zoomer, clic droit glissé pour déplacer la vue. Sans
  écran tactile, les pavés des pouces (la croix et Saut) ne s'affichent pas : le clavier les remplace ;
  le bouton d'arme, la grille et la minuterie restent cliquables.
- **Les touches au choix** (run C7, demandé par l'utilisateur : « pouvoir choisir ses touches sur PC
  très important », gardées « comme le nom d'équipe ») : dix-sept commandes (treize jusqu'au run
  C8), chacune sur une touche,
  se changent à l'écran **Touches** : marcher à gauche, à droite, monter et baisser l'angle (accroché,
  la corde ou le jetpack), tirer, sauter, la minuterie, et les dix cases de la grille, chacune sous le nom de son
  arme. Un clic sur la touche d'une commande attend la touche voulue ; Échap ou un clic ailleurs
  annule. Une touche ne sert qu'à une commande : choisir celle d'une autre commande échange les deux.
  **Par défaut** remet les touches ci-dessus. Le choix est gardé sur l'appareil à chaque changement,
  à côté du profil (un fichier de sauvegarde `keys`), et survit à un rechargement de la page ; une
  sauvegarde illisible, incomplète ou dont deux commandes partagent une touche rend les touches par
  défaut. Se choisissent : les lettres, les chiffres, les flèches, Espace, Entrée, Retour arrière,
  Inser, Suppr, Début, Fin, Page précédente et suivante, Maj, Ctrl, Alt, le pavé numérique et la
  ponctuation. Pas Échap (qui annule, et revient à l'Accueil depuis Touches), ni Tab, F1 à F12, les
  touches Windows et les verrouillages, que le navigateur ou le système gardent. La souris ne change
  pas. Le nom d'une touche vient du catalogue (`key.*`) ; en HTML5, une touche de ponctuation porte
  le caractère qu'elle écrit, lu au navigateur au moment du choix et gardé avec elle s'il est seul,
  ASCII et visible : Defold HTML5 nomme la ponctuation par sa place sur un clavier QWERTY, si bien
  que le M d'un clavier AZERTY lui arrive comme `;`. Les lettres et les chiffres, que Defold nomme
  comme sur la touche, gardent leur nom du catalogue (le 1 d'un clavier AZERTY écrit `&`). L'intro se passe toujours par Espace ou Entrée, quelles que soient
  les touches. Le bouton Touches de l'Accueil paraît sans écran tactile, ou dès qu'une touche du
  clavier a été pressée. Touches tient à 844×390 en quatre colonnes de cinq lignes (trois jusqu'au
  run C8), les commandes
  dans l'ordre ci-dessus (les mouvements et le tir dans la première), Retour et Par défaut en haut,
  chaque touche une case de 56 points de haut (44 sur un téléphone de 667×375, D-10) ; en portrait,
  en deux colonnes de neuf lignes (une seule jusqu'au run C8), des cases de 48 points.

### 7.4 Rendu

Un monde 3D vu de côté, en **voxels** : le jeu reste celui de la grille 2D de la sim (D-09), le rendu
l'extrude en profondeur. Tout est généré par le code, sans modèle ni texture importés. Référence : le
prototype jetable, ses mesures et son code, dans `docs/sonde-voxel/`.

- **Caméra** : perspective légère, un peu en plongée pour voir le dessus des reliefs ; elle suit seule
  le début du tour, le projectile et ce que l'explosion projette (§7.3).
- **Terrain** : une cellule pleine = un voxel, extrudé en profondeur ; seules les faces qui touchent
  l'air existent. Le maillage est découpé en morceaux de colonnes ; chaque morceau garde sa géométrie
  par rangée (faces avant, dessus, dessous) et par colonne (faces latérales), si bien qu'un cratère ne
  recalcule que les rangées et les colonnes qu'il touche. Ce calcul s'étale en tranches de quelques
  millisecondes par image pendant le flash de l'explosion ; un morceau n'est renvoyé au GPU qu'une
  fois complet. Les couleurs viennent du shader : la couleur du matériau de la case (voir « Les deux
  cartes »), dégradée avec la profondeur, plus claire sur les dessus, quadrillage discret et légère
  variation de teinte par voxel.
- **Le séisme de la forêt** (§5.3) : la caméra tremble à chaque secousse, sur les deux axes, d'autant
  plus fort que la poussée P du séisme est grande, et se calme en 0,45 s, avant la secousse
  suivante ; elle montre la faille qui s'ouvre tant que le sol bouge, et 1,2 s au moins (comme une
  explosion), plutôt que les blobs que les secousses soulèvent, puis rejoint le blob suivant. Une
  poussière de cubes (18 par faille) jaillit du haut de chaque faille qui s'ouvre ou
  s'écarte, et le terrain se reconstruit comme après un cratère, par tranches de 4 ms au plus, une
  par image, sur les colonnes de la faille (un pixel de plus de chaque côté pour le zigzag) de sa
  plus haute rangée creusée (`cracked.top`) à son bas, en moins d'images que n'en durent les
  secousses à 60 images par seconde (62) : mesuré à CPU ×4 dans Chromium, où SwiftShader, qui
  dessine en logiciel, ne tient pas 60 i/s et ne dit rien du temps réel sur un téléphone (H-11)
  (rendu seulement, D-09).
- **La dynamite** (run C6) : un bâton rouge en voxels, debout, plus haut que large, avec une mèche
  sombre au sommet qui crépite : des étincelles jaunes et orangées en jaillissent des deux côtés,
  montent en rapetissant et s'éteignent en moins d'une demi-seconde, jusqu'à l'explosion. Le bâton est
  dessiné devant le blob, en profondeur : posé à ses pieds, il se voit (rendu seulement, D-09).
- **Les caisses et leurs armes** (run C8) : la caisse est une boîte de bois en voxels marquée d'une
  croix claire ; elle descend sous un parachute (un dôme de voxels rouge et ses suspentes), qui
  disparaît quand elle se pose. La caméra la suit tant qu'elle descend, après le maintien sur la
  dernière explosion, puis rejoint le blob. La cible de l'appui aérien est une croix rouge posée sur
  le sol de la colonne choisie. Un avion en voxels traverse le haut de la carte d'un bord à l'autre au
  largage, et pour l'appui aérien, à vitesse constante, en passant au-dessus de la colonne. Une caisse ramassée fait monter « +1 » et le nom de l'arme
  (`hud.picked`) au-dessus du blob pendant 1,5 s. Le Waddler est un petit blob blanc et gélatineux,
  avec deux yeux, qui sautille et clignote en rouge pendant ses 2 dernières secondes. Le jetpack est
  un petit réservoir gris sur le dos du blob, avec des flammes (cubes orangés et jaunes) sous lui tant
  qu'il pousse ; la barre sous son nom montre alors le carburant, en orangé. La grappe est une boule
  violette, et ses mini-blobs ont chacun une couleur vive. Les obus de l'appui aérien sont des
  roquettes qui pointent vers le bas (rendu seulement, D-09).
- **Liquide** : un volume sous `L` dont la surface ondule dans le shader ; bleu pour l'eau, orangé
  pour la lave, avec des bulles qui éclatent à sa surface (elles suivent la vague : la même formule
  en Lua, interpolée tous les 4 px comme le maillage) ; la lave qui monte se voit monter : le liquide dessiné
  rejoint le niveau de la sim à 2 px par seconde, et la brume et les bulles le suivent.
- **Les deux cartes** (D-09) : une texture des matériaux (une case = un texel, la classe de la case :
  surface, terre, roche, bois, feuillage, acier), bâtie une fois au début de la partie, que lit le
  shader du terrain pour prendre la couleur de la carte : forêt — herbe sur la bande de surface
  (y compris le sol des grottes), terre brune, roche grise en profondeur, bois brun, feuillage vert,
  ciel bleu, quelques nuages blancs en fond qui dérivent ; volcan — cendre grise en surface, basalte
  noir, roche sombre, poutrelles d'acier gris-bleu (elles se lisent sur le ciel rouge comme sur le
  basalte), ciel rougeoyant, fumée sombre en fond, brume basse qui voile le bas du terrain au-dessus
  de la lave. Pas de couleur par sommet (trop cher en HTML5, run C) ; une classe par case plutôt
  qu'une couleur (trois fois moins d'écritures dans le buffer, mesuré au run C3). La texture se
  peint depuis le terrain reçu : un client qui rejoint une partie par un snapshot peint en herbe le
  fond des cratères déjà creusés (un écart de rendu seulement, D-09).
- **Chats** : des **blobs en voxels** d'environ 7 × 7 × 5 voxels (la boîte de collision de la sim fait
  6 × 7), à la couleur de leur équipe, avec deux yeux, tournés vers leur direction. Ils sont
  gélatineux : ils s'écrasent à l'atterrissage, s'étirent en sautant, penchent en marchant et
  tremblent quand ils sont touchés. Ces déformations viennent des événements de la sim (§5.8) et d'un
  ressort propre au rendu ; elles ne touchent jamais la sim. Un blob mort devient une flaque grise,
  qui retombe sur le sol si une explosion le creuse sous elle (rendu seulement). Les blobs changent
  aussi de visage, comme sur l'Accueil (§7.2) : un blob touché se fâche pendant 2 s, un blob vivant à
  moins de trois rayons d'une explosion qui ne l'a pas touché prend peur pendant 2 s ; ils reviennent
  ensuite au calme (rendu seulement, D-09).
- **Projectiles et explosions** : le bazooka tire une roquette en voxels qui pointe dans le sens de
  sa course, sans tournoyer, et laisse une traînée de petits cubes de fumée ; la grenade est un cube
  qui tournoie ; une explosion est un flash cubique de 0,4 s (0,3 s jusqu'au run C3 : les cartes à
  surplombs, arbres et grottes coûtent plus de faces par cratère, et le flash doit couvrir leur
  reconstruction) et une gerbe de petits cubes de terre projetés, sans effet sur la sim.
- **Équipes** : 8 couleurs distinctes, plus une lettre (A à H) : aucune information ne repose sur la
  seule couleur.
- **Au-dessus de chaque blob** : le nom du membre et ses PV. Le blob actif porte un repère et, sous
  son nom, une petite barre : sa jauge de déplacement (§5.4).
- **L'uppercut et le Chomp** : le blob frappe vers le haut en s'étirant ; le blob qui mange ouvre et
  ferme la bouche, des miettes de terre volent derrière lui.
- **Le tentacule** : un bras de voxels à la couleur de l'équipe, qui part du blob jusqu'au point
  d'accroche et ondule avec son ressort (un coup au crochetage, puis selon la vitesse du balancier) ;
  il se tend au lancer, et se rétracte s'il ne touche rien ou quand il lâche.
- **Interface de partie**, limpide d'un coup d'œil à 844×390 :
  - en haut à gauche, l'équipe qui joue : son nom, sa couleur, sa lettre ; dessous, une ligne par
    équipe : sa lettre, son nom (coupé s'il le faut, jamais sous 12 points), ses PV restants, et une
    petite icône de bot quand un bot la joue (une place Bot, ou l'équipe d'un joueur parti, §6.7 ;
    hors ligne, les équipes des bots) ; les 8 lignes tiennent à 844×390, sans toucher aucun pavé
    des pouces (une spec le vérifie) ;
  - en haut au centre, le temps restant du tour et le vent (sens et force) ;
  - la visée : une ligne de lance-pierre partant du blob (§7.3), orientée selon l'angle, dont la
    longueur et la couleur disent la puissance ;
  - en bas, les commandes (§7.3), dont l'arme choisie, ses munitions et, pour la grenade, la minuterie.
- **Palette** : peu de couleurs, douces, fixées dans un seul module du client.
- **Police** : **Fredoka One** (SIL Open Font License 1.1, sans nom réservé), ronde et épaisse, assortie
  aux blobs, committée avec sa licence dans `client/fonts/`, rendue en champ de distance avec un
  contour fin (1,5 px pour un corps de 24) : un contour épais mordait sur la lettre voisine. Aucun
  texte sous 12 points à l'échelle de référence (V0 §2, vérifié par une spec).

### 7.5 Performance

- 60 images par seconde sur un téléphone Android de milieu de gamme (le téléphone de l'utilisateur
  fait foi au run E).
- Un tick de sim ≤ 2 ms en LuaJIT sur ce téléphone. Après un cratère, la reconstruction du terrain ne
  prend jamais plus de 4 ms dans une image et se termine avant la fin du flash de l'explosion.
- Build HTML5 : moins de 8 Mio transférés au premier chargement.

## 8. Les armes

### 8.1 La grammaire d'une arme

```lua
-- shared/sim/weapons/bazooka.lua
return {
  id = "bazooka",
  kind = "projectile",
  aim = "angle_power",
  fuse = nil,             -- or { min = 1, max = 5, default = 3 } in seconds
  wind_percent = 100,
  bounce = nil,           -- or { restitution = 55, friction = 80 } in percent
  explosion = { carve = 12, radius = 16, damage = 50, push = 1920 },
  on_fire = nil,          -- optional hooks, each receives an EffectApi
  on_tick = nil,
  on_impact = nil,
  on_timer = nil,
}
```

- Les fonctions de rappel ne modifient le monde qu'à travers une `EffectApi` construite par la sim
  (`shared/sim/effects.lua`) : `explode{x, y, spec}`, `remove_projectile(p)`,
  `spawn_projectile{…}`. Elles ne touchent jamais les tableaux du monde directement. Leurs
  signatures : `on_fire(api, p)`, `on_tick(api, p)`, `on_impact(api, p, hit)` avec
  `hit = {x, y, cat}`, `on_timer(api, p, at)` avec `at = {x, y}`. Sans fonction de rappel, un impact
  ou une minuterie fait exploser le projectile à cet endroit puis le retire. Les bots évaluent un tir
  avec une variante de l'API qui enregistre la première explosion au lieu de l'appliquer
  (`effects.dry_run`) ; dans cette variante, `spawn_projectile` rend un projectile qui n'est pas
  simulé : un bot n'évalue que la première explosion d'une arme.
- Une arme `utility` (§8.3) ne vole ni n'explose : sa fonction de rappel `on_use(api, chat, visée)`
  agit sur le chat qui la lance à travers l'`EffectApi` (`grapple{cat, angle}` pour le tentacule) et
  rend `true` si elle a agi ; alors seulement une munition est décomptée, et le tour continue
  (`weapons.ends_turn` le dit au serveur et à la LocalAuthority).
- Une arme `digger` (§8.3) se vise comme le tentacule (`aim = "angle"`) ; sa fonction de rappel
  `on_use(api, chat, visée)` met le chat à table à travers l'`EffectApi` (`dig{cat, angle}`) ; le
  repas lui-même avance dans le pas du chat (champs `dig`, les ticks qui restent, et `dig_angle`).
  Comme un coup, il part toujours et termine le tour.
- Une arme `melee` (§8.3) se déclare sans visée (`aim = "none"`) avec
  `melee = {reach, damage, push_x, push_y}` ; sa fonction de rappel `on_use(api, chat, visée)` frappe
  à travers l'`EffectApi` (`strike{cat, spec}`). Le coup part toujours, qu'il touche ou non : la
  munition est décomptée, `fired` est émis avant les `damaged`, et le tour se termine comme après un
  tir.
- Une arme `placed` (§8.3, la dynamite) se déclare sans visée (`aim = "none"`) avec une mèche fixe
  (`timer`, en secondes) : elle se pose aux pieds du blob, projectile sans vitesse qui tombe, rebondit
  comme la grenade (`bounce`) et ne heurte que le terrain ; elle explose au bout de sa mèche. Le tour
  passe aussitôt au repli, qui dure autant que la mèche, et la jauge du blob se remplit (§5.4) : on
  a tout ce temps, et de quoi, pour s'éloigner. Tombée dans le liquide, elle disparaît sans exploser
  (§5.5), munition dépensée, et le repli dure quand même sa mèche.
- Une arme `walker` (run C8, le Waddler) se pose aux pieds du blob comme une arme `placed`, tournée
  comme lui (`facing`), puis marche seule ; le tour passe en `flight`, qui dure tant qu'elle vit, et
  la caméra la suit. Ses pieds sont sa position, sa boîte une colonne de 4 px de haut
  (`WADDLER_HEIGHT`), le terrain seul l'arrête. Au sol, elle avance d'une colonne par tick : à la
  première place libre en montant de 0 à 3 px, ou, si elle n'a pas de sol dessous, en descendant de
  1 à 3 px ; sans place, elle fait demi-tour ; sans sol à 3 px, elle tombe. Tous les 24 ticks au sol
  (`WADDLER_HOP_TICKS`, comptés sur son âge), elle saute, vitesse `(sens × 256, −512)`. En l'air :
  gravité, déplacement par pas d'au plus 1 px ; une case pleine de côté la renvoie dans l'autre
  sens, dessous la pose, au-dessus annule sa vitesse verticale. Elle explose au bout de sa mèche
  (`timer`), ou plus tôt sur `fire`.
- **Se déclencher à distance** : pendant `flight`, une entrée `fire` de l'équipe active fait agir
  chacun de ses projectiles vivants dont l'arme le permet (`trigger = true`) : sa fonction de
  rappel `on_trigger(api, p, at)`, ou, sans elle, une explosion à sa place. Aucune munition n'est
  regardée ni dépensée ; sans projectile à déclencher, l'entrée est ignorée.
- Une arme `strike` (run C8, l'appui aérien) se vise par une colonne (`aim = "target"`, champ
  `target` de `fire`, de 0 à la largeur de la carte − 1) ; sa fonction de rappel
  `on_use(api, chat, visée)` lâche ses obus par `spawn_projectile` ; le tour passe en `flight`
  comme après un tir.
- **Les éclats** (`weapons.parts`, run C8) : les projectiles qu'une arme lance sans qu'on les
  choisisse (les mini-blobs de la grappe, les obus de l'appui aérien). Ils se déclarent comme une
  arme (vent, rebond, explosion) mais sont rangés à part dans le registre, comptés après les armes
  dans la somme de contrôle, et jamais acceptés dans un `fire`.
- **Les munitions** ne sont pas dans le module d'une arme mais dans une seule table de
  `shared/sim/rules.lua`, `AMMO` (par équipe et par partie, `-1` = sans limite) : c'est là, et
  seulement là, qu'on change les seuils pour tout le jeu (pas de réglage par partie en V0).
- Ajouter une arme : son module, une ligne dans `shared/sim/weapons/registry.lua`, ses munitions dans
  `rules.AMMO`, ses textes
  (`shared/i18n/`, clé `weapon.<id>`, l'anglais en V0), son icône, et, si elle met un projectile dans
  le monde, sa couleur de tir (`client/ui/palette.lua`, `SHOTS` ; un test le vérifie). Le registre ne s'appelle pas `init.lua` :
  Nakama nomme un module par son chemin et ne résout pas `require "…weapons"` vers `init.lua`. Le test de contrat (§10.1) la prend en compte sans modification.

### 8.2 Les armes de la V0

| Arme | Vent | Déclenchement | Creuse | Rayon | Dégâts | Poussée |
|---|---|---|---|---|---|---|
| Bazooka | 100 % | à l'impact | 12 px | 16 px | 50 | 1920 FP/tick |
| Grenade | 0 % | minuterie 1–5 s (3 par défaut) ; rebondit (restitution 55 %, frottement 80 %) | 12 px | 16 px | 50 | 1280 FP/tick |
| Tentacule | — | à l'accroche, jusqu'à 120 px (genre `utility`, §5.4) ; sans munitions, ne termine pas le tour | — | — | — | — |
| Uppercut | — | au contact, sans visée, dans le sens du regard : tout blob dont la boîte entre dans les `10` px devant la boîte du frappeur, à sa hauteur (genre `melee`) ; termine le tour | — | — | 30 (plus la chute, §5.4) | `(±512, −1024)` FP/tick, en cloche |
| Dynamite | 0 % | posée aux pieds du blob (genre `placed`), mèche fixe de 5 s ; tombe et rebondit à peine (restitution 20 %, frottement 50 %), ne heurte que le terrain ; le repli dure autant que la mèche | 20 px | 30 px | 75 | 2304 FP/tick |
| Waddler | — | posé aux pieds du blob (genre `walker`), il marche seul dans le sens du regard (1 px par tick), saute tous les 24 ticks et fait demi-tour contre un mur ; `fire` pendant qu'il marche le fait sauter, sinon il explose au bout de 10 s ; il traverse les blobs ; tombé dans le liquide, il disparaît | 16 px | 24 px | 70 | 2048 FP/tick |
| Jetpack | — | s'allume au sol ou en l'air (genre `utility`, §5.4) : 150 ticks de poussée ; ne termine pas le tour | — | — | — | — |
| Grappe | 0 % | minuterie 1–5 s (3 par défaut), rebondit comme la grenade ; à la minuterie, explose et projette 5 mini-blobs (`cluster_bit`) aux vitesses `(±512, −896)`, `(±256, −1024)` et `(0, −1152)` | 12 px | 16 px | 40 | 1280 FP/tick |
| — un mini-blob de la grappe | 0 % | au premier contact, terrain ou blob | 8 px | 12 px | 25 | 1024 FP/tick |
| Appui aérien | — | une colonne choisie (genre `strike`) : 5 obus (`airstrike_shell`) lâchés à −24, −12, 0, 12 et 24 px d'elle, l'obus du milieu 16 px au-dessus de la rangée 0, ceux à 12 px 24 px au-dessus, ceux à 24 px 32 px au-dessus, vitesse initiale `(0, 768)` | — | — | — | — |
| — un obus de l'appui aérien | 50 % | au premier contact, terrain ou blob | 12 px | 16 px | 35 | 1536 FP/tick |
| Chomp | — | visé (seul l'angle compte) : pendant `60` ticks, le blob avance de `2/3` px par tick dans la direction visée et mange un disque de `5` px de rayon autour du centre de sa boîte à sa nouvelle place (le tunnel le dépasse de 2 px), sans gravité ni dégâts, tourné vers où il mange (genre `digger`) ; rien ne le cogne (§5.4) ; il s'arrête avant que sa boîte ne sorte de la carte, et retombe à la fin du repas ; termine le tour (`flight` tant qu'il mange, puis le repli) | tunnel à sa taille, 40 px | — | — | — |

La poussée du bazooka est passée de 1280 à 1920 au run C, à la demande de l'utilisateur après avoir
joué (« le bazooka n'expulse pas tant que ça ») : une explosion aux pieds d'un blob le lance à 77 px au
lieu de 34, et le blob qui se tire aux pieds perd 85 PV au lieu de 47 (la chute compte).

**La dynamite** (run C6), demandée par l'utilisateur : « elle se pose et on a le temps
de bouger au moins 5 sec […] gros radius quand même et fait très mal si on est vraiment dedans (comme
dans Worms) ». Dans Worms Armageddon, sa mèche de 5 s ne se règle pas, et un ver collé à elle perd 65
à 75 PV (une grenade, ~45). Ici, un blob collé à elle perd ~65 à 75 PV (la distance se compte depuis
le centre de sa boîte) et vole loin : avec la chute, c'est mortel pour un blob à 100 PV. Un voisin
à 6 px perd ~60 PV.

**Les munitions**, par équipe et par partie (`rules.AMMO`, run C6, à la demande de l'utilisateur :
« 1 seule dynamite, tentacule illimité, uppercut illimité, 10 grenades, 10 bazookas, etc. ») :

| Arme | Bazooka | Grenade | Tentacule | Uppercut | Chomp | Dynamite | Waddler | Jetpack | Grappe | Appui aérien |
|---|---|---|---|---|---|---|---|---|---|---|
| Munitions | 10 | 10 | sans limite | sans limite | 3 | 1 | 0 | 0 | 0 | 0 |

**Les armes des caisses** (run C8), demandées par l'utilisateur : « l'équivalent du
mouton worms (un mini blob rigolo qu'on peut faire sauter quand on veut avec une limite comme dans
worms), jetpack, grenade "banane" (des mini blob colorées qui explosent), appui aérien avec plein de
bazooka sur zone dédiée ». Chaque équipe en commence la partie sans aucune ; une caisse ramassée en
donne une (§5.10). Les noms sont à nous : le Waddler (`waddler`), le jetpack (`jetpack`), la
grappe (`cluster`, « Cluster ») et l'appui aérien (`airstrike`, « Air strike »).

Le Chomp, qui creuse, est compté comme les outils de creusage de Worms (chalumeau, perceuse), en
petite quantité. Une munition se décompte quand l'arme agit (§8.1) ; une arme épuisée n'est plus
acceptée (`no_ammo` au serveur, ignorée par la sim). Les seuils se changent dans `rules.AMMO`, pour
tout le jeu. La somme de contrôle compte les munitions dès le tick 0 : changer un seuil ré-enregistre
les vecteurs (`make vectors`, en le disant dans le commit, §10.1) et met à jour les tests qui figent
les seuils (`rules_spec`, qui fige la table, et ceux des armes : `turn_spec` pour les 10 bazookas,
`cat_spec` pour les 3 Chomp, `melee_spec` pour l'uppercut, `dynamite_spec` pour la dynamite unique)
et les libellés relus par les parcours (« Bazooka x10 », « Dynamite x1 »).

Le rebond réfléchit la vitesse sur la normale locale du terrain, estimée par le gradient des cellules
pleines dans un carré de 5×5 autour du point de contact, en arithmétique entière.

### 8.3 Les genres à venir

`projectile`, `utility`, `melee`, `digger`, `placed`, `walker` et `strike` existent en V0 : le tentacule est le premier `utility`,
une arme qui agit sur le chat qui la lance au lieu de créer un projectile, et qui ne termine pas le
tour ; l'uppercut le premier `melee` (sa fonction de rappel frappe à travers l'`EffectApi`) ; le Chomp
le premier `digger` (le chat mange la terre pendant quelques ticks) ; la dynamite le premier `placed`
(run C6) ; le Waddler le premier `walker`, le jetpack le deuxième `utility`, l'appui aérien le premier
`strike` (run C8). La grammaire doit pouvoir accueillir, sans changer le cœur de la sim : `hitscan` (fusil),
d'autres `placed` (mine), d'autres `utility` (téléporteur). Le champ `kind` est là pour ça.

## 9. Les bots

`shared/bots/` — Lua pur, soumis à D-02, sauf qu'un bot a le droit d'être lent : il ne tourne que
dans une partie qui lui en laisse le temps.

- **Candidats** : tirés sur le flux `bots` parmi les armes pour lesquelles l'équipe a des
  munitions : une arme, un angle (demi-cercle supérieur), une puissance de 15 à 100, et la minuterie
  de 2 à 4 s pour la grenade.
- **Évaluation** : le vol du projectile est simulé sur le terrain courant **en lecture seule** ; au
  point d'explosion, les dégâts et la poussée de chaque chat sont calculés par les formules de §5.5,
  et une poussée qui envoie un chat dans le liquide compte comme sa mort.
- **Score** : dégâts infligés aux ennemis + 50 par ennemi tué − 1,5 × dégâts à sa propre équipe
  − 2 × dégâts à soi-même. (Les coefficients sont des entiers ×10 dans le code.) Le bot garde le
  candidat de meilleur score **positif**. S'il n'y en a aucun, il garde celui dont l'impact tombe le
  plus près d'un ennemi, parmi ceux qui ne blessent pas son équipe. À défaut, il garde le candidat de meilleur score, quitte à se
  blesser pour creuser : un bot ne passe son tour que si aucun de ses tirs n'explose, ou s'il n'a
  plus ni bazooka ni grenade (§8.2).
- **Niveaux** (nombres de candidats de départ) :

| Niveau | Candidats | Bruit sur l'angle | Bruit sur la puissance |
|---|---|---|---|
| facile | 16 | ±24 | ±15 |
| moyen | 32 | ±8 | ±6 |
| difficile | 48, dont 12 d'affinage autour du meilleur | ±2 | ±2 |

Réglés au run B sur la mesure dans Nakama (au lieu de 64 / 320 / 640) : au budget du serveur, un bot
a ~36 000 unités de travail avant la limite de décision (121 appels de 300 ; ~45 000 depuis que le
début de tour dure 2 s). Sur 2 700 recherches du
niveau difficile mesurées (8 équipes de 5 et de 6), 14 dépassent ce budget, jusqu'à 46 000 unités :
le bot tire alors le meilleur candidat trouvé à la limite (§9, Décision). Hors ligne, le budget est
le même depuis le run C (§9) : une même graine donne les mêmes tirs des deux côtés, ces cas rares
compris. Les clients en ligne ne font jamais tourner les bots (D-06).

- **Budget** : la recherche est un état explicite (candidat en cours, vol, chat examiné ou chat
  projeté en cours) repris d'un tick à l'autre ; pas de coroutine, le runtime Lua de Nakama n'a pas
  cette bibliothèque. Un appel s'arrête dès qu'il a dépensé `N` **unités de travail**, quitte à
  s'arrêter au milieu d'un vol : un tick de projectile vaut 5, un tick de chat projeté 17, l'examen
  d'un chat au point d'explosion 1, un seul chat par unité. Ces poids sont les coûts mesurés sous
  Lua 5.1, l'interpréteur le plus proche de gopher-lua (13, 44 et 2,5 µs) : compter des pas égaux
  laissait un appel de 40 pas durer de 3 à 29 ms dans Nakama. Elle commence dès le `turn_start` du
  bot, puisque le vent est alors connu. Sur le serveur, un bot doit avoir décidé en **3 s au plus**,
  sans empêcher le match de tenir ses 30 Hz : `N` = 300 (`BOT_SERVER_WORK_PER_TICK`) ; hors ligne
  aussi, `N` = 300 (`BOT_WORK_PER_TICK`), réglé au run C sur la mesure dans le build HTML5 : à 1000
  unités, le tick de la plus grande partie (8 équipes de 6, bots difficiles) montait à 17–22 ms au
  p95 à CPU ×4 pendant la recherche d'un bot (~15 µs l'unité), au-delà d'une image. Avec le même
  budget des deux côtés, un bot joue hors ligne exactement comme en ligne. Mesuré au run B dans
  Nakama, sur la plus grande carte : une unité coûte ~8 µs sur un cœur performant du i9-13900KF
  de l'hôte et 20 à 28 µs sur un cœur économe (Go place le match où il veut) ; un appel coûte en
  moyenne 2 à 8 ms, et au pire ~24 ms, sous les 33 ms d'un tick. La cible de 8 ms par tick écrite
  avant la mesure ne tient qu'en moyenne ; la tenir au pire demanderait un budget trop petit pour
  que le niveau difficile finisse sa recherche.
- **Décision** : dès que la recherche est finie et l'attente écoulée, ou au plus tard après 90 ticks
  de visée (3 s) avec le meilleur candidat trouvé jusque-là, et toujours avant la fin du temps de
  tour. Pour un bot qui reprend un tour déjà en visée (§6.7), l'attente et ces 90 ticks se comptent
  depuis la reprise, pas depuis le début de la visée ; si aucun candidat évalué n'a explosé,
  il tire celui qu'il était en train d'évaluer. La recherche s'arrête dès la décision prise. Une fois prise, elle ne change plus de
  tout le tour ; le bot rend la même entrée tant qu'on la lui demande, sans tirer à nouveau sur le
  flux `bots`.
- **Rythme** : le bot attend entre 20 et 40 ticks avant de commencer, puis tire. Il ne marche pas et
  ne lance pas le tentacule en V0 : seules les armes de genre `projectile` sont des candidats (ni le
  tentacule, ni l'uppercut, ni le Chomp, ni la dynamite), hors des armes des caisses (§5.10) : une
  caisse peut tomber sur un blob de bot et lui donner une grappe, il ne la lance pas. Avec les munitions comptées (§8.2), un bot
  qui n'a plus ni bazooka ni grenade passe son tour.
- Le bruit vient du flux `bots`, que tient le pilote des bots (le serveur, ou le client hors ligne) et
  non le monde : il n'entre ni dans la somme de contrôle ni dans le snapshot, puisque les clients en
  ligne ne font pas tourner les bots. Une partie rejouée avec la même graine rejoue les mêmes tirs.

## 10. Tests

### 10.1 Conventions

- **busted**. `spec/` reflète `shared/`, `server/` et `client/` fichier par fichier
  (`shared/sim/terrain.lua` → `spec/shared/sim/terrain_spec.lua`).
- La suite `shared/` tourne **deux fois**, sous LuaJIT et sous Lua 5.1.
- **Test d'architecture** (D-01) : aucun fichier de `shared/` ne `require` hors de `shared/`, ni
  n'utilise un global de moteur.
- **Test de déterminisme** (D-02) : lit les sources de `shared/` et échoue sur un littéral décimal,
  une fonction interdite, `pairs` ou `next`.
- **Test de contrat des armes** (D-05) : chaque arme du registre se charge, a ses textes, tire, vole,
  et explose ou disparaît dans un nombre borné de ticks sur trois terrains de référence.
- **Mocker uniquement aux coutures** : la sim n'a pas de coutures ; le serveur en a une (`nk`), le
  client en a une (l'autorité, §7.1).
- Les specs et les outils lisent et écrivent le JSON avec **dkjson** 2.11, installé avec busted dans
  l'image d'outils ; il n'entre jamais dans le jeu.

### 10.2 Vecteurs de conformité (D-12)

`spec/vectors/*.lua` : une graine, des réglages, un script d'entrées, les sommes de contrôle
attendues à des ticks donnés, et les noms générés des équipes et de leurs membres (§6.1). Ce sont des modules de données purs, sans effet de bord. Ils passent
sous LuaJIT, sous Lua 5.1, et dans le runtime de Nakama : le profil Compose `conformance` démarre un
Nakama qui monte `shared/` en `modules/shared`, `spec/vectors/` en `modules/vectors` et
`tools/conformance/` (un RPC qui rejoue les vecteurs et renvoie ses sommes et ses noms) ; `server/` n'y est pas
monté. Les sommes attendues ne s'écrivent qu'une fois la physique stabilisée ; les changer demande
un commit qui dit pourquoi.

### 10.3 Harnais serveur

`tools/harness/` — Node 24 et `@heroiclabs/nakama-js`, pour les tests uniquement : jamais dans un
build du jeu. Il joue des clients complets contre le vrai serveur, enregistre le flux `ticks`, puis
un script Lua rejoue ce flux et vérifie chaque `checksum` reçu.

### 10.4 Le banc

`make bench` : `N` parties bots contre bots, réglages tirés au hasard (2 à 8 équipes, 1 à 6 chats),
sous LuaJIT. Toutes doivent se terminer sans erreur. Il écrit : nombre de tours, durée simulée, part
des parties qui atteignent la limite de §5.2 (en tout, puis en forêt et au volcan), morts par cause,
nombre de séismes et morts pendant qu'ils secouent, dégâts moyens par tir et par niveau de bot. Le banc mesure ; on ne règle rien d'après lui sans l'écrire dans la spec.

### 10.5 Le parcours dans le navigateur

Le build HTML5, dans Chromium sans interface piloté par le protocole DevTools depuis un script Node
(pas de Playwright), en paysage 844×390 avec le toucher émulé. On y joue pour de vrai : les
assertions portent sur ce que l'écran montre et sur l'état exposé en mode test.

En ligne (run D, `tools/journey/online.mjs`), plusieurs contextes du même Chromium, chacun avec son
stockage (donc son compte), jouent contre le Nakama de `make up`. Chaque client publie en mode test
une **trace** (`client/game/trace.lua`) : les entrées appliquées, les événements, les visages qui
changent et la position du blob actif, hachés tick par tick, un point de contrôle tous les 30 ticks,
et le compte de ce que la partie a montré (marches, sauts, tirs par arme, repas, tentacules,
dégâts, visages, morts). Le parcours compare les points de contrôle des deux contextes aux mêmes
ticks, et leurs comptes.

### 10.6 Plan TDD

Chaque tranche : écrire le test qui échoue, le regarder échouer, implémenter, le faire passer,
`luacheck` et `stylua --check`, relecture du diff par un sous-agent contre cette spec, commit. Aucune
tranche ne commence tant que la précédente n'est pas verte.

| # | Tranche | Le test qui ouvre la tranche |
|---|---|---|
| **Run A — socle et simulation** | | |
| 1 | Socle : image `blobattle-tools`, `Makefile`, busted sous LuaJIT et Lua 5.1, luacheck, StyLua | `make test` exécute une spec triviale sous les deux moteurs et sort 0 |
| 2 | Tests d'architecture et de déterminisme (D-01, D-02) | un fichier de test contenant `pairs(` ou `0.5` dans `shared/` fait échouer la suite |
| 3 | Arithmétique : `fixed`, `isqrt`, table trigonométrique, générateur, hachage | les premiers tirages de Park–Miller depuis 1 valent 48271 puis 182605794 |
| 4 | Terrain : grille, creusage, RLE, hachage des cellules | un creusage de rayon 12 vide exactement le nombre de cellules attendu |
| 5 | Génération de carte (§5.3) | pour 200 graines × 7 réglages : liquide aux deux bords, puits jusqu'au liquide, apparitions valides, même graine = même terrain |
| 6 | Chats (§5.4) | sur une marche de 4 px, le chat s'arrête ; sur 3 px, il monte |
| 7 | Projectiles, explosions, armes, registre et contrat (§5.5, §8) | à vitesse maximale, un projectile ne traverse pas un mur d'un pixel |
| 8 | Tour (§5.6) et entrées (§5.7) | une entrée `fire` hors de `aiming` est ignorée ; une transition hors table lève une erreur |
| 9 | Monde : `step`, événements, somme de contrôle, snapshot (§5.8, §5.9) | un snapshot désérialisé a la même somme et les mêmes cellules |
| 10 | Bots (§9) | un bot difficile face à un ennemi à découvert le blesse en au plus 3 tours |
| 11 | Banc (§10.4) | 200 parties se terminent sans erreur |
| 12 | Conformité : Nakama rejoue les vecteurs (§10.2), et y mesure la génération de la plus grande carte et le coût d'un candidat de bot | `make conformance` sort 0 avec des sommes identiques sous LuaJIT, Lua 5.1 et Nakama |
| **Run B — serveur** | | |
| 13 | Compose : Postgres, Nakama, configuration (taille des messages, clé serveur) | `make up` : Nakama sain et le module `room` chargé |
| 14 | Identité et pseudo, RPC `room_create` / `room_find`, codes (§6.1–6.3) | un code inconnu rend `room_not_found` |
| 15 | Salon : places, hôte, réglages, transfert d'hôte (§6.3, D-08) | un invité qui envoie `lobby_settings` reçoit `refused` |
| 16 | Partie : lancement, horloge `ticks`, `checksum`, validation (§6.5, §6.8) | un `fire` du joueur inactif est jeté et compté |
| 17 | Snapshot, reconnexion, absences et bot remplaçant (§6.6, §6.7) | un joueur déconnecté pendant son tour est joué par un bot, puis reprend la main |
| 18 | Harnais : partie complète 2 humains + 2 bots, rejeu Lua des sommes (§10.3) | toutes les sommes reçues correspondent au rejeu |
| **Run C — client hors ligne** | | |
| 19 | Carte à ciel ouvert (§5.3) et noms générés (`shared/names.lua`, flux `names`, §5.1, §6.1) | sur 200 graines × 7 réglages, aucun chat n'a de terre au-dessus de lui, et une même graine donne les mêmes noms sous LuaJIT, Lua 5.1 et Nakama |
| 20 | Projet Defold, `LocalAuthority`, build HTML5 dans le conteneur | le build HTML5 se charge dans Chromium et affiche l'Accueil |
| 21 | Rendu voxel : terrain, liquide, blobs, projectiles, explosions (§7.4) | après un cratère, le maillage des morceaux touchés a exactement une face par frontière terre-air de la sim |
| 22 | Caméra et commandes tactiles et clavier (§7.3) | un glisser depuis le chat produit un `fire` d'angle et de puissance entiers attendus |
| 23 | Interface de partie, noms et PV, écrans Accueil (pseudo, équipe), Entraînement, Fin, catalogue anglais, paysage imposé (§7.2, §7.4) | en portrait, la partie affiche l'écran de rotation et continue |
| 24 | Parcours : une partie d'entraînement jouée jusqu'au bout à 844×390 (§10.5) | le script atteint l'écran Fin |
| **Entre C et D — le tentacule** | | |
| 24a | Jauge de déplacement (§5.4) : marcher, sauter la vident ; affichée | une jauge vide arrête la marche au pixel près et refuse le saut, et le chat tire encore |
| 24b | Tentacule dans la sim (§5.4, §5.7, §8.2), protocole `climb` (§6.4, §6.8) | accroché à un plafond, un balancier lâché au bout de sa course part avec la vitesse attendue, et le même balancier à gauche reflète celui de droite tick par tick |
| 24c | Commandes, rendu et parcours du tentacule (§7.3, §7.4) | dans le build, le parcours lance le tentacule, se balance, lâche et retombe, sans divergence |
| **Après C2 — chocs, uppercut, Chomp, cartes** (run C3, `docs/runs/run-c3-armes-cartes.md`) | | |
| 24d | Chocs entre blobs projetés (§5.4) | un blob projeté contre un autre le projette à son tour (60 % de l'écart), le choc à gauche reflète celui de droite, et deux blobs qui marchent se croisent toujours |
| 24e | Uppercut (§8.2, genre `melee`), grille à 4 cases, touche 4 | un uppercut envoie le blob touché en cloche, 30 dégâts, et termine le tour ; le même coup à gauche reflète celui de droite |
| 24f | Chomp (§8.2, genre `digger`), grille à 5 cases, touche 5, animation | le Chomp creuse un tunnel à la taille du blob dans la direction visée, le blob au bout, et termine le tour ; dans toutes les directions |
| 24g | Les deux cartes : réglage `map`, matériaux, surplombs, arbres, stalactites, rendu (§5.3, §7.4) | sur 200 graines × 7 réglages, les deux cartes gardent les garanties de §5.3, la forêt a des arbres et des surplombs, le volcan des stalactites |
| 24h | La lave qui monte au volcan (§5.3) | au volcan, la lave monte de 2 px à la fin de chaque ronde dès la 5e (dès la 1re au run C4), noie qui elle atteint, et la somme de contrôle la suit ; la forêt ne monte pas |
| **Après C3 — des poutrelles partout, des bots qui jouent tout** (run C4, `docs/runs/run-c4-bots.md`) | | |
| 24i | Volcan : poutrelles plus nombreuses, à hauteurs variées, apparition dessus ; la lave monte dès la 1re ronde (§5.3) | sur 200 graines × 7 réglages, les garanties de §5.3 tiennent, les poutrelles ont leurs hauteurs et des chats apparaissent dessus ; la lave monte à la fin de la 1re ronde |
| 24j | Le plan d'un bot, la marche : tirer d'une meilleure place (§9) | un bot sans tir d'ici marche jusqu'à la place d'où il touche, puis tire ; il ne marche jamais dans le liquide |
| 24k | L'uppercut des bots (§9) | un bot au contact d'un ennemi au bord du liquide l'y envoie à l'uppercut ; il ne frappe jamais un allié |
| 24l | Le Chomp des bots : à couvert, loin de la lave (§9) | un bot à découvert sans attaque se met à couvert en mangeant ; au volcan, un bot que la lave va atteindre s'en éloigne |
| 24m | Le tentacule des bots (§9) | un bot au fond d'un creux que la lave va noyer en sort au tentacule, puis attaque dans le même tour |
| 24n | L'intro : le studio, puis le jeu (§7.2) | au lancement, le logo du studio tremble de plus en plus fort, puis le logo du jeu, puis l'Accueil ; un appui la passe |
| **Run D — en ligne** | | |
| 25 | `NakamaAuthority`, identité et équipe (`team_set`), Multi, Créer, Rejoindre par code, lien `?room=` (§7.2) | deux contextes navigateur se retrouvent dans le même Salon, chacun sous son nom d'équipe |
| 26 | Salon et partie en réseau, somme de contrôle vérifiée côté client | sur une partie complète, les deux contextes voient les mêmes marches, tirs, coups, projections, dégâts et visages aux mêmes ticks, sans aucune divergence |
| 26b | Les lignes des équipes : nom et icône de bot (§7.4), message `pilots` (§6.4, §6.7) | hors ligne, les équipes des bots portent l'icône ; en ligne, quand un contexte part, l'autre voit l'icône sur son équipe en moins d'une seconde et le bot jouer son tour |
| 27 | Reconnexion et Revanche | un contexte coupé en pleine partie reprend la main au tour suivant de son équipe, l'icône s'en va ; la Revanche relance le salon |
| **Run C5 — le séisme de la forêt et la croix des pouces** (`docs/runs/run-c5-seisme.md`) | | |
| 24o | Le séisme de la forêt dans la sim : secousses, failles qui s'ouvrent et s'écartent, état, somme, snapshot (§5.3, §5.8, §5.9) | en forêt, à la fin de la 8e ronde, les blobs posés sont secoués trois fois et une faille s'ouvre jusqu'à l'eau ; au séisme suivant, plus fort, elle s'écarte de 2 px et une autre s'ouvre ; un blob sur son bord y tombe et se noie ; le volcan n'a pas de séisme ; même partie, même somme sous les trois moteurs |
| 24p | Le séisme à l'écran (§7.4) | la caméra tremble aux secousses, la faille apparaît et s'élargit à l'écran comme dans la sim, la poussière jaillit ; en ligne, les deux contextes voient le même séisme aux mêmes ticks |
| 24q | La croix des pouces et le bouton Saut (§7.3) | au doigt, accroché au tentacule, ▲ de la croix remonte la corde sans lâcher, ▼ l'allonge, et Saut, à part et marqué de son mot, lâche ; aucune cible sous 44 points, sur une encoche ni sur les lignes des équipes |
| **Run C6 — la dynamite et les munitions** (`docs/runs/run-c6-dynamite.md`) | | |
| 24r | Les munitions par partie : une table `AMMO` dans `rules.lua` (§8.2) | une équipe qui a tiré ses 10 bazookas ne peut plus en tirer (la sim ignore le tir, le serveur répond `no_ammo`) ; le tentacule et l'uppercut ne s'épuisent jamais ; un bot sans munitions de tir passe son tour |
| 24s | La dynamite dans la sim (§5.6, §8.1, §8.2, genre `placed`) | posée aux pieds du blob, elle explose 5 s plus tard : le blob a pu s'éloigner pendant tout ce temps (repli de 150 ticks), et un blob collé à elle perd au moins 65 PV ; une seule par équipe et par partie ; même partie, même somme sous les trois moteurs |
| 24t | La dynamite à l'écran et au doigt (§7.3, §7.4) | au doigt et au clavier, la dynamite se choisit dans la grille à six cases (touche 6) et se pose ; à l'écran, un bâton rouge dont la mèche crépite jusqu'à l'explosion |
| **Run C7 — les touches au choix** (`docs/runs/run-c7-touches.md`) | | |
| 24u | Toutes les touches liées à des actions génériques, une table qui les mène aux commandes, gardée sur l'appareil (§7.3) | une sauvegarde où Tirer est sur X fait tirer X et plus Espace ; une sauvegarde où deux commandes partagent une touche rend les touches par défaut |
| 24v | L'écran Touches et son bouton à l'Accueil (§7.2, §7.3) | dans le build, sur ordinateur, Tirer passe sur X depuis Touches, le reste après un rechargement, et X tire en partie |
| **Run C8 — les caisses et leurs armes** (`docs/runs/run-c8-caisses.md`) | | |
| 24w | La grappe et l'appui aérien dans la sim et au serveur : les éclats, le genre `strike`, la colonne `target` (§5.7, §6.8, §8.1, §8.2) | une grappe explose à sa minuterie et ses 5 mini-blobs creusent 5 cratères de plus ; l'appui aérien sur une colonne y creuse 5 cratères en ligne, symétriques autour d'elle sans vent ; un `fire` d'éclat ou de colonne hors carte est refusé ; même partie, même somme sous les trois moteurs |
| 24x | Le Waddler et le jetpack dans la sim et au serveur : le genre `walker`, le déclenchement en vol, `jet` (§5.4, §5.6, §8.1) | posé, le Waddler monte une marche de 3 px, fait demi-tour contre un mur, et saute sur `fire` au tick suivant, sans munition ; laissé seul, il explose à 10 s ; au jetpack, ▲ tenu monte un blob sur une falaise de 40 px, le carburant s'épuise en 150 ticks de poussée et le moteur se coupe quand il se pose |
| 24y | Les caisses dans la sim : largage un tour sur trois, parachute, ramassage, explosion, perte, `turn_start` qui attend, snapshot en version 11 (§5.6, §5.10) | au 3e tour, une caisse descend sous parachute et `aiming` attend qu'elle se pose ; le blob actif qui marche dessus donne à son équipe une munition de son arme ; une explosion la fait sauter ; tombée à l'eau, elle est perdue ; jamais plus de 3 ; un bot qui en reçoit une ne la joue pas ; même partie, même somme sous les trois moteurs |
| 24z | Les caisses, la grappe et l'appui aérien à l'écran, la grille à dix cases, Touches à dix-sept commandes (§7.3, §7.4) | dans le build, une caisse descend sous son parachute, se pose, le blob la ramasse (« +1 »), la grappe lance ses mini-blobs colorés, l'appui aérien se pose d'un clic et le bouton Strike lâche ses obus |
| 24z2 | Le Waddler et le jetpack à l'écran et au doigt (§7.3, §7.4) | dans le build, le Waddler marche, le bouton Boom le fait sauter ; au jetpack, ▲ fait monter le blob, la flamme se voit et la barre montre le carburant |
| **Run D2 — le tunnel** (`docs/runs/run-d2-tunnel.md`, écrit à la fin du run D) | | |
| 28 | nginx, PWA, profil `tunnel` avec cloudflared | le build se charge par l'adresse publique |
| **Run D3 — le panneau d'administration** (`docs/runs/run-d3-admin.md`) | | |
| 28b | Le journal des salons et des parties (§6.9) | une partie jouée jusqu'au bout laisse dans le stockage, au nom du compte système et illisible par un client, son code, ses équipes, son gagnant et ses statistiques ; le salon suit ses phases jusqu'à sa fermeture |
| 28c | Le panneau (§11.1) | sur `127.0.0.1:1341`, le panneau montre la partie que joue le harnais en cours, puis terminée avec son gagnant et ses équipes, et ses joueurs ; il ne répond sur aucune autre adresse |
| **Run E — Android, finitions, clôture** | | |
| 29 | APK Android (arm64, clé de debug), écran allumé, sortie propre en arrière-plan | l'APK s'installe et rejoint une partie en ligne |
| 30 | Finitions du rendu voxel, icônes PWA | le téléphone de l'utilisateur tient 60 i/s sur une partie à 8 équipes de 6 (H-11) |
| 31 | Vérification de bout en bout (§12) | `make verify` sort 0 et la liste manuelle est cochée par l'utilisateur |

## 11. Observabilité

- Logs Nakama en JSON ; chaque ligne applicative porte le code du salon, la phase et le tick.
- Emojis par composant : 🏠 salon · 🎮 partie · 🤖 bot · 🔁 reconnexion · 🧮 somme de contrôle ·
  🚫 refus · 💥 explosion (debug seulement).
- Une divergence de somme de contrôle est un `warn` avec le tick, le code du salon et l'équipe du
  client ; elle ne doit jamais arriver.
- Client, mode test seulement : un objet d'état exposé à la page HTML5 (écran courant, phase, tick,
  somme de contrôle), pour que le parcours affirme sur l'état réel.

### 11.1 Le panneau d'administration

Une page pour voir ce que le jeu a produit, sur le modèle du panneau de telegraph
(`telegraph/admin/`), en plus simple : **lecture seule**, rien ne s'y modifie.

- **Où** : `admin/`, une API Node 24 et une seule page HTML et JavaScript, sans framework, que l'API
  sert elle-même. Une seule bibliothèque, **`pg`** (node-postgres), épinglée par `package-lock.json`
  et installée sans ses scripts (comme le harnais). Un service Compose `blobattle-admin` (profil
  `admin`, l'image d'outils, qui a déjà Node), `make admin`.
- **Jamais sur internet** : il écoute sur `127.0.0.1:1341` seulement et n'a pas d'authentification :
  l'adresse d'écoute est le contrôle d'accès. Le tunnel (§7.1, `tools/tunnel/`) n'y mène pas.
- **Ses sources** : le Postgres de Nakama (tables `users` et `storage`, collections `room`, `game`
  et `team`), par des requêtes `SELECT` seulement ; et l'API console de Nakama
  (`blobattle-nakama:7351`, identifiants de `.env`) pour savoir quels matchs vivent encore. Nakama
  éteint, le panneau montre tout ce qui est en base, sans ce qui est vivant.
- **Ce qu'il montre** :
  - un tableau de bord : comptes, salons ouverts, parties en cours, parties terminées, les
    dernières parties ;
  - les parties : en cours (salon vivant en phase `playing`), terminées, interrompues (un salon
    parti en `playing` dont le match n'existe plus, Nakama redémarré par exemple) ; pour chacune, le
    code, la date, la durée, la carte, les équipes (nom, humain ou bot, pseudo, membres), le
    gagnant, les dégâts et éliminations par équipe, les rondes, la graine ;
  - les joueurs : pseudo, nom d'équipe et membres (`team`), date de création du compte, parties
    jouées et gagnées, dernières parties.
- **Rien de personnel** (D-15) : aucun identifiant d'appareil (la table `user_device` n'est jamais
  lue), aucune adresse ; le compte système est exclu des décomptes.

## 12. Critères d'acceptation V0 et vérification bout en bout

`make verify` exécute la séquence et **vérifie** chaque attendu, pour que « §12 passe » soit un code
de retour et non un souvenir :

```bash
make up                 # postgres, nakama, web
make test lint          # LuaJIT + Lua 5.1, luacheck, stylua --check
make conformance        # LuaJIT, Lua 5.1, Nakama : mêmes sommes
make bench N=200        # 200 parties bots contre bots terminées
make harness            # 2 humains simulés + 2 bots, rejeu des sommes
make journey            # parcours navigateur : entraînement, puis partie en ligne à deux contextes
```

Attendu, vérifié par le script :

- [ ] la suite verte sous les deux moteurs, `luacheck` et `stylua --check` propres ;
- [ ] les vecteurs de conformité identiques sous LuaJIT, Lua 5.1 et Nakama ;
- [ ] 200 parties bots contre bots terminées sans erreur ;
- [ ] une partie en ligne complète sans aucune divergence de somme de contrôle ;
- [ ] un joueur coupé en pleine partie remplacé par un bot, puis qui reprend la main ;
- [ ] le build HTML5 sous 8 Mio.

Liste manuelle, cochée par l'utilisateur :

- [ ] depuis son téléphone, par l'adresse publique : une partie d'entraînement jouée jusqu'au bout ;
- [ ] une partie en ligne à 8 équipes lancée avec 3 humains (téléphone, APK Android, ordinateur),
  5 équipes jouées par des bots, menée jusqu'au bout ;
- [ ] fluide sur son téléphone, sans texte illisible ni cible trop petite.

## 13. Suite

Hors V0, dans l'ordre pressenti :

1. Des caisses posées à la génération, des caisses de soins et d'outils (les caisses parachutées et
   leurs armes sont faites au run C8), puis une roue de choix des armes quand on joue son blob.
2. La mort subite hors du volcan, et d'autres cartes (ville en ruine, mine, hiver : la planche).
3. Les skins par membre d'équipe, le modèle économique pressenti.
4. Statistiques et hauts faits par membre, médailles pour ceux qui survivent à plusieurs parties, un
   hall of fame de ses petits persos ; renommer ses membres.
5. Le français, puis d'autres langues (D-11).
6. Les sons (packs CC0 de Kenney), voir la visée des autres, de nouvelles armes par genre (§8.3), des
   bots qui se déplacent, des bots pilotés par JEV (à la demande de l'utilisateur), iOS, Steam (Nakama
   sait authentifier par Steam), la prédiction du déplacement.

## 14. Questions ouvertes

- **Q-01** — La marche avec l'aller-retour réseau (D-04) suffit-elle à travers le tunnel sur un
  réseau mobile ? Mesurer au run D ; si non, prédiction locale du chat actif avec correction.
- **Q-02** — Domaine du tunnel. **Tranchée par l'utilisateur** : « le domaine
  blobattle.npc.fm qui arrive sur le jeu en tunnel cloudflared », en reprenant le conteneur
  `cloudflared` de telegraph, comme pour npchero : un tunnel nommé `blobattle`, un seul hôte
  (`blobattle.npc.fm`), le build et Nakama derrière, partagés par chemin (§7.1) ; profil Compose
  `tunnel`, identifiants dans `./cloudflared/` (ignoré par git).
- **Q-03** — **La durée des parties.** Au banc du run A (200 parties bots contre bots), 70,5 % des
  parties s'arrêtent à la limite des 30 rondes : 11 à 15 dégâts par tir en moyenne contre 100 à
  600 PV par équipe. Avec des humains à 45 s par tour, une partie à 2 équipes de 4 dure jusqu'à
  60 tours, près d'une heure. Au run B, avec les niveaux ramenés à 16 / 32 / 48 candidats (§9), le
  même banc donne 79,5 % de parties à la limite (11,2 / 12,5 / 14,2 dégâts par tir). Au run C, avec
  l'apparition à ciel ouvert (§5.3), plus personne ne commence à l'abri d'une grotte : 56,0 % à la
  limite, 13,6 / 15,5 / 19,0 dégâts par tir, 88,7 tours et 10,1 min simulées par partie en moyenne,
  1 937 morts par les PV et 1 199 dans le liquide. Avec la poussée du bazooka portée à 1920 (§8.2,
  à la demande de l'utilisateur), 47,5 % à la limite, 80,3 tours et 9,2 min simulées par partie,
  1 688 morts par les PV et 1 475 dans le liquide. Avec la tolérance de 2 px par vol en l'air (§5.4),
  47,0 % à la limite, 77,7 tours et 8,9 min simulées par partie, 1 612 morts par les PV et 1 579 dans
  le liquide ; avec en plus le début de tour de 2 s (§5.6), 47,0 %, 77,8 tours et 10,1 min simulées
  par partie, 1 614 morts par les PV et 1 577 dans le liquide ; avec les rebonds et la glissade des
  blobs projetés (§5.4), 41,0 %, 77,8 tours et 10,2 min, 1 556 morts par les PV et 1 662 dans le
  liquide. Pistes, à trancher par l'utilisateur : mort
  subite dès la V0 (le liquide monte après N rondes), moins de PV, des explosions plus fortes, des
  tours plus courts. **Au run C3, l'utilisateur a choisi la lave qui monte au volcan** (2 px par ronde
  dès la 5e, §5.3 ; dès la 1re au run C4) ; la forêt reste sans limite que les 30 rondes. Au banc du run C3 : 46,5 % à la
  limite avec les chocs entre blobs, 53,0 % avec les deux cartes (surplombs, arbres et poutrelles
  couvrent), **43,5 %** avec la lave qui monte (82,5 tours par partie, 1 594 morts par les PV et
  1 605 dans le liquide). Au run D, avec la chute blessante à ~40 px au lieu de ~24 (§5.4, à la
  demande de l'utilisateur) : 41,0 % à la limite (39,0 % avant), 83,5 tours et 10,8 min simulées par
  partie, 1 494 morts par les PV et 1 707 dans le liquide. **L'utilisateur a choisi
  la mort subite de la forêt** : un séisme à chaque fin de ronde dès la 8e, de plus en plus fort,
  sans dégâts directs (§5.3, run C5). Au banc du run C5 : 20,0 % à la limite (41,0 % avant) ; en
  forêt 5,6 % (44,9 % sans séisme), au volcan 36,6 % ; 70,5 tours et 9,2 min simulées par partie ;
  1 292 morts par les PV et 2 028 dans le liquide ; 7,4 séismes par partie en forêt, qui tuent 457
  blobs en 200 parties. En duel, un blob né sur la pente d'une rive glisse souvent au bassin dès le
  premier séisme. La durée des parties au volcan (36,6 % à la limite) reste à l'utilisateur. **Au run
  C6, les munitions comptées** (§8.2 ; les bots ne tirent qu'au bazooka et à la grenade, et passent
  leur tour une fois à sec) : 30,5 % à la limite, dont 5,6 % en forêt (inchangé, le séisme finit les
  parties avant) et **59,1 % au volcan** (36,6 % avant) ; 74,4 tours et 8,9 min simulées par partie ;
  les bots passent 2 129 tours sur 200 parties (3 avant). Des bots qui jouent aussi l'uppercut, le
  Chomp et la dynamite (run C4), ou des caisses d'armes (§13), y répondraient.
- **Q-04** — **Le rendu** : tranchée par l'utilisateur, **3D en voxels** (terrain
  destructible voxel par voxel, blobs gélatineux ; §7.4, D-09), après un prototype jetable mesuré en
  HTML5 (`docs/sonde-voxel/`). Reste à le voir tenir sur son téléphone (H-11, run C).
- **Q-05** — **Le grappin**, demandé par l'utilisateur après avoir joué le build du
  run C : une action qui ne termine pas le tour (on s'accroche, on se balance, on tire ensuite). C'est
  le premier genre `utility` (§8.3) : une corde déterministe dans la sim (longueur et point d'ancrage
  entiers, balancier en virgule fixe), son entrée et ses bornes dans le protocole (§6.4, D-14), le
  rendu de la corde, et des bots qui l'ignorent. **Tranchée** par l'utilisateur : un
  tentacule que le blob tend, choisi comme une arme, à balancier comme dans Worms, qui ne termine pas
  le tour, et une jauge de déplacement par tour que marcher, sauter et le tentacule vident (§5.4) ;
  trois tranches entre les runs C et D (§10.6, `docs/runs/run-c2-tentacule.md`). **Faite au run C2**
  (tranches 24a à 24c).
