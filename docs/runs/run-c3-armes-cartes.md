# Run C3 — les chocs entre blobs, l'uppercut, le Chomp et deux cartes · **fait**

Conservé pour mémoire : ce run est terminé (tranches 24d à 24h, puis
l'image de marque et la clôture). Le
prompt et les avertissements qui suivent ont servi à le conduire ; le bilan est en fin de fichier.

Tranches 24d à 24h du plan TDD de `SPEC.md` §10.6, après le run C2 (le tentacule, fait) et avant le
run D (en ligne). Demandé par l'utilisateur après avoir joué le build, tranché avec lui
dans la foulée (questions et réponses dans la session) ; la planche de référence des cartes est
`docs/planche_maps_worms_like.pdf` (la « Forêt » : collines, surplombs, arbres
qui servent de couverture, herbe sur la terre puis la roche, cavernes, eau en bas).

**Avant de lancer** : `/clear` si le run se fait dans une nouvelle session. L'état des runs A à C2,
leurs mesures et leurs pièges sont dans `docs/runs/` (bilans).

**Ce qui reste ouvert et ne se règle pas dans ce run** : Q-03 (la durée des parties) hors du volcan,
dont la lave qui monte presse la fin de partie ; ne toucher ni aux dégâts des armes existantes, ni
aux PV, ni aux rondes.

---

## Le prompt

```
Lis SPEC.md, CLAUDE.md et V0.md à la racine, puis docs/runs/run-c2-tentacule.md (le
tentacule, ses pièges, la graine 119) et docs/runs/run-c3-armes-cartes.md (ce fichier).

/goal Les tranches 24d à 24h de SPEC.md §10.6 sont faites : un blob projeté qui en
touche un autre le projette à son tour ; l'uppercut envoie en l'air en
cloche le blob qu'il touche et termine le tour ; le Chomp creuse un tunnel à la taille du
blob dans la direction visée, le blob avançant dedans, et termine le tour ; le réglage
« Carte » donne une forêt (herbe, terre et roche, arbres destructibles, surplombs,
cavernes, eau qui ne monte pas) ou un volcan (basalte, lave, ciel rougeoyant, brume,
bulles, stalactites, cavernes), et la lave du volcan monte de 2 px à chaque ronde dès la
5e. `make test`, `make lint`, `make conformance`, `make harness` et `make journey`
restent verts. Respecte CLAUDE.md (déterminisme, champs d'un enregistrement, D-04, D-05,
D-09, D-11, la couture de l'autorité). Chaque tranche : test rouge vu échouer, code, vert,
lint, relecture du diff par un sous-agent contre SPEC.md, commit en français sans trailer
Co-Authored-By, push sur origin main. À la fin : ce fichier en « fait » avec les mesures
(banc de 200 parties, tick de sim et reconstruction du terrain à CPU ×4, génération de la
plus grande carte sous les trois moteurs) et les pièges.
```

## Ce qui est déjà tranché et ne se rediscute pas dans ce run

- **Les chocs entre blobs** (§5.4) : les blobs ne se bloquent toujours pas en marchant ; un blob
  **projeté** (plus de `384` FP/tick de côté, en vol ou en glissade) dont la boîte en touche une autre
  pendant son déplacement pixel par pixel, en s'en rapprochant, lui transmet `60` % de leur écart de
  vitesse et en garde le reste (quantité de mouvement conservée, arrondis symétriques) ; le touché
  décolle (au moins `256` FP vers le haut), et rebondit ou glisse à son tour comme un blob projeté.
  Sans dégâts : la chute compte comme d'habitude. Un seul choc par paire et par tick ; les blobs se
  traitent dans l'ordre du tableau. Le fantôme des bots ne voit pas les autres blobs (D-06 : il
  évalue le tir, pas les chocs en chaîne).
- **L'uppercut** (`uppercut`, genre `melee`, §8.2) : au contact, sans visée, dans le sens du regard ;
  touche tout blob dont la boîte entre dans une zone de `10` px devant la boîte du frappeur (à sa
  hauteur) ; `30` dégâts et une poussée en cloche `(±512, −1024)` FP/tick (vers l'avant et le haut,
  comme un Shoryuken) ; le frappeur n'est pas touché ; termine le tour (le tour passe par `flight`
  puis `retreat`, comme après un tir). Sans munitions. Les bots ne s'en servent pas.
- **Le Chomp** (`chomp`, genre `digger`) : visé comme le tentacule (seul l'angle compte) ; le blob
  mange la terre devant lui : pendant `60` ticks (2 s), à chaque tick il avance de `2/3` px dans la
  direction visée et creuse un disque de `5` px de rayon autour du centre de sa boîte à sa nouvelle
  place (un tunnel de 40 px à sa taille, qui le dépasse de 2 px), sans gravité ni dégâts, tourné vers
  où il mange, et aucun blob projeté ne le cogne ; il s'arrête avant que sa boîte ne sorte de la
  carte, et retombe à la fin du repas. Termine le tour comme dans Worms : `flight` tant qu'il mange, puis le repli de 3 s. Sans
  munitions. Un événement `chomped{cat, x, y, radius}` par tick nourrit la reconstruction du terrain
  et l'animation (le blob « mange » : sa bouche s'ouvre et se ferme, des miettes de terre volent).
- **La carte** (§5.2, §5.3) : un réglage `map` (`forest`, `volcano`, `random`) remplace `liquid` ; la
  forêt a de l'eau qui ne monte pas, le volcan de la lave qui monte. Le tirage de `random` reste sur
  le flux `map`. Le terrain garde ses cellules pleines ou vides pour la sim, mais une case pleine
  porte un matériau (`1` terre ou roche, `2` bois, `3` feuillage, `4` acier) : `terrain.solid` ne regarde que
  « non vide », le rendu colore par matériau, la somme de contrôle et le snapshot le couvrent déjà
  (hachage des cellules, RLE par valeur).
- **La forêt** : les collines de la planche, avec des surplombs (des creux horizontaux sous le rebord
  des pentes) et des cavernes ; 1 arbre tous les ~60 px de surface à ciel ouvert (tronc de 2 px sur
  10 à 16 px, houppier rond de 5 à 8 px de rayon), en terrain destructible, tiré sur le flux `map` ;
  l'apparition à ciel ouvert (§5.3) exclut d'elle-même le dessous d'un houppier.
- **Le volcan** : même relief de base, plus de cavernes, des stalactites (pointes de 3 à 10 px sous
  les plafonds et les surplombs), des poutrelles d'acier en travers du ciel (ajoutées par
  l'utilisateur pendant le run, comme la planche « Mine et chantier ») ; la lave **monte de 2 px à chaque fin de ronde dès la 5e** (une
  ronde finit quand chaque équipe en vie a joué une fois de plus) ; le niveau du liquide entre dans la
  somme de contrôle (il y manquait, puisqu'il ne bougeait pas).
- **Rendu** (D-09) : une texture des matériaux de la carte (une case = un texel), bâtie au début de
  la partie, que lit le shader du terrain pour colorer : forêt — herbe sur la bande de surface, terre
  brune, roche grise en profondeur, bois brun, feuillage vert ; volcan — cendre grise en surface,
  basalte noir, roche sombre. Pas de couleur par sommet (piège du run C). Le ciel par biome (bleu ;
  rouge rougeoyant), des nuages en fond (blancs en forêt ; de la fumée sombre au volcan, ajoutés par
  l'utilisateur), une brume basse au volcan, des bulles qui éclatent sur la lave. La lave qui monte
  se voit monter.
- **Commandes** : la grille d'armes passe à cinq cases (deux colonnes), touches 4 (uppercut) et 5
  (Chomp). L'uppercut part du même geste que les autres armes (lance-pierre au doigt, glisser à la
  souris, Espace au clavier, qui frappe aussitôt) : seul le relâcher compte, le coup part dans le sens
  du regard (◀ ▶ ou ← → le tournent). Le Chomp se vise comme le tentacule (seul l'angle compte).

## Les tranches

| # | Contenu | Le test qui l'ouvre | Vérifications |
|---|---|---|---|
| 24d | Chocs entre blobs : un blob projeté transmet sa vitesse à celui qu'il touche | un blob projeté contre un autre le projette à son tour (60 % de l'écart), le choc à gauche reflète celui de droite, et deux blobs qui marchent se croisent toujours | test, lint, conformance (vecteurs ré-enregistrés), harnais, banc |
| 24e | Uppercut : sim, registre et contrat des armes (genre `melee`), grille à 4 cases, touche 4, rendu du coup | un uppercut envoie le blob touché en cloche, 30 dégâts, et termine le tour ; le même coup à gauche reflète celui de droite | test, lint, conformance, harnais, parcours |
| 24f | Chomp : sim (état « mange », creusage par tick), événements, grille à 5 cases, touche 5, animation de la bouche et des miettes | le Chomp creuse un tunnel à la taille du blob dans la direction visée, le blob au bout, et termine le tour ; dans toutes les directions | test, lint, conformance, harnais, parcours |
| 24g | Cartes : réglage `map`, matériaux, surplombs, arbres, stalactites, texture des matériaux, ciel, brume, bulles | sur 200 graines × 7 réglages, les deux biomes gardent les garanties de §5.3, la forêt a des arbres et des surplombs, le volcan des stalactites | test (génération), lint, conformance (vecteurs ré-enregistrés), harnais (graines re-sondées), parcours (écran comparé) , banc |
| 24h | La lave qui monte au volcan | au volcan, la lave monte de 2 px à la fin de chaque ronde dès la 5e, noie qui elle atteint, et la somme de contrôle la suit ; la forêt ne monte pas | test, lint, conformance, harnais, parcours, banc (Q-03) |

## Pièges déjà rencontrés, à ne pas redécouvrir

- **Chaque changement de la sim ré-enregistre les vecteurs** et rend caduques les graines choisies
  pour leurs propriétés : la partie entière de la LocalAuthority (47), la partie du banc à la limite
  (index 40), le plus gros snapshot, `AIMING_TICK` et les graines du harnais, **la graine 119 du
  tentacule** (parcours et scénario 24). Les re-sonder, pas les forcer.
- **Un blob apparaît à ciel ouvert** : la génération ne doit pas le faire naître sous un houppier ni
  sous un surplomb.
- **Écrire un buffer élément par élément coûte cher en HTML5** : la texture des matériaux se remplit
  une fois, au début de la partie ; un cratère n'y change rien (il ne fait que vider des cases).
- **Les ressources de `resource.create_*` meurent avec la partie**, les modules non : créer et
  libérer la texture par partie.
- **Le budget de reconstruction du terrain (4 ms par image à CPU ×4)** : le Chomp creuse à chaque
  tick ; mesurer ses tranches, pas seulement celles des cratères.

---

## Bilan

Run conduit dans la même session que le run C2, une tranche après l'autre : le test
qui ouvre la tranche écrit et vu rouge, le code, la suite sous LuaJIT et Lua 5.1, le lint, une
relecture du diff par un sous-agent contre SPEC.md (avec des mutants lancés sur une copie du dépôt),
les constats corrigés, le banc, la conformité, le harnais et le parcours, puis un commit et un push
par tranche. La tranche 24g a fait deux commits (la génération, puis le rendu), et la
génération a gagné un commit de vitesse avant 24h. Les algorithmes et les graines ont
été réglés sur des copies jetables du dépôt avant d'être posés.

Demandé en route par l'utilisateur et fait dans le run : les poutrelles d'acier au volcan, des
nuages en fond (de la fumée sombre au volcan), le nom « Blobattle » pour la fenêtre, la page et
l'application, le logo rond de `logo-base.png` (fourni à côté du dépôt) au chargement à la place de celui de Defold, et un
README complet.

### Ce qui a été mesuré

| Mesure | Valeur |
|---|---|
| Banc, 200 parties (`make bench N=200`, après 24h) | 36,5 s, **0 erreur** ; 43,5 % à la limite des rondes (87 parties), 82,5 tours par partie, 1 nul ; 1 594 morts par les PV, 1 605 dans le liquide ; 12,8 / 14,4 / 19,0 dégâts par tir (facile, moyen, difficile). Avant le run : 41,0 % ; après les chocs de 24d, 46,5 % ; après les cartes de 24g, 53,0 % (les surplombs, les arbres et les poutrelles couvrent) ; la lave de 24h ramène à 43,5 % |
| Tick de sim du client en HTML5, CPU ×4 (parcours) | partie à 4 équipes de 4 : 0,62 ms en moyenne, 1,8 ms au p95, 5,2 ms au pire ; partie du tentacule : 0,16 ms en moyenne, 0,7 ms au p95 ; repas du Chomp : 0,34 à 0,39 ms en moyenne, 1,0 à 1,2 ms au p95 |
| Reconstruction du terrain, CPU ×4 | cratère : tranches de 2,5 à 2,7 ms en moyenne, 3,0 à 3,4 ms au p95 (4,1 ms une fois, pendant qu'un autre conteneur tournait) ; reconstruit en 0,27 à 0,31 s en moyenne, 0,29 à 0,35 s au pire selon la charge de la machine, sous le flash de 0,4 s (0,3 s jusqu'au run C3 : les nouvelles cartes coûtent plus de faces, mesuré 0,25 à 0,27 s avant tout rendu) ; tunnel du Chomp (une bouchée par tick) : tranches de 2,6 ms en moyenne, 3,1 à 3,2 ms au p95, 3,4 à 4,9 ms au pire ; à CPU ×1, 2,5 ms au pire. Le budget de 4 ms tient au p95 ; une image isolée le dépasse, comme au run C |
| Texture des matériaux, CPU ×4 | peinte une fois au début de la partie : 170 à 200 ms, la plus grande carte comprise (523 ms quand chaque case écrivait sa couleur, trois octets) |
| Génération de la plus grande carte (8 équipes de 6) | LuaJIT 25 ms, Lua 5.1 240 ms (pire de 5), Nakama 1,53 s ; avant la ligne de ciel lue case par case : 28 ms, 353 ms et 2,45 à 3,10 s (au-delà du budget de 3 s sur une machine chargée) |
| Cartes, 200 graines, 4 équipes de 4 | 3,5 surplombs par carte (6 cartes sans), 7,1 arbres en forêt, 28 stalactites et 1,8 poutrelle au volcan, 6 % de vide en plus au volcan ; les garanties de §5.3 tiennent sur 200 graines × 7 réglages |
| Plus gros snapshot (8 équipes de 6 après 15 600 ticks de bots) | 25 606 octets (20 854 au run C2) : deux champs de plus par chat, les rondes, et des plages de matériaux ; borne re-mesurée, 24 000 à 27 000 (H-06). Snapshot de la plus grande carte dans Nakama : 25 578 octets |
| Nakama (`make conformance`) | mêmes sommes et mêmes noms sous LuaJIT, Lua 5.1 et Nakama après chaque tranche ; un tick du vecteur `brawl` 1,5 à 2,2 ms |
| Harnais (`make harness`) | 79 contrôles, dont les scénarios de l'uppercut (graine 65), du Chomp (graine 213, snapshot pendant le repas) et de la lave (graine 7 : 232 jusqu'à la 4e ronde, 228 après la 6e), sommes rejouées sous LuaJIT et Lua 5.1 |
| Parcours (`make journey`) | 82 contrôles, ~40 min : la grille à cinq cases, l'uppercut et le Chomp au doigt et au clavier, les deux cartes (couleurs, nuages, basalte, bulles, herbe au-dessus de la roche), la partie entière au volcan avec la lave qui monte et la lave dessinée qui suit, le nom et le logo |

- **Suite** : 606 tests, verts sous LuaJIT et Lua 5.1 (539 après 24d, 556 après 24e, 579 après 24f,
  586 après la génération de 24g, 598 après son rendu) ; `luacheck` et `stylua --check` propres.

### Ce que les relectures ont trouvé

1. **24d** : une glissade qui cognait un blob à l'arrêt restait collée à lui (10 s de repos
   attendues) ; une approche non stricte ; la règle « un choc par paire » mal dite ; des mutants.
2. **24e** : le décor des menus envoie un `fired` sans arme, et la gelée plantait à chaque blob
   effrayé ; la grammaire `melee` manquait à §8.1 ; cinq mutants.
3. **24f** : un blob projeté contre un blob qui mange lui donnait une vitesse perdue (on le traverse
   maintenant) ; le blob mangeait dos à son tunnel ; quatre mutants.
4. **24g, génération** : les trois quarts des surplombs tombaient sur les pentes des rives (dont 221
   sous le liquide) ; 27 % des apparitions en forêt se faisaient sur un houppier ; des réglages en
   dur ; sept mutants.
5. **24g, rendu** : le sol sous chaque tronc était peint en roche (le bois comptait dans la
   profondeur) ; les bulles ignoraient la vague ; les faces du bord lisaient la case du dessous ; la
   SPEC ne suivait plus ; le parcours laissait passer une texture vide ou à l'envers.
6. **24h** : la lave noyait un tick trop tard (le tour suivant commençait sur un blob condamné, et à
   la limite des rondes le vainqueur se calculait avant la noyade) ; le fond de la lave dessinée
   apparaissait ; une allocation par image ; des mutants sur le comptage des rondes.

### Pièges rencontrés

- **Les graines choisies pour leurs propriétés tombent à chaque changement de la carte**, et 24g l'a
  changée trois fois. Graines d'aujourd'hui : autorité locale 7, mort par les PV au serveur 5, duel
  des vecteurs 1240 (il doit finir avant le tick 2400), tentacule 213 à l'angle 178, Chomp 213,
  uppercut 65 (le harnais marche 44 ticks), partie entière 821 (un volcan : le bot joue d'abord,
  l'ennemi est visible à gauche, la partie dure assez pour que la lave monte), cartes 4242, banc 40.
  Les sondes sont dans l'historique de ce run : **une sonde doit rejouer les minutages du vrai
  chemin** (le harnais en ligne décale d'un à quelques ticks : exiger la réussite sur une plage de
  minutages), et une graine du parcours ne se choisit pas sur la sim seule quand des tirs au doigt
  s'y mêlent (choisir l'ennemi visible et le bot en premier).
- **Un enregistrement du harnais sans `game_end`** fait échouer le rejeu dès que la partie finit dans
  la fenêtre : les scénarios 24 l'enregistrent.
- **Le RLE du terrain alternait vide et plein sans le dire** : avec des matériaux, chaque plage porte
  sa valeur (`longueur × 8 + matériau`, qui refuse un matériau inconnu).
- **Un surplomb perd sa lèvre** s'il la coupe de la colline (îlot retiré) : il faut que le relief
  remonte derrière lui, et que les puits soient placés avant lui ; la règle des 12 px sous la surface
  se mesure à la ligne de relief, pas à la première terre.
- **Écrire un buffer case par case en HTML5** : une classe par case (un octet) plutôt qu'une couleur
  (trois) divise le temps par trois ; la couleur se choisit dans le shader.
- **Le temps d'un cratère se mesure au calme** : ± 0,03 s de bruit, et bien plus quand d'autres
  conteneurs tournent ou que la machine sert à autre chose ; la marge sous le flash se garde en
  allongeant le flash, pas en espérant.
- **Un appel de fonction coûte cher dans gopher-lua** : la ligne de ciel par `terrain.solid` case par
  case doublait le temps de la carte dans Nakama.
- **Le mode test ne publie l'état qu'une fois par seconde en vol** : une animation à 8 Hz s'y voit
  toujours dans la même phase ; il publie aussi quand un visage change.
- **Un long script de parcours déclare ses `const` une seule fois** (`deadline`, `ground`, `top` s'y
  sont heurtés) : des noms propres à chaque section.
- **Le dossier du bundle HTML5 prend le titre du projet** (`out/web/Blobattle`), et la page efface le
  fond du canvas après le chargement : le logo de chargement se vérifie dans la page servie.

### Ce qui reste ouvert

- **Q-03** (la durée des parties, 43,5 % à la limite des rondes), à l'utilisateur.
- **Le téléphone** (H-09, H-11) : l'uppercut, le Chomp et les deux cartes ne sont vérifiés que dans
  Chromium ; `make serve` sert désormais `out/web/Blobattle` (relancer un `make serve` démarré avant).
- **Les icônes Android** (run E) : à tirer de `client/brand/`.
- **Une partie rejointe par snapshot** peint en herbe le fond des cratères déjà creusés (écart de rendu
  seulement, écrit dans SPEC §7.4).
- **Le run D** (en ligne) : `docs/runs/run-d-en-ligne.md`, mis à jour pour l'état du run C3.
