# Run A — socle et simulation · **fait**

Conservé pour mémoire : ce run est terminé (tranches 1 à 12, puis la
revue de clôture). Le prompt et les avertissements qui suivent ont servi à le conduire ; le bilan est
en fin de fichier.

Tranches 1 à 12 du plan TDD de `SPEC.md` §10.6.

**Avant de lancer** : `/clear`. Ce qui n'est pas sur le disque n'existe plus après.

**Ce run n'a besoin ni de Defold, ni d'un client, ni d'un écran.** La sim, les bots, le banc et la
conformité se testent dans des conteneurs. Seuls Docker et Internet (images, rocks) sont requis. Si
une tranche semble exiger `client/` ou le match `room`, elle déborde sur les runs B ou C : la noter
dans le bilan et s'arrêter là pour cette tranche.

---

## Le prompt

```
Lis SPEC.md, CLAUDE.md et V0.md à la racine, puis docs/conventions.md,
docs/adr-001-defold-lua.md, docs/sonde/README.md et docs/runs/run-a-socle-simulation.md
(ce fichier : ce qui est tranché et les pièges).

Le dépôt ne contient que la documentation et la sonde de référence (docs/sonde/, jamais
requise par le code). Rien n'est installé sur l'hôte à part Docker et make : Lua 5.1,
LuaJIT, busted, luacheck et StyLua vivent dans l'image blobattle-tools que la tranche 1 crée ;
toutes les commandes passent ensuite par le Makefile.

/goal Les tranches 1 à 12 de SPEC.md §10.6 sont faites : `make test` est vert sous LuaJIT
et sous Lua 5.1, `make lint` est propre (luacheck et stylua --check), les tests
d'architecture et de déterminisme font respecter D-01 et D-02 sur tout shared/, la
génération respecte §5.3 sur 200 graines × 7 réglages, le contrat des armes passe pour le
bazooka et la grenade, un bot difficile blesse un ennemi à découvert en au plus 3 tours,
`make bench N=200` termine 200 parties bots contre bots sans erreur, et `make conformance`
donne des sommes de contrôle identiques sous LuaJIT, Lua 5.1 et Nakama 3.41.0. Respecte
CLAUDE.md, en particulier D-02 (entiers seulement ; ni trigonométrie, ni pairs, ni
horloge dans shared/), D-05 (une arme = un fichier, test de contrat) et D-06 (un bot
n'évalue que sur le terrain courant en lecture seule). Chaque tranche : test rouge vu
échouer, code, vert sous les deux moteurs, lint, relecture du diff par un sous-agent
contre SPEC.md, commit en français sans trailer Co-Authored-By. À la fin : revue de
clôture de V0.md §4, mise à jour de ce fichier en « fait » avec les mesures (génération
de la plus grande carte sous les trois moteurs, coût d'un candidat de bot sous les trois
moteurs, résumé du banc) et les pièges, report des hypothèses H-04 et H-10 dans SPEC §3,
et écriture de docs/runs/run-b-serveur.md. Ou stop après 60 tours.
```

## Ce qui est déjà tranché et ne se rediscute pas dans ce run

- **Arborescence** créée par ce run : `shared/sim/`, `shared/sim/weapons/`, `shared/bots/`,
  `spec/shared/…` (miroir fichier par fichier), `spec/support/` (terrains faits à la main),
  `spec/vectors/`, `tools/gen_trig.lua`, `tools/bench/`, `tools/conformance/`, `compose.yaml`,
  `Makefile`, `.luacheckrc`, `stylua.toml`, `.gitignore`, `.env.example`. **Ni `client/` ni `server/`**
  dans ce run.
- **Image `blobattle-tools`** : Debian slim, `lua5.1`, `luajit`, `luarocks`, `curl`, `make` ; busted
  **2.3.0** et luacheck **1.2.0** par luarocks ; StyLua **2.5.2** en binaire officiel vérifié par sa
  somme. Le dépôt est monté dans le conteneur ; aucun port publié.
- **`make test`** lance la même suite deux fois, sous LuaJIT puis sous Lua 5.1, et échoue si l'une
  échoue. **`make lint`** = luacheck + `stylua --check`. **`make bench N=…`**, **`make conformance`**,
  **`make perf`** (tests étiquetés `perf`, exclus de `make test`), **`make sweep`** (tests étiquetés
  `sweep`, sous LuaJIT seulement, exclus de `make test` : le balayage de génération 200 graines ×
  7 réglages, trop long pour Lua 5.1 à chaque commit ; `make test` en garde une version à 10 graines
  sous les deux moteurs).
- **Épinglage de l'image** : l'image Debian par digest ; les moteurs (`lua5.1`, `luajit`) et
  `luarocks` par version de paquet ; chaque rock à sa version exacte, installé sans résolution de
  dépendances ; StyLua par somme SHA-256. Les outils de build (`gcc`, `curl`, `make`) suivent la
  distribution figée par le digest.
- **Compose** : noms préfixés `blobattle-`. Profil `tools` pour l'image d'outils. Profil `conformance`
  pour `blobattle-postgres` (16-alpine) et `blobattle-nakama` (3.41.0), **épinglés par digest**, sans port
  publié sur l'hôte : `make conformance` appelle le RPC depuis le conteneur d'outils sur le réseau
  Compose, en `http_key`. Montages de SPEC §10.2 : `shared/` → `modules/shared`, `spec/vectors/` →
  `modules/vectors`, `tools/conformance/` → le module du RPC. Rien de `server/`.
- **Valeurs de départ** : celles de SPEC §5 et §8.2, dans `shared/sim/rules.lua`. Le banc mesure ;
  il ne règle rien sans que la spec change d'abord.
- **Réglage réservé aux tests** : `wind_max` (défaut 10, borne 0–10) dans les réglages résolus, pour
  que les specs de bots et de trajectoires puissent couper le vent. Il n'est pas exposé dans le salon
  en V0.
- **Graine** : un entier ≥ 1. Les trois flux (`map`, `sim`, `bots`) se dérivent de la graine de
  partie de façon fixe et documentée dans `rng.lua` ; l'état de Park–Miller reste dans
  `[1, 2147483646]`.
- **Vecteurs de conformité** : au moins trois (2 équipes sur petite carte ; 8 équipes sur la plus
  grande ; un script riche en grenades et en rebonds), avec des sommes à plusieurs ticks, écrits
  **après** la tranche 11, quand la physique ne bouge plus. Un appel RPC par vecteur.

## Pièges à éviter

- **Nakama exécute chaque `.lua` de son dossier de modules au démarrage** (sonde) : tout module de
  `shared/` et de `spec/vectors/` définit et renvoie sa table, sans rien exécuter d'autre au
  chargement.
- **Registre Lua de Nakama trop petit par défaut** (sonde : un `table.concat` de 256 éléments échoue).
  Relever la taille du registre dans la configuration du Nakama de conformité ; vérifier le nom
  exact de la clé dans la documentation de Nakama 3.41 plutôt que de le deviner, et reporter la
  valeur retenue dans H-10.
- **Nakama coupe un RPC HTTP au-delà d'environ 10 s** (sonde) et gopher-lua est 60 à 120 fois plus
  lent que LuaJIT : un vecteur trop long ne revient jamais. Un RPC par vecteur, et des vecteurs
  courts (quelques milliers de ticks).
- **La garde de déterminisme doit lire le code, pas le texte** : elle ignore les commentaires et les
  chaînes (le mot `pairs` dans un commentaire ne doit pas la faire échouer), attrape `0.5`, `.5`,
  `1e3`, `pairs(`, `next(`, `math.sin`, les accès à `os` et `io`, un `require` hors de `shared.`. La
  tranche 2 la teste sur des fichiers d'exemple dans `spec/support/`, dont un qui doit passer.
- **`fixed.div` et `fixed.mod`** : `math.floor(a / b)` n'est exact que parce que tout reste sous 2^50
  (D-02). Le test de bornes de `rules.lua` doit calculer le pire produit réel (vitesse maximale ×
  table trigonométrique, dégâts × rayon, etc.), pas une borne écrite à la main.
- **busted sous deux moteurs** : les rocks sont installés pour Lua 5.1 ; lancer busted sous LuaJIT
  (option `--lua`) marche pour du Lua pur mais peut buter sur des rocks en C. Vérifier dès la
  tranche 1 que les **deux** passages exécutent réellement leur moteur (une spec qui affiche
  `jit ~= nil` dans un cas et pas dans l'autre).
- **Un test de physique doit faire bouger le monde comme le jeu** : des entrées passées à
  `world.step`, jamais un `cat.x` écrit à la main. Un chat immobile fait passer des tests de marche
  qui ne prouvent rien.
- **Un fichier qui porte deux tranches** (`rules.lua`, `world.lua`) : ne committer que ce qui
  appartient à la tranche ; vérifier la version de chaque tranche dans une copie isolée
  (`git archive HEAD` + fichiers de la tranche) avant son commit.
- **Le bot n'a pas le droit de cloner le terrain** pour évaluer un tir (D-06) : le vol se simule
  sur le terrain courant en lecture seule, sans creuser. S'il semble falloir creuser pour évaluer,
  c'est l'évaluation qui est trop fine pour la V0.
- **`#t` sur un tableau à trous** n'est pas défini pareil partout : un chat mort reste dans le
  tableau avec `alive = false`, il n'est pas mis à `nil`.

## Bilan

Run conduit dans la session qui avait écrit la spec, sans `/clear`, avec une relecture par un
sous-agent à chaque tranche. Pour avancer pendant qu'une relecture tournait, chaque relecture
travaillait sur une copie de l'index git (`git checkout-index`) : la tranche suivante pouvait se
préparer dans l'arbre de travail sans se mélanger au diff relu.

### Ce qui a été mesuré

| Mesure | LuaJIT | Lua 5.1 | Nakama (gopher-lua) |
|---|---|---|---|
| Plus grande carte (8 équipes × 6 chats, 1024×256) | 21 à 22 ms | 243 à 306 ms | 1,7 à 2,4 s |
| Un candidat de bot (8 équipes × 4, niveau facile) | 0,39 à 0,58 ms | 1,29 à 1,38 ms | 10,3 à 12,8 ms |

- **Suite** : 201 tests, verts sous LuaJIT (3,6 s) et sous Lua 5.1 (17 s) ; `luacheck` et
  `stylua --check` propres sur 53 fichiers. Le nombre de tests n'a baissé à aucun commit.
- **Conformité** (`make conformance`) : 3 vecteurs de 2400 ticks enregistrés en jeu réel (bots,
  marches, sauts, bazooka, grenades ; jusqu'à 8 équipes de 6 chats sur la plus grande carte),
  27 sommes de contrôle identiques sous LuaJIT, Lua 5.1 et Nakama. H-04 est vérifiée sur la vraie
  sim.
- **Balayage de génération** (`make sweep`) : 200 graines × 7 réglages, toutes conformes au §5.3,
  en 24 à 32 s sous LuaJIT.
- **Banc** (`make bench N=200`, 152 à 170 s sous LuaJIT, chiffres identiques d'une exécution à
  l'autre) : 0 erreur, 0 tour passé par un bot,
  110 tours et 12,1 min simulées par partie, 1831 morts par PV et 983 noyades ; facile 11,5 dégâts
  par tir (39 % de tirs qui blessent), moyen 13,3 (44 %), difficile 14,8 (46 %). **141 parties sur
  200 (70,5 %) s'arrêtent à la limite des 30 rondes** : voir SPEC §14 Q-03.
- **Budget des bots dans Nakama** : à 11–13 ms par candidat, 3 s de décision à 8 ms par tick ne
  laissent qu'environ 60 candidats, contre 64 / 320 / 640 écrits au §9. C'est au run B de régler
  `BOT_STEPS_PER_TICK` et les nombres de candidats, la spec d'abord.
- 3 531 lignes dans `shared/` (dont 1 044 pour la table trigonométrique générée), 2 772 lignes de
  specs.

### Ce que les relectures ont trouvé

Chaque tranche a eu sa relecture ; toutes ont trouvé quelque chose de réel, corrigé avant le commit
de la tranche (le détail est dans chaque message de commit). Les plus lourds :

1. **La garde de déterminisme se contournait** de cinq façons (alias `local math = math`, directives
   luacheck en ligne, méthode `:format`, écriture dans `math.floor`, `require"x"` sans parenthèses).
   Elle fonctionne maintenant par liste blanche, avec un fixture par contournement.
2. **Les arrondis vers le bas brisaient la symétrie gauche-droite** (45° : 1629, 135° : -1630 ; 13
   grenades sur 72 pas miroir ; centre d'explosion décalé d'un demi-pixel ; projectile parti d'un
   pixel à côté du centre de la boîte). Règle `fixed.round_div` écrite au §5.1, distances en
   demi-pixels, `cat.muzzle`, et des tests qui comparent des tirs à leur miroir.
3. **Beaucoup de règles écrites ne pouvaient pas faire échouer les tests** (carte : 7 règles ; tour :
   24 mutants sur 29 survivants). Les relectures ont muté le code ; chaque mutant survivant a reçu son
   test, et les lots de mutants ont été rejoués jusqu'à tous mourir.
4. **Un projectile traversait une paroi diagonale d'un pixel** par un coin.
5. **Le journal des cratères se perdait** à l'aller-retour RLE, ce qui aurait cassé le snapshot.
6. **Le budget des bots en candidats entiers ne pouvait pas tenir 8 ms par tick** dans Nakama : la
   recherche est reprise pas à pas, dès le `turn_start`, et décide au plus tard après 3 s.
7. **Le banc sous-comptait les parties à la limite** (19 % affichés au lieu de 70,5 %).
8. **La conformance laissait sa pile debout** sur un démarrage raté, avalait un RPC en erreur 500, et
   partageait un volume Postgres nommé entre projets Compose.

La revue de clôture est rapportée plus bas.

### Pièges rencontrés

- **Le runtime Lua de Nakama n'a pas la bibliothèque `coroutine`.** La première version des bots
  était découpée en coroutine et plantait au premier appel côté serveur ; seule la conformance l'a
  montré. Tout ce qui tourne dans `shared/` doit passer `make conformance`, pas seulement la suite.
- **Nakama exécute chaque `.lua` de son dossier de modules**, y compris un script en ligne de
  commande posé à côté : ne monter que les modules, fichier par fichier.
- **Le nom de nœud Nakama est limité à 16 caractères** (`--name`).
- **Un volume nommé (`name:`) traverse les projets Compose** : une copie lancée avec `-p autre` écrit
  dans la base du dépôt. Pas de volume pour la conformance.
- **StyLua reformate les fichiers** : un remplacement de texte préparé avant `make fmt` ne trouve
  plus sa cible. Relire le fichier formaté avant de l'éditer.
- **Un test de physique qui n'observe pas le bon instant ment** : un `skip` traverse `settling` et
  arrive à `turn_end` dans le même tick ; un tour interrompu a déjà rendu la main à l'équipe
  suivante 200 ticks plus tard. Observer les événements, pas l'état à un instant.
- **Un bot sans tir sûr passait son tour** indéfiniment (93 tours passés sur 20 parties) : règle du
  « moins mauvais » au §9.
- **Le hasard des candidats trouve presque toujours un tir légèrement positif** : une règle de choix
  se teste directement (`brain.choose`), pas par un scénario qui espère qu'aucun tir ne marche.

### La revue de clôture

Elle a rejoué tous les critères du goal sur un export du HEAD (tous passent), vérifié qu'il n'y a ni
`server/` ni `client/` ni identifiant d'arme dans le cœur de la sim, et rendu six constats, tous
corrigés dans le commit `revue de clôture` :

1. **Un bot qui reprend une équipe en plein tour rejouait le tir de son tour précédent.** Il ne
   repartait qu'au `turn_start` ; le remplaçant d'un absent (D-08, §6.7, run B) passe justement par
   là. Le tour se reconnaît au compteur de tours de l'équipe, lisible dans tous les états ; un test
   reprend l'équipe à 10 ticks de visée.
2. **`make conformance` vérifiait moins que D-12** : il comparait les moteurs entre eux mais pas aux
   sommes enregistrées, la borne de 3 s de Nakama n'était qu'affichée, et la spec des vecteurs
   nommait trois fichiers en dur. Les quatre sources sont comparées, la borne fait échouer, les
   vecteurs se découvrent dans le dossier.
3. **Les fonctions de rappel des armes et l'EffectApi n'avaient pas de test** (seul `on_fire` en
   avait), et `effects.dry_run` rendait `nil` pour un projectile créé : une arme à sous-munitions
   aurait fait planter l'évaluation d'un bot. `effects_spec` et `driver_spec` exercent `on_tick`,
   `on_impact`, `on_timer`, une bombe à fragmentation dans le monde et dans l'évaluation d'un bot.
4. **Le §5.1 ne disait pas les vrais multiplicateurs** des flux : la spec décrit maintenant les
   multiplicateurs, décalages et la graine par équipe du flux `bots` (changer le code aurait
   invalidé les vecteurs).
5. **`world.step` allouait sa liste d'événements à chaque tick** : elle est vidée et réutilisée,
   valable jusqu'au pas suivant (§5.8).
6. **`make conformance` aurait démonté la pile de développement du run B** (même projet Compose,
   `down -v`) : la conformance a son propre projet, `blobattle-conformance`.
