# BitlBee with additional plugins in a container

![Docker](https://img.shields.io/docker/pulls/mbologna/docker-bitlbee)
![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/mbologna/docker-bitlbee/build-scan-push.yml?branch=master)

This repository provides a Docker-based setup for running [Bitlbee](https://www.bitlbee.org/) with additional plugins for extended functionality and an optional [Stunnel](https://www.stunnel.org/) service to enable secure IRC communications over TLS.

## Features

- **[Bitlbee](https://www.bitlbee.org)**: A popular gateway that connects instant messaging services with IRC. In addition to the [Bitlbee's out of the box supported protocols](https://wiki.bitlbee.org/), these are the pre-installed plugins:
    - Google Hangouts via [purple-hangouts](https://github.com/EionRobb/purple-hangouts)
    - Discord via [purple-discord](https://github.com/EionRobb/purple-discord)
    - Matrix via [purple-matrix](https://github.com/matrix-org/purple-matrix)
    - Microsoft Teams via [teams](https://github.com/EionRobb/purple-teams)
    - Slack via [slack-libpurple](https://github.com/dylex/slack-libpurple)
    - Skype via [skype4pidgin](https://github.com/EionRobb/skype4pidgin)
    - Facebook (MQTT) via [bitlbee-facebook](https://github.com/bitlbee/bitlbee-facebook)
    - Mastodon via [bitlbee-mastodon](https://alexschroeder.ch/software/Bitlbee_Mastodon)
    - Telegram via [tdlib-purple](https://github.com/BenWiederhake/)
- **[Stunnel](https://www.stunnel.org/)**: Adds TLS encryption for secure IRC connections.
- Multi-architecture support: builds for `linux/amd64` and `linux/arm64`.
- Kubernetes resources included for deployment in containerized environments.
- Linting and security scans integrated into CI/CD workflows.

## Quick Start

### Running Locally with Podman or Docker Compose

1. Clone this repository:
   ```bash
   git clone https://github.com/mbologna/docker-bitlbee.git
   cd docker-bitlbee

2. Build and run the containers:

    ```
    podman-compose up --build
    ```

    If you're using Docker:
    ```
    docker-compose up --build
    ```

3. Access the Bitlbee service on port 6667 and the Stunnel service on port 16697.

#### Environment Variables

`UID` and `GID`: Set these to match your local user for proper volume permissions.

#### Persistent Data

The `data/` directory is mounted as a volume to store Bitlbee configurations and data. Ensure it is backed up for persistent setups.

### Kubernetes Deployment

Kubernetes manifests for deploying Bitlbee and Stunnel are located in the `k8s/` directory.

1. Apply the manifests:

```
kubectl apply -f k8s/
```

Verify deployment:
```
kubectl get pods -n bitlbee
```
Expose the service as needed (e.g., via `NodePort` or `Ingress`).

## CI/CD Workflow

This repository uses GitHub Actions for automated builds and deployments:

* Build and Push: Docker images are built for amd64 and arm64 platforms and pushed to:
    - Docker Hub: `mbologna/docker-bitlbee:latest`
    - GitHub Container Registry: `ghcr.io/mbologna/docker-bitlbee:latest`

* Linting: Integrated linters for Dockerfile, shell scripts, and Kubernetes resources.
* Security Scans: Uses Trivy to scan Docker images for vulnerabilities.

## Local Development

### Building Multi-Arch Images Locally

For multi-architecture builds with Podman:

```
podman build --platform linux/amd64,linux/arm64 -t mbologna/docker-bitlbee:latest .
```

Or with Docker:

```
docker buildx build --platform linux/amd64,linux/arm64 -t mbologna/docker-bitlbee:latest --push .
```

## Resources

[BitlBee Documentation](https://wiki.bitlbee.org/)
