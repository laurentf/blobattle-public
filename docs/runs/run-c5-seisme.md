# Run C5 — le séisme de la forêt et la croix des pouces · **fait**

Conservé pour mémoire : ce run est terminé (tranches 24o à 24q, puis la
clôture). Le prompt et les avertissements qui suivent ont servi à le conduire ; le
bilan est en fin de fichier.

Tranches 24o à 24q du plan TDD de `SPEC.md` §10.6. Demandé par l'utilisateur après
avoir joué en ligne sur son téléphone :

- « la map de la forêt devrait avoir un système d'urgence quand la partie dure trop longtemps, des
  tremblements de terre se déclenchent, ça tremble (ça peut donc faire bouger les blobs) et ça créé
  des failles ça s'écarte et les blobs peuvent alors tomber dans l'eau etc pour accélérer la fin de
  partie » ;
- « sur mobile pour [le] tentacule : 2 soucis, pas de bouton "bas" j'ai l'impression et haut fait
  sauter donc on ne peut pas remonter la tentacule non plus, bouton dédié pour sauter serait mieux et
  avoir gauche droite haut bas ».

Tranché avec lui dans la foulée : **dès la 8e ronde**, **de plus en plus fort**, **sans dégâts
directs** (seulement la chute et l'eau).

**Avant de lancer** : `/clear`. L'état des runs A à D et leurs pièges sont dans `docs/runs/`
(bilans), en particulier les graines choisies pour leurs propriétés (`run-c3-armes-cartes.md`,
`run-c4-bots.md`, `run-d-en-ligne.md`).

**Ce qui reste ouvert et ne se règle pas dans ce run** : les bots qui jouent tout (24j à 24m) ; la
limite de `room_create` (D2).

---

## Le prompt

```
Lis SPEC.md, CLAUDE.md et V0.md à la racine, puis docs/conventions.md,
docs/runs/run-c3-armes-cartes.md (la lave qui monte : le modèle du séisme ; les cartes ; les
graines), docs/runs/run-c2-tentacule.md (les commandes du tentacule), docs/runs/run-d-en-ligne.md
(le jeu en ligne, le parcours à plusieurs contextes, les pièges) et docs/runs/run-c5-seisme.md
(ce fichier).

Les runs A à D sont faits, le tunnel est en place (https://blobattle.npc.fm). Tout tourne en
conteneur : make test, make lint, make conformance, make up, make harness, make web,
make journey (J=offline ou J=online), make serve, make tunnel, make bench N=200.

/goal Les tranches 24o à 24q de SPEC.md §10.6 sont faites. En forêt, à la fin de chaque
ronde dès la 8e, un séisme de plus en plus fort secoue trois fois les blobs posés (sans les
blesser : seules la chute et l'eau comptent), ouvre une faille nouvelle jusqu'à l'eau et
écarte de 2 px les failles déjà ouvertes, et le tour suivant n'est visé qu'une fois tout
immobile ; le volcan n'a pas de séisme ; tout est déterministe (flux sim, entiers, failles
dans l'état, la somme de contrôle et le snapshot) et identique sous LuaJIT, Lua 5.1 et
Nakama ; la caméra tremble, les failles s'ouvrent à l'écran et la poussière jaillit ; en
ligne, les deux contextes voient le même séisme aux mêmes ticks. Au doigt, une croix
◀ ▶ ▲ ▼ au pouce gauche et un bouton Saut à part, marqué de son mot, au pouce droit :
accroché au tentacule, ▲ remonte la corde sans lâcher, ▼ l'allonge, Saut lâche. make test,
make lint, make conformance, make harness et make journey restent verts, et le banc de 200
parties dit ce que le séisme fait à la durée des parties (Q-03). Respecte CLAUDE.md, en
particulier D-02 (entiers, flux sim, aucun pairs), D-09, D-10 (44 points, pas d'encoche, rien
sur les lignes des équipes) et D-11 (le mot Jump vient du catalogue). Chaque tranche : la spec
d'abord si une décision change, test rouge vu échouer, code, vert, lint, relecture du diff
par un sous-agent contre SPEC.md, commit en français sans trailer Co-Authored-By, push sur
origin main. À la fin : revue de clôture, ce fichier en « fait » avec les mesures (banc de
200 parties, reconstruction du terrain d'une faille à CPU ×4, taille du plus gros snapshot)
et les pièges, et le build servi par le tunnel. Ou stop après 60 tours.
```

## Ce qui est déjà tranché et ne se rediscute pas dans ce run

- **Le séisme** (SPEC §5.3) : en forêt seulement, à la fin de chaque ronde à partir de la 8e
  (`QUAKE_FROM = 8`), là où la lave du volcan monte (`close_rounds` dans `shared/sim/turn.lua`). Le
  n-ième séisme (n = rondes finies − 7) : trois secousses espacées de 15 ticks pendant le début de
  tour qui suit ; à chaque secousse, chaque blob vivant posé reçoit, tirée sur le flux `sim`, une
  poussée de côté entre −P et +P et vers le haut de 256 FP/tick, P = 192 + 64 × n, borné à 704. Aucun
  dégât direct. Une faille nouvelle par séisme (dans les 60 % centraux, à plus de 24 px d'un puits et
  des autres failles, 8 tirages au plus), de la surface à 4 px sous `L`, large de 4 px, en zigzag
  d'un pixel au plus tous les 4 px ; les failles ouvertes s'écartent de 2 px. Creusées par des
  disques (le journal du terrain, §5.9). Le tour suivant n'est visé qu'une fois tout immobile (300
  ticks au plus).
- **Tous les chiffres dans `shared/sim/rules.lua`**, épinglés par une spec à part (les chiffres de
  SPEC, pas ceux de `rules`).
- **Les événements** `quaked{n}`, `shook{n}`, `cracked{x, width}` (§5.8) nourrissent le rendu et la
  trace du parcours ; rien n'y retourne dans la sim (D-09).
- **La croix et Saut** (§7.3) : au pouce gauche, ◀ ▶ ▲ ▼ ; ▲ ▼ grisés tant qu'on n'est pas
  accroché, pour que la croix garde sa forme ; au pouce droit, Saut, marqué de son mot
  (`hud.jump`, catalogue anglais), à côté du bouton d'arme. Au clavier, rien ne change.

## Pièges déjà rencontrés, à ne pas redécouvrir

- **Chaque changement de la sim ré-enregistre les vecteurs** (en disant pourquoi) et peut faire
  tomber les graines choisies pour leurs propriétés : les re-sonder, pas les forcer, en rejouant les
  minutages du vrai chemin. Les vecteurs actuels (2 400 ticks) n'atteignent sans doute pas la 8e
  ronde : **un vecteur doit atteindre le séisme**, sans quoi la conformité ne le couvre pas.
- **Le snapshot passe en version 7** (les failles) : constructeur, somme de contrôle et snapshot dans
  le même commit ; le plus gros snapshot est borné par un test (8 équipes de 6), à re-mesurer.
- **Un tirage sur le flux `sim` décale le vent des tours suivants** : c'est voulu (le séisme fait
  partie de la partie), mais toute graine qui dépend du vent après la 8e ronde en forêt change.
- **Une faille de 100 px de haut, ce sont des dizaines de disques** : la reconstruction du terrain
  se mesure à CPU ×4 (4 ms par image, fini avant la fin des secousses), comme le tunnel du Chomp.
- **La machine des tours est une table** : attendre l'immobilité après un séisme est une transition
  à y écrire, et à tester (une transition hors table lève une erreur).
- **Les pavés des pouces** : au moins 56 px dans le `.gui` (44 points sur un téléphone de 667×375),
  pas sous l'encoche (x ≥ 47 + la demi-largeur), et jamais sur les 8 lignes des équipes (la spec des
  cibles le vérifie). Les identifiants `left`, `right`, `jump`, `climb_up`, `climb_down` peuvent
  rester : le parcours (`run.mjs` section 24c, `online.mjs`) les touche par leur nom, et la section
  24c vérifie aujourd'hui que ▲ ▼ sont « au-dessus de Saut » — à réécrire pour la croix.
- **Faire secouer la caméra ne touche jamais la sim** ; la poussière est une gerbe de cubes comme
  les débris des explosions.

---

## Bilan

Run conduit dans une seule session, une tranche après l'autre. Pour chaque tranche :
la spec d'abord quand une décision changeait, le test qui ouvre la tranche vu rouge, le code, puis
la suite sous LuaJIT et Lua 5.1 et le lint. Venait ensuite une relecture du diff par un sous-agent
contre SPEC.md, avec des mutants lancés sur une copie du dépôt, dont les constats ont été corrigés
avant le commit. Enfin, la vérification sur un export de l'index (`git checkout-index` : tests,
lint, conformité, harnais, build, parcours), puis un commit et un push.

**Un écart avec ce qui était tranché** : le séisme ne se joue pas « pendant le début de tour qui
suit » mais dans un état à lui, `quake`, entre la fin de la ronde et le tour suivant (§5.3, §5.6
réécrits avant le code). Un bot cherche son tir dès le début de son tour (§9) : pendant les
secousses, il l'aurait cherché sur des blobs qui bougeaient encore (D-06). Le reste est tel que
tranché. Le champ `top` a été ajouté à l'événement `cracked` (§5.8), dont le rendu a besoin.

### Ce qui a été mesuré

| Mesure | Valeur |
|---|---|
| Banc, 200 parties (`make bench N=200`, après 24o) | 34,5 s, **0 erreur**. 20,0 % des parties à la limite des rondes (41,0 % avant le run). Par carte : forêt 5,6 % (6 sur 107), contre 44,9 % sans séisme ; volcan 36,6 % (34 sur 93). 70,5 tours et 9,2 min simulées par partie (83,5 et 10,8 avant). 1 292 morts par les PV et 2 028 dans le liquide (1 494 et 1 707 avant). 796 séismes, 7,4 par partie en forêt, et 457 morts pendant qu'ils secouaient. Dégâts par tir : 14,0 / 16,1 / 21,1 (facile, moyen, difficile). Le banc sépare maintenant forêt et volcan et compte les séismes (Q-03) |
| Reconstruction du terrain d'une faille, CPU ×4, machine calme | tranches de 2,4 ms en moyenne, 3,5 ms au p95, 4,0 ms au pire ; 22 images au plus pour le 2e séisme (la faille écartée et une nouvelle), contre 62 pour les secousses à 60 i/s. Durée dans SwiftShader : 0,68 à 0,87 s. À CPU ×1 : 0,06 à 0,13 s. Une partie de maillage coûte ~0,1 à 0,7 ms, un envoi de morceau au GPU ~2,6 ms. Avant d'alléger `build_row`, 1,25 à 1,75 s dans SwiftShader. Sous la charge d'une autre session (15 à 27), les tranches montent à 4,4–5,8 ms au p95, comme celles des cratères (5,0 ms mesurés au même moment) |
| Plus gros snapshot | 30 784 octets pour une forêt de 8 équipes de 6 après 20 rondes et 10 failles (graine 29, borné par un test entre 29 000 et 32 000), 31 314 sur la graine 2 (11 failles), relevé par la revue de clôture ; 25 606 au run C3 ; le snapshot de 8 × 6 du parcours en ligne, reçu par le client Defold vers le tick 1 500, fait 25 192 à 27 170 octets (H-06) |
| Coût des failles dans la sim, au pire (22 séismes sur la plus grande carte) | 0,5 ms sous LuaJIT, 6,9 ms sous Lua 5.1, en un tick ; la plus grande carte se génère en 1,38 s dans Nakama |
| Conformité (`make conformance`) | 4 vecteurs : les trois anciens sont ré-enregistrés (la somme de contrôle gagne les puits et les failles ; sans ces champs, leurs sommes d'avant reviennent sous LuaJIT et Lua 5.1). Le nouveau vecteur `quake` (graine 4, 2 équipes de 2) traverse trois séismes jusqu'à la fin de la partie. Mêmes sommes sous LuaJIT, Lua 5.1 et Nakama |
| Harnais (`make harness`) | 86 contrôles (79 avant), dont le scénario 24o : deux humains passent leur tour jusqu'à trois séismes, avec deux snapshots en plein séisme (version 7, failles et puits) et toutes les sommes rejouées |
| Parcours du séisme (`make journey J=quake`, lancé aussi par `J=online`) | 9 contrôles. Deux contextes mènent une forêt (graine 4, 2 équipes de 2) jusqu'au 2e séisme : 150 à 154 points de contrôle identiques ; la caméra tremble plus fort au 2e séisme ; chaque faille est dessinée exactement comme la sim, première faille élargie comprise ; la poussière est vue en l'air ; aucune divergence |
| Suite | 732 tests sous LuaJIT et Lua 5.1 (689 avant le run), dont un qui garantit que le vecteur `quake` traverse bien des séismes ; lint propre |
| Parcours complet (`make journey`, état final) | **134 contrôles, aucun rouge** : 85 hors ligne (dont la croix et Jump au doigt, dans la section du tentacule), 40 en ligne et 9 pour le séisme. En ligne : retour par le lien en 8,6 s, socket revenue en 2,5 s, aller-retour d'une entrée de 72 ms en moyenne, snapshot de 8 × 6 de 25 372 octets reçu par le client Defold. Faille à CPU ×4 : tranches de 3,3 ms au p95, 21 images au plus |
| Build servi par le tunnel | le build de l'état final (4,66 Mo) sur **https://blobattle.npc.fm** : `Blobattle_wasm.js` et les archives y sont identiques au bit près à `out/web/Blobattle`, et Nakama tourne depuis le dépôt. Cloudflare ajoute à `index.html` son script de détection des bots (réglages de l'utilisateur), sans effet sur le jeu |

### Ce que les relectures ont trouvé

1. **24o : aucun défaut de la sim.**
   - Les statistiques de fin de partie créditaient à l'équipe qui venait de jouer ce que faisait le
     séisme : sur 60 parties sondées, 44 avaient d'autres chiffres. Corrigé par
     `turn.acting_team`, qui rend 0 pendant `quake`.
   - Placer `quake` avant `ended` renumérotait `ended` : il est rangé après.
   - La relecture a laissé 7 mutants en vie sur 50, fermés par des tests : le plafond des 300 ticks,
     les morts appliquées à la fin du séisme, les statistiques de l'autorité locale et la copie des
     tracés au snapshot.
2. **24p.**
   - La caméra ne montrait presque jamais la faille : les blobs soulevés par la secousse la lui
     volaient (5 ticks sur 36).
   - Le contrôle du parcours ne regardait pas les rangées qu'un bord élargi creuse au-dessus du
     haut de la faille.
   - La zone à reconstruire était recopiée à la main dans les tests : elle est maintenant une
     fonction partagée, `voxel_mesh.crack_area`.
   - Le contrôle de la poussière ne pouvait pas échouer.
   - Huit mutants survivants ont été fermés par des tests : le haut de l'événement quand les deux
     bords sont plus bas, un bord gauche plus haut (deux variantes), le liseré des rangées 0 à 2, le
     séisme qui oublie l'explosion, le tour suivant qui oublie la faille, la faille montrée tout le
     séisme, et l'amortissement de la secousse.
3. **24q.**
   - Le test de la croix supposait des disques alors que le HUD teste des rectangles.
   - Rien ne vérifiait que le mot « Jump » survive à un changement de disposition, ni que Jump
     évite la grille d'armes.
   - Le gris n'était vérifié que par un drapeau, et un disque à 15 % d'opacité se lisait comme
     absent (c'était la plainte de l'utilisateur) : les flèches prennent maintenant le gris des
     boutons inactifs, et le disque reste visible.
   - ▼ descendait à 14 px du bas : il est remonté à 20.

### Pièges rencontrés

- **Une autre session sur la même machine fausse les mesures à CPU ×4** : son Nakama, son lint et
  son Chromium sans interface montent la charge à 15–27 par moments. Les tranches de reconstruction
  (cratères comme failles) dépassent alors 4 ms au p95. Mesurer quand la charge est sous 3
  (`/proc/loadavg`) et le dire.
- **SwiftShader à CPU ×4 dessine une image en 30 à 60 ms** : la durée d'une reconstruction mesurée
  dans Chromium dépend surtout de la cadence du rendu logiciel. Pour la faille, on compte les images
  (une tranche par image) et on les rapporte à 60 i/s.
- **Dans le navigateur, la reconstruction coûte surtout en envoi** : une rangée coûte ~14 µs sous
  Lua 5.1 natif une fois `build_row` allégé, mais une partie scellée (`buffers.seal`, un tampon et
  une écriture par flottant) et un envoi de morceau (~2,6 ms à CPU ×4) dominent. Une tranche qui
  envoie un morceau n'a de place pour rien d'autre.
- **Un estimateur trop optimiste fait déborder les tranches** : une moyenne glissante du coût des
  parties (0,05 ms appris) a fait passer le p95 à 5,1 ms. L'estimateur prudent (le maximum qui
  décroît) est gardé.
- **Un monde restauré perdait ses puits** : un client revenu par snapshot aurait placé ses failles
  ailleurs que le serveur. Les puits sont dans l'état, la somme de contrôle et le snapshot v7.
- **En duel, un blob né sur la pente d'une rive** glisse souvent jusqu'au bassin dès le premier
  séisme (trois bonds vers le bas). C'est la règle telle qu'écrite ; beaucoup de graines d'un blob
  par équipe finissent donc à la 8e ronde. Les graines à propriétés en tiennent compte : le test de
  limite des rondes passe sur des alcôves hors de la zone des failles, et celui du serveur sur un
  volcan (graine 3).
- **Un blob qui se pose meurt au tick même où le séisme finit** : dans un test, relire son état
  après le tick le montre déjà mort ; vérifier le montant du `damaged` plutôt que `alive`.
- **Graines d'aujourd'hui** :
  - vecteur `quake` 4 ; harnais 24o 2 ; parcours du séisme 4 (hôte `?seed=4`, mode test) ;
  - maillage des failles 22 (un bord y monte au-dessus du haut de la faille) ;
  - statistiques de l'autorité locale 11 ; plus gros snapshot 29 (8 × 6, forêt, facile) ;
  - limite des rondes au serveur 3 ;
  - partie du banc à la limite, index 40 (inchangé).
- **`make journey` recrée le Nakama du tunnel depuis le dossier où on le lance** : après une
  vérification sur un export, le relancer depuis le dépôt.
- **Le sous-agent de relecture peut laisser des boucles d'attente** en arrière-plan, et des copies
  de sauvegarde dans le dossier de travail : les arrêter et vérifier que l'arbre n'a pas bougé.

### Ce qui reste ouvert

- **Les bots qui jouent tout** (24j à 24m, run C4) ; la limite de `room_create` et la PWA (run D2) ;
  le panneau d'administration (run D3).
- **Q-03** : avec le séisme, 5,6 % des parties en forêt atteignent la limite des rondes. Au volcan,
  c'est 36,6 %, pour une lave qui monte de 2 px par ronde.
- **Les encoches** : la règle est de 47 px de côté (SPEC). Un iPhone récent en paysage a jusqu'à
  59 pt d'encoche : ◀ y commence à 51 pt. ▼ est à 20 px du bas, près de la zone du geste
  d'accueil (21 pt). Ce sera à revoir au téléphone de l'utilisateur (run E).
- **Le téléphone** : le séisme et la croix ne sont vérifiés que dans Chromium, au toucher émulé.
- **Le coût d'un tick de séisme** n'est mesuré qu'en natif : 0,5 ms sous LuaJIT et 6,9 ms sous
  Lua 5.1, au pire, pour 22 séismes sur la plus grande carte. Ni le tick de Nakama ni celui du client
  HTML5 à ce tick-là ne sont mesurés (à voir avec H-07 et H-11, au run E).
