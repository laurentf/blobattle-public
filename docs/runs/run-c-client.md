# Run C — client hors ligne · **fait**

Conservé pour mémoire : ce run est terminé (tranches 19 à 24, la
poussée du bazooka demandée par l'utilisateur, puis la revue de clôture). Le prompt et les
avertissements qui suivent ont servi à le conduire ; le bilan est en fin de fichier.

Tranches 19 à 24 du plan TDD de `SPEC.md` §10.6.

**Avant de lancer** : `/clear`. Ce qui n'est pas sur le disque n'existe plus après : l'état des runs A
et B, leurs mesures et leurs pièges sont écrits dans `docs/runs/run-a-socle-simulation.md` et
`docs/runs/run-b-serveur.md` (bilans) ; le style de rendu, tranché après un prototype,
est décrit avec ses mesures et son code de référence dans `docs/sonde-voxel/`.

**Préalables** : Docker, Internet (`bob.jar` compile l'extension WebSocket sur `build.defold.com`),
le port 5373 libre (build web). Le téléphone de l'utilisateur servira à la fin pour H-11 et H-09 :
le run sert le build sur le réseau local et lui laisse l'adresse, il ne l'attend pas.

**Ce qui reste ouvert et ne se règle pas dans ce run** : Q-03 (la durée des parties, 79,5 % à la
limite des rondes) : ne toucher ni aux dégâts, ni aux PV, ni aux rondes.

---

## Le prompt

```
Lis SPEC.md, CLAUDE.md et V0.md à la racine, puis docs/conventions.md,
docs/sonde/README.md (build sans éditeur, CDP), docs/sonde-voxel/README.md (le rendu
voxel : mesures, pièges, code de référence dans docs/sonde-voxel/ref/),
docs/runs/run-b-serveur.md (le bilan du run B : protocole, mesures, pièges) et
docs/runs/run-c-client.md (ce fichier : ce qui est tranché et les pièges).

Les runs A et B sont faits : shared/ (sim, bots, protocole) est complet et déterministe
sous LuaJIT, Lua 5.1 et Nakama ; server/ joue une partie complète, absences et
snapshots compris. Tout tourne en conteneur :
  make test         (busted sous LuaJIT puis Lua 5.1)
  make lint         (luacheck + stylua --check)
  make conformance  (vecteurs rejoués dans Nakama, mesures)
  make up           (Postgres + Nakama de développement)
  make harness      (clients Node contre le vrai Nakama, rejeu Lua des sommes)

/goal Les tranches 19 à 24 de SPEC.md §10.6 sont faites : sur 200 graines × 7 réglages
aucun chat n'apparaît avec de la terre au-dessus de lui et une même graine donne les
mêmes noms d'équipes et de membres sous LuaJIT, Lua 5.1 et Nakama ; le projet Defold
client/ se construit en HTML5 dans l'image d'outils et s'ouvre dans Chromium sur
l'Accueil ; après un cratère, le maillage voxel des morceaux touchés a exactement une
face par frontière terre-air de la sim ; un glisser depuis le blob produit un `fire`
d'angle et de puissance entiers attendus ; en portrait, la partie affiche l'écran de
rotation et continue ; et `make journey` joue une partie d'entraînement jusqu'à
l'écran Fin à 844×390, en affichant l'équipe qui joue, le temps, le vent, le nom et
les PV de chaque blob et la ligne de visée. `make test`, `make lint`, `make
conformance` et `make harness` restent verts. Respecte CLAUDE.md, en particulier
D-04 (visée locale, entiers avant l'envoi), D-09 (rendu voxel, rien d'affiché ne
retourne dans la sim), D-10 (paysage, cibles de 44 points), D-11 (aucun texte en
dur, catalogue anglais seul) et la couture unique de l'autorité (§7.1). Chaque
tranche : test rouge vu échouer, code, vert, lint, relecture du diff par un
sous-agent contre SPEC.md, commit en français sans trailer Co-Authored-By. À la fin :
revue de clôture de V0.md §4, mise à jour de ce fichier en « fait » avec les mesures
(build HTML5 à froid et à chaud et sa taille, tick de sim et tranche de
reconstruction du terrain en HTML5 à CPU ×4, budget des bots hors ligne retenu) et les
pièges, report des hypothèses H-01, H-05, H-09 et H-11 dans SPEC §3 (le téléphone de
l'utilisateur : laisser l'adresse du build sur le réseau local), et écriture de
docs/runs/run-d-en-ligne.md. Ou stop après 60 tours.
```

## Ce qui est déjà tranché et ne se rediscute pas dans ce run

- **Le rendu est en 3D voxel** (SPEC §7.4, D-09, Q-04 tranchée) : un voxel par cellule de la sim,
  terrain extrudé en profondeur, blobs gélatineux en voxels, explosions en cubes. Le code de
  `docs/sonde-voxel/ref/` montre une façon qui marche et ses mesures ; il se réécrit proprement dans
  `client/` (règles de CLAUDE.md), il ne se copie pas tel quel.
- **Ce qui se teste avec busted** : la géométrie pure (quelles faces pour quelles cellules, quelles
  rangées et colonnes recalculer après un cratère, le ressort des blobs) vit dans des modules Lua
  sans API Defold, testés sous LuaJIT et Lua 5.1 ; une couche mince écrit les buffers Defold. Le
  reste du client se vérifie par le parcours (`make journey`).
- **Anglais seul** (D-11) : un catalogue `en`, tout texte par identifiant ; le catalogue `fr` existant
  n'est plus exigé. Les noms ne se traduisent pas.
- **Les noms** (SPEC §6.1) : `shared/names.lua`, un dictionnaire anglais et des mots-valises de
  16 caractères au plus, tirés sur le quatrième flux de hasard `names` (39373, `g + 3000009`, §5.1).
  Hors ligne, `LocalAuthority` nomme les équipes de bots avec la graine de la partie ; le joueur
  choisit le nom de son équipe au premier lancement, ses six membres sont tirés une fois puis gardés
  localement. Le RPC `team_set` et le stockage côté serveur sont au run D (tranche 25).
- **L'apparition à ciel ouvert** (SPEC §5.3) change les cartes, donc les sommes des vecteurs de
  conformité : les ré-enregistrer (`make vectors`) dans le commit de la tranche 19, qui dit pourquoi,
  puis `make conformance` sous les trois moteurs, et relancer le banc (`make bench N=200`) pour en
  reporter les chiffres (Q-03).
- **L'interface « limpide »** (SPEC §7.4, V0 §2) : équipe qui joue en haut à gauche (nom, couleur,
  lettre, PV des équipes), temps et vent en haut au centre, nom et PV au-dessus de chaque blob, blob
  actif signalé, ligne de lance-pierre dont la longueur et la couleur disent la puissance, arme,
  munitions et minuterie en bas.
- **Versions** : Defold et `bob.jar` 1.13.1 ; nakama-defold v3.4.0 et extension-websocket 4.2.4
  épinglés par release dans `game.project` (le client n'en a besoin qu'au run D, mais le projet les
  déclare dès maintenant) ; un JDK et `bob.jar` entrent dans l'image d'outils, épinglés par somme
  (D-13), Chromium aussi pour le parcours.
- **Organisation** : `client/` est le projet Defold ; il voit `shared/` par le lien symbolique
  committé `client/shared → ../shared`, que `bob.jar` suit (D-01, H-03). Rien dans `client/` n'est
  requis par `server/` ni l'inverse.
- **L'autorité** (§7.1) : `LocalAuthority` fait tourner la sim et les bots dans le client, avec le
  pilote de `shared/bots/driver.lua` au budget hors ligne, et produit le même flux que le serveur
  (`ticks {to, inputs:[{at, input}]}`, `checksum`, `game_end`), pour que le reste du client ignore
  laquelle est branchée. `NakamaAuthority` vient au run D.
- **Le parcours** : Chromium sans interface piloté par CDP depuis un script Node sans dépendance
  (`docs/sonde-voxel/ref/tools/cdp.mjs`), en paysage 844×390 avec le toucher émulé ; l'état exposé en
  mode test (§11) sert aux assertions. Pas de Playwright.

## Ce que le run B laisse en place et qui sert ici

- **Le protocole** (`shared/protocol.lua`, SPEC §6.4) : codes, formes et décodeurs de chaque
  message, raisons de refus. Le client construit ses messages avec les mêmes règles (angle, puissance
  et minuterie entiers et bornés avant l'envoi, D-04).
- **Le flux de partie** : une entrée `{at, input}` s'applique au pas qui mène de `at` à `at + 1`,
  dans l'ordre du message ; un `ticks` couvre les ticks après le `to` du précédent jusqu'à `to`
  compris ; après un snapshot au tick `T`, seules les entrées d'un `at` ≥ `T` s'appliquent (§6.6).
  `tools/harness/replay.lua` fait exactement ce que le client doit faire : c'est la référence.
- **`game_end {winner, stats}`** : `winner` vaut 0 pour un match nul ; `shared/sim/stats.lua` calcule
  les statistiques de l'écran Fin hors ligne comme le serveur en ligne.
- **Les événements de la sim** (`landed`, `damaged`, `fired`, `exploded`, `died`, `turn_started`…)
  pilotent le ressort des blobs, les explosions et la reconstruction du terrain ; ils se lisent, rien
  n'y retourne.

## Pièges déjà rencontrés, à ne pas redécouvrir

- **Le buffer placeholder d'un composant `mesh` fixe son format de sommets** : tout buffer mis à
  l'exécution doit avoir exactement les mêmes flux, sinon des triangles géants apparaissent.
- **Écrire un buffer élément par élément coûte cher en HTML5** : buffers par rangée et par colonne
  assemblés par `buffer.copy_stream`, pas de couleur par sommet.
- **Defold normalise les normales en espace monde** : jamais de normale nulle.
- **`[mesh] max_count`** vaut 128 par défaut : le relever (morceaux, blobs, projectiles, débris).
- **Le budget des bots hors ligne (1 000 unités par tick) coûte 11 ms au p95 en HTML5 à CPU ×4** :
  le régler sur la mesure dans le build HTML5, la spec d'abord (§9).
- **Chromium sans interface rend avec SwiftShader** : ses images par seconde ne disent rien d'un
  téléphone ; mesurer le CPU là, le GPU sur le téléphone (H-11).
- **Une liste vide venue de Nakama peut être `{}`** (SPEC §6.4) ; **un label de match n'est trouvable
  qu'environ 1 s après sa création** ; **gopher-lua interdit `or nil`** dans tout ce qui tourne sur le
  serveur, `shared/` compris (test d'architecture).
- **Trier des mesures à chaque image fausse les images par seconde** : statistiques une fois par
  seconde.
- **La somme de contrôle ne dit rien des événements** : une divergence visuelle sans divergence de
  somme vient du rendu, pas de la sim.
- **HTML5 est le moteur le plus lent** (Lua 5.1 en WebAssembly, ~10 fois LuaJIT) : mesurer le tick de
  sim, la tranche de reconstruction et le budget des bots hors ligne dans le build HTML5, pas sous
  LuaJIT.

---

## Bilan

Run conduit dans une seule session, avec une relecture par un sous-agent à chaque tranche, sur un
export de l'index git (`git checkout-index`). Les tranches 21 à 23 ont avancé ensemble dans l'arbre de
travail ; chacune a été indexée seule (les fichiers partagés par une version dérivée, écrite dans
l'index par `git hash-object`), vérifiée seule sur son export (suite, lint, build, parcours), relue,
corrigée, puis committée. Quand une relecture revenait alors que la suite avançait, la suite était
mise de côté (`git diff` et archive des fichiers nouveaux), puis réappliquée par `git apply -3`.

### Ce qui a été mesuré

| Mesure | Valeur |
|---|---|
| Build HTML5 dans l'image d'outils (H-01) | 25,0 à 35,1 s à froid, dont 21 à 31 s de compilation de l'extension WebSocket sur `build.defold.com` (selon sa charge) ; 2,8 à 3,9 s à chaud ; 2,89 Mo non compressés (`out/web/Blobattle`) |
| Tick de sim du client en HTML5, CPU ×4, 8 équipes de 6 | 0,9 ms en moyenne, 1,4 à 1,8 ms au p95, 4 à 7 ms au pire (le monde du client seul, `sim_ms`) |
| Autorité locale (sa sim et les bots) par image, même partie | 0,7 ms en moyenne et 1,4 ms au p95 hors recherche ; 6 à 11 ms au p95 et 16 ms au pire pendant la recherche d'un bot difficile |
| Budget des bots hors ligne retenu | **300 unités de travail par tick**, comme le serveur : à 1 000, le tick de la plus grande partie (8 équipes de 6, bots difficiles) montait à 17 à 22 ms au p95 à CPU ×4 (11 ms mesurés avant le run, sur une partie plus petite) ; à 300, 6 à 11 ms au p95 pendant la recherche. Un même budget des deux côtés : une graine donne les mêmes tirs hors ligne et en ligne (une spec vérifie l'égalité) |
| Tranche de reconstruction du terrain, CPU ×4 | 2,8 ms en moyenne, 3,3 à 3,6 ms au p95, 3,9 ms au pire sur 4 équipes de 4 ; une tranche à 5,0 ms sur 76 sur 8 équipes de 6 (un pic isolé) |
| Reconstruction complète d'un cratère, CPU ×4 | 0,12 à 0,27 s, sous le flash de 0,3 s ; 0,43 s une fois pour deux cratères rapprochés |
| Terrain | 22 800 sommets (4 équipes de 4) à 40 000 (8 équipes de 6) |
| Images par seconde | sans objet ici : Chromium sans interface rend avec SwiftShader (logiciel), ~25 ms par image à CPU ×4 ; le GPU d'un téléphone au run E (H-11) |
| Banc, 200 parties | 0 erreur ; 56,0 % à la limite des rondes (79,5 % au run B) avec l'apparition à ciel ouvert ; 13,6 / 15,5 / 19,0 dégâts par tir ; 47,5 % avec la poussée du bazooka à 1920 |
| Parcours (`make journey`) | 51 contrôles, ~14 min : Accueil (paysage, portrait, bureau), premier lancement, Solo, rendu, CPU ×4, lance-pierre, pouces, clavier, interface comparée à la sim, portrait, une partie entière jusqu'à l'écran Fin sans divergence ni tick dépassé, puis une deuxième partie à trois équipes, et l'Accueil, Solo et une partie à 667×375 et 1280×720 |

- **Suite** : 400 tests, verts sous LuaJIT et Lua 5.1 (307 au run B) ; `luacheck` et `stylua --check`
  propres, scripts Defold (`.script`, `.gui_script`) compris. `make conformance` : mêmes sommes et
  mêmes noms sous les trois moteurs. `make harness` : 54 contrôles verts contre le vrai Nakama.

### Ce que les relectures ont trouvé

Chaque tranche a eu sa relecture ; toutes ont trouvé quelque chose de réel, corrigé avant son commit
(le détail est dans chaque message). Les plus lourds :

1. **Une deuxième partie dans la même session plantait** (tranche 23) : les maillages des blobs
   étaient gardés dans un module qui survit au déchargement de la partie, alors que le moteur les
   libérait avec elle ; ils sont créés et libérés par partie, comme le terrain.
2. **La reconstruction du terrain dépassait 4 ms par image** à CPU ×4 (tranche 21), invisible à
   CPU ×1 : le parcours contrôle maintenant une page à CPU ×4.
3. **Un simple appui à côté du blob tirait**, un deuxième doigt changeait le tir, la vue bougeait
   pendant une visée (tranche 22).
4. **Des opérations de salon acceptées comme entrées de jeu** par la LocalAuthority, et **un build
   release qui avalait les erreurs Lua** (tranche 20) : elles sont publiées en mode test et le
   parcours les vérifie.
5. **Un nom tapé sans Entrée n'était pas pris** par l'appui sur Solo (tranche 23).
6. **Des boutons de menu à 41 points sur un téléphone de 667×375** (tranche 23) : la spec des
   cibles compte maintenant à cette taille.
7. **Des mutants survivants à chaque tranche** (maillage, playback, LocalAuthority, interface) :
   tous tués par de nouveaux tests ; le parcours compare chaque texte affiché à la valeur de la sim,
   et une spec refuse tout texte écrit dans le code qui arriverait à l'écran (D-11).
8. **Des allocations à chaque image** (vecteurs, débris, rotations, textes de l'interface formatés à
   chaque image) : retirées.

### La revue de clôture (V0.md §4)

Un sous-agent a relu le diff complet du run contre SPEC.md, CLAUDE.md et V0.md :
aucun défaut bloquant ; les exigences du §2 de V0, D-04, D-09, D-10, D-11 et la couture (§7.1) sont
tenues, et la spec a été réécrite avec chaque demande de l'utilisateur. Corrigé dans le commit de
clôture :

- **Deux pavés cachés sans que la spec le dise** : sans écran tactile, ◀ ▶ et Saut ne s'affichent
  pas (le clavier les remplace) ; D-10 et §7.3 le disent maintenant.
- **V0 §2 demande aussi 667×375 et 1280×720** : le parcours ouvre l'Accueil, Solo et une partie à
  ces deux tailles et vérifie que chaque cible fait 44 points au moins, tient dans l'écran et ne
  chevauche aucune autre (le mode test publie la taille des cibles).
- **Deux textes de la spec en retard sur la poussée** : l'exemple du §8.1 (`push = 1280`) et H-04 (le
  duel finit maintenant au tick 851, 22 sommes en tout).
- **Des tables allouées à chaque tick ou à chaque image** : la liste des entrées en attente et celle
  que rend `poll()` dans la LocalAuthority, et le tir affiché pendant la visée ; elles sont
  réutilisées (une liste rendue par `poll()` ne vaut que jusqu'au `poll()` suivant).
- **Trois fonctions publiques à plus de trois paramètres positionnels** (`camera_rig.pan`,
  `voxel_mesh.crater`, `terrain_view.crater`) : champs nommés.

### Ce qui reste ouvert

- **Le téléphone de l'utilisateur** (H-09, H-11) : le build est servi sur le réseau local
  (`make serve`, `http://192.168.0.21:5373/`, `?test=1` pour lire les mesures dans
  `window.blobattle`) ; au plus tard au run E.
- **Les 4 ms par image de la reconstruction du terrain** sont tenues au p95 à CPU ×4, pas au pire :
  l'envoi d'un morceau au GPU ne se coupe pas, et une tranche a été mesurée une fois à 5,0 ms sur la
  plus grande partie. À mesurer sur le téléphone (run E), et à couper l'assemblage d'un morceau si
  le dépassement s'y confirme.
- **La saisie du pseudo sur l'APK** : `client/ui/text_fields.lua` pose des `<input>` du navigateur,
  qui n'existent qu'en HTML5 ; un premier lancement sur Android ne pourrait pas taper son nom. Au
  run E.
- **Q-03** (la durée des parties, 47,5 % à la limite des rondes) et **Q-05** (le grappin), à
  l'utilisateur.

### Les retours de l'utilisateur

Le build était servi sur le réseau local pendant le run (`make serve`) ; l'utilisateur l'a joué sur
son PC et a demandé, avant la fin du run :

- **au PC, les flèches et une visée au clavier** : ← → marcher, ↑ ↓ l'angle, Espace maintenu charge
  et relâché tire, Entrée sauter (§7.3 réécrit, tranche 22) ;
- **une caméra qui ne coupe pas l'action** : elle suit le projectile, puis l'explosion et les blobs
  projetés jusqu'à la fin du tour, et une seconde un blob qui meurt ; des flaques grises qui ne
  restent plus en l'air quand le sol disparaît dessous ; une grenade qui ne tourne plus au repos ;
- **un Accueil propre** : de vrais champs de saisie du navigateur au lieu de `prompt()`, une taille
  normale sur un grand écran, « Solo » ; le nom d'équipe (et le pseudo) modifiables depuis l'Accueil
  (§2, §6.1, §7.2 réécrits, tranche 23) ;
- **un bazooka qui pousse plus** : 1280 → 1920 FP/tick (§8.2), vecteurs ré-enregistrés ;
- **le grappin**, qui ne termine pas le tour : écrit en Q-05, à placer (une tranche du run E, ou après
  la V0) ;
- **le multijoueur par code** : c'est le run D (`docs/runs/run-d-en-ligne.md`).

### Pièges rencontrés

- **`bob.jar` 1.13.1 est compilé pour Java 25** (classe 69) : le JRE 21 le refuse. AWT a besoin de
  freetype et fontconfig pour lire une police ; sans eux, « Problem reading font data ».
- **Une scène `.gui` doit nommer ses deux dispositions** (Landscape et Portrait) : avec la seule
  disposition Portrait, Defold la prenait pour une fenêtre en paysage. **Au changement de
  disposition, les textes posés par le script sont perdus** : les réappliquer sur `layout_changed`.
- **Defold HTML5 ne fabrique pas d'événement souris depuis le toucher** : écouter `TOUCH_MULTI`
  (`client/ui/pointer.lua` ignore la souris dès qu'un doigt a été vu).
- **Un build release avale les erreurs Lua** : en mode test, `sys.set_error_handler` les publie dans
  `window.blobattle.errors`, que le parcours vérifie. **`json.encode` rend `{}` pour une liste vide.**
- **Le fils d'un nœud GUI hérite de son opacité** : un modèle d'étiquette à `alpha = 0` cachait ses
  textes. **Un nœud `pie` descend au mieux à 4 sommets** : un demi-losange (4 sommets, 180°) fait le
  triangle. **`until` est un mot réservé de Lua.**
- **`socket.gettime` n'a que la milliseconde en HTML5** ; `os.clock` donne 0,1 à 0,3 ms.
- **La reconstruction du terrain** : le dernier morceau commencé dépasse le budget, et l'envoi au GPU
  compte aussi ; une estimation du coût des morceaux gonflée par un pic isolé bloquait la
  reconstruction pour toujours (chaque image fait maintenant au moins un morceau, l'estimation est
  plafonnée). Une colonne de 256 rangées coûtait trop : bandes de 32 rangées.
- **CDP et Defold** : la position de la souris ne change qu'avec `mouseMoved` (cliquer sans bouger
  touche toujours au même endroit) ; un appui et un relâcher de touche dans la même image sont perdus ;
  `mouseWheel` n'atteint pas le jeu dans Chromium sans interface (la molette n'est pas vérifiée).
- **`prompt()` dans `html5.run`** : laid et bloquant ; des champs `<input>` posés sur le canevas font
  venir le clavier du téléphone parce que c'est le doigt du joueur qui les touche.
- **Une grande fenêtre de bureau étire l'interface** (l'ajustement FIT suit la fenêtre) : sans écran
  tactile, `client/ui/widgets.lua` la ramène vers ses ancrages.
- **Les mesures à CPU ×4 dépendent de la charge de l'hôte** (OBS, navigateurs) : le parcours vérifie
  le p95 des tranches et rapporte le pire.
- **Le vecteur `duel` finit avant 2400 ticks** avec les nouvelles cartes : le rejeu tournait sans fin
  sur un contrôle après la fin ; il échoue maintenant avec une raison.
- **Une ressource créée par `resource.create_buffer` meurt avec la partie** (le proxy qui la
  charge), mais un module Lua lui survit (`shared_state`) : garder la ressource dans un module fait
  planter la partie suivante. Elles se créent et se libèrent par partie (`client/game/models.lua`,
  `terrain_view.lua`). L'état du mode test survit aussi : un contrôle qui suit une nouvelle partie
  attend une valeur que seule elle peut produire.
- **Comparer l'écran à la sim, pas au modèle de l'interface** : un contrôle qui lit `hud_model`
  laisse passer une valeur fausse que `game.script` y écrit. Le mode test publie ce que dit la sim
  (`game.sim`) et ce que montrent les nœuds (`shown`) ; l'interface peut avoir une image de retard,
  d'où un seuil de 90 % des images relevées.
- **Une partie de test dépend des réglages de la sim** : avec la poussée du bazooka à 1920, le
  premier bot du harnais éjectait l'humain de l'équipe 1 avant son tour (graine 12 → 4, où l'équipe 1
  joue la première) ; trois autres tests ont dû être re-visés de la même façon.
