# Héberger Blobattle chez soi

Ce guide installe le jeu sur sa propre machine, tout en conteneurs Docker, et le rend jouable de
quatre façons :

| | Pour qui | Adresse du jeu | Ce qu'il faut en plus |
|---|---|---|---|
| **A. En http** | le réseau local, ou un serveur sans nom de domaine | `http://<ip>:5380` | rien |
| **B. Par un tunnel Cloudflare** | une machine chez soi, sans ouvrir de port | `https://jeu.example.org` | un domaine géré par Cloudflare (offre gratuite) |
| **C. En https avec le Caddy du dépôt** | un serveur avec une IP publique, un VPS | `https://jeu.example.org` | un domaine qui pointe vers le serveur, les ports 80 et 443 libres et ouverts |
| **D. Derrière son propre reverse proxy** | un serveur où nginx, Caddy ou Traefik tient déjà les ports 80 et 443 | `https://jeu.example.org` | un domaine qui pointe vers le serveur |

Selon la façon, ces conteneurs tournent :

- **Postgres**, les comptes anonymes ;
- **Nakama**, le serveur de jeu, qui charge `server/` et `shared/` du dépôt ;
- **nginx**, qui sert le build web (`out/web/Blobattle`) ;
- **cloudflared**, pour la façon B seulement ;
- **Caddy**, pour la façon C seulement.

Le jeu cherche le serveur à l'adresse même de sa page :

- **en http**, sur le port 7550 de la même machine ;
- **en https**, à la même origine. Le tunnel ou le reverse proxy envoie alors `/v2/`, `/ws` et
  `/healthcheck` à Nakama, et tout le reste à nginx.

## Ce qu'il faut

- **Linux x86-64**, avec **Docker** et **Docker Compose v2** (`docker compose version`), `git`,
  `make` et `openssl`.
  - Sur un VPS neuf, le script officiel installe Docker et Compose :
    `curl -fsSL https://get.docker.com | sh`.
  - Ensuite, `sudo usermod -aG docker $USER`, puis se reconnecter.
- Pour construire le jeu web, une seule fois puis à chaque mise à jour :
  - environ 3 Go de disque pour l'image d'outils, qui contient Defold, Java, Node et Chromium ;
  - Internet, car les extensions natives de Defold se compilent sur le serveur de build de Defold.
- **Serveur ARM** (Raspberry Pi, VPS ARM) : les conteneurs du serveur tournent dessus, mais pas
  l'image d'outils, qui ne télécharge que des binaires x86-64. On construit alors le jeu web sur un
  PC (voir plus bas).

### Sur un petit VPS

Un VPS x86-64 à **1 vCPU, 1 Go de mémoire et 10 Go de disque** suffit. Mesures :

| | Mesure |
|---|---|
| Mémoire au repos | 80 Mo pour Nakama, Postgres, nginx et cloudflared réunis |
| Mémoire du serveur de jeu en charge | 130 à 200 Mo, pendant 4 parties simultanées à 8 équipes de 6 blobs, avec les bots en difficile |
| Construction du jeu web (`make web`) | pic à 364 Mo ; elle réussit même bridée à 512 Mo |
| Processeur | Nakama bridé à un demi-cœur d'un i9-13900KF : ces 4 parties extrêmes tiennent 29 ticks par seconde sur 30. Une partie ordinaire entre amis coûte bien moins. |
| Disque | environ 2,1 Go pour l'image d'outils, 0,9 Go pour les autres images, moins de 50 Mo pour le jeu construit |

- Pour gagner 2 Go de disque après la construction : `docker image rm blobattle-tools:dev`. Il faudra
  refaire `make tools` à la prochaine mise à jour.
- **Le pare-feu** :
  - Les ports que Docker publie passent à côté d'ufw. C'est le pare-feu de l'hébergeur, dans son
    interface web, qui décide.
  - Si on active ufw, autoriser SSH d'abord (`sudo ufw allow OpenSSH`), sous peine de perdre l'accès
    à la machine.

## 1. Le dépôt et `.env`

```sh
git clone https://github.com/laurentf/blobattle-public.git blobattle
cd blobattle
cp .env.example .env
sed -i "s/^UID=.*/UID=$(id -u)/; s/^GID=.*/GID=$(id -g)/" .env
for k in SERVER_KEY HTTP_KEY SESSION_KEY REFRESH_KEY CONSOLE_PASSWORD CONSOLE_SIGNING_KEY; do
  sed -i "s/^NAKAMA_$k=$/NAKAMA_$k=$(openssl rand -hex 32)/" .env
done
```

`.env` tient les secrets du serveur. Il est ignoré par git : ne le committer ni le partager jamais.

- La **clé serveur** (`NAKAMA_SERVER_KEY`) finit dans le build web, donc elle n'est pas secrète.
  Elle doit simplement être la même dans le build et dans Nakama.
- Les **cinq autres clés** restent secrètes.
- `NAKAMA_CONSOLE_PASSWORD` ouvre la console d'administration de Nakama (utilisateur `admin`).

## 2. Le jeu web

```sh
make tools   # l'image d'outils, une seule fois (plusieurs minutes)
make web     # le build HTML5 dans out/web/Blobattle
```

`make web` lit la clé serveur dans `.env`. Après un changement de cette clé, il faut le relancer.

**Construire sur un autre ordinateur** (serveur ARM, ou disque trop petit pour l'image d'outils) :

1. Sur un PC x86-64, cloner le dépôt, puis `cp .env.example .env`.
2. Dans ce `.env`, mettre `NAKAMA_SERVER_KEY` à la même valeur que sur le serveur. Les autres clés
   n'ont rien à faire sur le PC.
3. `make tools web`.
4. Copier le résultat dans le dépôt du serveur, au même endroit :
   `rsync -a --delete out/web/ serveur:blobattle/out/web/`.

## 3. Démarrer

### A. En http : réseau local, ou serveur sans domaine

Dans `.env` : `WEB_BIND=0.0.0.0` ; `NAKAMA_BIND` reste à `0.0.0.0`. Puis :

```sh
make site    # Postgres, Nakama et nginx, relancés avec la machine
```

Le jeu est sur `http://<ip-de-la-machine>:5380`, sur les téléphones et ordinateurs qui voient cette
IP. Sur un serveur public, il faut ouvrir les ports **5380** et **7550** au pare-feu de l'hébergeur.

Sans https :

- le navigateur marque la page « non sécurisée » ;
- le bouton de partage du Salon copie le lien au lieu d'ouvrir le menu de partage ;
- le reste du jeu fonctionne.

### B. Par un tunnel Cloudflare

Il faut un compte Cloudflare et un domaine dont Cloudflare gère le DNS. `jeu.example.org` est le nom
choisi pour le jeu, à remplacer par le vôtre.

Dans `.env` : `NAKAMA_BIND=127.0.0.1`, puisque le tunnel parle à Nakama de l'intérieur de Docker.
`WEB_BIND` reste à `127.0.0.1`.

**1. Créer le tunnel**, avec le cloudflared du dépôt :

```sh
mkdir -p cloudflared ~/.cloudflared && chmod 700 cloudflared ~/.cloudflared
cf() { docker compose --profile tunnel run --rm --no-deps -e HOME=/tmp \
  -v "$HOME/.cloudflared:/tmp/.cloudflared" -v "$PWD/cloudflared:/out" blobattle-cloudflared "$@"; }
cf tunnel login                                            # ouvrir l'URL affichée, choisir le domaine
cf tunnel create --credentials-file /out/blobattle.json blobattle
cf tunnel route dns blobattle jeu.example.org
```

Ce que font ces commandes :

- `tunnel login` dépose `~/.cloudflared/cert.pem`, le certificat du compte. Il ne sert qu'à créer
  des tunnels et des routes DNS : le garder hors du dépôt.
- `tunnel create` écrit les identifiants du tunnel dans `cloudflared/blobattle.json`.

**2. La configuration du tunnel**, depuis le modèle :

```sh
cp tools/tunnel/config.example.yml cloudflared/config.yml
id=$(grep -o '"TunnelID":"[^"]*"' cloudflared/blobattle.json | cut -d'"' -f4)
test -n "$id" && sed -i "s/TUNNEL_ID/$id/" cloudflared/config.yml
chmod 600 cloudflared/config.yml && chmod 400 cloudflared/blobattle.json
```

Le modèle ne nomme aucun domaine : le domaine n'est écrit que dans la route DNS, et le modèle
aiguille par chemin. Le dossier `cloudflared/` est ignoré par git.

**3. Lancer** :

```sh
make tunnel  # Postgres, Nakama, nginx, puis cloudflared
```

Le jeu est sur `https://jeu.example.org`. Si le navigateur dit que le nom n'existe pas, c'est le
cache DNS de la machine qui le mémorise : un nom demandé avant que la route existe reste
« inexistant » quelques minutes.

### C. En https avec le Caddy du dépôt (un VPS)

Avant de lancer :

- le domaine pointe vers le serveur (enregistrement A, ou AAAA en IPv6) ;
- les ports 80 et 443 sont libres sur la machine ;
- ces ports sont ouverts au pare-feu de l'hébergeur (voir « Sur un petit VPS »).

Dans `.env` : `DOMAIN=jeu.example.org`, `NAKAMA_BIND=127.0.0.1` et `WEB_BIND=127.0.0.1`. Puis :

```sh
make https   # Postgres, Nakama, nginx, puis Caddy sur les ports 80 et 443
```

Au premier démarrage, Caddy obtient un certificat Let's Encrypt pour le domaine, en quelques
secondes. Il le renouvelle tout seul et le garde dans le volume `caddy-data`. Le jeu est sur
`https://jeu.example.org`.

Si la page ne s'ouvre pas, lire `docker compose --profile https logs blobattle-caddy` :

- le DNS ne pointe pas encore vers le serveur ;
- ou le port 80 est fermé (Let's Encrypt passe par lui).

### D. Derrière son propre reverse proxy

Le domaine pointe vers le serveur, où un proxy tient déjà les ports 80 et 443.

Dans `.env` : `NAKAMA_BIND=127.0.0.1` et `WEB_BIND=127.0.0.1`. Puis `make site`.

Avec **Caddy** installé sur la machine, le bloc du `Caddyfile` :

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

Avec un **autre proxy** (nginx, Traefik…), la règle est la même :

- `/v2/`, `/ws` et `/healthcheck` vont à `127.0.0.1:7550`. `/ws` est une WebSocket : le proxy doit
  laisser passer l'upgrade.
- Tout le reste va à `127.0.0.1:5380`.
- Le proxy transmet `X-Forwarded-Proto: https`. Sinon, le nginx du jeu redirige vers https.

## 4. Vérifier

```sh
make up      # avec l'image d'outils : ✅ Nakama répond, la clé serveur ouvre une session,
             # la clé par défaut est refusée, la console s'ouvre, le module room est chargé
curl -fsS http://127.0.0.1:7550/healthcheck && echo ok   # sans l'image d'outils
```

Puis ouvrir l'adresse du jeu sur un téléphone, en paysage :

1. **Solo** joue contre les bots, sans serveur.
2. **Multi**, puis **Create a room**, donne un code de 5 lettres et un lien.
3. Un deuxième appareil prend ce code par **Join**.

Avec `?test=1` à la fin de l'adresse, une ligne en bas de l'écran donne le temps de réponse du
serveur.

## Mettre à jour

```sh
git pull
make web
docker compose up -d --wait --force-recreate --no-deps blobattle-nakama
```

- Nakama ne lit son code qu'au démarrage : le redémarrer fait tomber les parties en cours.
- nginx sert `out/` tel quel, il n'a pas besoin de redémarrer.
- Si `compose.yaml` a changé (une version d'image), relancer `make site`, `make https` ou
  `make tunnel`, qui recréent les conteneurs concernés.

## Arrêter

```sh
make down                 # tout s'arrête, les comptes restent dans le volume Postgres
docker compose down -v    # efface aussi les comptes
```

Les conteneurs ont `restart: unless-stopped` : ils repartent avec la machine, sauf si on les a
arrêtés.

## Sécurité

- **Les ports** :
  - la console de Nakama (7551) et Postgres (5438) n'écoutent que sur `127.0.0.1` ;
  - nginx aussi, par défaut ;
  - derrière un tunnel ou un proxy, `NAKAMA_BIND=127.0.0.1` empêche de joindre Nakama en clair de
    l'extérieur ;
  - en façon C, seuls les ports 80 et 443 de Caddy sont ouverts à tous.
- **La console de Nakama** se lit à distance par SSH : `ssh -L 7551:127.0.0.1:7551 serveur`, puis
  `http://127.0.0.1:7551`, utilisateur `admin`, mot de passe `NAKAMA_CONSOLE_PASSWORD`.
- **Le mot de passe de Postgres** (`localdb`, dans `compose.yaml`) ne sert qu'entre les conteneurs :
  Postgres n'est joignable que de la machine.
- **Aucune limite sur la création de salons et de comptes** pour l'instant : n'importe qui avec la
  page peut en créer en boucle. C'est sans conséquence entre amis, mais mieux vaut ne pas annoncer
  l'adresse partout.
- **Ce que le serveur garde** : pour chaque appareil, un identifiant tiré au hasard, un pseudo et un
  nom d'équipe. Pas d'adresse IP dans les logs de l'application.

## Dépannage

| Symptôme | Cause probable |
|---|---|
| Nakama s'arrête sur `missing from .env` | une clé est vide dans `.env` |
| La page s'ouvre, Multi n'arrive pas à se connecter | le build a une autre clé serveur que `.env` : refaire `make web` ; ou Nakama est injoignable : en http, le port 7550 ; en https, les chemins du proxy |
| cloudflared : `permission denied` sur `blobattle.json` | `UID`/`GID` de `.env` ne sont pas ceux du propriétaire de `cloudflared/` |
| `port is already allocated` | un autre service prend le port : changer `WEB_PORT` ; le port 7550 de Nakama, lui, est fixe |
| Caddy : pas de certificat | le domaine ne pointe pas encore vers le serveur, ou le port 80 est fermé : `docker compose --profile https logs blobattle-caddy` |
| Les journaux | `docker compose logs -f blobattle-nakama` (ou `blobattle-web` ; `--profile tunnel` pour `blobattle-cloudflared`, `--profile https` pour `blobattle-caddy`) |
