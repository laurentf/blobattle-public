# ADR-001 — Defold et Lua de bout en bout, plutôt que le web TS, LÖVE ou Godot

Statut : accepté.

## Le contexte

Blobattle est un jeu d'artillerie au tour par tour, multijoueur, **pensé d'abord pour le téléphone**,
joué par un lien à travers un tunnel Cloudflare, puis distribué en APK Android, plus tard sur iOS et
Steam. Le serveur de jeu est Nakama, comme sur telegraph, clinch et npchero.

Dans un Worms, **la physique est tout le jeu** : trajectoire soumise au vent, rebonds, terrain qui se
creuse, chats projetés. Si le serveur la calcule dans un langage et que le client l'affiche dans un
autre, elle existe deux fois et il faut la tenir identique à la main. C'est le coût que telegraph paie
avec ses « formules recopiées » et ses vecteurs de conformité.

Le critère qui a tranché : **une seule simulation, exécutée telle quelle des deux côtés**, dans un
client qui sort nativement sur mobile, sur le web et sur desktop.

## Les options

| | Web TS + PixiJS | Defold (Lua) | LÖVE (Lua) | Godot 4 |
|---|---|---|---|---|
| Android / iOS | Capacitor (WebView) | exports natifs officiels | love-android ; iOS par Xcode | exports natifs officiels |
| Steam | Electron + steamworks.js | extension-steam | luasteam (Balatro) | GodotSteam |
| Jouer par un lien | PWA | export HTML5 officiel, léger | non (love.js arrêté en 2022) | export web (threads, COOP/COEP) |
| Client Nakama | nakama-js officiel | nakama-defold officiel | aucun ; WSS/TLS à compiler par plateforme | officiel |
| Sim partagée avec le serveur | TS ↔ runtime TS | Lua ↔ runtime Lua | Lua ↔ runtime Lua | non : GDScript ≠ TS/Lua |

## La décision

**Defold pour le client, le runtime Lua de Nakama pour le serveur, et une simulation en Lua pur
partagée par les deux.** Le même fichier `.lua` calcule une explosion sur le serveur et sur chaque
client.

- Defold sort d'un seul projet vers Android, iOS, HTML5, Windows, macOS et Linux ; il est minuscule,
  conçu pour le mobile et le web, maintenu par la Defold Foundation (1.13.1 stable en août 2026) dont
  Heroic Labs, l'éditeur de Nakama, et Poki sont partenaires.
- Nakama a un runtime Lua (gopher-lua, Lua 5.1) : les modules sont de simples fichiers, sans bundle.
- L'utilisateur voulait voir une stack « full Lua ».

## Pourquoi pas les autres

- **Web TS** : le chemin le plus rapide vers une première partie, sur une stack connue. Écarté parce
  que les apps natives et Steam sont un vrai objectif, et qu'une WebView reste une WebView.
- **LÖVE** : Balatro le prouve en solo, pas en réseau. Pas de client Nakama, pas de WebSocket chiffrée
  sans compiler LuaSec pour chaque plateforme, pas de web, et LÖVE 12 n'est pas sorti.
- **Godot** : excellent moteur, mais la physique serait écrite deux fois (GDScript côté client).

## Ce que ça coûte, et qu'on accepte

- Une stack nouvelle pour l'utilisateur : le modèle de Defold (collections, game objects, messages)
  et du Lua sans typage. L'infra TS de telegraph (bundle rollup, correctif goja) ne se réutilise pas.
- **Le déterminisme devient une discipline** (D-02) : trois moteurs Lua exécutent la sim — LuaJIT
  (Defold natif), Lua 5.1 (Defold HTML5) et gopher-lua (Nakama). Leurs fonctions mathématiques
  peuvent différer au dernier bit ; la sim n'en utilise donc aucune.
- Les extensions natives de Defold (WebSocket) se compilent sur le serveur de build de Defold : un
  build qui en dépend a besoin d'Internet.
- iOS exige un Mac ou une CI macOS et un compte Apple, comme avec n'importe quel moteur.

## Ce qui remettrait la décision en cause

- Le runtime Lua de Nakama ne tient pas 30 Hz pour quelques parties simultanées (mesuré au run B).
- nakama-defold ou extension-websocket cessent d'être maintenus et cassent sur une version de Defold.
- Le déterminisme entre les trois moteurs Lua se révèle intenable malgré D-02.
