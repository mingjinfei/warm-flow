#!/usr/bin/env sh
set -eu

APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$APP_DIR"

COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.deploy.yml}
MAVEN=${MAVEN:-mvn}
DOCKER_COMPOSE=${DOCKER_COMPOSE:-docker compose}
NPM=${NPM:-npm}

# docker compose can read .env by itself, but fail fast here before spending
# time on frontend/backend builds. Preserve that .env workflow by importing only
# this one required value when the caller did not export it.
if [ -z "${RUOYI_TOKEN_SECRET:-}" ] && [ -f .env ]; then
  RUOYI_TOKEN_SECRET=$(sed -n 's/^RUOYI_TOKEN_SECRET=//p' .env | tail -n 1)
  export RUOYI_TOKEN_SECRET
fi
: "${RUOYI_TOKEN_SECRET:?Set RUOYI_TOKEN_SECRET to a strong random value before deployment}"

(
  cd ruoyi-ui
  $NPM ci --no-audit --no-fund
  $NPM run build:prod
)
scripts/sync_ruoyi_static.sh
$MAVEN -DskipTests clean package
$DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d --build
$DOCKER_COMPOSE -f "$COMPOSE_FILE" ps
