# =============================================================================
#  Image de vérification du dépôt FiveMGunFight
#  - Ubuntu 24.04, le même système que le runner CI ubuntu-24.04 ;
#  - tous les outils de scripts/verifier.sh installés et épinglés ;
#  - construite par scripts/verifier-docker.sh, puis exécutée avec le dépôt
#    monté dans /depot : une seule commande, la même en local et en CI.
#
#  Les binaires tiers sont épinglés par version ET par empreinte SHA256, puis
#  vérifiés par `sha256sum -c` avant installation, comme les actions GitHub le
#  sont par leur SHA de commit.
# =============================================================================
FROM ubuntu:26.04@sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db

# pipefail pour que les téléchargements vérifiés ne masquent aucun échec.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG ACTIONLINT_VERSION=1.7.12
ARG ACTIONLINT_SHA256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8

ARG HADOLINT_VERSION=2.15.1
ARG HADOLINT_SHA256=c7187db94eeeeca956519a6af171adc31453941a1e777961f6e680f697c8c507

# Version et empreinte tenues à l'identique avec le job « securite » de
# .github/workflows/qualite.yml (tests/test_depot.py le vérifie).
ARG GITLEAKS_VERSION=8.30.1
ARG GITLEAKS_SHA256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb

ARG RUFF_VERSION=0.17.6
ARG RUFF_SHA256=94b33791f48cd54ab35ad673a443a5c001d3e6d87effeaba9899070b700d45f3

ARG NODE_VERSION=20.20.2
ARG NODE_SHA256=df770b2a6f130ed8627c9782c988fda9669fa23898329a61a871e32f965e007d

ARG DOCKER_CLI_VERSION=29.10.1
ARG DOCKER_CLI_SHA256=061642059fa7f2ed9b2f04a327a951cff4249585cf04b2661c2a6539197c9962

ARG DOCKER_COMPOSE_VERSION=5.8.0
ARG DOCKER_COMPOSE_SHA256=b8840f5008c447f41fce0a57ae3adeab42c89b1eb6e6012524bcabbfb4ffbaf6

# Outils Debian : Lua 5.4 + LuaRocks (luacheck), gcc et libc6-dev pour les
# dépendances natives de LuaRocks, shellcheck, Python (tests + JSON), git et
# curl/xz-utils pour les téléchargements vérifiés.
# DL3008 est ignoré par .hadolint.yaml : les paquets suivent les correctifs de
# sécurité d'Ubuntu plutôt que d'être figés à une version qui disparaîtrait.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      gcc \
      git \
      libc6-dev \
      lua5.4 \
      luarocks \
      python3 \
      shellcheck \
      xz-utils \
 && rm -rf /var/lib/apt/lists/*

# Luacheck est un paquet LuaRocks (même version que l'ancienne CI).
RUN luarocks install luacheck 1.2.0-1

# Téléchargement et installation des 7 binaires. Chaque archive est vérifiée
# par son empreinte avant d'être utilisée ; /tmp est nettoyé ensuite.
RUN set -eux; \
    curl -fsSL -o /tmp/actionlint.tar.gz \
      "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"; \
    printf '%s  %s\n' "${ACTIONLINT_SHA256}" /tmp/actionlint.tar.gz | sha256sum -c -; \
    tar -xzf /tmp/actionlint.tar.gz -C /usr/local/bin actionlint; \
    chmod 0755 /usr/local/bin/actionlint; \
    curl -fsSL -o /tmp/hadolint \
      "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-linux-x86_64"; \
    printf '%s  %s\n' "${HADOLINT_SHA256}" /tmp/hadolint | sha256sum -c -; \
    install -m 0755 /tmp/hadolint /usr/local/bin/hadolint; \
    curl -fsSL -o /tmp/gitleaks.tar.gz \
      "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"; \
    printf '%s  %s\n' "${GITLEAKS_SHA256}" /tmp/gitleaks.tar.gz | sha256sum -c -; \
    tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks; \
    chmod 0755 /usr/local/bin/gitleaks; \
    curl -fsSL -o /tmp/ruff.tar.gz \
      "https://github.com/astral-sh/ruff/releases/download/${RUFF_VERSION}/ruff-x86_64-unknown-linux-gnu.tar.gz"; \
    printf '%s  %s\n' "${RUFF_SHA256}" /tmp/ruff.tar.gz | sha256sum -c -; \
    tar -xzf /tmp/ruff.tar.gz -C /tmp; \
    install -m 0755 /tmp/ruff-x86_64-unknown-linux-gnu/ruff /usr/local/bin/ruff; \
    curl -fsSL -o /tmp/node.tar.xz \
      "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz"; \
    printf '%s  %s\n' "${NODE_SHA256}" /tmp/node.tar.xz | sha256sum -c -; \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1; \
    node --version; \
    curl -fsSL -o /tmp/docker.tgz \
      "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_CLI_VERSION}.tgz"; \
    printf '%s  %s\n' "${DOCKER_CLI_SHA256}" /tmp/docker.tgz | sha256sum -c -; \
    tar -xzf /tmp/docker.tgz -C /tmp docker/docker; \
    install -m 0755 /tmp/docker/docker /usr/local/bin/docker; \
    mkdir -p /usr/local/lib/docker/cli-plugins; \
    curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-compose \
      "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64"; \
    printf '%s  %s\n' "${DOCKER_COMPOSE_SHA256}" /usr/local/lib/docker/cli-plugins/docker-compose | sha256sum -c -; \
    chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose; \
    rm -rf /tmp/actionlint.tar.gz /tmp/hadolint /tmp/gitleaks.tar.gz \
      /tmp/ruff.tar.gz /tmp/ruff-x86_64-unknown-linux-gnu /tmp/node.tar.xz \
      /tmp/docker.tgz /tmp/docker

# Le dépôt est monté depuis l'hôte : son propriétaire diffère du conteneur.
RUN git config --system --add safe.directory '*'

ENV PYTHONDONTWRITEBYTECODE=1

WORKDIR /depot
