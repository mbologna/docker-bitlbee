# bitlbee Dockerfile
[This repository](https://github.com/mbologna/docker-bitlbee/) contains **Dockerfile** of [*bitlbee*](https://github.com/bitlbee/bitlbee), for [Docker](https://www.docker.com/)'s [automated build](https://registry.hub.docker.com/u/mbologna/docker-bitlbee/) published to the public [Docker Hub Registry](https://registry.hub.docker.com/).

## Features

In addition to the [Bitlbee's out of the box supported protocols](https://wiki.bitlbee.org/), this container also supports the following protocols:

- Skype via [skype4pidgin](https://github.com/EionRobb/skype4pidgin)
- Telegram via [telegram-purple](https://github.com/majn/telegram-purple)
- Facebook (MQTT) via [bitlbee-facebook](https://github.com/bitlbee/bitlbee-facebook)
- Google Hangouts via [purple-hangouts](https://bitbucket.org/EionRobb/purple-hangouts)
- Mastodon via [bitlbee-mastodon](https://alexschroeder.ch/software/Bitlbee_Mastodon)

## Base Docker image

* buildpack-deps/stretch-curl

## Installation

1. Install [Docker](https://www.docker.com/).

2. Download [automated build](https://registry.hub.docker.com/u/mbologna/docker-bitlbee/) from public [Docker Hub Registry](https://registry.hub.docker.com/): `docker pull mbologna/docker-bitlbee`

   (alternatively, you can build an image from Dockerfile: `docker build -t="mbologna/docker-bitlbee" github.com/mbologna/docker-bitlbee`)

## Usage

1. (Optional) Customize bitlbee configuration file in `etc/bitlbee/bitlbee.conf`

2. Run bitlbee via:

    a. [Docker Compose](https://docs.docker.com/compose/install/):

        docker-compose up

    b. or via Docker:

        docker volume create bitlbee_data
        docker run -d --name bitlbee -p 16667:6667 --restart=always -v $PWD/etc/bitlbee:/usr/local/etc/bitlbee mbologna/docker-bitlbee

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
