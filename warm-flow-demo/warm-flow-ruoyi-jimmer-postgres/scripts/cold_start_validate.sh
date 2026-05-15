#!/usr/bin/env sh
set -eu

# Non-destructive cold-start validation for the RuoYi + Warm-Flow Jimmer demo.
#
# The script must run on a Docker host that can access the target PostgreSQL and
# Redis containers. It creates a temporary PostgreSQL database/user, imports the
# bootstrap SQL as that application user, starts a temporary application
# container against the fresh database, waits for /health, and then cleans up by
# default. No shared demo database is reset.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$APP_DIR"

DOCKER=${DOCKER:-docker}
POSTGRES_CONTAINER=${POSTGRES_CONTAINER:-dev-postgres}
POSTGRES_SUPERUSER=${POSTGRES_SUPERUSER:-postgres}
POSTGRES_MAINT_DB=${POSTGRES_MAINT_DB:-postgres}
DOCKER_NETWORK=${DOCKER_NETWORK:-dev-infra}
APP_IMAGE=${APP_IMAGE:-eclipse-temurin:8-jre}
APP_JAR=${APP_JAR:-$APP_DIR/ruoyi-admin/target/ruoyi-admin.jar}
CONTAINER_NAME=${CONTAINER_NAME:-warm-flow-jimmer-coldstart}
COLDSTART_PORT=${COLDSTART_PORT:-18081}
REDIS_HOST=${REDIS_HOST:-dev-redis}
REDIS_PORT=${REDIS_PORT:-6379}
REDIS_DATABASE=${REDIS_DATABASE:-15}
REDIS_PASSWORD=${REDIS_PASSWORD:-}
JIMMER_SHOW_SQL=${JIMMER_SHOW_SQL:-false}
JIMMER_PRETTY_SQL=${JIMMER_PRETTY_SQL:-false}
HEALTH_RETRIES=${HEALTH_RETRIES:-90}
HEALTH_INTERVAL_SECONDS=${HEALTH_INTERVAL_SECONDS:-2}
KEEP_COLDSTART=${KEEP_COLDSTART:-false}
KEEP_FAILED_COLDSTART=${KEEP_FAILED_COLDSTART:-false}
COLDSTART_ACTION=${COLDSTART_ACTION:-run}
STATE_FILE=${STATE_FILE:-/tmp/warm-flow-jimmer-coldstart.state}
DB_SQL=${DB_SQL:-$APP_DIR/sql/postgresql/00-create-database.sql}
BOOTSTRAP_SQL=${BOOTSTRAP_SQL:-$APP_DIR/sql/postgresql/ruoyi-warm-flow-jimmer-postgres.sql}
UPLOAD_VOLUME=${UPLOAD_VOLUME:-${CONTAINER_NAME}_uploads}
LOG_VOLUME=${LOG_VOLUME:-${CONTAINER_NAME}_logs}

now_stamp() {
  date +%Y%m%d%H%M%S
}

random_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-24
  else
    printf 'ColdStart_%s_%s_Pw' "$(date +%s)" "$$"
  fi
}

RUOYI_TOKEN_SECRET=${RUOYI_TOKEN_SECRET:-$(random_password)$(random_password)}

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$(pwd)" "$1" ;;
  esac
}

APP_DB=${APP_DB:-warm_flow_jimmer_cold_$(now_stamp)}
APP_USER=${APP_USER:-$APP_DB}
APP_PASSWORD=${APP_PASSWORD:-$(random_password)}
APP_JAR=$(absolute_path "$APP_JAR")
DB_SQL=$(absolute_path "$DB_SQL")
BOOTSTRAP_SQL=$(absolute_path "$BOOTSTRAP_SQL")
CREATED_DATABASE=false
STARTED_CONTAINER=false

write_state() {
  umask 077
  cat > "$STATE_FILE" <<STATE
APP_DB=$APP_DB
APP_USER=$APP_USER
CONTAINER_NAME=$CONTAINER_NAME
COLDSTART_PORT=$COLDSTART_PORT
UPLOAD_VOLUME=$UPLOAD_VOLUME
LOG_VOLUME=$LOG_VOLUME
STATE
}

load_state() {
  if [ ! -f "$STATE_FILE" ]; then
    echo "state file not found: $STATE_FILE" >&2
    exit 1
  fi
  # shellcheck disable=SC1090 # POSIX sh users may run shellcheck externally.
  . "$STATE_FILE"
}

cleanup() {
  code=$?
  if [ "${COLDSTART_ACTION:-run}" = "run" ]; then
    if [ "${KEEP_COLDSTART:-false}" = "true" ] && [ "$code" -eq 0 ]; then
      echo "KEEP_COLDSTART=true; temporary app remains at http://127.0.0.1:${COLDSTART_PORT}/"
      echo "Cleanup later with: COLDSTART_ACTION=cleanup STATE_FILE=$STATE_FILE $0"
      return "$code"
    fi
    if [ "${KEEP_FAILED_COLDSTART:-false}" = "true" ] && [ "$code" -ne 0 ]; then
      echo "KEEP_FAILED_COLDSTART=true; preserving failed cold-start resources for diagnostics" >&2
      echo "Cleanup later with: COLDSTART_ACTION=cleanup STATE_FILE=$STATE_FILE $0" >&2
      return "$code"
    fi
  fi

  $DOCKER rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  $DOCKER volume rm "$UPLOAD_VOLUME" "$LOG_VOLUME" >/dev/null 2>&1 || true

  if [ -n "${APP_DB:-}" ]; then
    $DOCKER exec "$POSTGRES_CONTAINER" psql \
      -U "$POSTGRES_SUPERUSER" \
      -d "$POSTGRES_MAINT_DB" \
      -v ON_ERROR_STOP=1 \
      -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$APP_DB' and pid <> pg_backend_pid();" >/dev/null 2>&1 || true
    $DOCKER exec "$POSTGRES_CONTAINER" dropdb \
      -U "$POSTGRES_SUPERUSER" \
      --if-exists "$APP_DB" >/dev/null 2>&1 || true
  fi

  if [ -n "${APP_USER:-}" ]; then
    $DOCKER exec "$POSTGRES_CONTAINER" dropuser \
      -U "$POSTGRES_SUPERUSER" \
      --if-exists "$APP_USER" >/dev/null 2>&1 || true
  fi

  rm -f "$STATE_FILE"
  return "$code"
}

if [ "$COLDSTART_ACTION" = "cleanup" ]; then
  load_state
  KEEP_COLDSTART=false
  cleanup
  echo "CLEANED db=$APP_DB user=$APP_USER container=$CONTAINER_NAME"
  exit 0
fi

if [ ! -f "$APP_JAR" ]; then
  echo "application jar not found: $APP_JAR" >&2
  echo "Run mvn -DskipTests clean package or set APP_JAR=/path/to/app.jar." >&2
  exit 1
fi
if [ ! -f "$DB_SQL" ] || [ ! -f "$BOOTSTRAP_SQL" ]; then
  echo "PostgreSQL bootstrap SQL files are missing under sql/postgresql/." >&2
  exit 1
fi

trap cleanup EXIT INT TERM
write_state

echo "Creating temporary PostgreSQL database $APP_DB ..."
$DOCKER exec -i "$POSTGRES_CONTAINER" psql \
  -U "$POSTGRES_SUPERUSER" \
  -d "$POSTGRES_MAINT_DB" \
  -v ON_ERROR_STOP=1 \
  -v app_db="$APP_DB" \
  -v app_user="$APP_USER" \
  -v app_password="$APP_PASSWORD" \
  < "$DB_SQL" >/dev/null
CREATED_DATABASE=true

echo "Importing bootstrap SQL as temporary application user ..."
$DOCKER exec -i \
  -e PGPASSWORD="$APP_PASSWORD" \
  "$POSTGRES_CONTAINER" \
  psql -h 127.0.0.1 -U "$APP_USER" -d "$APP_DB" -v ON_ERROR_STOP=1 \
  < "$BOOTSTRAP_SQL" >/dev/null

$DOCKER exec "$POSTGRES_CONTAINER" psql \
  -U "$POSTGRES_SUPERUSER" \
  -d "$APP_DB" \
  -Atc "select 'tables=' || count(*) from information_schema.tables where table_schema='public' and table_type='BASE TABLE'; select 'users=' || count(*) from sys_user; select 'menus=' || count(*) from sys_menu;" \
  | sed 's/^/BOOTSTRAP /'

echo "Starting temporary app container $CONTAINER_NAME on host port $COLDSTART_PORT ..."
$DOCKER rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
$DOCKER run -d \
  --name "$CONTAINER_NAME" \
  --network "$DOCKER_NETWORK" \
  -p "$COLDSTART_PORT:18080" \
  -v "$APP_JAR:/app/app.jar:ro" \
  -v "$UPLOAD_VOLUME:/home/ruoyi/uploadPath" \
  -v "$LOG_VOLUME:/app/logs" \
  -w /app \
  -e SERVER_PORT=18080 \
  -e SPRING_PROFILES_ACTIVE=druid \
  -e RUOYI_PROFILE=/home/ruoyi/uploadPath \
  -e WARM_FLOW_DB_URL="jdbc:postgresql://$POSTGRES_CONTAINER:5432/$APP_DB" \
  -e WARM_FLOW_DB_USERNAME="$APP_USER" \
  -e WARM_FLOW_DB_PASSWORD="$APP_PASSWORD" \
  -e REDIS_HOST="$REDIS_HOST" \
  -e REDIS_PORT="$REDIS_PORT" \
  -e REDIS_DATABASE="$REDIS_DATABASE" \
  -e REDIS_PASSWORD="$REDIS_PASSWORD" \
  -e RUOYI_TOKEN_SECRET="$RUOYI_TOKEN_SECRET" \
  -e RUOYI_TOKEN_EXPIRE_MINUTES=120 \
  -e RUOYI_LOG_LEVEL=info \
  -e WARM_FLOW_LOG_LEVEL=info \
  -e SPRING_DEVTOOLS_RESTART_ENABLED=false \
  -e SWAGGER_ENABLED=false \
  -e DRUID_WEB_STAT_ENABLED=false \
  -e DRUID_STAT_VIEW_ENABLED=false \
  -e JIMMER_SHOW_SQL="$JIMMER_SHOW_SQL" \
  -e JIMMER_PRETTY_SQL="$JIMMER_PRETTY_SQL" \
  "$APP_IMAGE" \
  java -jar /app/app.jar >/dev/null
STARTED_CONTAINER=true

health_url="http://127.0.0.1:$COLDSTART_PORT/health"
i=1
while [ "$i" -le "$HEALTH_RETRIES" ]; do
  if curl -fsS "$health_url" >/tmp/warm-flow-coldstart-health.json 2>/dev/null; then
    printf 'HEALTH_OK '
    cat /tmp/warm-flow-coldstart-health.json
    echo
    echo "Cold-start validation passed for db=$APP_DB port=$COLDSTART_PORT"
    exit 0
  fi
  if ! $DOCKER ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "container exited before health became available" >&2
    $DOCKER logs --tail=240 "$CONTAINER_NAME" >&2 || true
    exit 1
  fi
  sleep "$HEALTH_INTERVAL_SECONDS"
  i=$((i + 1))
done

echo "health timeout: $health_url" >&2
$DOCKER logs --tail=240 "$CONTAINER_NAME" >&2 || true
exit 1
