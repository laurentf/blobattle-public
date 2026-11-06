# Run C7 — les touches au choix · **fait**

Tranches 24u et 24v du plan TDD de `SPEC.md` §10.6. Demandé par l'utilisateur, en
tête d'un lot d'évolutions : « la priorité pouvoir choisir ses touches sur PC très important, go !
garde ça comme le nom équipe etc ».

---

## Ce qui est tranché

- **Treize commandes, une touche chacune** (§7.3) : marcher à gauche, à droite, monter et baisser
  l'angle (accroché, la corde), tirer, sauter, la minuterie, et les six cases de la grille. Une
  touche ne sert qu'à une commande : en choisir une déjà prise échange les deux. La souris ne change
  pas.
- **Defold ne change pas ses liaisons en cours de route** : `game.input_binding` lie chaque touche
  qu'on peut choisir à une action qui porte son nom (`key_space`, `key_a`…), et une table du client
  (`client/input/keymap.lua`) mène chaque touche à sa commande. Une spec vérifie que le fichier de
  liaisons et la table disent les mêmes touches.
- **Gardé sur l'appareil** comme le profil : un fichier de sauvegarde `keys`, écrit à chaque
  changement. Une sauvegarde illisible, incomplète, ou dont deux commandes partagent une touche rend
  les touches par défaut.
- **Les touches qu'on ne choisit pas** : Échap (il annule un choix, et ramène de Touches à
  l'Accueil), Tab, F1 à F12, les touches Windows, les verrouillages.
- **Les noms des touches** : du catalogue (`key.*`) ; en HTML5, pour la ponctuation seulement, le
  caractère que le navigateur lit au moment du choix quand la touche en écrit un seul, ASCII et
  visible. Le build HTML5 de Defold 1.13.1 lit la ponctuation par `event.code`, la place de la
  touche sur un clavier QWERTY : sur un clavier AZERTY, le M arrive comme `KEY_SEMICOLON`, et le nom
  lu au navigateur affiche quand même M. Les lettres et les chiffres viennent de `event.keyCode`,
  comme sur la touche : ils gardent le nom du catalogue (le 1 d'un AZERTY écrit `&`).
- **L'écran Touches**, depuis l'Accueil, dont le bouton paraît sans écran tactile ou dès qu'une
  touche a été pressée. Trois colonnes de cinq à 844×390, des cases de 56 points (D-10 : 44 points
  sur le téléphone de 667×375, que `targets_spec` mesure) ; une colonne en portrait. Le bouton de
  l'Accueil est en bas à droite, après Multi : le titre en voxels occupe tout le haut.

## Les tranches

| # | Contenu | Le test qui l'ouvre | Vérifications |
|---|---|---|---|
| 24u | Les touches liées à des actions génériques, la table, sa sauvegarde ; la partie et l'intro la lisent | une sauvegarde où Tirer est sur X fait tirer X et plus Espace ; deux commandes sur une touche rendent les touches par défaut | test, lint, parcours (les touches par défaut jouent comme avant) |
| 24v | L'écran Touches, son bouton à l'Accueil, le catalogue | dans le build, sur ordinateur, Tirer passe sur X depuis Touches, le reste après un rechargement, et X tire en partie | test, lint, parcours |

## Bilan

Run conduit dans une seule session : la décision, les tranches 24u et 24v, puis
cette clôture. 797 tests sous LuaJIT et Lua 5.1, lint propre ;
parcours `J=keys` vert (12 contrôles) ; parcours hors ligne vert avec les touches par défaut, sauf
une mesure de performance (ci-dessous).

**Écarts avec ce qui était tranché**, écrits dans SPEC avant le code :
- **Le nom lu au navigateur ne vaut que pour la ponctuation.** Lu pour toutes les touches, il aurait
  affiché `&` pour le 1 d'un AZERTY, et `é` (hors de la police) pour le 2.
- **Trois colonnes de cinq, et non deux de sept.** Sept lignes ne tiennent pas en 390 points avec
  des cases de 56 ; `targets_spec` a refusé la première mise en page (cases de 36 points, un bouton
  sous l'encoche).

## Pièges déjà rencontrés, à ne pas redécouvrir

- **`make journey` met le build en ligne** : nginx sert `out/web/Blobattle` du dépôt, si bien que
  chaque build du parcours est aussitôt sur https://blobattle.npc.fm.
- **La mesure des cratères à CPU ×4** (5 ms au p95 pour 4) tombe quand la machine est chargée : le
  Chromium du parcours prend une douzaine de cœurs, et un jeu tournait à côté (charge de 15 à 19).
  Elle se reprend quand la charge est sous 3.
- **Un `.gui` ne doit pas porter une case de touche plus basse que 56 points** en paysage :
  `targets_spec` ne voit que les boutons de `BUTTONS`, et les lignes clonées sont vérifiées par le
  parcours (`lowest`).
