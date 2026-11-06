# Run C6 — la dynamite et les munitions · **fait**

Tranches 24r à 24t du plan TDD de `SPEC.md` §10.6. Demandé par l'utilisateur :

- « ajouter la dynamite elle se pose et on a le temps de bouger au moins 5 sec un petit moment quoi,
  elle est rouge rectangulaire avec le petit effet mèche, gros radius quand même et fait très mal si
  on est vraiment dedans (comme dans Worms) » ;
- « ensuite on limitera les armes par match, 1 seule dynamite, tentacule illimité, uppercut illimité,
  10 grenades, 10 bazookas, etc. (regarder un peu comment c'était dans Worms), que ce soit
  configurable facilement si on veut changer les seuils (pas par partie pour le moment, au global
  ok) ».

Lancé comme un /goal dans la session qui a clos le run C5 : l'état des runs A à C5, leurs mesures et
leurs pièges sont dans `docs/runs/` (bilans).

**Ce qui reste ouvert et ne se règle pas dans ce run** : les bots qui jouent tout (24j à 24m) ; ils
n'utilisent pas la dynamite (§9).

---

## Ce qui est tranché

- **Worms Armageddon** : la dynamite y a une mèche fixe de 5 s, et un ver collé à elle perd 65 à 75
  PV (une grenade ~45).
- **La dynamite** (`dynamite`, genre `placed`, SPEC §8.1, §8.2) : posée aux pieds du blob, sans visée,
  comme l'uppercut (seul le relâcher compte, Espace la pose aussitôt) ; un projectile sans vitesse
  qui tombe et rebondit à peine (restitution 20 %, frottement 50 %), insensible au vent, qui ne heurte
  que le terrain. Mèche fixe de 5 s (`timer`). Explosion : creuse 20 px, rayon 30 px, 75 dégâts,
  poussée 2304 FP/tick.
- **Le repli** : poser une arme posée mène droit au repli, sans vol, et le repli dure autant que la
  mèche (150 ticks) ; on marche et on saute pendant ce temps. `timer` compte le repli qui reste
  (§5.6), après un tir comme après la dynamite.
- **Les munitions** (§8.2), par équipe et par partie, dans une seule table de `rules.lua`
  (`AMMO`, `-1` = sans limite) : bazooka 10, grenade 10, tentacule et uppercut sans limite, Chomp 3,
  dynamite 1. Les modules des armes ne portent plus de munitions. Une arme épuisée quitte la grille ;
  le serveur répond `no_ammo`.
- **Les bots** ne posent pas la dynamite ; sans bazooka ni grenade, ils passent leur tour.
- **À l'écran** (§7.3, §7.4) : grille à six cases (deux colonnes de trois), touche 6 ; un bâton rouge
  en voxels, debout, avec une mèche sombre au sommet d'où jaillissent des étincelles jaunes et
  orangées.

## Les tranches

| # | Contenu | Le test qui l'ouvre | Vérifications |
|---|---|---|---|
| 24r | Munitions par partie (`rules.AMMO`), bots, banc | une équipe qui a tiré ses 10 bazookas ne peut plus en tirer ; tentacule et uppercut ne s'épuisent jamais ; un bot sans munitions de tir passe son tour | test, lint, conformance (vecteurs ré-enregistrés), harnais, banc (Q-03) |
| 24s | La dynamite dans la sim et au serveur | posée, elle explose 5 s plus tard, le blob a pu s'éloigner ; collé à elle, il perd au moins 65 PV ; une seule par partie | test, lint, conformance (un vecteur la pose), harnais (scénario en ligne) |
| 24t | La dynamite à l'écran et au doigt | grille à six cases, touche 6, bâton rouge et mèche qui crépite, dans le parcours | test, lint, parcours |

## Pièges déjà rencontrés, à ne pas redécouvrir

- **Chaque changement de la somme de contrôle ré-enregistre les vecteurs** (une sixième munition,
  `timer` qui compte le repli) : le dire, et vérifier que les parties rejouées sont les mêmes.
- **Les graines choisies pour leurs propriétés tombent** quand les bots manquent de munitions (des
  tours passés au lieu de tirs) : les re-sonder, pas les forcer.
- **Une autre session charge parfois la machine** : les mesures à CPU ×4 du parcours se prennent
  quand la charge est sous 3.
- **`make journey` recrée le Nakama du tunnel** depuis le dossier où on le lance.

## Bilan

Run conduit dans une seule session, une tranche après l'autre. Pour chaque tranche :
- la spec d'abord quand une décision changeait ;
- le test qui ouvre la tranche, vu rouge, puis le code ;
- la suite sous LuaJIT et Lua 5.1, et le lint ;
- une relecture du diff par un sous-agent contre SPEC.md, avec des mutants lancés sur une copie du
  dépôt, et ses constats corrigés avant le commit ;
- la vérification réelle (conformité, harnais, parcours), un commit, un push.

**Deux écarts avec ce qui était tranché**, écrits dans SPEC avant le code :
- **La pose remplit la jauge de déplacement** (§5.4, §5.6, §8.1). La relecture de clôture a montré
  qu'un blob qui a vidé sa jauge en marchant jusqu'à l'ennemi ne pouvait plus fuir : il avait les
  5 s, mais pas de quoi bouger. Posée après 150 px de marche, la dynamite le tuait sur place. Worms
  n'a pas de jauge ; l'utilisateur voulait « le temps de bouger ».
- **La dynamite se pose dans la colonne de pixels devant le centre du blob**, du côté où il regarde,
  et non au centre exact. Au centre exact, le souffle poussait toujours à gauche. Deux poses en
  miroir donnent maintenant des explosions en miroir, et le blob posé dessus part en arrière.

### Ce qui a été mesuré

| Mesure | Valeur |
|---|---|
| Banc, 200 parties (`make bench N=200`, après 24r, identique après 24s) | 24,3 s, **0 erreur**. 30,5 % des parties à la limite des rondes (20,0 % avant le run) : forêt 5,6 % (inchangé, le séisme finit les parties avant), **volcan 59,1 %** (36,6 % avant). 74,4 tours et 8,9 min simulées par partie. Les bots, qui ne tirent qu'au bazooka et à la grenade, passent 2 129 tours une fois à sec (3 avant). Dégâts par tir : 15,0 / 17,0 / 22,1 (facile, moyen, difficile) |
| La dynamite dans la sim | un blob posé dessus perd 67 PV au souffle, et la chute l'achève (mortel à 100 PV) ; un voisin à 6 px perd 60 PV. Dans le vecteur `dynamite`, le poseur, au bord du souffle, perd 27 PV ; un blob adverse en perd 66, puis se noie |
| Plus gros snapshot | 31 654 octets pour une forêt de 8 équipes de 6 après 18 rondes et 11 failles (graine 2, borné par un test entre 29 000 et 32 000), en version 8 (H-06) |
| Conformité (`make conformance`) | 5 vecteurs, mêmes sommes sous LuaJIT, Lua 5.1 et Nakama. Les quatre anciens sont ré-enregistrés deux fois (les munitions comptées, puis la sixième munition et `timer`), scripts d'entrées inchangés. Le nouveau, `dynamite` (graine 42), pose la dynamite au deuxième tour de l'équipe 1 ; un test vérifie qu'elle explose 150 ticks plus tard et touche deux blobs (il échoue sur une dynamite noyée) |
| Harnais (`make harness`) | 94 contrôles (86 avant). Le scénario 24s : un humain pose la dynamite, s'éloigne pendant le repli, un snapshot à mi-mèche la montre posée avec la mèche et le repli qui comptent le même temps, le bot ne joue qu'après la mèche et son début de tour, une deuxième dynamite est refusée (`no_ammo`), et toutes les sommes sont retrouvées sous LuaJIT et Lua 5.1 |
| Parcours de la dynamite (`make journey J=dynamite`, joué aussi par `J=offline`) | 7 contrôles, en forêt sur un sol plat (graine 376), à CPU ×4 : la sixième case « Dynamite x1 », ni ligne de visée ni minuterie au glisser, le bâton rouge vu à l'écran devant le blob (738 pixels rouges, 18 × 41), au moins 4 cubes d'étincelles à chaque instant, 11 cubes faits pour toute la mèche (le contrôle en tolère 40, sans réemploi ils seraient ~150), l'horloge 5, 4, 3, 2, 1 au rythme de la sim, le blob qui s'éloigne de 50 px avec la caméra sur lui (la jauge remplie à la pose), l'explosion à 150 ticks sans objet laissé, 6 puis Espace au clavier |
| Suite | 777 tests sous LuaJIT et Lua 5.1 (732 avant le run) ; lint propre |
| Parcours complet (`make journey`, état final) | **142 contrôles, aucun rouge sur une machine calme** : 86 hors ligne, 7 pour la dynamite, 40 en ligne et 9 pour le séisme. Le parcours entier, lancé à une charge de 1,6, a fini à 16–21 (une autre session) : 140 verts et 2 rouges de mesure, le tunnel du Chomp à CPU ×4 (p95 4,0000000000013 ms pour 4) et la crête de la secousse au 2e séisme dans le contexte à CPU ×4 (1,13 contre 1,14). Relancés sous une charge de 3 : `J=offline` 93 sur 93, `J=quake` 9 sur 9, failles en tranches de 3,0 ms au p95. En ligne : retour par le lien en 9,8 s, socket revenue en 2,7 s, aller-retour d'une entrée de 58 ms en moyenne, snapshot de 8 × 6 de 27 262 octets reçu par le client Defold |
| Build servi par le tunnel | le build de l'état final (4,66 Mo) sur **https://blobattle.npc.fm** : `Blobattle_wasm.js`, `Blobattle.wasm` et les archives y sont identiques au bit près à `out/web/Blobattle`, et Nakama tourne depuis le dépôt |

### Ce que les relectures ont trouvé

1. **24r** (21 mutants).
   - Un bloquant : le nouveau champ `shown.labels` entrait en collision avec le compte des
     étiquettes des blobs, d'où une erreur Lua à chaque changement de libellé. Il est renommé
     `weapon_labels`.
   - L'arme choisie changeait pendant le tour adverse.
   - Cinq mutants survivants, fermés par des tests : le Chomp qui ne dépense rien, l'autorité
     locale sans `no_ammo`, la liste sans repli, une arme hors liste acceptée, la grenade dépensée
     avant le contrôle de la mèche.
2. **24s** (29 mutants).
   - Sans couleur de tir, le rendu d'une dynamite plantait pendant 5 s chez tous les clients.
   - La marche tenue ne repartait pas dans le repli.
   - La pose n'était pas symétrique.
   - Le snapshot restait en version 7.
   - Deux tests de conformité tournaient sans fin si une partie finissait trop tôt.
   - Cinq mutants survivants, fermés par des tests.
3. **24t** (24 mutants).
   - Sur un sol plat, le bâton, sa mèche et ses étincelles étaient cachés dans le blob, opaque. Le
     parcours, sur une graine où le bâton glissait le long d'une falaise, ne le voyait pas ; il relève
     maintenant les pixels du bâton à l'écran.
   - Quatre contrôles du parcours trop faibles.
   - Douze mutants survivants, fermés par des tests.
4. **Clôture.**
   - Un bloquant : la marche tenue ne repartait toujours pas dans le vrai jeu. `game.script` passe
     aux commandes la même table, modifiée à chaque image, alors que le test en fabriquait une neuve
     à chaque appel. Le test reprend maintenant la table du jeu.
   - La jauge vide qui empêchait de fuir (voir plus haut).
   - Les cubes d'étincelles n'étaient pas vraiment réutilisés (88 faits pour une mèche à 60 i/s) :
     ils sont gardés avec leur étincelle et repris.
   - Les touches d'arme lisaient les munitions de l'équipe qui joue, pas celles du joueur.
   - Les docs : les touches « 1 à 5 », le repli de la dynamite, la dynamite mortelle avec la chute,
     comment changer un seuil, la couleur de tir d'une arme nouvelle, les bots à sec, H-04.
   - La relecture des corrections (13 mutants) : aucun défaut. Le contrôle des cubes d'étincelles
     était trop serré après une image lente ; la liste des tests qui figent les seuils était
     incomplète. Trois mutants survivants, fermés par un test : le recyclage des étincelles, leurs
     tables, leur couleur gardée.

### Pièges rencontrés

- **Un snapshot se demande au plus tous les 150 ticks** (`SNAPSHOT_REQUEST_TICKS`) : un scénario de
  harnais qui en demande deux trop près reçoit `too_soon`.
- **Une table Lua vide arrive en JSON comme `{}`**, pas `[]` : dans les parcours, lire les listes
  publiées avec `Object.values`.
- **Le mode test ne publie l'état qu'une fois par seconde** hors de la visée (ou quand l'état du tour
  change) : un parcours qui échantillonne plus vite relit le même état. Compter les ticks distincts.
- **Un blob tenu sur une pente par le bord de sa boîte** : la dynamite posée au milieu n'a pas de sol
  dessous et glisse le long de la pente. C'est la règle. Une graine de parcours à sol plat se choisit
  par un sondage de la sim, bots compris.
- **Un contrôle de données ne dit pas si un objet se voit** : le bâton était publié, teinte comprise,
  mais caché dans le blob. Relire les pixels de la capture.
- **Un test qui fabrique une table neuve à chaque appel** ne voit pas une comparaison entre une table
  et elle-même : reprendre la façon dont le jeu appelle le module.
- **`make harness` et `make journey` recréent le Nakama du tunnel** depuis le dossier où on les lance.
  Le tunnel a servi un moment un client de C5 face à un serveur de 24s, donc des parties en ligne qui
  divergeaient, jusqu'au `make web` suivant. Refaire le build juste après.
- **Une autre session charge la machine**, par bouffées : la charge passe de 1,6 à 16–21 en quelques
  minutes. Les mesures à CPU ×4 des runs précédents tombent alors, alors que ce run ne touche pas
  leur code : le tunnel du Chomp à 4,8 ms au p95, les failles à 5,3 ms, et la crête de la secousse,
  échantillonnée à chaque image, qui manque son maximum quand les images s'espacent. Relancer la
  partie concernée (`J=offline`, `J=quake`) sous une charge de 3, et le dire.
- **Graines d'aujourd'hui** :
  - vecteur `dynamite` 42 (deuxième tour de l'équipe 1) ;
  - harnais 24s 7 ;
  - parcours de la dynamite 376 (forêt, sol plat) ; la graine 7 cachait le bâton dans la pente ;
  - plus gros snapshot 2 ;
  - 10 bazookas sur une falaise de lave de 60 px.

### Ce qui reste ouvert

- **Les bots ne posent pas la dynamite**, et ne jouent ni l'uppercut ni le Chomp (24j à 24m, run C4).
- **Q-03** : avec les munitions comptées, 59,1 % des parties au volcan vont à la limite des rondes,
  parce que les bots à sec passent leur tour. Des bots qui jouent tout, ou des caisses d'armes (§13),
  y répondraient.
- **L'horloge montre 0 pendant l'arrangement** quand des dégâts ont coupé le repli alors que la
  dynamite brûle encore.
- **Une dynamite tombée dans l'eau** disparaît, munition dépensée, et le repli dure quand même 5 s.
- **Pas vu au téléphone**, et la dynamite n'est jouée en ligne que par le harnais et un snapshot, pas
  par deux navigateurs.
