# Installer Blobattle : instructions pour un agent

Tu es l'agent de quelqu'un qui veut héberger Blobattle sur sa machine. Ton travail : installer le jeu
en conteneurs Docker, le rendre jouable, puis dire à ton utilisateur l'adresse du jeu. Tu ne
développes pas le jeu. `CLAUDE.md` et `SPEC.md` décrivent le développement, tu n'en as pas besoin
ici.

`docs/heberger.md` est le même guide écrit pour un humain. Ce fichier-ci le découpe en étapes
vérifiables. En cas de doute, c'est `docs/heberger.md` qui fait foi.

Toutes les commandes se lancent à la racine du dépôt.

## Règles

1. **Les secrets ne sortent jamais.** Sont secrets : `.env`, le dossier `cloudflared/` et
   `~/.cloudflared/cert.pem`.
   - Ne jamais les afficher, ni les recopier dans la conversation, ni les committer, ni les envoyer
     où que ce soit.
   - Pour vérifier `.env`, compter les lignes remplies, sans lire les valeurs.
2. **Ne modifie rien du dépôt.** Ni le code, ni `compose.yaml`, ni le `Makefile`, ni
   `tools/tunnel/config.example.yml` : tout se règle dans `.env`. Ne committe pas, ne pousse pas.
   Si une étape semble demander une modification, arrête-toi et explique pourquoi à ton
   utilisateur.
3. **Demande avant d'agir hors du dépôt** :
   - installer un paquet ;
   - ouvrir un port au pare-feu ;
   - toucher la configuration d'un reverse proxy existant ;
   - créer un tunnel ou un enregistrement DNS ;
   - lancer une commande avec `sudo`.

   Si `sudo` demande un mot de passe, ton shell ne peut pas le taper : donne la commande à ton
   utilisateur pour qu'il la lance lui-même.
4. **Le pare-feu** :
   - Ne lance jamais `ufw enable` : sans règle pour SSH, ton utilisateur perdrait l'accès à sa
     machine. Si `sudo ufw status` dit `inactive`, n'y touche pas.
   - Les ports que Docker publie passent de toute façon à côté d'ufw. Celui qui compte, c'est le
     pare-feu de l'hébergeur, dans son interface web.
5. **Ne lance jamais `docker compose down -v`** sans accord explicite : cette commande efface les
   comptes des joueurs.
6. **Les commandes longues** : `make tools` (plusieurs minutes, environ 3 Go à télécharger) et
   `make web`. Donne-leur un délai de 20 minutes, ou lance-les en arrière-plan.
7. **Pas de commande de développement.** `make journey`, `make harness`, `make bench`, `make test`
   et `make conformance` ne servent pas à héberger. `make journey` et `make harness` redémarrent même
   le serveur de jeu.

## Étape 0 : ce qu'il faut demander à ton utilisateur

Demande ces informations au début, en une seule fois.

1. **Quelle façon de servir le jeu ?**
   - **A, en http** : sur le réseau local, ou sur un serveur sans nom de domaine. C'est le plus
     simple. L'adresse sera `http://<ip>:5380`.
   - **B, par un tunnel Cloudflare** : il faut un domaine dont Cloudflare gère le DNS. Aucun port à
     ouvrir.
   - **C, en https avec le Caddy du dépôt** : le choix pour un VPS. Il faut un domaine qui pointe
     vers la machine, et les ports 80 et 443 libres et ouverts. Le certificat se fait tout seul.
   - **D, derrière son propre reverse proxy** : seulement si nginx, Caddy ou Traefik tient déjà les
     ports 80 et 443 de la machine.

   Pour savoir si la façon D s'impose, regarde toi-même ce qui écoute :
   `ss -ltnp | grep -E ':(80|443)\b'`.
2. **Pour B, C ou D**, le nom complet du jeu, par exemple `jeu.example.org`.
3. **Pour A ou C sur un serveur public**, s'il accepte d'ouvrir les ports au pare-feu : 5380 et
   7550 pour A, 80 et 443 pour C.

## Étape 1 : les prérequis

```sh
uname -m                     # x86_64 attendu
docker compose version       # v2 ou plus
docker info > /dev/null && echo docker-ok
command -v git make openssl curl
df -h .                      # au moins 5 Go libres
free -m                      # 1 Go de mémoire suffit (mesures dans docs/heberger.md)
ss -ltn | grep -E ':(5380|5438|7550|7551)\b' || echo ports-libres
ss -ltn | grep -E ':(80|443)\b' || echo 80-443-libres    # façon C seulement
```

| Résultat | Que faire |
|---|---|
| `uname -m` donne autre chose que `x86_64` (ARM) | Le serveur de jeu tourne sur ARM, mais pas la construction du jeu web. Dis à ton utilisateur de construire le jeu sur un PC x86-64 (étape 3, dernier paragraphe). Continue sans `make tools` ni `make web`. |
| `docker` n'existe pas | Sur un VPS neuf, le script officiel installe Docker et Compose : `curl -fsSL https://get.docker.com \| sh`, puis `sudo usermod -aG docker $USER`. Demande l'accord de ton utilisateur avant, c'est du `sudo`. Ensuite **arrête-toi** : le groupe ne compte qu'après une reconnexion. Ton utilisateur se reconnecte et te relance, et tu reprends à l'étape 1. |
| `docker info` échoue sur une permission | L'utilisateur n'est pas dans le groupe `docker`. Donne-lui `sudo usermod -aG docker $USER`, puis arrête-toi jusqu'à sa reconnexion. Ne contourne pas en mettant `sudo` devant chaque commande. |
| Façon C : le port 80 ou 443 est pris | Un proxy tourne déjà : c'est la façon D. |
| `git`, `make` ou `openssl` manque | Demande l'accord de ton utilisateur pour l'installer. |
| Le port 5380 est pris | Plus tard, mets un autre port dans `WEB_PORT` de `.env`. |
| Le port 7550, 7551 ou 5438 est pris | Arrête-toi et dis-le : ces ports sont fixes. |

## Étape 2 : `.env`

```sh
test -e .env && echo "ATTENTION : .env existe déjà"
```

Si `.env` existe déjà, ne l'écrase pas : demande à ton utilisateur. Sinon :

```sh
cp .env.example .env
sed -i "s/^UID=.*/UID=$(id -u)/; s/^GID=.*/GID=$(id -g)/" .env
for k in SERVER_KEY HTTP_KEY SESSION_KEY REFRESH_KEY CONSOLE_PASSWORD CONSOLE_SIGNING_KEY; do
  sed -i "s/^NAKAMA_$k=$/NAKAMA_$k=$(openssl rand -hex 32)/" .env
done
grep -cE '^NAKAMA_[A-Z_]+=.+' .env    # 6 attendu
```

Puis règle les adresses d'écoute selon la façon choisie :

| Façon | Commande |
|---|---|
| A | `sed -i 's/^WEB_BIND=.*/WEB_BIND=0.0.0.0/; s/^NAKAMA_BIND=.*/NAKAMA_BIND=0.0.0.0/' .env` |
| B, C ou D | `sed -i 's/^WEB_BIND=.*/WEB_BIND=127.0.0.1/; s/^NAKAMA_BIND=.*/NAKAMA_BIND=127.0.0.1/' .env` |
| C, en plus | `sed -i 's/^DOMAIN=.*/DOMAIN=jeu.example.org/' .env`, avec le nom donné à l'étape 0 |

Si le port 5380 était pris : `sed -i 's/^WEB_PORT=.*/WEB_PORT=<port libre>/' .env`.
Vérifie sans afficher les clés : `grep -E '^(UID|GID|WEB_BIND|WEB_PORT|NAKAMA_BIND|DOMAIN)=' .env`.

## Étape 3 : le jeu web

```sh
make tools          # long, une seule fois
make web            # attendu : « 📦 HTML5 build: … bytes in out/web/Blobattle »
test -f out/web/Blobattle/index.html && echo build-ok
```

- **Si `make web` échoue**, les 40 dernières lignes de `out/web-build.log` s'affichent.
  - La construction a besoin d'Internet : le serveur de build de Defold compile les extensions
    natives.
  - `missing from .env` veut dire qu'une clé est vide : reviens à l'étape 2.
  - `Killed`, le code 137 ou `OutOfMemoryError` veulent dire que la mémoire manque. Ça n'arrive pas
    avec 1 Go libre. Propose de construire sur un PC (ci-dessous), ou d'ajouter du swap, avec
    l'accord de ton utilisateur.
- **Sur une machine ARM**, ou si la construction échoue sur la machine, demande à ton utilisateur
  de faire ceci sur un PC x86-64 :
  1. cloner le dépôt, puis `cp .env.example .env` ;
  2. dans ce `.env`, mettre `NAKAMA_SERVER_KEY` à la même valeur que sur le serveur, et rien
     d'autre ;
  3. lancer `make tools web` ;
  4. copier le résultat : `rsync -a --delete out/web/ <serveur>:<dépôt>/out/web/`.

  Ne lui fais pas copier tout le `.env` du serveur : les cinq autres clés n'ont rien à faire sur
  le PC. Attends que `out/web/Blobattle/index.html` existe sur le serveur.

## Étape 4 : démarrer

### Façon A

```sh
make site
make up             # x86-64 seulement ; attendu : 5 lignes ✅, aucune ❌
curl -s http://127.0.0.1:7550/healthcheck    # attendu : {}
echo "http://$(hostname -I | awk '{print $1}'):5380"
```

Sur un serveur public, ton utilisateur ouvre les ports 5380 et 7550 en TCP au pare-feu de son
hébergeur (règle 4). Si `WEB_PORT` a changé, le jeu est sur ce port au lieu de 5380.

### Façon B : le tunnel Cloudflare

Remplace `jeu.example.org` par le nom donné à l'étape 0. Avant chaque commande `cf tunnel`, dis à
ton utilisateur ce qu'elle va faire sur son compte Cloudflare.

`cf` lance le cloudflared du dépôt. Une fonction shell ne survit pas d'une commande à l'autre : lance
chaque bloc ci-dessous **en une seule commande**, avec sa ligne `cf()`.

```sh
mkdir -p cloudflared ~/.cloudflared && chmod 700 cloudflared ~/.cloudflared
```

1. **La connexion au compte** attend que ton utilisateur se connecte dans un navigateur. Si
   `~/.cloudflared/cert.pem` existe déjà, saute ce point.

   ```sh
   cf() { docker compose --profile tunnel run --rm --no-deps -e HOME=/tmp \
     -v "$HOME/.cloudflared:/tmp/.cloudflared" -v "$PWD/cloudflared:/out" blobattle-cloudflared "$@"; }
   cf tunnel login
   ```

   1. Lance ce bloc en arrière-plan.
   2. Lis dans sa sortie l'URL qui commence par `https://dash.cloudflare.com/argotunnel`.
   3. Donne cette URL à ton utilisateur : il l'ouvre et choisit son domaine.
   4. Attends que `~/.cloudflared/cert.pem` existe et que la commande se termine.
2. **Le tunnel et sa route DNS** :

   ```sh
   cf() { docker compose --profile tunnel run --rm --no-deps -e HOME=/tmp \
     -v "$HOME/.cloudflared:/tmp/.cloudflared" -v "$PWD/cloudflared:/out" blobattle-cloudflared "$@"; }
   cf tunnel create --credentials-file /out/blobattle.json blobattle
   cf tunnel route dns blobattle jeu.example.org
   ```

   - **Si un tunnel `blobattle` existe déjà sur le compte**, demande à ton utilisateur avant d'aller
     plus loin.
     - S'il ne sert nulle part ailleurs, récupère ses identifiants au lieu de le créer :
       `cf tunnel token --cred-file /out/blobattle.json blobattle`.
     - Sinon, prends un autre nom, par exemple `blobattle-2`, dans `create` et dans `route dns`. Garde
       le fichier `/out/blobattle.json` : la configuration attend ce chemin.
   - **Si un enregistrement DNS existe déjà pour ce nom**, `route dns` échoue : demande à ton
     utilisateur.
3. **La configuration** :

   ```sh
   cp tools/tunnel/config.example.yml cloudflared/config.yml
   id=$(grep -o '"TunnelID":"[^"]*"' cloudflared/blobattle.json | cut -d'"' -f4)
   test -n "$id" || { echo "TunnelID introuvable dans cloudflared/blobattle.json"; exit 1; }
   sed -i "s/TUNNEL_ID/$id/" cloudflared/config.yml
   chmod 600 cloudflared/config.yml && chmod 400 cloudflared/blobattle.json
   ```

4. **Démarrer et vérifier** :

   ```sh
   make tunnel
   make up             # x86-64 seulement ; 5 lignes ✅
   docker compose --profile tunnel logs blobattle-cloudflared | grep -c "Registered tunnel connection"   # 1 ou plus
   curl -s https://jeu.example.org/healthcheck                      # attendu : {}
   curl -s -o /dev/null -w '%{http_code}\n' https://jeu.example.org/   # attendu : 200
   ```

Si `curl` ne trouve pas le nom, c'est que le cache DNS de la machine garde l'absence du nom, demandé
avant que la route existe. Attends quelques minutes, ou passe l'IP à `curl` toi-même :
`curl --resolve jeu.example.org:443:<ip> …`, avec une IP donnée par la requête DNS de la façon C
ci-dessous.

### Façon C : en https avec le Caddy du dépôt

Vérifie d'abord que le domaine pointe vers la machine. Cette requête DNS ne passe que par `curl`,
sans `dig` :

```sh
d=jeu.example.org
for t in A AAAA; do
  echo "$t: $(curl -s -H 'accept: application/dns-json' "https://cloudflare-dns.com/dns-query?name=$d&type=$t" \
    | grep -o '"data":"[^"]*"' | cut -d'"' -f4 | tr '\n' ' ')"
done
echo "IPv4 de la machine : $(curl -s -4 https://ifconfig.me)"
echo "IPv6 de la machine : $(curl -s -6 -m 5 https://ifconfig.me)"
```

- `A` doit donner l'IPv4 de la machine.
- `AAAA` doit être vide, ou donner son IPv6. Un ancien `AAAA` laissé par le registrar suffit à faire
  échouer Let's Encrypt.

Sinon, ton utilisateur crée ou corrige ces enregistrements chez son registrar. Refais la requête
jusqu'à ce qu'elle soit juste : Let's Encrypt échoue tant que ce n'est pas le cas.

Ton utilisateur ouvre ensuite les ports 80 et 443 en TCP au pare-feu de son hébergeur (règle 4).

```sh
make https
make up             # x86-64 seulement ; 5 lignes ✅
docker compose --profile https logs blobattle-caddy | grep -iE 'certificate obtained|error' | tail -5
curl -s https://jeu.example.org/healthcheck                      # attendu : {}
curl -s -o /dev/null -w '%{http_code}\n' https://jeu.example.org/   # attendu : 200
```

Un `error` dans les journaux de Caddy vient presque toujours du DNS ou du port 80 fermé. Corrige,
puis `docker compose --profile https restart blobattle-caddy`.

### Façon D : derrière son propre reverse proxy

```sh
make site
make up             # x86-64 seulement ; 5 lignes ✅
```

Le proxy doit envoyer :

- `/v2/*`, `/ws` et `/healthcheck` à `127.0.0.1:7550`. `/ws` est une WebSocket : l'upgrade doit
  passer.
- tout le reste à `127.0.0.1:5380`, ou au port de `WEB_PORT`.
- l'en-tête `X-Forwarded-Proto: https`. Sinon, nginx redirige en boucle.

Montre la configuration à ton utilisateur et attends son accord avant de toucher à celle de son
proxy et de le recharger. Pour **Caddy**, ce bloc dans le `Caddyfile` (testé) :

```
jeu.example.org {
	@nakama path /v2/* /ws /healthcheck
	handle @nakama {
		reverse_proxy 127.0.0.1:7550
	}
	handle {
		reverse_proxy 127.0.0.1:5380
	}
}
```

Pour **nginx**, l'équivalent : deux `location`, avec `proxy_http_version 1.1`,
`proxy_set_header Upgrade $http_upgrade`, `proxy_set_header Connection "upgrade"` pour `/ws`, et
`proxy_set_header X-Forwarded-Proto $scheme` partout.

Vérifie ensuite :

```sh
curl -s https://jeu.example.org/healthcheck                      # attendu : {}
curl -s -o /dev/null -w '%{http_code}\n' https://jeu.example.org/   # attendu : 200
```

## Étape 5 : rendre la main

Tu ne peux pas jouer à sa place. Dis à ton utilisateur :

- **L'adresse du jeu.** Il l'ouvre sur un téléphone, en paysage.
  1. **Solo** lance une partie contre les bots.
  2. **Multi**, puis **Create a room**, donne un code.
  3. Un deuxième appareil rejoint par **Join** avec ce code.
- **Où sont les secrets** : `.env`, `cloudflared/` (façon B) et `~/.cloudflared/cert.pem`, à ne
  jamais partager. Ne donne pas leur contenu.
- **La console du serveur de jeu** se lit à distance par SSH :
  `ssh -L 7551:127.0.0.1:7551 <serveur>`, puis `http://127.0.0.1:7551`, utilisateur `admin`. Le mot
  de passe est `NAKAMA_CONSOLE_PASSWORD` dans `.env` : il le lira lui-même.
- **Les conteneurs repartent seuls au redémarrage de la machine.**
- **Aucune limite sur la création de salons pour l'instant** : mieux vaut ne pas publier l'adresse
  partout.

## Plus tard : mettre à jour, arrêter

Quand ton utilisateur le demande :

```sh
git pull
make web
docker compose up -d --wait --force-recreate --no-deps blobattle-nakama
```

Préviens-le avant : redémarrer le serveur de jeu fait tomber les parties en cours. Si `git pull` a
changé `compose.yaml`, relance aussi `make site` (A, D), `make tunnel` (B) ou `make https` (C).

Pour arrêter : `make down`. Les comptes restent.

## Si ça ne marche pas

| Symptôme | Diagnostic |
|---|---|
| Nakama s'arrête au démarrage | `docker compose logs blobattle-nakama \| tail -30` ; `missing from .env` veut dire qu'une clé est vide |
| `make up` : ❌ sur la clé serveur | `.env` a changé après le build : refaire `make web` |
| La page s'ouvre, mais Multi ne se connecte pas | Façon A : `curl http://<ip>:7550/healthcheck` depuis une autre machine (pare-feu ? `NAKAMA_BIND` ?). Façons B, C et D : `curl https://<domaine>/healthcheck` (les chemins du proxy ou du tunnel) |
| Façon C : pas de certificat | `docker compose --profile https logs blobattle-caddy \| tail -30` : le DNS ou le port 80 |
| cloudflared redémarre en boucle | `docker compose --profile tunnel logs blobattle-cloudflared \| tail -20`. Un `permission denied` veut dire que `UID`/`GID` de `.env` ne sont pas ceux du propriétaire de `cloudflared/`. Si `grep '^tunnel:' cloudflared/config.yml` montre `TUNNEL_ID` ou rien après les deux-points, l'étape de configuration n'a pas abouti. |
| `make web` : `Killed`, code 137, `OutOfMemoryError` | La mémoire manque : construire sur un PC (étape 3), ou ajouter du swap avec l'accord de ton utilisateur |
| Une redirection en boucle derrière le proxy | Le proxy n'envoie pas `X-Forwarded-Proto: https` |
| `port is already allocated` | Un autre service a le port : changer `WEB_PORT`, ou demander pour 7550, 7551 et 5438 |
