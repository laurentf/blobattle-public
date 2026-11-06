# Run C4 — des poutrelles partout au volcan, des bots qui jouent tout

Tranches 24i à 24m du plan TDD de `SPEC.md` §10.6, après le run C3 (fait) et avant le run D (en
ligne). Demandé par l'utilisateur après avoir joué le build du run C3 : « pour les
poutrelles côté volcan il en faut un peu plus à différentes hauteurs, on peut pop dessus » ; « les
bots doivent utiliser tout ce qu'il faut : avancer si besoin, tentacule, creuser pour se protéger, le
coup corps à corps, grenade ou bazooka » ; puis « la lave peut monter de suite ». Tranché avec lui dans la foulée : **les trois niveaux
utilisent tout**, le facile essaie moins d'options et vise plus mal, le difficile en essaie plus.

**Avant de lancer** : `/clear` si le run se fait dans une nouvelle session. L'état des runs A à C3,
leurs mesures et leurs pièges sont dans `docs/runs/` (bilans), en particulier les graines choisies
pour leurs propriétés (`docs/runs/run-c3-armes-cartes.md`).

**Ce qui reste ouvert et ne se règle pas dans ce run** : Q-03 (la durée des parties) — le banc dira ce
que des bots plus mobiles y changent ; ne toucher ni aux armes, ni aux PV, ni aux rondes.

---

## Ce qui est déjà tranché et ne se rediscute pas dans ce run

- **L'intro** (§7.2), demandée en cours de run : le logo du studio **Panis Vult** (`panisvult.png`,
  fourni) tremble de plus en plus fort, façon « Deus Vult intensifies », puis le logo rond de
  Blobattle, puis l'Accueil ; 6,5 s, qu'un appui passe. Le studio d'abord, le jeu ensuite, comme
  d'usage.
- **La lave du volcan monte dès la fin de la première ronde** (2 px par ronde, au lieu de dès la 5e).
- **Les poutrelles** (§5.3) : plus nombreuses (une tous les 40 à 90 px entre les rives), à des
  hauteurs variées (12 à 56 px au-dessus du plus haut sol sous elles), posées avant les apparitions ;
  un chat peut apparaître dessus (elles comptent comme un sol, pas les arbres).
- **Un bot joue un plan** (§9) : au lieu d'un seul tir, il choisit une suite d'actions pour son tour —
  marcher jusqu'à une place, se tourner, puis tirer, frapper, manger ou lancer le tentacule — et
  l'exécute par les entrées ordinaires (D-06 : `move`, `jump`, `climb`, `fire`), une par tick au plus.
  Il évalue tout sur le terrain courant, en lecture seule : sa marche, son saut et son tentacule sont
  simulés sur un fantôme de son blob ; le Chomp se prévoit par la géométrie (40 px dans la direction
  visée), sans creuser.
- **Les options** d'un tour, toutes notées sur la même échelle que les tirs (dégâts aux ennemis,
  morts, dégâts à son camp et à soi) :
  - tirer d'ici (la recherche de toujours) ;
  - marcher jusqu'à une place accessible à gauche ou à droite (quelques places, dans la jauge, sans
    tomber dans le liquide ni se blesser en tombant), puis tirer de là ;
  - frapper à l'uppercut un ennemi à portée, d'ici ou après quelques pas, la projection simulée (un
    ennemi envoyé dans le liquide compte comme tué) ;
  - manger (Chomp) pour se mettre à couvert quand aucune attaque ne touche d'ennemi et que le blob est
    à découvert, ou pour s'éloigner de la lave qui va monter ;
  - lancer le tentacule pour gagner une place plus haute quand la lave va monter ou qu'aucune place
    à pied ne permet d'attaquer, puis attaquer de là dans le même tour (le tentacule ne termine pas le
    tour).
- **Le budget ne change pas** : 300 unités de travail par tick, décision au plus tard après 3 s de
  visée ; les options se partagent les candidats du niveau. Hors ligne comme en ligne, un bot joue
  pareil (D-06).
- **Les niveaux** : même palette d'options pour les trois ; le facile essaie moins de places et de
  candidats et garde son bruit de visée, le difficile en essaie plus et affine.

## Les tranches

| # | Contenu | Le test qui l'ouvre | Vérifications |
|---|---|---|---|
| 24i | Volcan : poutrelles plus nombreuses, à hauteurs variées, apparition dessus ; la lave monte dès la 1re ronde | sur 200 graines × 7 réglages, les garanties de §5.3 tiennent, les poutrelles ont leurs hauteurs et des chats apparaissent dessus ; la lave monte à la fin de la 1re ronde | test (génération), lint, conformance (vecteurs), harnais et parcours (graines re-sondées), banc |
| 24n | L'intro : le studio Panis Vult qui tremble, puis le logo du jeu, puis l'Accueil (demandée en cours de run, faite avant 24j) | au lancement, le logo du studio tremble de plus en plus fort, puis le logo du jeu, puis l'Accueil ; un appui la passe | test (le déroulé), lint, parcours (captures des deux logos, le saut au clic) |
| 24j | Le plan d'un bot, la marche : tirer d'une meilleure place | un bot sans tir d'ici marche jusqu'à la place d'où il touche, puis tire ; il ne marche jamais dans le liquide | test, lint, conformance, harnais, parcours, banc |
| 24k | L'uppercut des bots | un bot au contact d'un ennemi au bord du liquide l'y envoie à l'uppercut ; il ne frappe jamais un allié | idem |
| 24l | Le Chomp des bots : à couvert, loin de la lave | un bot à découvert sans attaque se met à couvert en mangeant ; au volcan, un bot que la lave va atteindre s'en éloigne | idem |
| 24m | Le tentacule des bots | un bot au fond d'un creux que la lave va noyer en sort au tentacule, puis attaque dans le même tour | idem |

## Pièges déjà rencontrés, à ne pas redécouvrir

- **Chaque changement de la carte ou des bots ré-enregistre les vecteurs** et fait tomber les graines
  choisies pour leurs propriétés : les re-sonder, pas les forcer, et une sonde rejoue les minutages
  du vrai chemin. Graines d'aujourd'hui (après 24i) : tentacule 244 à l'angle 176, Chomp 244,
  uppercut 148 au harnais (il marche 44 ticks) et 121 au parcours (deux équipes de quatre : le joueur
  joue d'abord et atteint un ennemi en ~32 ticks de marche), lave du harnais 7, partie entière du parcours 922 (une
  forêt : le bot joue d'abord, l'ennemi est visible à gauche), lave du parcours 6 (un volcan à deux
  équipes d'un blob, le joueur laisse filer ses tours), lecture du client 70, banc index 3 ;
  inchangées depuis le run C3 : autorité locale 7, mort par les PV au serveur 5, duel des vecteurs
  1240 (il finit avant le tick 2400), cartes 4242.
- **Le budget des bots se mesure dans Nakama** (gopher-lua : un appel de fonction coûte cher) et hors
  ligne dans le build HTML5 à CPU ×4.
- **Un fantôme n'est pas le monde** : il ne voit ni les autres blobs, ni les projectiles (D-06 : le
  bot évalue sur le terrain courant, en lecture seule).
