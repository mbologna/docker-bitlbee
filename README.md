## Features

* In addition to the [Bitlbee's out of the box supported protocols](https://wiki.bitlbee.org/), this container also supports the following protocols:

    - Skype via [skype4pidgin](https://github.com/EionRobb/skype4pidgin)
    - Telegram via [tdlib-purple](https://github.com/ars3niy/tdlib-purple)
    - Facebook (MQTT) via [bitlbee-facebook](https://github.com/bitlbee/bitlbee-facebook)
    - Google Hangouts via [purple-hangouts](https://github.com/EionRobb/purple-hangouts)
    - Mastodon via [bitlbee-mastodon](https://alexschroeder.ch/software/Bitlbee_Mastodon)
    - Rocket.Chat via [purple-rocketchat](https://github.com/EionRobb/purple-rocketchat)
    - Discord via [bitlbee-discord](https://github.com/sm00th/bitlbee-discord/)
    - Slack via [slack-libpurple](https://github.com/dylex/slack-libpurple)
    - Steam via [bitlbee-steam](https://github.com/bitlbee/bitlbee-steam)
    - Matrix via [purple-matrix](https://github.com/matrix-org/purple-matrix)
    - Mattermost via [puple-mattermost](https://github.com/EionRobb/purple-mattermost)
    - Instagram via [purple-instagram](https://github.com/EionRobb/purple-instagram)

* The `docker-compose.yml` provided in this repository enables bitlbee to be TLS terminated via [stunnel](https://www.stunnel.org/).

## Usage

1. Clone the project:

       % git clone https://www.github.com/mbologna/docker-bitlbee

2. (Optional) Customize bitlbee configuration file in `etc/bitlbee/bitlbee.conf`

3. Start `bitlbee` either via:

    * [Docker Compose](https://docs.docker.com/compose/install/) (recommended):

        ```
        % docker-compose up
        ```

    * Docker:

        ```
        % docker volume create bitlbee_data
        % docker run -d --name bitlbee \
                        --restart=always \
                        -p 16667:6667 \
                        -v $PWD/etc/bitlbee:/usr/local/etc/bitlbee \
                        mbologna/docker-bitlbee
        % docker run -d --name bitlbee-stunnel \
                        --restart=always \
                        --link bitlbee:bitlbee
                        -e STUNNEL_SERVICE=bitlbee-stunnel \
                        -e STUNNEL_ACCEPT=6697 \
                        -e STUNNEL_CONNECT=bitlbee:6667 \
                        -p 16697:6697 \
                        dweomer/stunnel
        ```

4. Connect your IRC client either to:

    * localhost:16697 (TLS terminated) (recommended)
    * localhost:16667 (non-TLS, plain connection)

## Building

You can build a `bitlbee` image from Dockerfile: `docker build -t="mbologna/docker-bitlbee" github.com/mbologna/docker-bitlbee`
