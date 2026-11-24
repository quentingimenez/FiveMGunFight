# =============================================================================
#  Image du serveur FiveM Gunfight
#  - Debian minimal + FXServer (version Linux officielle de Cfx.re)
#  - Les scripts (server-data) sont copiés dans l'image ET peuvent être
#    remplacés par un dossier monté (c'est ce que fait docker-compose.yml)
# =============================================================================
FROM debian:bookworm-slim

# Quelle version de FXServer télécharger :
#   FX_CHANNEL = recommended (stable, conseillé) | latest
#   FX_URL     = lien direct vers un fx.tar.xz précis (prioritaire si rempli)
# Pour changer de canal il faut reconstruire avec l'argument :
#   docker compose build --build-arg FX_CHANNEL=latest
# (sans l'argument, l'image en cache est réutilisée telle quelle)
ARG FX_CHANNEL=recommended
ARG FX_URL=""

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
 && rm -rf /var/lib/apt/lists/*

# Téléchargement et extraction de FXServer
WORKDIR /opt/fivem/server
RUN set -eux; \
    url="$FX_URL"; \
    if [ -z "$url" ]; then \
      url="$(curl -fsSL https://changelogs-live.fivem.net/api/changelog/versions/linux/server \
            | sed -n "s/.*\"${FX_CHANNEL}_download\":\"\([^\"]*\)\".*/\1/p")"; \
    fi; \
    test -n "$url"; \
    echo "Téléchargement de FXServer : $url"; \
    curl -fsSL "$url" | tar -xJ; \
    echo "$url" > /opt/fivem/server/FX_VERSION.txt

# Script de démarrage
COPY docker/entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

# Copie par défaut des scripts du serveur (utile sur un VPS sans montage)
COPY server-data/ /opt/fivem/server-data/

WORKDIR /opt/fivem/server-data

# 30120 = port du jeu (TCP + UDP), 40120 = panneau web txAdmin
EXPOSE 30120/tcp 30120/udp 40120/tcp

ENTRYPOINT ["/entrypoint.sh"]
