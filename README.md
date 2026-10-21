# BitlBee Docker Container

[![Docker Pulls](https://img.shields.io/docker/pulls/mbologna/docker-bitlbee)](https://hub.docker.com/r/mbologna/docker-bitlbee)
[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/mbologna/docker-bitlbee/ci.yml?branch=main)](https://github.com/mbologna/docker-bitlbee/actions)
[![Docker Image Size](https://img.shields.io/docker/image-size/mbologna/docker-bitlbee/latest)](https://hub.docker.com/r/mbologna/docker-bitlbee)
[![License](https://img.shields.io/github/license/mbologna/docker-bitlbee)](LICENSE)

A Docker container for [BitlBee](https://www.bitlbee.org/) with extensive protocol support via plugins. TLS is built in: the container only listens on port **6697** (BitlBee) and port **6698** (Matrix), both IRC over TLS; plaintext is never exposed.

## Technical Features

- 🏗️ **Multi-architecture support:** `linux/amd64`, `linux/arm64`
- 🔒 **Security-hardened:** Non-root user, minimal capabilities, security contexts
- 🔐 **TLS-only:** stunnel terminates TLS inside the container; BitlBee and matrix2051 bind loopback-only
- 📊 **Health checks:** Built-in monitoring with liveness/readiness probes
- 📦 **SBOM generation:** Software Bill of Materials for supply chain security
- 🔍 **Automated vulnerability scanning:** Trivy and Grype scans in CI/CD
- 🚀 **Optimized builds:** Layer caching and multi-stage builds
- ☸️ **Kubernetes-ready:** Production-grade manifests included

## Supported Protocols

**Built-in:** BitlBee's [built-in protocols](https://wiki.bitlbee.org/)

**Via Plugins:**
- Discord ([purple-discord](https://github.com/EionRobb/purple-discord))
- Facebook Messenger & Instagram DMs ([mautrix-meta](https://github.com/mautrix/meta) via built-in Matrix homeserver, reached on port 6698)
- Google Chat ([purple-googlechat](https://github.com/EionRobb/purple-googlechat))
- Mastodon ([bitlbee-mastodon](https://github.com/kensanata/bitlbee-mastodon))
- Microsoft Teams ([purple-teams](https://github.com/EionRobb/purple-teams))
- Telegram ([tdlib-purple](https://github.com/BenWiederhake/tdlib-purple))
- WhatsApp ([purple-whatsmeow](https://github.com/hoehermann/purple-gowhatsapp))

**Matrix:** any homeserver, through [matrix2051](https://github.com/progval/matrix2051) on port 6698 (see [Matrix](#matrix)). This is a second IRC network next to BitlBee, not a BitlBee account.

> **Note:** Twitter/X's built-in BitlBee support requires a paid API key since free-tier access was removed in 2023.

## Versioning

The image has its own version, separate from BitlBee's. A tag `vX.Y.Z` (image
`mbologna/docker-bitlbee:X.Y.Z`) identifies a build of this repository: a new
patch release is cut automatically whenever the weekly rebuild produces a
different image, for example because of a base-image or plugin update.

Up to `v3.6.18` the tags started with BitlBee's version (3.6) and the last
number counted rebuilds. Releases from `v4.0.0` on use the image's own version.

The bundled component versions are recorded as image labels:

```bash
docker inspect -f '{{json .Config.Labels}}' mbologna/docker-bitlbee:<tag>
```

Components with no usable release tags (tdlib-purple, matrix2051 and the
EionRobb plugins) are built from a branch pinned to a commit, and labelled
with that commit's SHA. Renovate proposes each new branch commit as a pull
request that merges only once the image builds and passes CI, so every
upstream change shows up as a commit here before it reaches a release.

### Upgrading from conduwuit to tuwunel

Images up to `4.x` shipped the Matrix homeserver conduwuit 0.4.6, which is no longer maintained. Later images ship its successor, [tuwunel](https://github.com/matrix-construct/tuwunel). The first start on an existing volume:

- copies the database to `/var/lib/bitlbee/conduwuit/db.conduwuit-0.4.6-backup`, then
- migrates the database in place. Accounts, rooms and the Facebook bridge are kept.

The migration is one-way: older images can't open the migrated database. To go back, stop the container and restore the copy. Once everything works, delete the copy to free the space. Paths and the config file keep the `conduwuit` name, as upstream recommends.

## Quick Start

### Docker

```bash
# Create a volume for persistent data
docker volume create bitlbee-data

# Run BitlBee (TLS only; connect your IRC client with SSL/TLS enabled)
docker run -d \
  --name bitlbee \
  --user $(id -u):$(id -g) \
  -p 6697:6697 \
  -p 6698:6698 \
  -v bitlbee-data:/var/lib/bitlbee \
  mbologna/docker-bitlbee:latest
```

A self-signed TLS certificate is generated automatically on first run and stored in the persistent volume. Replace `/var/lib/bitlbee/ssl/bitlbee.pem` with your own certificate if needed.

### Docker Compose

```bash
# Clone repository
git clone https://github.com/mbologna/docker-bitlbee.git
cd docker-bitlbee

# Configure environment
cp .env.example .env
# Edit .env with your UID/GID

# Start services
docker-compose up -d

# Access BitlBee (TLS)
# IRC over TLS: localhost:6697 (BitlBee), localhost:6698 (Matrix)
```

#### Docker Compose Configuration

###### Environment Variables

Create a `.env` file:

```env
UID=1000                        # User ID for file permissions
GID=1000                        # Group ID for file permissions
BITLBEE_PORT=6697               # BitlBee TLS port (default: 6697)
MATRIX_PORT=6698                # matrix2051 TLS port (default: 6698)
TZ=UTC                          # Timezone
MATRIX_REGISTRATION_TOKEN=      # Optional: set a fixed Matrix registration token
                                 # (auto-generated on first run if left empty)
```

##### Data Persistence

Data is stored in `./data` directory or the `bitlbee-data` named volume.


### Kubernetes

```bash
# Deploy to cluster
kubectl apply -f k8s/

# Check status
kubectl get pods -n bitlbee

# Access from within cluster (TLS only)
# bitlbee.bitlbee.svc.cluster.local:6697 (BitlBee), :6698 (Matrix)

# Port forward for external access
kubectl port-forward -n bitlbee svc/bitlbee 6697:6697 6698:6698
```

#### Kubernetes Configuration

##### Data Persistence

Managed by PersistentVolumeClaim (default: 128Mi, configurable in `k8s/pvc.yaml`).

##### Exposing Services

Edit `k8s/ingress.yaml` (uncomment the relevant block) to choose between NodePort and LoadBalancer. Both examples expose ports **6697** (BitlBee) and **6698** (Matrix).

**NodePort** (for bare-metal clusters):
```yaml
spec:
  type: NodePort
  ports:
    - name: ircs
      port: 6697
      nodePort: 30697  # Choose 30000-32767
    - name: ircs-matrix
      port: 6698
      nodePort: 30698
```

**LoadBalancer** (for cloud providers):
```yaml
spec:
  type: LoadBalancer
  ports:
    - name: ircs
      port: 6697
    - name: ircs-matrix
      port: 6698
```

##### Resource Limits

Edit `k8s/deployment.yaml`:
```yaml
resources:
  limits:
    memory: 1Gi    # Increase as needed
    cpu: 2000m
  requests:
    memory: 256Mi
    cpu: 200m
```

##### Storage Size

Edit `k8s/pvc.yaml`:
```yaml
resources:
  requests:
    storage: 5Gi  # Adjust size
```

##### Timezone Configuration

Edit `k8s/configmap.yaml`:
```yaml
data:
  TZ: "Europe/Rome"  # Change timezone
```

## Using BitlBee

### First-Time Setup

1. Connect to BitlBee with **SSL/TLS enabled** in your IRC client:
   ```
   /server -ssl localhost 6697
   ```
   Accept the self-signed certificate (or replace it with your own at
   `/var/lib/bitlbee/ssl/bitlbee.pem`).

2. Register an account:
   ```
   register <password>
   ```

3. Add a messaging account:
   ```
   account add <protocol> <username> <password>
   account <id> on
   ```

4. Save configuration:
   ```
   save
   ```

### Example: Discord

```
account add discord your-email@example.com your-password
account discord on
save
```

## Matrix

> Looking for `account add matrix`? Matrix is not a BitlBee account here: add a second IRC server on port 6698 instead, as described below.

BitlBee has no maintained Matrix plugin, so Matrix is served by [matrix2051](https://github.com/progval/matrix2051), a Matrix client that acts as an IRC server. It is a **second IRC network** in your client, on port **6698** (TLS), next to BitlBee on 6697. It reaches the container's built-in homeserver (needed for Facebook) and any other homeserver.

matrix2051 logs in with SASL PLAIN. The SASL username is your Matrix ID without the leading `@` (`me:matrix.org`), and the password is your Matrix password. The IRC "real name" (GECOS) can carry the homeserver URL when it can't be discovered.

Limitations:

- **No end-to-end encryption.** Encrypted rooms are unreadable, which on most public homeservers includes direct messages.
- Rooms without an alias (direct chats, and every bridged Facebook chat) show up as channels named after the room ID, like `!AbCdEf:localhost`. matrix2051 doesn't list them when you connect, only when a message arrives.
- Anyone who can reach port 6698 can use it to log into any Matrix homeserver (with valid credentials). Only expose it where you would expose BitlBee.

### Example: external Matrix account

In WeeChat (adapt for your client):

```
/server add matrix example.org/6698 -tls
/set irc.server.matrix.sasl_mechanism plain
/set irc.server.matrix.sasl_username me:matrix.org
/set irc.server.matrix.sasl_password <your-matrix-password>
/connect matrix
```

Leave the real name empty; the homeserver is found through `.well-known`. Join rooms with `/join #room:matrix.org`.

On matrix.org:

- You need a password. Accounts created with "Sign in with Google/GitHub/…" have none; check at [account.matrix.org](https://account.matrix.org/).
- Direct messages and most private rooms are end-to-end encrypted by default, so in practice only public rooms are readable.

### Example: Facebook Messenger (with 2FA)

Facebook Messenger is bridged by [mautrix-meta](https://github.com/mautrix/meta) on the container's built-in Matrix homeserver ([tuwunel](https://github.com/matrix-construct/tuwunel)). Both run inside the container; no extra services needed. The homeserver is private: it listens on loopback only and doesn't federate.

1. Create your account on the built-in homeserver (one-time):
   ```bash
   docker exec bitlbee matrix-register me 'my-password'
   ```
   This also opens a chat with the bridge bot, `@facebookbot:localhost`, as the channel `#facebook-me:localhost`.

2. Connect to port 6698 as `me:localhost`, with the real name set to the built-in homeserver's address:
   ```
   /server add fb example.org/6698 -tls
   /set irc.server.fb.sasl_mechanism plain
   /set irc.server.fb.sasl_username me:localhost
   /set irc.server.fb.sasl_password my-password
   /set irc.server.fb.realname homeserver-url=http://127.0.0.1:6167
   /connect fb
   ```

3. In `#facebook-me:localhost`, say `login facebook`. The bridge logs in with your browser's session cookies, not your password:
   1. Log into facebook.com in a private browser window.
   2. Open devtools, go to the Network tab and filter for `graphql`.
   3. Right-click one of the requests, then choose **Copy** → **Copy as cURL**.
   4. Join the copied command into a single line and paste it to the bot. Most IRC clients send each pasted line as a separate message.

   See the [mautrix-meta authentication docs](https://docs.mau.fi/bridges/go/meta/authentication.html) for details. Meta may flag the login as suspicious and ask for a captcha, a phone number or a password reset; enabling 2FA beforehand helps.

Once linked, the bridge invites you to a Matrix room for each Facebook chat. Accept with `/join <channel>` when your client shows the invite. Each chat then appears as a `!…:localhost` channel when a message arrives (see the limitations above).

`matrix-register` reads the registration token from the container. The token is also printed in the logs on first start, or can be fixed with `MATRIX_REGISTRATION_TOKEN` in `.env`.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=mbologna/docker-bitlbee&type=date&legend=top-left)](https://www.star-history.com/#mbologna/docker-bitlbee&type=date&legend=top-left)