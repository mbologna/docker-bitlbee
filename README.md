# BitlBee Docker Container

[![Docker Pulls](https://img.shields.io/docker/pulls/mbologna/docker-bitlbee)](https://hub.docker.com/r/mbologna/docker-bitlbee)
[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/mbologna/docker-bitlbee/build-scan-push.yml?branch=main)](https://github.com/mbologna/docker-bitlbee/actions)
[![Docker Image Size](https://img.shields.io/docker/image-size/mbologna/docker-bitlbee/latest)](https://hub.docker.com/r/mbologna/docker-bitlbee)
[![License](https://img.shields.io/github/license/mbologna/docker-bitlbee)](LICENSE)

A Docker container for [BitlBee](https://www.bitlbee.org/) with extensive protocol support via plugins. Includes optional Stunnel ([docker-stunnel](https://github.com/mbologna/docker-stunnel)) for TLS encryption and Kubernetes deployment manifests.

## Technical Features

- 🏗️ **Multi-architecture support:** `linux/amd64`, `linux/arm64`
- 🔒 **Security-hardened:** Non-root user, minimal capabilities, security contexts
- 📊 **Health checks:** Built-in monitoring with liveness/readiness probes
- 📦 **SBOM generation:** Software Bill of Materials for supply chain security
- 🔍 **Automated vulnerability scanning:** Trivy and Grype scans in CI/CD
- 🚀 **Optimized builds:** Layer caching and multi-stage builds
- ☸️ **Kubernetes-ready:** Production-grade manifests included

## Supported Protocols

**Built-in:** BitlBee's [built-in protocols](https://wiki.bitlbee.org/)

**Via Plugins:**
- Discord ([purple-discord](https://github.com/EionRobb/purple-discord))
- Matrix ([purple-matrix](https://github.com/matrix-org/purple-matrix))
- Microsoft Teams ([purple-teams](https://github.com/EionRobb/purple-teams))
- Slack ([slack-libpurple](https://github.com/dylex/slack-libpurple))
- Facebook Messenger ([mautrix-meta](https://github.com/mautrix/meta) via built-in Matrix homeserver)
- Mastodon ([bitlbee-mastodon](https://github.com/kensanata/bitlbee-mastodon))
- Telegram ([tdlib-purple](https://github.com/BenWiederhake/tdlib-purple))
- WhatsApp ([purple-whatsmeow](https://github.com/hoehermann/purple-gowhatsapp))

## Quick Start

### Docker

```bash
# Create a volume for persistent data
docker volume create bitlbee-data

# Run BitlBee
docker run -d \
  --name bitlbee \
  --user $(id -u):$(id -g) \
  -p 6667:6667 \
  -v bitlbee-data:/var/lib/bitlbee \
  mbologna/docker-bitlbee:latest
```

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

# Access BitlBee
# Plain IRC: localhost:6667
# TLS IRC:   localhost:16697
```

#### Docker Compose Configuration

###### Environment Variables

Create a `.env` file:

```env
UID=1000                        # User ID for file permissions
GID=1000                        # Group ID for file permissions
BITLBEE_PORT=6667               # BitlBee port (default: 6667)
STUNNEL_PORT=16697              # Stunnel TLS port (default: 16697)
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

# Access from within cluster
# Plain: bitlbee.bitlbee.svc.cluster.local:6667
# TLS:   bitlbee-stunnel.bitlbee.svc.cluster.local:6697

# Port forward for external access
kubectl port-forward -n bitlbee svc/bitlbee 6667:6667
```

#### Kubernetes Configuration

##### Data Persistence

Managed by PersistentVolumeClaim (default: 128Mi, configurable in `k8s/pvc.yaml`).

##### Exposing Services

Edit `k8s/service.yaml` to change service type:

**NodePort** (for bare-metal clusters):
```yaml
spec:
  type: NodePort
  ports:
    - port: 6667
      nodePort: 30667  # Choose 30000-32767
```

**LoadBalancer** (for cloud providers):
```yaml
spec:
  type: LoadBalancer
  ports:
    - port: 6667
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

1. Connect to BitlBee:
   ```
   /server localhost 6667
   ```

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

### Example: Facebook Messenger (with 2FA)

Facebook Messenger is bridged via an embedded [Matrix](https://matrix.org/) homeserver ([conduwuit](https://github.com/girlbossceo/conduwuit)) and a [mautrix-meta](https://github.com/mautrix/meta) bridge. Both run inside the same container — no extra services needed.

**On first container start**, look for the Matrix registration token in the logs:

```
docker logs bitlbee | grep "registration token"
# or set MATRIX_REGISTRATION_TOKEN in your .env to choose your own
```

**In your IRC client:**

1. Register a local Matrix account (one-time setup):
   ```
   register_matrix <your-matrix-username> <password> <registration-token>
   ```
   Or, using the raw Matrix account add:
   ```
   account add matrix <username>@localhost <password> http://localhost:6167
   ```
   When BitlBee asks for a registration token, paste the one from the logs.

2. Enable the account:
   ```
   account matrix on
   ```

3. Start a conversation with the bridge bot to link your Facebook account:
   ```
   /msg @facebookbot:localhost login
   ```
   The bot will guide you through a QR code or link-based login — this works with 2FA and does not use the old (broken) mobile API.

4. Once linked, your Facebook contacts appear as channels/users in BitlBee. Save:
   ```
   save
   ```

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=mbologna/docker-bitlbee&type=date&legend=top-left)](https://www.star-history.com/#mbologna/docker-bitlbee&type=date&legend=top-left)
