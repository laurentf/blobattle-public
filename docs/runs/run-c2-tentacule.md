# Run C2 — le tentacule · **fait**

Conservé pour mémoire : ce run est terminé (tranches 24a à 24c, puis la
clôture). Le prompt et les avertissements qui suivent ont servi à le conduire ; le
bilan est en fin de fichier.

Tranches 24a à 24c du plan TDD de `SPEC.md` §10.6, entre le run C (fait) et le run D (en ligne).

**Avant de lancer** : `/clear` si le run se fait dans une nouvelle session. L'état des runs A à C, leurs
mesures et leurs pièges sont dans `docs/runs/run-a-socle-simulation.md`, `docs/runs/run-b-serveur.md`
et `docs/runs/run-c-client.md` (bilans).

**Ce qui reste ouvert et ne se règle pas dans ce run** : Q-03 (la durée des parties, 41 % à la limite
des rondes sur le banc) : ne toucher ni aux dégâts, ni aux PV, ni aux rondes.

---

## Le prompt

```
Lis SPEC.md, CLAUDE.md et V0.md à la racine, puis docs/runs/run-c-client.md (le client,
LocalAuthority, le parcours, les pièges de Defold) et docs/runs/run-c2-tentacule.md (ce
fichier).

/goal Les tranches 24a à 24c de SPEC.md §10.6 sont faites : une jauge vide arrête la
marche au pixel près et refuse le saut, et le chat tire encore ; accroché à un plafond, un
balancier lâché au bout de sa course part avec la vitesse attendue, et le même balancier à
gauche reflète celui de droite tick par tick ; dans le build, le parcours lance le
tentacule, se balance, lâche et retombe, sans divergence. `make test`, `make lint`,
`make conformance`, `make harness` et `make journey` restent verts. Respecte CLAUDE.md, en
particulier le contrat de déterminisme (entiers, fixed, table trigonométrique, arrondis
symétriques), la règle des champs d'un enregistrement (constructeur, somme de contrôle et
snapshot ensemble), D-04, D-09, D-11 et la couture de l'autorité (§7.1). Chaque tranche :
test rouge vu échouer, code, vert, lint, relecture du diff par un sous-agent contre
SPEC.md, commit en français sans trailer Co-Authored-By, push sur origin main. À la fin :
mise à jour de ce fichier en « fait » avec les mesures (banc de 200 parties, tick de sim à
CPU ×4) et les pièges.
```

## Ce qui est déjà tranché et ne se rediscute pas dans ce run

- **La jauge** (§5.4) : 3000 points par tour pour le chat actif ; marcher 20 par pixel, sauter 200,
  lancer le tentacule 300, rester accroché 10 par tick. Un pas, un saut ou un lancer non couvert n'a
  pas lieu ; accroché, jauge vide = lâcher. Jauge vide : on vise et on tire encore. Tous les chiffres
  dans `rules.lua`, épinglés par une spec (comme ceux des rebonds).
- **Le tentacule** (§5.4, §8.2) : une arme de genre `utility`, toujours disponible, sans munitions,
  qui ne termine pas le tour. Lancé selon l'angle (la puissance est ignorée), depuis le centre de la
  boîte, pixel par pixel sur la table trigonométrique, jusqu'à 120 px ; accroché au premier pixel de
  terre ; corde bornée entre 16 et 120 px. Accroché : jauge −10, corde ±256 FP (`climb`), gravité et
  poussée tangente de 32 FP/tick (`move`), projection sur le cercle (`isqrt`, `round_div`), puis
  déplacement pixel par pixel comme en vol, une case pleine l'arrêtant. `jump` lâche avec la vitesse
  (§5.4 s'applique : rebonds, glissade). Une explosion ou la sortie de `aiming` lâche aussi. On
  relance en l'air ; on ne tire pas accroché. Pas d'enroulement autour des coins.
- **Nouveaux champs du chat** : `gauge`, `hanging`, `anchor_x`, `anchor_y` (pixels), `rope` (FP),
  `climb`. Dans le constructeur, `world.checksum` et le snapshot (version 3) dans le même commit.
- **Entrées et protocole** : `input {kind = "climb", direction}` (−1, 0, 1), validé dans
  `shared/protocol.lua` (§6.4, §6.8) ; le tentacule se lance par un `fire` ordinaire (arme
  `tentacle`, puissance bornée comme les autres, ignorée). Le serveur l'accepte donc sans code
  propre ; le harnais le vérifie.
- **Bots** : le tentacule n'est jamais un candidat (§9) ; la jauge les concerne, ils ne marchent pas.
- **Commandes** (§7.3) : dans la grille d'armes, visé du même geste ; accroché, ◀ ▶ balancent, ▲ ▼
  apparaissent au-dessus de Saut, Saut lâche. Clavier : Espace lance ; accroché, ← → balancent,
  ↑ ↓ jouent sur la corde, Entrée lâche.
- **Rendu** (§7.4) : un bras de voxels à la couleur de l'équipe du blob au point d'accroche, qui
  ondule avec le ressort ; la jauge en petite barre sous le nom du blob actif. Rien ne remonte dans
  la sim (D-09).

## Les tranches

| # | Contenu | Le test qui l'ouvre | Vérifications |
|---|---|---|---|
| 24a | Jauge : champ `gauge`, coûts, remise à plein au `turn_start`, affichage | une jauge vide arrête la marche au pixel près et refuse le saut, et le chat tire encore | test, lint, conformance (vecteurs ré-enregistrés : la marche change), harnais, parcours |
| 24b | Tentacule dans la sim, registre et contrat des armes, protocole `climb` | accroché à un plafond, un balancier lâché au bout de sa course part avec la vitesse attendue ; le balancier à gauche reflète celui de droite tick par tick | test, lint, conformance, harnais (un scénario lance le tentacule en ligne), banc |
| 24c | Commandes au doigt et au clavier, rendu du tentacule, parcours | le parcours lance le tentacule, se balance, lâche et retombe, sans divergence | test, lint, parcours complet |

## Pièges déjà rencontrés, à ne pas redécouvrir

- **Un décalage répété sans réserve s'additionne** : la tolérance de 2 px en l'air, sans budget par
  vol, laissait gravir un escalier. Tout ce qui corrige une position (projection sur la corde,
  arrêt contre la terre) doit être borné par tick et prouvé contre des marches et des pentes.
- **Une spec qui calcule l'attendu depuis `rules` ne prouve pas les chiffres de SPEC** : épingler
  les chiffres dans une spec à part, et chercher les mutants (pourcentages, arrondi non symétrique).
- **La symétrie** : une poussée orientée passe par `round_div` ; une spec compare un balancier à
  gauche et son reflet à droite, tick par tick (la boîte de 6 px n'est pas centrée sur son pixel).
- **Chaque changement de la sim** ré-enregistre les vecteurs (en disant pourquoi) et peut rendre
  caduques des graines choisies pour leurs propriétés : la partie entière de la LocalAuthority
  (graine 47), la partie du banc qui atteint la limite après la chute d'une équipe (index 40), le
  plus gros snapshot (sous 18 000 octets), `AIMING_TICK` du harnais. Les re-sonder, pas les forcer.
- **Le fantôme des bots** suit une projection jusqu'au repos (`cat.at_rest`) : un chat accroché
  n'est jamais au repos ; une explosion le décroche d'abord.
- **Defold** : les ressources de `resource.create_buffer` meurent avec la partie, les modules non
  (`render/paths` donne des chemins uniques) ; une géométrie du tentacule refaite à chaque image
  est une allocation par image : réutiliser un tampon, ou un nombre fixe de segments déplacés.

---

## Bilan

Run conduit dans une seule session, une tranche après l'autre : le test qui ouvre la
tranche écrit et vu rouge, le code, la suite sous LuaJIT et Lua 5.1, le lint, puis une relecture du
diff par un sous-agent contre SPEC.md (avec des mutants lancés sur une copie du dépôt), les constats
corrigés, un commit et un push par tranche.
Les chiffres de l'algorithme (projection, poussée, symétrie) et les graines des tests ont été
réglés sur une copie jetable du dépôt avant d'être posés, pour que l'arbre de travail ne porte que
ce qui était relu.

### Ce qui a été mesuré

| Mesure | Valeur |
|---|---|
| Banc, 200 parties (`make bench N=200`, après 24b) | 21,7 s, **0 erreur** ; 41,0 % à la limite des rondes (82 parties), 77,8 tours et 10,2 min simulées par partie, 6 nuls ; 1 556 morts par les PV, 1 662 dans le liquide ; 14,0 / 14,8 / 18,6 dégâts par tir (facile, moyen, difficile). **Identique au banc d'avant le run** : les bots ne marchent ni ne lancent le tentacule, et le tentacule n'entre pas dans leurs candidats (le tirage sur le flux `bots` est inchangé) |
| Tick de sim du client en HTML5, CPU ×4 (parcours) | partie à 4 équipes de 4 (graine 4242) : 0,51 ms en moyenne, 1,0 ms au p95, 4,6 ms au pire ; partie du tentacule (graine 119, lancer, montée, balancier, lâcher) : 0,17 à 0,21 ms en moyenne, 0,7 à 0,8 ms au p95, 1,0 à 2,0 ms au pire |
| Autorité locale par image, CPU ×4, 4 équipes de 4 | 0,28 ms en moyenne, 0,9 ms au p95 |
| Reconstruction d'un cratère, CPU ×4 | tranches de 2,6 ms en moyenne, 3,1 ms au p95, 3,2 ms au pire ; un cratère en 0,21 à 0,23 s sous le flash de 0,3 s |
| Nakama (`make conformance`) | mêmes sommes et mêmes noms sous LuaJIT, Lua 5.1 et Nakama après chaque tranche ; plus grande carte 2,17 s, un tick du vecteur `brawl` 2,0 ms, snapshot de la plus grande carte 20 430 octets (134 ms après un cratère, 0,96 ms depuis le cache) |
| Plus gros snapshot (8 équipes de 6 après 15 600 ticks de bots) | 20 854 octets en JSON (17 090 avant le run : six champs de plus par chat) ; borne du test re-mesurée, 19 000 à 22 000 (H-06) |
| Harnais (`make harness`) | 60 contrôles, dont le nouveau scénario 24 : un humain lance le tentacule en ligne, monte, se balance, demande un snapshot accroché (qui porte `hanging`, l'ancre et la corde) et lâche ; les 14 sommes reçues se retrouvent par le rejeu Lua, sous LuaJIT et Lua 5.1 |
| Parcours (`make journey`) | 70 contrôles, ~17 min : ceux du run C, la barre de jauge comparée à la sim à chaque échantillon (14 px marchés et un saut : 2520 dans la sim, 0,84 de la barre), puis le tentacule au doigt à CPU ×4 (choisi dans la grille, lancé au lance-pierre, bras dessiné jusqu'à l'ancre, ▲ ▼ au-dessus de Saut et seulement accroché, monté, balancé, lâché, retombé vivant) et au clavier sans pavés (3, ↑, Espace qui accroche en moins de 0,8 s, ↑, ←, Entrée qui lâche en moins d'une seconde), sans divergence ni tick dépassé |
| Le balancier | lâché au repos, sa vitesse au point bas vaut ~91 % de √(2gh) : la projection sur le cercle dissipe (le balancier perd ~30 % de sa hauteur par demi-oscillation) ; la poussée de 32 FP/tick suffit à le relancer |

- **Suite** : 514 tests, verts sous LuaJIT et Lua 5.1 (460 après 24a, 500 après 24b) ; `luacheck` et
  `stylua --check` propres, scripts Defold compris.

### Ce que les relectures ont trouvé

Aucune relecture n'a trouvé de défaut dans le code de la sim ; celle de 24c en a trouvé un dans les
commandes, et toutes ont trouvé des tests qui laissaient passer des mutants, tués avant le commit :

1. **24a** : un saut refusé seulement à jauge nulle (une jauge à 180 laissait sauter et passait sous
   zéro), un saut en l'air facturé, le pas qui quitte un rebord et la remise à plein dès le
   `turn_start` n'étaient pas épinglés ; une allocation par changement de jauge pour le seul mode
   test ; une visibilité de la barre publiée d'après le booléen du script et non d'après le nœud.
2. **24b** (41 mutants) : le lâcher au temps écoulé et au `skip` (le test lâchait par jauge vide
   avant), le glissement le long d'une pente, la symétrie du rayon aux frontières de colonnes, la
   réserve de 2 px remplie au lâcher, un lâcher avec moins de 200 points, un lancer à exactement
   300, la noyade accrochée, les bornes de `climb` dans la sim ; et un défaut latent : un `utility`
   ne décomptait jamais de munition.
3. **24c** : **Espace tenu à travers un lâcher relançait le tentacule** — le verrou « déjà tiré »
   était remis à zéro pendant l'accrochage par l'appel de chaque image ; un bras relancé juste après
   un lâcher sortait déjà tendu ; le parcours ne prouvait ni que ▲ ▼ disparaissent hors
   accrochage, ni qu'Entrée lâche (la jauge vide aurait fini par lâcher), ni qu'Espace lance avant
   une charge ; ↑ ↓ qui changeraient l'angle accroché, un lance-pierre commencé accroché et une
   onde figée passaient les tests. Tout est corrigé et épinglé ; `arm.points` est passé à trois
   paramètres (règle des champs nommés de CLAUDE.md).

Trouvé en route, hors relecture : **le serveur fermait le tick après tout `fire`** (un `move` envoyé
juste après un lancer de tentacule aurait été refusé) ; **un humain qui part accroché** laissait au
bot un tour entier de tirs refusés : le serveur lâche maintenant le tentacule par un saut ordinaire.

### Pièges rencontrés

- **Un déplacement en ligne droite vers le point projeté reste collé à toute pente** : accroché au
  flanc d'une colline, le blob ne bougeait plus (corde à 16 px, chaque sous-pas bloqué). « Comme en
  vol » veut dire horizontalement puis verticalement, chaque axe arrêté seul : tiré contre une pente,
  il la longe. SPEC §5.4 le dit maintenant.
- **Un blob apparaît à ciel ouvert** : sur 300 graines, 14 503 lancers de sonde sur 15 120 depuis le
  point d'apparition ne touchent rien ; les accroches viennent des rives en pente. Accroché à une
  pente, pousser *vers* elle le plaque ; pousser à l'opposé le balance. Le parcours et le harnais
  utilisent la graine 119 (le joueur joue en premier, s'accroche entre 180 et 194 et se balance en
  poussant à l'opposé) : **une graine choisie pour ses propriétés**, à re-sonder si la carte ou la
  sim change (la sonde : rejouer la première visée du joueur pour chaque graine, lancer à chaque
  angle du demi-cercle supérieur, puis monter, pousser à l'opposé, lâcher et vérifier la retombée).
- **L'invariant de la corde n'est pas « dans le cercle »** : quand la terre bloque le blob pendant
  que la corde raccourcit, il reste au-delà. L'invariant tenu et testé : jamais dans la terre, et
  jamais plus loin de l'ancre que max(corde, distance du tick d'avant).
- **Un rayon qui suit la ligne médiane de la boîte** (6 px, centrée entre deux colonnes) casse le
  miroir avec un simple `floor` : le point exactement entre deux colonnes compte dans celle vers
  laquelle va le rayon, celle du regard s'il monte droit.
- **Le premier tick accroché est celui du lancer** : il paie déjà ses 10 points (jauge 2690 et non
  2700 après un lancer qui accroche).
- **Deux asymétries d'un pixel, antérieures au run**, restent hors de l'air libre : la position
  arrondie vers le bas (`floor`, comme en vol) fait qu'un blob qui arrive exactement sur une
  frontière de pixel heurte la terre d'un côté et pas de l'autre (6 cas sur 126 balanciers en
  miroir sur des escaliers), et qu'il meurt au pixel W à droite mais au pixel −1 à gauche en sortant
  de la carte. Le test de reflet tick par tick court en l'air libre, où elles n'apparaissent pas.
- **À CPU ×4, un relâcher arrive plusieurs ticks après la condition** : tenir ▲ « jusqu'à 3 px de
  montée » raccourcissait la corde jusqu'à 16 px, où le balancier ne fait plus que 2 à 5 px. Le
  parcours s'arrête à 2 px et prouve le balancier dès 3 px, en l'air.
- **Au clavier, un appui long pour régler l'angle déborde la fenêtre d'accroche** : le parcours règle
  l'angle par petits appuis sur ↑ et ↓ en relisant l'angle publié.
- **Lancer « aussitôt » à Espace** : l'état « déjà tiré » doit tenir jusqu'au relâcher d'Espace, sans
  quoi Espace tenu relance le tentacule dès qu'on lâche.
- **La borne de 18 000 octets du plus gros snapshot** : six champs de plus par chat donnent 20 854 ;
  la borne a été re-mesurée, pas forcée.
- **Le snapshot version 3** est né en 24a (la jauge) et s'est complété en 24b : aucun build n'a
  échangé la version partielle.
- **Les `const` d'un script de parcours ne sont pas hissés** : la section du tentacule, qui utilise
  `fits`, vit après la revue de clôture qui le définit.

### Ce qui reste ouvert

- **Q-03** (la durée des parties, 41,0 % à la limite des rondes), à l'utilisateur.
- **Le tentacule au téléphone** (H-09, H-11) : ▲ ▼ et le lance-pierre du tentacule ne sont vérifiés
  qu'en toucher émulé dans Chromium ; le build est servi sur le réseau local (`make serve`).
- **Le run D** (en ligne) : `docs/runs/run-d-en-ligne.md` ; le tentacule y passe déjà par le chemin
  ordinaire des entrées (scénario 24 du harnais).

### Après le run, à la demande de l'utilisateur

Après avoir joué le build, l'utilisateur a trouvé que le tentacule « ne permet pas de rebondir
facilement sur une paroi pour remonter au-dessus », « consomme beaucoup d'énergie », puis qu'« on ne
peut pas remonter ». Mesuré : quand l'ancre est plantée dans la face d'une paroi, la paroi coupe le
cercle de la corde, et le blob ne passe jamais au-dessus de son ancre de ce côté, quels que soient le
rebond et la poussée ; autour d'une ancre libre, il passait déjà par-dessus en 1 à 2 s. Tranché avec
lui, écrit dans SPEC §5.4 avant le code, les quatre mécaniques ensemble :

- **rester accroché coûte 3 points par tick** au lieu de 10 (~30 s de corde au lieu de 9), et un
  **lancer en l'air 100** au lieu de 300, pour enchaîner les prises ;
- **le balancier garde son élan** : la corde tendue, la vitesse perd seulement ce qui tirerait sur
  elle, avant le pas. Il perdait 22 à 30 % de sa hauteur par demi-oscillation, il en perd 3 à 10 %
  (retirer une seconde fois au point atteint ne changeait rien, mesuré sur un pendule seul : pas
  gardé). **Remonter en se balançant accélère** (la part tournante de la vitesse suit le rapport des
  longueurs), la poussée passe de 32 à 64 ;
- **il rebondit sur la terre à 90 %** au lieu de s'y arrêter ;
- **la corde descend à 4 px** au lieu de 16 (on remonte jusqu'à l'ancre), et **sauter depuis la
  corde ajoute l'élan d'un saut** (200 points, s'il les a ; sinon il lâche seulement).

Un test le prouve : au pied d'une falaise de 60 px, le blob accroche la face, remonte, saute, relance
en l'air (deux fois), puis lance vers le bas sur le dessus et s'y hisse, en 4 lancers, ~5,5 s et
1 700 points.

La relecture du premier jet (rebond à 60 %) a trouvé un **défaut sérieux** : le blob retenu contre
une paroi au-delà de sa corde accumulait de la gravité sans bouger (sa vitesse n'était plus le
déplacement obtenu), jusqu'à tomber à pleine vitesse au lâcher (177 PV pour 5 px de chute) et ne
plus franchir un pilier que la version d'avant franchissait. Corrigé : quand un axe est bloqué, la
vitesse de l'autre devient le déplacement qu'il a fait, et le rebond ne s'applique qu'à une vitesse
qui allait vers la terre (plus de −0 non plus). La relecture des quatre mécaniques en a trouvé deux
autres de la même famille : **laisser filer la corde** empilait la gravité dans une vitesse que le
blob ne prenait pas (il rebondissait jusqu'au plafond, ou mourait d'un saut à 4 px du sol), et
**coincé dans un angle, les deux axes bloqués**, pareil. Corrigés : la vitesse perd aussi ce qui
tirerait sur la corde au point atteint (ce second retrait, jugé inutile sur un pendule seul, sert
quand la corde s'allonge), tout axe arrêté qui n'a pas rebondi prend son déplacement réel, et la
vitesse accrochée est bornée à 3072 par axe en fin de tick (le déplacement réel pouvait la porter à
3282). Tests ajoutés : rebond exact et son miroir, rebond sur le sol, glissement le long d'un mur,
invariant de la corde à borne fixe (corde + 1 px), un blob immobile qui ne stocke pas de vitesse
(angle, pilier, corde qu'on laisse filer), le rapport des longueurs en laissant filer, le miroir
avec montée et descente de corde, la borne de vitesse après 900 ticks de pompage, le saut payé à
200 tout juste, le lancer en l'air avec 160 points.

Le repli de 3 s après un tir est gardé (après la grenade comme après le bazooka), et le clavier
aussi (Entrée saute, Espace tire).
