This repository contains a Docker container for [BitlBee](https://www.bitlbee.org/), a chat gateway that connects different messaging protocols (like IRC, Facebook, Skype, etc.). The container is built with plugins for various services such as Skype, Discord, Mastodon, and more.

## Features

* In addition to the [Bitlbee's out of the box supported protocols](https://wiki.bitlbee.org/), this container also supports the following protocols:

    - Skype via [skype4pidgin](https://github.com/EionRobb/skype4pidgin)
    - Telegram via [tdlib-purple](https://github.com/BenWiederhake/tdlib-purple)
    - Facebook (MQTT) via [bitlbee-facebook](https://github.com/bitlbee/bitlbee-facebook)
    - Google Hangouts via [purple-hangouts](https://github.com/EionRobb/purple-hangouts)
    - Mastodon via [bitlbee-mastodon](https://alexschroeder.ch/software/Bitlbee_Mastodon)
    - Discord via [purple-discord](https://github.com/EionRobb/purple-discord)
    - Slack via [slack-libpurple](https://github.com/dylex/slack-libpurple)
    - Matrix via [purple-matrix](https://github.com/matrix-org/purple-matrix)
    - Microsoft Teams via [teams](https://github.com/EionRobb/purple-teams)

## Usage via Docker

1. Configuration:

Configuration files for BitlBee are stored in /usr/local/etc/bitlbee.
You can edit the configuration files by accessing the container or volume mounted at `bitlbee_data`.

2. Start `bitlbee` via [Docker Compose](https://docs.docker.com/compose/install/):

```
docker-compose up -d
```

3. Connect your IRC client either to:

    * localhost:16697 (TLS terminated via stunnel) (recommended)
    * localhost:16667 (non-TLS, plain connection)

## Usage via Kubernetes

1. Configuration (optional):

Configure the ConfigMap stored in k8s/bitlbee-config.yaml.
Then create it:

```
kubectl apply -f bitlbee-configmap.yaml
```

2. Create the Deployment:

```
kubectl apply -f bitlbee-deployment.yaml
```

NOTE: If you are using ClusterIP, BitlBee will be accessible internally within the Kubernetes cluster. If you need external access, you can modify the service type to NodePort or LoadBalancer.

## Building the Container

To build the Docker container, clone this repository and build the image using the following command:

```bash
git clone https://github.com/mbologna/bitlbee-docker.git
cd bitlbee-docker
docker build -t bitlbee:latest .
```
