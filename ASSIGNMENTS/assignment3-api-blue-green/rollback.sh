#!/usr/bin/env bash
# rollback.sh — switch traffic back to the previous release
# Usage: ./rollback.sh
# Reuses the existing image of the previous release (nothing is rebuilt).

set -euo pipefail

#Settings
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

STATE_DIR="/opt/bluegreen"
ENV_FILE="$STATE_DIR/deploy.env"
STATE_FILE="$STATE_DIR/state.env"
ROUTES_FILE="$STATE_DIR/traefik/routes.yml"

PROXY_URL="http://localhost:8080"
READY_TIMEOUT=60
REQUEST_TIMEOUT=2

umask 002

#Helpers 
log() {
  echo "[rollback] $*"
}

fail() {
  echo "[rollback] ERROR: $*" >&2
  exit 1
}

compose() {
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
}

set_env() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

write_routes() {
  local color="$1"
  local tmp="$STATE_DIR/routes.yml.tmp"
  cat > "$tmp" <<EOF
http:
  routers:
    api:
      rule: "PathPrefix(\`/\`)"
      entryPoints:
        - web
      service: api-active

  services:
    api-active:
      loadBalancer:
        servers:
          - url: "http://api_${color}:8000"
EOF
  mv "$tmp" "$ROUTES_FILE"
}

container_ready() {
  docker exec "api_$1" python -c \
    "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health/ready', timeout=$REQUEST_TIMEOUT)" \
    >/dev/null 2>&1
}

wait_ready() {
  local color="$1"
  local deadline=$((SECONDS + READY_TIMEOUT))
  local attempt=0
  while true; do
    attempt=$((attempt + 1))
    if container_ready "$color"; then
      log "api_$color is ready (attempt $attempt)"
      return 0
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      return 1
    fi
    log "api_$color not ready yet (attempt $attempt), retrying..."
    sleep 2
  done
}

verify_proxy() {
  local expected="$1"
  local deadline=$((SECONDS + 15))
  local version
  while true; do
    if curl -fsS --max-time "$REQUEST_TIMEOUT" "$PROXY_URL/health/ready" >/dev/null 2>&1 &&
       curl -fsS --max-time "$REQUEST_TIMEOUT" "$PROXY_URL/db-time" >/dev/null 2>&1; then
      version="$(curl -fsS --max-time "$REQUEST_TIMEOUT" "$PROXY_URL/health/live" | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || true)"
      if [ "$version" = "$expected" ]; then
        return 0
      fi
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      return 1
    fi
    sleep 1
  done
}

#Input 
[ -f "$ENV_FILE" ] || fail "$ENV_FILE not found"

#Identify the previous release 
ACTIVE_COLOR=""; ACTIVE_IMAGE=""; ACTIVE_VERSION=""
PREVIOUS_COLOR=""; PREVIOUS_IMAGE=""; PREVIOUS_VERSION=""
if [ -f "$STATE_FILE" ]; then
  . "$STATE_FILE"
fi

if [ -z "$ACTIVE_COLOR" ]; then
  fail "no deployment found: nothing to roll back"
fi
if [ -z "$PREVIOUS_COLOR" ] || [ -z "$PREVIOUS_IMAGE" ]; then
  fail "no previous release exists (active: $ACTIVE_COLOR, version $ACTIVE_VERSION). Cannot roll back"
fi
log "active:   $ACTIVE_COLOR (version $ACTIVE_VERSION)"
log "previous: $PREVIOUS_COLOR (version $PREVIOUS_VERSION) $PREVIOUS_IMAGE"

#Make sure the previous container runs the previous (existing) image 
PREVIOUS_UPPER="${PREVIOUS_COLOR^^}"
DEFAULT_DATABASE_URL="$(grep '^DATABASE_URL=' "$ENV_FILE" | cut -d= -f2- || true)"
[ -n "$DEFAULT_DATABASE_URL" ] || fail "DATABASE_URL is missing in $ENV_FILE"
set_env "${PREVIOUS_UPPER}_IMAGE" "$PREVIOUS_IMAGE"
set_env "${PREVIOUS_UPPER}_DATABASE_URL" "$DEFAULT_DATABASE_URL"
compose up -d --no-deps "api_$PREVIOUS_COLOR"

#Check that it is healthy
if ! wait_ready "$PREVIOUS_COLOR"; then
  fail "previous release api_$PREVIOUS_COLOR is not healthy. Routing unchanged: traffic stays on $ACTIVE_COLOR"
fi

#Switch traffic back 
log "switching traffic: $ACTIVE_COLOR -> $PREVIOUS_COLOR"
write_routes "$PREVIOUS_COLOR"

#Verify through the router 
if ! verify_proxy "$PREVIOUS_VERSION"; then
  write_routes "$ACTIVE_COLOR"
  fail "verification through $PROXY_URL failed. Traffic switched back to $ACTIVE_COLOR"
fi
log "proxy OK: ready, database reachable, version $PREVIOUS_VERSION"

#Update deployment state 
cat > "$STATE_FILE.tmp" <<EOF
ACTIVE_COLOR="$PREVIOUS_COLOR"
ACTIVE_IMAGE="$PREVIOUS_IMAGE"
ACTIVE_VERSION="$PREVIOUS_VERSION"
PREVIOUS_COLOR="$ACTIVE_COLOR"
PREVIOUS_IMAGE="$ACTIVE_IMAGE"
PREVIOUS_VERSION="$ACTIVE_VERSION"
UPDATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
mv "$STATE_FILE.tmp" "$STATE_FILE"

log "SUCCESS: active=$PREVIOUS_COLOR version=$PREVIOUS_VERSION image=$PREVIOUS_IMAGE"