# Docker BitlBee

![Docker](https://img.shields.io/docker/pulls/mbologna/docker-bitlbee)
![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/mbologna/docker-bitlbee/build-scan-push.yml?branch=master)

This repository provides a containerized version of [BitlBee](https://www.bitlbee.org/), an IRC gateway for instant messaging services, along with additional plugins for extended functionality (e.g., Skype, Facebook, Discord, Mastodon, and more).
The image is built for both amd64 and arm64 platforms.

## Features

- **BitlBee Version**: `3.6`
- Pre-installed plugins:
    - Skype via [skype4pidgin](https://github.com/EionRobb/skype4pidgin)
    - Telegram via [tdlib-purple](https://github.com/BenWiederhake/tdlib-purple)
    - Facebook (MQTT) via [bitlbee-facebook](https://github.com/bitlbee/bitlbee-facebook)
    - Google Hangouts via [purple-hangouts](https://github.com/EionRobb/purple-hangouts)
    - Mastodon via [bitlbee-mastodon](https://alexschroeder.ch/software/Bitlbee_Mastodon)
    - Discord via [purple-discord](https://github.com/EionRobb/purple-discord)
    - Slack via [slack-libpurple](https://github.com/dylex/slack-libpurple)
    - Matrix via [purple-matrix](https://github.com/matrix-org/purple-matrix)
    - Microsoft Teams via [teams](https://github.com/EionRobb/purple-teams)
- Secured IRC communication with optional TLS using **stunnel**.
- Customizable and persistent storage.
- Lightweight and production-ready container.

---

## Getting Started (Docker and docker compose)

Follow these instructions to set up and run the BitlBee container.

### Prerequisites

- [Docker](https://www.docker.com/get-started) installed on your system.
- [Docker Compose](https://docs.docker.com/compose/) (optional for multi-container setup).

---

### Installation

#### Clone the Repository

```bash
git clone https://github.com/mbologna/docker-bitlbee.git
cd docker-bitlbee
```

#### Build and Run with Docker Compose

Build the image:

```
docker compose build
```

Run the containers:

```
docker compose up -d
```

Check the container logs:

```
docker logs -f bitlbee
```

### Configuration
#### Volumes

The container uses /var/lib/bitlbee to store persistent data, including user configuration files. Mount a local directory to this volume to retain data:

```
volumes:
  - ./data:/var/lib/bitlbee
```

#### Ports

* 6667: Standard IRC port for BitlBee.
* 6697: Secure IRC port (`stunnel`).

You can change these ports in `docker-compose.yml` if needed.

### Usage

* Connect to the BitlBee server using any IRC client (e.g., HexChat, mIRC):
    Server: localhost
    Port: 6667 or 6697 (TLS)
* Add IM accounts by typing commands in the IRC client. Example for adding a Google account:

    ```
    account add jabber username@gmail.com
    ```

Refer to the BitlBee User Guide for detailed instructions.

## Getting Started (Kubernetes version)
This repository provides Kubernetes manifests to deploy **BitlBee** with **Stunnel**. The setup ensures a secure communication channel by using Stunnel as a TLS wrapper for BitlBee.

### Architecture

The system consists of two components:

1. **BitlBee**:
   - IRC gateway for IM services.
   - Exposes port `6667` for internal communication.
   - Uses a PersistentVolumeClaim for data persistence.

2. **Stunnel**:
   - Provides TLS encryption for BitlBee communication.
   - Listens on port `6697` and forwards traffic to BitlBee's port `6667`.

---

### Prerequisites

1. A Kubernetes cluster (minikube, kind, or a cloud provider).
2. `kubectl` CLI tool installed and configured.
3. A storage class available for the PersistentVolumeClaim (PVC).

### Configuration

#### Environment Variables for Stunnel

The Stunnel pod uses a ConfigMap to define key environment variables:

```
STUNNEL_SERVICE: Name of the Stunnel service.
STUNNEL_ACCEPT: Port Stunnel listens on (6697).
STUNNEL_CONNECT: Target BitlBee service and port (bitlbee:6667).
```

#### Storage

BitlBee data is persisted using a PVC:

Default size: 1Gi
Modify the PersistentVolumeClaim if more storage is required.

### Deployment

#### Step 1: Apply the Namespace

```bash
kubectl apply -f k8s/bitlbee-namespace.yml
```

#### Step 2: Deploy the ConfigMap

```
kubectl apply -f k8s/bitlbee-stunnel-configmap.yml
```

#### Step 3: Deploy BitlBee and Stunnel

```
kubectl apply -f k8s/bitlbee-deployment.yml
kubectl apply -f k8s/bitlbee-stunnel-deployment.yml
```

#### Step 3: Create the PersistentVolumeClaim

```
kubectl apply -f k8s/bitlbee-pvc.yml
```

#### Step 4: Apply Services

```
kubectl apply -f k8s/bitlbee-service.yml
kubectl apply -f k8s/bitlbee-stunnel-service.yml
```

#### Accessing the Services (ClusterIP)

* BitlBee: Internally available on port 6667 within the cluster.
* Stunnel: Internally available on port 6697 within the cluster.

## Resources

[BitlBee Documentation](https://wiki.bitlbee.org/)
