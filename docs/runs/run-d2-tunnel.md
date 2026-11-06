# Run D2 — le tunnel

Tranche 28 du plan TDD de `SPEC.md` §10.6 : le build web et Nakama servis par nginx derrière un
tunnel Cloudflare, et le build installable en PWA. Après le run D (en ligne sur le réseau local,
fait) et avant le run E (Android, finitions, clôture).

**Déjà fait, à la demande de l'utilisateur** (« je veux le domaine blobattle.npc.fm
qui arrive sur le jeu en tunnel cloudflared ») : le tunnel nommé `blobattle` (créé avec le
`cert.pem` de la zone npc.fm, repris de telegraph), le CNAME `blobattle.npc.fm`, les services
Compose `blobattle-web` (nginx) et `blobattle-cloudflared` du profil `tunnel` (`make tunnel`,
`make tunnel-down`), un seul hôte partagé par chemin (`/v2/`, `/ws`, `/healthcheck` vers Nakama,
le reste vers nginx), le client qui trouve Nakama à l'origine de la page en `https:` (SPEC §7.1),
et le parcours en ligne joué par l'adresse publique, en WSS
(`JOURNEY_ORIGIN=https://blobattle.npc.fm`, et `JOURNEY_RESOLVE="blobattle.npc.fm <ip>"` tant que
le DNS de la machine garde en cache l'absence du nom). **Restent** la PWA, la limite de
`room_create` et le nom technique.

**Avant de lancer** : `/clear`. L'état des runs A à D, leurs mesures et leurs pièges sont écrits dans
`docs/runs/` (bilans), en particulier `docs/runs/run-d-en-ligne.md` : la connexion au salon, la couture
en ligne, le parcours à plusieurs contextes, et les mesures sur le réseau local.

**Préalables, à régler par l'utilisateur avant de lancer** (V0.md §3) :

1. **Q-02, le domaine et le tunnel** : **tranché et fait** (ci-dessus) : un tunnel
   nommé `blobattle`, un seul hôte `blobattle.npc.fm`, ses identifiants et son `config.yml` dans
   `./cloudflared/` (ignoré par git ; modèle `tools/tunnel/config.example.yml`). Le `cert.pem` du
   compte (celui de la zone npc.fm, dans `telegraph/cloudflared/`) n'est pas dans le conteneur
   exposé : il ne sert qu'à créer un tunnel ou une route DNS.
2. **La limite de `room_create`, et des comptes** : le tunnel est ouvert, et n'importe qui avec la
   clé serveur (elle est dans le client) peut créer des salons en boucle, et des comptes par
   `AuthenticateDevice`. Un salon sans humain se ferme en 60 s, mais rien ne borne le rythme. À
   trancher : une limite par compte et par minute, ou un plafond de salons ouverts (SPEC §6.2
   d'abord).
3. **Le nom technique** : le jeu s'affiche sous le nom de **Blobattle** ; le code, Compose, l'image
   d'outils, le dossier de sauvegarde et le domaine gardent le nom de travail. Renommer, ou le
   garder comme nom technique.

**Ce qui reste ouvert et ne se règle pas dans ce run** : Q-03 (la durée des parties).

---

## Le prompt

```
Lis SPEC.md, CLAUDE.md et V0.md à la racine, puis docs/conventions.md,
docs/runs/run-d-en-ligne.md (le client en ligne, la connexion au salon, le parcours à
plusieurs contextes, les mesures et les pièges) et docs/runs/run-d2-tunnel.md (ce fichier).

Les runs A à D sont faits : shared/, server/ et client/ jouent une partie en ligne par code
sur le réseau local, absences, reconnexion et revanche comprises. Tout tourne en conteneur :
  make test, make lint, make conformance, make up, make harness, make web,
  make journey (J=online pour la seule partie en ligne), make serve.

/goal La tranche 28 de SPEC.md §10.6 est finie : le tunnel blobattle.npc.fm étant déjà en
place (profil Compose `tunnel`, nginx, cloudflared), le build servi par l'adresse publique
est une PWA installable (manifeste, icônes) ; depuis l'adresse publique, deux contextes
navigateur se retrouvent dans le même Salon et jouent en ligne sans divergence. La console Nakama et Postgres restent sur
127.0.0.1 (D-15), la limite de room_create tranchée par l'utilisateur est en place et testée.
make test, make lint, make conformance, make harness et make journey restent verts.
Chaque tranche : la spec d'abord si une décision change, test rouge vu échouer, code, vert,
lint, relecture du diff par un sous-agent contre SPEC.md, commit en français sans trailer
Co-Authored-By, push sur origin main. À la fin : ce fichier en « fait » avec les mesures
(aller-retour d'une entrée par le tunnel depuis le téléphone de l'utilisateur sur le réseau
mobile : c'est Q-01), report de H-08 et Q-01 dans SPEC, et écriture de docs/runs/run-e-android.md.
Ou stop après 60 tours.
```

## Ce que le run D laisse en place et qui sert ici

- **L'adresse de Nakama** (SPEC §7.1, `client/net/endpoint.lua`) : sur une page en `http:`, l'hôte
  de la page et le port `nakama.port` (7550) ; en `https:`, l'origine même de la page, en TLS (le
  tunnel partage l'hôte par chemin). Une page ouverte en `http://blobattle.npc.fm` est redirigée
  vers `https://` par nginx (`X-Forwarded-Proto`), avec HSTS.
- **La clé serveur** est dans le build (`make web` la lit dans `.env` et la passe à `bob.jar` par
  `--settings` : un chemin **absolu**, sinon `bob.jar` le lit depuis `client/` et tombe sur une
  `NullPointerException` à la lecture des tâches). Elle n'est pas un secret : c'est ce qui rend
  pressante la limite de `room_create`.
- **CORS** : Nakama répond `Access-Control-Allow-Origin: *`, erreurs comprises (vérifié au run D) ;
  une page servie par un autre domaine que Nakama n'a rien à régler de ce côté.
- **Le parcours en ligne** (`tools/journey/online.mjs`) joint Nakama par un relais
  `127.0.0.1:7550 → blobattle-nakama:7350` dans l'image d'outils (`tools/journey/forward.mjs`) ; par
  le tunnel : `JOURNEY_ORIGIN=https://blobattle.npc.fm` (et `JOURNEY_RESOLVE` si le DNS de la
  machine garde en cache l'absence du nom), vert.
- **La reconnexion** : la connexion au salon se rétablit seule toutes les 2 s (`link.RETRY_SECONDS`)
  et rentre dans le même match ; `session.single_socket` de Nakama coupe l'ancienne socket d'un
  compte qui en ouvre une autre ; après trois pertes de suite, chacune moins de 5 s après son
  entrée, la connexion abandonne (`reason.elsewhere` : un autre onglet joue ce profil).

## Pièges déjà rencontrés, à ne pas redécouvrir

- **Deux onglets du même navigateur sont le même compte** (même identifiant d'appareil) : avec
  `single_socket`, chacun coupe la socket de l'autre ; la connexion abandonne au bout de trois
  pertes rapides. Le parcours ferme un onglet avant d'en rouvrir un dans le même contexte.
- **`make journey` et `make harness` redémarrent Nakama** (sauf `J=offline`) : une partie en cours
  tombe, sur le réseau local comme par le tunnel.
- **Le cache négatif du DNS** : un nom demandé avant sa création reste « inexistant » jusqu'à
  30 min chez la box (le minimum du SOA de npc.fm) ; les résolveurs publics le voient aussitôt.
- **Un corps d'erreur de Nakama porte `"error": {}`** (un objet vide) et la raison dans
  `message` ; les réponses de socket la portent dans `error.message`.
- **Le label d'un salon n'est trouvable qu'environ 1 s après sa création** : `room_find` réessaie
  (5 fois, toutes les 0,5 s).

## Ce qui reste ouvert d'avant

- **Les bots qui jouent tout** (tranches 24j à 24m du run C4) ne sont pas faites ; SPEC §9 dit
  toujours que les bots ne tirent qu'au bazooka et à la grenade.
- **Le téléphone de l'utilisateur** : voir H-09 et H-11 dans SPEC §3, et le bilan du run D.

