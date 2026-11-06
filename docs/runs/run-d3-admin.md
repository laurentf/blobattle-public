# Run D3 — le panneau d'administration

Tranches 28b et 28c du plan TDD de `SPEC.md` §10.6 : le serveur tient le journal des salons et des
parties (§6.9), et un panneau local en lecture seule (§11.1) montre ce que le jeu a produit. Demandé
par l'utilisateur : « dans telegraph […] on avait fait un petit dashboard admin ça
vaudrait le coup peut-être pour voir parties (en cours/terminées), équipes, résultats etc (pas
ouvert sur le net évidemment) ». Indépendant du run D2 : l'un ou l'autre d'abord.

**Avant de lancer** : `/clear`. L'état des runs A à D, leurs mesures et leurs pièges sont dans
`docs/runs/` (bilans) ; le tunnel est en place (`docs/runs/run-d2-tunnel.md`).

**Préalables** : Docker ; le port 1341 libre sur `127.0.0.1` (V0.md §3) ; `.env` avec le mot de passe
de la console Nakama (`NAKAMA_CONSOLE_PASSWORD`), qui existe déjà.

---

## Le prompt

```
Lis SPEC.md, CLAUDE.md et V0.md à la racine, puis docs/conventions.md,
docs/runs/run-b-serveur.md (le match room, les pièges de Nakama), docs/runs/run-d-en-ligne.md
(le jeu en ligne, les pièges) et docs/runs/run-d3-admin.md (ce fichier). Lis aussi le panneau
de telegraph, qui sert de modèle : ../telegraph/admin/README.md, ../telegraph/admin/api/src/
(db.ts, nakama.ts, dashboard.ts, main.ts, env.ts).

Les runs A à D sont faits et le tunnel est en place. Tout tourne en conteneur :
  make test, make lint, make conformance, make up, make harness, make web,
  make journey (J=online pour la seule partie en ligne), make serve, make tunnel.

/goal Les tranches 28b et 28c de SPEC.md §10.6 sont faites. Le serveur écrit le journal des
salons (collection room : phase, places, jusqu'à la fermeture) et des parties (collection
game, une par partie, revanches comprises : code, réglages, graine, roster, gagnant,
statistiques, rondes, limite des rondes, équipes parties), au nom du compte système,
illisible et non modifiable par un client, sans rien de personnel (§6.9). Le panneau
(admin/, API Node 24 + pg, une page HTML sans framework, service Compose blobattle-admin du
profil admin, make admin) écoute sur 127.0.0.1:1341 seulement, en lecture seule, et montre
le tableau de bord, les parties en cours, terminées et interrompues avec leurs équipes,
leur gagnant, leurs dégâts et éliminations, et les joueurs avec leur équipe et leurs parties
(§11.1) ; une vérification jouée contre le vrai Nakama (le harnais joue une partie) le
prouve, en cours puis terminée, et prouve qu'il ne répond pas sur l'adresse du réseau local.
make test, make lint, make conformance, make harness et make journey restent verts.
Respecte CLAUDE.md, en particulier D-14, D-15 (aucun identifiant d'appareil, la table
user_device jamais lue) et la règle des bibliothèques (pg seulement, nommée dans SPEC §11.1).
Chaque tranche : la spec d'abord si une décision change, test rouge vu échouer, code, vert,
lint, relecture du diff par un sous-agent contre SPEC.md, commit en français sans trailer
Co-Authored-By, push sur origin main. À la fin : revue de clôture, ce fichier en « fait »
avec ce qui a été mesuré (coût d'une écriture du journal dans la boucle du match, temps de
réponse du panneau) et les pièges, CLAUDE.md (la carte du dépôt gagne admin/), README.
Ou stop après 40 tours.
```

## Ce qui est déjà tranché et ne se rediscute pas dans ce run

- **Lecture seule.** Le panneau de telegraph bannit, supprime et réécrit la configuration ; celui-ci
  ne modifie rien. C'est aussi pourquoi il tourne en conteneur (D-13) : telegraph fait tourner le
  sien sur l'hôte parce qu'il doit réécrire des fichiers et redémarrer Nakama, ce que celui-ci ne
  fait pas.
- **Le contrôle d'accès est l'adresse d'écoute.** Le port est publié sur `127.0.0.1:1341` seulement
  (dans le conteneur, le serveur écoute sur toutes ses interfaces, sans quoi la publication ne
  l'atteint pas) ; pas d'authentification. Le tunnel n'y mène pas : son `config.yml` ne route que
  `blobattle.npc.fm` vers nginx et Nakama.
- **Le journal est écrit par le match** (§6.9), à chaque changement de phase et à la fin d'une
  partie, jamais à chaque tick ; une écriture qui échoue est un `warn` et n'arrête pas le match.
- **Le panneau ne lit que la base et l'API console.** Pour savoir quels salons vivent encore : l'API
  console de Nakama (`/v2/console/authenticate`, puis la liste des matchs), comme le fait
  `telegraph/admin/api/src/nakama.ts` (jeton en cache, un nouvel essai sur un 401). Un salon en
  `playing` dont le match n'existe plus est une partie **interrompue**.
- **Les données** : `users` (pseudo = `display_name`, date de création), `storage` (collections
  `room`, `game`, `team`). Jamais `user_device`, `user_edge`, les sessions ni les adresses.
- **La page** : du HTML et du JavaScript sans framework ni étape de build, servie par l'API ; aucun
  texte du jeu n'y est concerné (D-11 porte sur le jeu, le panneau est un outil de l'opérateur, en
  français comme les docs).

## Pièges déjà connus, à ne pas redécouvrir

- **Le compte système** (`00000000-0000-0000-0000-000000000000`) est une vraie ligne de `users` : à
  exclure des décomptes (telegraph, `db.ts`). Dans le runtime Lua de Nakama, un objet de stockage
  écrit sans `user_id` appartient au compte système : le vérifier par une lecture en base, pas en le
  supposant.
- **`users.disable_time`** vaut l'époque zéro pour un compte actif, pas `NULL` (telegraph).
- **Nakama exécute chaque `.lua` de ses modules au démarrage**, et `or nil` est interdit dans
  `server/` (gopher-lua) ; une écriture de stockage dans `match_init` ou `match_loop` est permise,
  mais elle coûte un aller-retour à Postgres : la mesurer.
- **`make journey` et `make harness` redémarrent Nakama** : les salons vivants deviennent
  interrompus, ce que le panneau doit montrer comme tel.
- **Le panneau lit des données écrites par des joueurs** (pseudos, noms d'équipes) : les échapper
  dans la page (`textContent`, jamais `innerHTML` sur une valeur de la base).
