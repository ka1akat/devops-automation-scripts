#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="gitlab-runner"
SERVICE_NAME="gitlab-runner"
SERVICE_FILE="/etc/systemd/system/gitlab-runner.service"
DATA_DIR="/srv/gitlab-runner"
STATE_FILE="$DATA_DIR/state/runner.env"

for cmd in curl docker sudo systemctl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is not installed" >&2
    exit 1
  fi
done

if sudo test -f "$STATE_FILE"; then
  RUNNER_ID="$(sudo sed -n 's/^RUNNER_ID=//p' "$STATE_FILE")"
  GITLAB_URL="$(sudo sed -n 's/^GITLAB_URL=//p' "$STATE_FILE")"
  GITLAB_URL="${GITLAB_URL:-https://gitlab.com}"

  if [ -z "${GITLAB_TOKEN:-}" ]; then
    echo "Error: GITLAB_TOKEN is not set, cannot delete runner $RUNNER_ID" >&2
    exit 1
  fi

  HTTP_CODE="$(curl -sS -o /dev/null -w '%{http_code}' --request DELETE \
    --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$GITLAB_URL/api/v4/runners/$RUNNER_ID")"

  case "$HTTP_CODE" in
    204) echo "Runner $RUNNER_ID deleted from GitLab" ;;
    404) echo "Runner $RUNNER_ID was already deleted from GitLab" ;;
    *)   echo "Error: cannot delete runner $RUNNER_ID (HTTP $HTTP_CODE)" >&2
         exit 1 ;;
  esac
else
  echo "No saved runner ID, skipping GitLab cleanup"
fi

sudo systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
sudo rm -f "$SERVICE_FILE"
sudo systemctl daemon-reload

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  docker rm -f "$CONTAINER_NAME" >/dev/null
  echo "Container $CONTAINER_NAME removed"
else
  echo "Container $CONTAINER_NAME not found, skipping"
fi

sudo rm -rf "$DATA_DIR"
echo "Cleanup finished"