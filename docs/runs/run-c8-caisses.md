# Run C8 — les caisses et leurs armes · **fait**

Tranches 24w à 24z2 du plan TDD de `SPEC.md` §10.6. Demandé par l'utilisateur :

- « nouvelle évol quelques largage avec des trucs forts l'équivalent du mouton worms (un mini blob
  rigolo qu'on peut faire sauter quand on veut avec une limite comme dans worms), jetpack, grenade
  "banane" (des mini blob colorées qui explosent), appui aérien avec plein de bazooka sur zone
  dédiée, 1 largage au 3eme 6eme etc tour ? » ;
- « comme dans worms.. une boite larguée par avion qui tombe parachute sur la map, on peut ensuite
  aller dessus pour drop une arme/action ».

La proposition détaillée (ci-dessous) lui a été montrée ; il a répondu « go ». Les noms, les nombres
et le détail des règles sont nos choix, à corriger quand il aura joué.

---

## Ce qui est tranché

- **Le largage** (SPEC §5.10) : au 3e, 6e, 9e… tour de la partie, toutes équipes confondues, un avion
  lâche une caisse au-dessus d'une colonne tirée au hasard (flux `sim`), s'il y en a moins de 3 sur
  la carte. Elle descend sous parachute à 1,5 px par tick, dérive avec le vent, se pose ; le début
  du tour attend qu'elle soit posée.
- **Ramasser** : le blob actif qui touche la caisse, à tout moment de son tour, donne à son équipe
  une munition de l'arme qu'elle contient, tirée au hasard parmi les quatre. Une explosion fait
  sauter la caisse ; tombée dans le liquide, elle est perdue.
- **Les quatre armes** (SPEC §8.2), qu'on ne trouve que dans les caisses (0 munition au départ) :
  - le **Waddler** (genre `walker`) : un mini-blob posé aux pieds, qui marche seul, saute, fait
    demi-tour contre un mur ; Tirer pendant qu'il marche le fait sauter, sinon il explose au bout de
    10 s ;
  - le **jetpack** (genre `utility`, champ `jet` du chat) : 150 ticks de poussée, ▲ monte, ◀ ▶ de
    côté, Saut coupe le moteur ; il ne termine pas le tour ;
  - la **grappe** (`cluster`) : lancée comme la grenade, elle explose et projette 5 mini-blobs qui
    explosent au contact ;
  - l'**appui aérien** (genre `strike`) : on pose une cible sur la carte, 5 obus tombent en ligne
    au-dessus d'elle.
- **Les éclats** (`weapons.parts`) : les mini-blobs de la grappe et les obus de l'appui aérien sont
  des projectiles qu'on ne choisit pas, rangés à part dans le registre.
- **Les bots** ne vont pas chercher les caisses et ne jouent pas leurs armes.
- **À l'écran** : caisse en bois sous un parachute, avion, « +1 » et le nom de l'arme au ramassage,
  grille à dix cases (touches 7 à 9 et 0), boutons Boom (Waddler) et Strike (appui aérien), flamme et
  carburant du jetpack ; Touches passe à dix-sept commandes, en quatre colonnes.

## Les tranches

| # | Contenu | Le test qui l'ouvre | Vérifications |
|---|---|---|---|
| 24w | La grappe et l'appui aérien dans la sim et au serveur | 5 cratères de plus pour la grappe ; 5 cratères en ligne, symétriques, pour l'appui aérien ; un éclat ou une colonne hors carte refusés | test, lint, conformance |
| 24x | Le Waddler et le jetpack dans la sim et au serveur | le Waddler monte une marche, fait demi-tour, saute sur `fire` sans munition, ou à 10 s ; le jetpack monte une falaise de 40 px et s'épuise en 150 ticks | test, lint, conformance |
| 24y | Les caisses dans la sim | largage au 3e tour, `aiming` qui attend, ramassage, explosion, perte, au plus 3, snapshot en version 9 | test, lint, conformance (vecteurs ré-enregistrés), harnais, banc |
| 24z | Caisses, grappe et appui aérien à l'écran, grille, Touches | dans le build : la caisse, le parachute, « +1 », les mini-blobs, l'appui aérien posé d'un clic | test, lint, parcours |
| 24z2 | Waddler et jetpack à l'écran et au doigt | dans le build : le Waddler marche et saute sur Boom ; le jetpack monte, sa flamme et son carburant se voient | test, lint, parcours |

## Pièges déjà rencontrés, à ne pas redécouvrir

- **Chaque changement de la somme de contrôle ré-enregistre les vecteurs** : le dire, et vérifier que
  les parties rejouées sont les mêmes. Le largage tire sur le flux `sim` au début des tours 3, 6, 9… :
  toutes les parties changent à partir du 3e tour.
- **`make journey` et `make harness` recréent le Nakama du tunnel** depuis le dossier où on les
  lance, et `make web` met le build en ligne aussitôt (nginx sert `out/web`).
- **Une autre session charge parfois la machine** : les mesures à CPU ×4 du parcours se prennent
  quand la charge est sous 3.
- **Le mode test ne publie l'état qu'une fois par seconde** hors de la visée : compter les ticks
  distincts.
- **Une table Lua vide arrive en JSON comme `{}`** : lire les listes publiées avec `Object.values`.

## Bilan

Run conduit dans une session, une tranche après l'autre. Chaque
tranche a suivi le même chemin :
- la spec d'abord quand une décision changeait ;
- le test qui ouvre la tranche, vu rouge, puis le code ;
- la suite sous LuaJIT et Lua 5.1, et le lint ;
- une relecture du diff par un sous-agent contre SPEC.md, avec des mutants lancés sur une copie du
  dépôt, et ses constats corrigés avant le commit ;
- la vérification réelle (conformité sous les trois moteurs, banc, parcours), puis un commit.

**Écarts avec ce qui était tranché**, écrits dans SPEC :
- **Version du snapshot.** Elle monte d'un cran à chaque tranche qui change la forme de l'état
  (9, 10, 11) au lieu d'un seul cran à la fin. Un client d'une tranche ne lit donc jamais l'état
  d'une autre.
- **Ordre de la grille.** 7 la grappe, 8 l'appui aérien, 9 le Waddler, 0 le jetpack, dans l'ordre
  des tranches.
- **Un seul bouton d'action.** Il est à gauche de Saut et porte le mot Strike ou Boom. Deux boutons
  séparés se seraient chevauchés, même s'ils ne paraissent jamais ensemble.
- **Le parachute est rouge, pas rayé** : un objet en voxels n'a qu'une teinte.
- **La vue d'ensemble garde 32 px de ciel** au-dessus de la carte, centrée pour l'inclinaison de la
  caméra. Sans cette marge, sur ordinateur, l'avion et la caisse qui descend restaient hors de
  l'écran.
- **Touches en portrait sur deux colonnes de neuf** : dix-sept lignes ne tenaient pas sur une.
- **Le jetpack ne freine pas un blob déjà lancé plus vite** que sa poussée de côté.
- **La lave qui monte prend aussitôt une caisse**, qui ne compte plus pour les 3 du largage
  suivant.

### Ce qui a été mesuré

| Mesure | Valeur |
|---|---|
| Suite | 957 tests sous LuaJIT et Lua 5.1 (797 avant le run) ; lint propre |
| Conformité (`make conformance`) | 6 vecteurs, mêmes sommes sous LuaJIT, Lua 5.1 et Nakama. Ré-enregistrés à 24w et 24x avec les mêmes scripts, puis à 24y avec de nouveaux scripts (les caisses changent les parties dès le 3e tour). `quake` passe à la graine 10. Le nouveau vecteur `crates` (graine 105, 3 équipes de 3, 6 000 ticks) largue au moins 4 caisses, en ramasse au moins 4 et joue les quatre armes : la grappe et ses 5 mini-blobs, l'appui aérien et ses 5 obus, le Waddler déclenché, le jetpack allumé |
| Banc, 200 parties (`make bench N=200`) | 37,2 s, **0 erreur**. 29,5 % des parties à la limite des rondes (30,5 % avant), volcan 59,1 % (inchangé : les bots ne jouent pas les armes des caisses). 73,6 tours par partie, 2 007 tours passés par des bots à sec |
| Plus gros snapshot | 31 011 octets (graine 2, 8 équipes de 6, 19 rondes, 10 failles, 3 caisses), en version 11 (H-06) |
| Parcours des caisses (`make journey J=crates`) | 24 contrôles sur quatre parties d'entraînement (graines 120, 29, 110, 48 ; un uppercut dans le vide au 1er tour, la caisse au 3e). Vérifiés : l'avion et la caisse sous parachute à l'écran, la caméra sur elle, l'atterrissage, le ramassage et « +1 », « Cluster x1 » en 7e case, les 5 couleurs des mini-blobs, la croix et Strike sans ligne de visée, l'avion de l'appui aérien, le Waddler blanc et Boom, le blob qui monte au jetpack avec ses flammes et le carburant orange, Saut qui coupe le moteur, 0 divergence |
| Parcours complet (`make journey`) | **178 contrôles, aucun rouge**, mesures à CPU ×4 comprises (hors ligne, dynamite, caisses, touches, en ligne, séisme), sur l'état d'avant les corrections de la dernière relecture ; `J=offline` rejoué ensuite sur l'état final : 129 contrôles, aucun rouge |
| Harnais (`make harness`) | 94 contrôles, aucun rouge, après avoir porté à 11 la version du snapshot que cinq scénarios figeaient encore à 8 |

### Ce que les relectures ont trouvé

1. **24w** (37 mutants).
   - Le départ des éclats et des obus n'était vérifié par aucun test (11 mutants survivants).
   - La LocalAuthority ne transmettait pas la colonne visée.
   - `invalid_target` manquait à SPEC, et l'ordre de la liste des armes n'était pas figé.
2. **24x** (50 mutants).
   - La poussée de côté du jetpack freinait un blob déjà lancé plus vite.
   - 15 survivants, fermés par 13 tests : le pas de 3 px vers le bas, le rebond en l'air, le toit
     bas, la coupure du moteur au tentacule, ▼ sans effet, la poussée de côté qui brûle du
     carburant, le déclenchement en solo.
3. **24y** (49 mutants).
   - La lave qui monte laissait une caisse noyée compter pour les 3 du largage suivant.
   - 19 survivants, et 14 mutants que seuls les vecteurs voyaient, fermés par 22 tests.
4. **24z** (25 mutants).
   - Une ligne de visée s'affichait pour l'appui aérien au clavier.
   - Un appui hors de la carte gardait une colonne que le serveur refuse.
   - Le doigt immobile d'un pincement déplaçait la cible.
   - L'avion ne traversait pas la carte d'un bord à l'autre.
   - « +1 » avait une image de retard, et ses clones gardaient leur échelle après un
     redimensionnement.
   - Les légendes de Touches mordaient sur l'encoche.
   - 9 survivants, fermés par le premier test du routeur tactile.
5. **24z2** (18 mutants).
   - Au jetpack, la touche ↑ bougeait aussi la visée au clavier.
   - Lancer le tentacule en plein vol bloquait ▲ jusqu'à ce qu'on le relâche.
   - ▼ n'était plus grisé.
   - Boom pouvait partir deux fois.
   - Deux dépenses à chaque image : des messages enable/disable et un quaternion.
   - 3 survivants, fermés par 2 tests.

### Pièges rencontrés

- **Les caisses changent toutes les parties dès le 3e tour.** Les graines choisies pour une
  propriété tombent : le vecteur du séisme, la mort en fin de tour du test serveur, l'index du banc
  aux séismes meurtriers, les chiffres du plus gros snapshot. Les re-sonder, pas les forcer.
- **`timeout` tue le client docker, pas le conteneur.** Deux suites de tests bloquées ont tourné
  une heure en fond. Tuer le conteneur (`docker kill`).
- **Une partie finie n'avance plus de tick.** Un test qui attend un nombre de tours en se gardant
  par `w.tick` tourne sans fin si la partie se termine avant : se garder par un nombre
  d'itérations.
- **Les scénarios du harnais figent la version du snapshot** : la monter oblige à les mettre à jour
  (cinq à 8, oubliés jusqu'à la clôture).
- **Le script d'enregistrement des vecteurs n'écrivait pas `target`.** Le vecteur `crates` ne se
  rejouait donc pas à l'identique. Un nouveau champ d'entrée doit passer dans sa liste.
- **Un appui de souris sans déplacement avant** arrive à Defold à la dernière position connue (ici
  le bouton Lancer de l'écran précédent) : dans un parcours, passer par `page.tap`.
- **Une liste Lua vide arrive en JSON comme `{}`** : `Object.values` dans les parcours, encore.
- **Graines d'aujourd'hui** :
  - vecteurs : `crates` 105, `quake` 10 ;
  - parcours : grappe 120, appui aérien 29, Waddler 110, jetpack 48 ;
  - test serveur de la mort 2 ;
  - banc aux séismes meurtriers 11 ;
  - plus gros snapshot 2.

### Ce qui reste ouvert

- **Les bots** ne vont pas chercher les caisses et ne jouent pas leurs armes.
- **Pas vu au téléphone** : le parcours joue les quatre armes au clavier et à la souris. Le doigt
  (appui sur la carte, Boom, ▲ au jetpack) n'est vérifié que par les tests du routeur et des
  commandes.
- **En ligne**, les armes des caisses ne sont jouées que par les vecteurs de conformité et le
  harnais, pas par deux navigateurs.
- **Le Waddler** n'a pas d'animation gélatineuse, seulement son clignotement et ses sauts.
- **Les noms, nombres et règles sont nos choix**, à corriger quand l'utilisateur aura joué : la
  cadence, la force des armes, le carburant, le parachute.
