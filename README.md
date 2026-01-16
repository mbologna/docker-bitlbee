# BitlBee Docker Container

[![Docker Pulls](https://img.shields.io/docker/pulls/mbologna/docker-bitlbee)](https://hub.docker.com/r/mbologna/docker-bitlbee)
[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/mbologna/docker-bitlbee/build-scan-push.yml?branch=master)](https://github.com/mbologna/docker-bitlbee/actions)
[![Docker Image Size](https://img.shields.io/docker/image-size/mbologna/docker-bitlbee/latest)](https://hub.docker.com/r/mbologna/docker-bitlbee)
[![License](https://img.shields.io/github/license/mbologna/docker-bitlbee)](LICENSE)

A Docker container for [BitlBee](https://www.bitlbee.org/) - the IRC gateway to instant messaging networks. This container includes extensive plugin support and optional TLS encryption via Stunnel.

## ✨ Features

### Core Components

- **[BitlBee](https://www.bitlbee.org)** - IRC gateway for instant messaging
- **[Stunnel](https://www.stunnel.org/)** - TLS/SSL encryption wrapper (optional)

### Supported Protocols

In addition to BitlBee's [built-in protocols](https://wiki.bitlbee.org/) (Jabber/XMPP, Oscar/AIM, MSN, Twitter, etc.), this container includes:

| Protocol | Plugin | Repository |
|----------|--------|------------|
| Discord | purple-discord | [EionRobb/purple-discord](https://github.com/EionRobb/purple-discord) |
| Matrix | purple-matrix | [matrix-org/purple-matrix](https://github.com/matrix-org/purple-matrix) |
| Microsoft Teams | purple-teams | [EionRobb/purple-teams](https://github.com/EionRobb/purple-teams) |
| Slack | slack-libpurple | [dylex/slack-libpurple](https://github.com/dylex/slack-libpurple) |
| Facebook (MQTT) | bitlbee-facebook | [bitlbee/bitlbee-facebook](https://github.com/bitlbee/bitlbee-facebook) |
| Telegram | tdlib-purple | [BenWiederhake/tdlib-purple](https://github.com/BenWiederhake/tdlib-purple) |
| WhatsApp | purple-whatsmeow | [hoehermann/purple-gowhatsapp](https://github.com/hoehermann/purple-gowhatsapp) |

### Technical Features

- 🏗️ Multi-architecture support: `linux/amd64`, `linux/arm64`
- 🔒 Security-hardened with minimal capabilities
- 📊 Health checks and monitoring ready
- 🚀 Optimized build with layer caching
- 📦 SBOM and provenance attestations
- 🔍 Automated vulnerability scanning
- ☸️ Kubernetes manifests included

## 🚀 Quick Start

### Prerequisites

- Docker 20.10+ or Podman 3.0+
- docker-compose or podman-compose (optional, for orchestration)

### Option 1: Docker Run

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

### Option 2: Docker Compose (Recommended)

1. **Clone the repository:**
   ```bash
   git clone https://github.com/mbologna/docker-bitlbee.git
   cd docker-bitlbee
   ```

2. **Create environment file:**
   ```bash
   cp .env.example .env
   # Edit .env with your preferred settings
   ```

3. **Start the services:**
   ```bash
   docker-compose up -d
   ```

4. **Access BitlBee:**
   - Plain IRC: `localhost:6667`
   - TLS/SSL (via Stunnel): `localhost:16697`

### Option 3: Podman

```bash
# Using podman-compose
podman-compose up -d

# Or with podman directly
podman run -d \
  --name bitlbee \
  --user $(id -u):$(id -g) \
  -p 6667:6667 \
  -v bitlbee-data:/var/lib/bitlbee \
  docker.io/mbologna/docker-bitlbee:latest
```

## ⚙️ Configuration

### Environment Variables

Configure the container using a `.env` file or environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `UID` | `1000` | User ID for file permissions |
| `GID` | `1000` | Group ID for file permissions |
| `BITLBEE_PORT` | `6667` | BitlBee IRC port |
| `STUNNEL_PORT` | `16697` | Stunnel TLS port |
| `TZ` | `UTC` | Timezone |

**Example `.env` file:**
```env
UID=1000
GID=1000
BITLBEE_PORT=6667
STUNNEL_PORT=16697
TZ=Europe/Rome
```

### Volume Mounts

The container uses `/var/lib/bitlbee` for persistent data:
- User accounts
- Configuration files
- Plugin settings

**Important:** Ensure the volume is writable by the user specified in `UID:GID`.

### Custom Configuration

To use a custom BitlBee configuration:

```bash
# Create your config
mkdir -p ./data
# Place your bitlbee.conf in ./data

# Mount it
docker run -d \
  --name bitlbee \
  -v $(pwd)/data:/var/lib/bitlbee \
  mbologna/docker-bitlbee:latest
```

## 🔐 Security

### TLS/SSL Encryption

The included Stunnel service provides encrypted IRC connections:

```bash
# Connect with SSL-enabled IRC client
/server localhost 16697 -ssl
```

### Security Features

- ✅ Runs as non-root user
- ✅ Minimal Linux capabilities
- ✅ `no-new-privileges` security option
- ✅ Regular vulnerability scanning
- ✅ SBOM generation for supply chain security

### Health Checks

Built-in health checks monitor service availability:

```bash
# Check container health
docker inspect bitlbee --format='{{.State.Health.Status}}'

# View health check logs
docker inspect bitlbee --format='{{json .State.Health}}' | jq
```

## 📊 Monitoring

### Logs

```bash
# View logs
docker-compose logs -f bitlbee

# Follow specific service
docker-compose logs -f stunnel
```

### Resource Usage

```bash
# Check resource consumption
docker stats bitlbee bitlbee-stunnel
```

## 🎮 Using BitlBee

### First-Time Setup

1. **Connect to BitlBee:**
   ```
   /server localhost 6667
   ```

2. **Register your account:**
   ```
   register <password>
   ```

3. **Add an account (example: Discord):**
   ```
   account add discord <email> <password>
   account discord on
   ```

4. **Save configuration:**
   ```
   save
   ```

### Useful Commands

```irc
# List available protocols
account list

# Add account
account add <protocol> <username> <password>

# Enable account
account <id> on

# Join channels
chat add <account> <channel>

# Get help
help
help account
```

### Protocol-Specific Setup

Refer to the individual plugin documentation:
- [Discord setup](https://github.com/EionRobb/purple-discord/wiki)
- [Matrix setup](https://github.com/matrix-org/purple-matrix/blob/master/README.md)
- [Teams setup](https://github.com/EionRobb/purple-teams#usage)
- [WhatsApp setup](https://github.com/hoehermann/purple-gowhatsapp/wiki)

## ☸️ Kubernetes Deployment

Kubernetes manifests are available in the `k8s/` directory:

```bash
# Deploy to Kubernetes
kubectl apply -f k8s/

# Check deployment
kubectl get pods -n bitlbee

# Access logs
kubectl logs -n bitlbee -l app=bitlbee -f
```
