# Conventions

Les règles d'écriture du code sont dans **`CLAUDE.md`** et ne sont pas recopiées ici. Ce document
couvre ce qui n'est écrit nulle part ailleurs : **comment un changement traverse le dépôt**.

---

## 1. Le cycle d'un changement

Dans cet ordre, et l'ordre est le fond du sujet.

1. **La décision d'abord.** Si le changement touche une décision numérotée, une règle de jeu (§5), la
   grammaire des armes (§8), le protocole (§6.4) ou le périmètre, le document change **avant** le
   code — `SPEC.md` ou `V0.md`. Un code qui contredit un document en silence est une dette qui se
   paie au prochain lecteur, qui appliquera le document.
2. **Le test ensuite, et on le regarde échouer.** Un test écrit après le code passe du premier coup,
   ce qui ne prouve rien.
3. **Le code, juste assez pour le faire passer.**
4. **La vérification réelle.** La suite verte prouve que ce qu'on a pensé à tester marche. Pour la
   sim, c'est le banc et les vecteurs de conformité. Pour le serveur, le harnais contre un vrai
   Nakama. Pour le client, le parcours dans le navigateur, et au run E le téléphone de
   l'utilisateur. Une hypothèse de SPEC §3 vérifiée ou démentie est reportée dans le tableau, avec
   le résultat.
5. **Le commit**, avec la suite, `luacheck` et `stylua --check` propres.

## 2. Les messages de commit

En **français**, comme les documents. Le code et les commentaires restent en anglais.

Un sujet en minuscules, préfixé par le sujet touché : `socle :`, `sim :`, `carte :`, `armes :`,
`bots :`, `protocole :`, `serveur :`, `client :`, `rendu :`, `commandes :`, `outils :`, `décision :`,
`docs :`, `revue de clôture :`. Court et parlant.

Le corps répond à **pourquoi**, pas à quoi. Ce qui mérite d'y être :

- **Ce qui a été mesuré.** « la plus grande carte se génère en 41 ms sous LuaJIT, 380 ms sous
  Lua 5.1 » vaut mieux que « la génération est rapide ».
- **Ce qui a cassé en chemin**, y compris de notre fait.
- **La décision citée** : `(D-02)`, `(§5.5)`.

Pas de trailer `Co-Authored-By`. Pas de « fix », « wip », « refacto » seuls.

## 3. Ce qu'on vérifie avant de committer

```bash
make test          # busted sous LuaJIT puis sous Lua 5.1
make lint          # luacheck + stylua --check
```

Et selon ce qui a changé : `make conformance` (la sim), `make bench` (règles, armes, bots),
`make harness` (serveur), `make journey` (client).

Le nombre de tests ne doit **jamais baisser**. S'il baisse, un test a disparu.

## 4. Où va ce qui est factorisé

Une répétition se retire vers **le propriétaire de la chose**, jamais vers un fourre-tout. Pas de
`utils.lua`, `helpers.lua` ni `common.lua` : un calcul de distance entière va dans
`shared/sim/fixed.lua`, un test de cellule pleine dans `shared/sim/terrain.lua`, une conversion
d'écran en monde dans la caméra du client. Deux fonctions de même forme qui disent des choses
différentes restent deux.

## 5. La langue

| quoi | langue |
|---|---|
| code, noms, commentaires, `CLAUDE.md` | anglais |
| `SPEC.md`, `V0.md`, `docs/`, ADR | français |
| messages de commit | français |
| textes du jeu | `fr` et `en`, par identifiant (D-11) |

## 6. Les runs

Un run est une session de travail cadrée par un prompt versionné dans `docs/runs/`. La conduite est
dans `V0.md` §4 : contexte propre entre deux runs, et **une revue de clôture par un sous-agent à la
fin de chaque run**, contre `SPEC.md`, `CLAUDE.md` et `V0.md`. À la fin d'un run, son fichier passe
à **fait**, avec ce qui a été mesuré et les pièges rencontrés, pour que le run suivant ne les
redécouvre pas.

## 7. Les dépendances

Chaque outil ou bibliothèque est épinglé : images Docker par digest, `bob.jar` par version, les
dépendances Defold de `game.project` par version de release, les paquets npm du harnais par
`package-lock.json`. Une montée de version est un commit à part, qui dit ce qui a été revérifié.
