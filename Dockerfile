# =============================================================================
#  Image du serveur FiveM Gunfight
#  - Debian minimal + FXServer (version Linux officielle de Cfx.re)
#  - Les scripts (server-data) sont copiés dans l'image ET peuvent être
#    remplacés par un dossier monté en développement (docker-compose.dev.yml)
#  - Le conteneur tourne avec l'utilisateur non privilégié fivem (UID/GID 10001)
# =============================================================================
# Digest figé : Debian bookworm-slim, résolu le 2026-11-25. Dependabot propose
# les mises à jour de digest ; on ne change pas de distribution sans test.
FROM debian:bookworm-slim@sha256:e67eeead736ff7bbe258ef088bff683635c561b1fcfefad0806c1df4ab49ce0e

# Version du build : sha court du commit, injecté par la CI au moment de la
# construction (.github/workflows/docker.yml, étape « Calculer le sha du
# build »). L'entrypoint la recopie dans secrets.cfg sous forme de convar
# (gf_build_sha) : le lobby affiche ainsi le commit réellement déployé, même
# quand server-data est monté en volume. Hors CI la valeur reste « dev ».
ARG BUILD_SHA=dev
ENV GF_BUILD_SHA=${BUILD_SHA}

# Quelle version de FXServer télécharger :
#   FX_CHANNEL = recommended (stable, conseillé) | latest
#   FX_URL     = lien direct vers un fx.tar.xz précis (prioritaire si rempli)
#   FX_SHA256  = empreinte de cette archive ; recommandée avec FX_URL pour
#                garantir que le binaire déployé est toujours le même.
# Pour changer de canal il faut reconstruire avec l'argument :
#   docker compose -f docker-compose.yml -f docker-compose.dev.yml build --build-arg FX_CHANNEL=latest
ARG FX_CHANNEL=recommended
ARG FX_URL=""
ARG FX_SHA256=""

# L'image de base épinglée peut retarder sur les correctifs de sécurité Debian
# (ex. CVE-2025-6020, libpam) : l'upgrade au build les applique ; Dependabot propose les nouveaux digests.
# hadolint ignore=DL3005
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
 && rm -rf /var/lib/apt/lists/*

# Utilisateur non privilégié du serveur. L'UID/GID est fixe pour que les volumes
# nommés (txData, maps) gardent les mêmes droits d'un déploiement à l'autre.
RUN groupadd --gid 10001 fivem \
 && useradd --uid 10001 --gid 10001 --home-dir /opt/fivem \
      --no-create-home --shell /usr/sbin/nologin fivem

# Téléchargement, vérification et extraction de FXServer
WORKDIR /opt/fivem/server
RUN set -eux; \
    url="$FX_URL"; \
    if [ -z "$url" ]; then \
      url="$(curl -fsSL https://changelogs-live.fivem.net/api/changelog/versions/linux/server \
            | sed -n "s/.*\"${FX_CHANNEL}_download\":\"\([^\"]*\)\".*/\1/p")"; \
    fi; \
    test -n "$url"; \
    echo "Téléchargement de FXServer : $url"; \
    curl -fsSL "$url" -o /tmp/fx.tar.xz; \
    if [ -n "$FX_SHA256" ]; then \
      echo "$FX_SHA256  /tmp/fx.tar.xz" | sha256sum -c -; \
    else \
      echo "AVERTISSEMENT : FX_SHA256 vide, l'archive n'est pas vérifiée"; \
    fi; \
    tar -xJf /tmp/fx.tar.xz -C /opt/fivem/server; \
    rm -f /tmp/fx.tar.xz; \
    echo "$url" > /opt/fivem/server/FX_VERSION.txt

# Script de démarrage
COPY docker/entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod 0755 /entrypoint.sh

# Copie par défaut des scripts du serveur (utile sur un VPS sans montage)
COPY server-data/ /opt/fivem/server-data/
# Copie de référence : sert à amorcer maps.json dans un volume vide (production)
COPY server-data/ /opt/fivem/defaults/

# Droits de l'utilisateur fivem :
#  - txData : volume nommé de txAdmin (comptes, configuration) ;
#  - server-data : secrets.cfg est généré ici au démarrage, FXServer y écrit
#    aussi cache/ et les journaux ;
#  - le dossier data de gf_maps : point de montage du volume « maps » en prod.
# Docker recopie le propriétaire de ces dossiers dans un volume nommé neuf.
RUN mkdir -p /opt/fivem/txData \
 && chown -R 10001:10001 /opt/fivem

# HOME évite que FXServer ou txAdmin tentent d'écrire dans /root.
ENV HOME=/opt/fivem

# Tout ce qui suit (et le processus lancé au démarrage) tourne sans privilège.
USER 10001:10001

WORKDIR /opt/fivem/server-data

# 30120 = port du jeu (TCP + UDP), 40120 = panneau web txAdmin
EXPOSE 30120/tcp 30120/udp 40120/tcp

ENTRYPOINT ["/entrypoint.sh"]
