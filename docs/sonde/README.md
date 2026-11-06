# Sonde Defold + Nakama Lua

Expérience jetable menée avant la spec, pour vérifier que la stack de l'ADR-001 tient. Le code de
`ref/` **n'est pas du code produit** : il sert de référence aux runs C et D (texture dynamique, client
Nakama, parcours CDP). Les mesures brutes sont dans `mesures/`.

## Versions

| Brique | Version |
|---|---|
| Defold / `bob.jar` | 1.13.1 (sha1 `574678c7`) |
| Nakama | image `registry.heroiclabs.com/heroiclabs/nakama:3.41.0` |
| nakama-defold | v3.4.0 (`dependencies#0` de `ref/client/game.project`) |
| extension-websocket | 4.2.4 |
| JDK sur l'hôte | OpenJDK 25 (bob n'exige pas le 21) |
| Chromium | 153, WebGL2 par SwiftShader |

## 1. Terrain sur texture dynamique — ✅

- **La mise à jour d'une sous-région existe** : `resource.set_texture` accepte `x` et `y`. Le buffer
  passé doit faire exactement la taille de la sous-région ; on y copie les lignes du cratère avec
  `buffer.copy_stream`.
- Build HTML5 à 844×390, 50 cratères de rayon 40, moyenne / p95 en ms :

| Carte, CPU | creusage pixel par pixel | creusage par lignes (`copy_stream`) | envoi sous-région | envoi complet |
|---|---|---|---|---|
| 2048×1024, ×1 | 0,93 / 1,0 | 0,10 / 0,2 | 0,21 / 0,3 | 1,1 / 1,7 |
| 2048×1024, ×4 | 3,5 / 4,5 | 0,54 / 1,0 | 0,82 / 1,2 | 4,5 / 7,9 |
| 3072×1536, ×4 | 3,3 / 4,4 | 0,34 / 0,8 | 0,70 / 1,1 | 12,5 / 19,3 |

- Avec l'envoi par sous-région, l'image ne descend jamais sous 60 i/s ; l'envoi complet fait tomber
  à 25–37 ms par image à ×4.
- Générer la carte au démarrage : 0,28 s (2048) et 0,59 s (3072) à ×4.
- Test « cette cellule est-elle pleine ? », en ns : HTML5 ×1 — tableau Lua plat 65, flux de buffer
  201, grille empaquetée 32 bits 343. Nakama — tableau 228, chaîne par ligne 262, grille empaquetée
  3 122. **Le tableau Lua plat est le plus rapide partout** (D-09).

**Pour Blobattle** : la plus grande carte fait 1024×256, bien sous toutes les limites de texture ; pas
de découpage en tuiles. Toujours envoyer la sous-région.

**Pièges** :
- Defold remplace par une texture vide une texture plus grande que la limite de l'appareil : lire
  `graphics.get_adapter_info().limits.max_texture_size_2d` au démarrage.
- `clear_color_alpha` doit valoir 1, sinon le canvas HTML5 montre des mouchetures.
- Le matériau du terrain doit porter le tag `tile` : le script de rendu par défaut dessine `model`
  sans mélange alpha.
- La variante native *headless* limite les textures à 1024 : ne pas y mesurer l'envoi de texture.

## 2. nakama-defold de bout en bout — ✅

- En HTML5 et en natif Linux, sans modifier la bibliothèque : authentification par appareil, RPC,
  socket, `match_create` par RPC, rejoindre, écho, horloge du match.
- Page sur :8093 et Nakama sur :7650 : aucun réglage CORS nécessaire.
- Authentification 146–700 ms (le premier appel crée le compte). Aller-retour d'écho 83–100 ms en
  local, surtout l'attente du tick serveur (10 Hz dans la sonde).
- Moteur HTML5 : 2,4 Mo (0,99 Mo compressé).

**Pièges** : Nakama coupe un RPC HTTP au-delà d'environ 10 s. La branche principale de
nakama-defold contient des correctifs non publiés ; v3.4.0 suffit pour ces appels.

## 3. Un même module Lua des deux côtés — ⚠️ fonctionne, avec les règles de D-02

- **Organisation qui marche** : `shared/` à la racine du dépôt ; Nakama le monte comme
  `modules/shared` (lecture seule) ; le projet Defold `client/` y accède par le lien symbolique
  `client/shared → ../shared`, que `bob.jar` suit. `require "shared.sim.probe"` fonctionne des deux
  côtés.
- **Sommes identiques** sous Nakama, Defold HTML5 (Lua 5.1.4), Defold natif (LuaJIT), Lua 5.1 et
  LuaJIT : projectile en virgule fixe `1612344986` ; grille 2048 après 50 cratères `164214745`.
- **`sin`, `cos`, `exp`, `atan2` divergent** : la somme HTML5 finit par …193161, les autres par
  …193152. D'où la table trigonométrique en entiers.
- **Les opérations binaires divergent** : Defold a `bit`, à résultats signés
  (`lshift(0xFFFFFFFF, 4) = -16`) ; Nakama n'a que `bit32`, non signé (`4294967280`). D'où
  l'interdiction de `bit` et le générateur de Park–Miller, exact en double.
- Vitesse pour 1 million de pas de projectile : LuaJIT ~25 ms, HTML5 ~275 ms, **Nakama 1,5–3,1 s**.

**Pièges** :
- **Nakama exécute chaque fichier `.lua` de son dossier de modules au démarrage** : un module de
  `shared/` ne doit avoir aucun effet de bord au chargement.
- Avec la taille de registre Lua par défaut de Nakama, un `table.concat` de 256 éléments échoue (64
  passe). Relever la taille du registre dans la configuration de Nakama.

## 4. Build sans éditeur — ✅

- `bob.jar` tourne sous Java 25 (avertissements JVM seulement).
- Build HTML5 : 24,6 s à froid, dont 21,4 s pour compiler l'extension WebSocket sur
  `build.defold.com` ; 3,0–3,4 s à chaud. Build Linux *headless* : 14 s.
- `resolve` télécharge les zips `dependencies#N` dans `client/.internal/lib` **à chaque exécution**.

## Fichiers de référence

| Fichier | Ce qu'il montre |
|---|---|
| `ref/client/terrain.script` | texture dynamique, creusage par lignes, envoi de sous-région, mesures |
| `ref/client/terrain.material`, `.vp`, `.fp` | matériau du terrain avec le tag `tile` |
| `ref/client/net.script` | nakama-defold : authentification, RPC, socket, match |
| `ref/client/game.project` | dépendances épinglées, réglages HTML5 |
| `ref/server/docker-compose.yml` | Nakama 3.41.0 avec `shared/` monté en `modules/shared` |
| `ref/server/spike_match.lua` | squelette de match autoritaire en Lua |
| `ref/shared/probe.lua` | la sonde de déterminisme (entiers, flottants, trigonométrie, bits) |
| `ref/tools/cdp.mjs` | pilotage de Chromium par CDP depuis Node, sans dépendance |
