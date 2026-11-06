#!/usr/bin/env bash
set -euo pipefail

IMAGE="gitlab/gitlab-runner:v17.11.0"
CONTAINER_NAME="gitlab-runner"
CONFIG_DIR="/srv/gitlab-runner/config"
STATE_DIR="/srv/gitlab-runner/state"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_SOURCE="$SCRIPT_DIR/gitlab-runner.service"
SERVICE_TARGET="/etc/systemd/system/gitlab-runner.service"

for cmd in docker systemctl sudo; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is not installed" >&2
    exit 1
  fi
done

if [ ! -f "$SERVICE_SOURCE" ]; then
  echo "Error: $SERVICE_SOURCE not found" >&2
  exit 1
fi

sudo mkdir -p "$CONFIG_DIR" "$STATE_DIR"
sudo chmod 700 "$CONFIG_DIR" "$STATE_DIR"

docker pull "$IMAGE"

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "Container $CONTAINER_NAME already exists, keeping it"
else
  docker create \
    --name "$CONTAINER_NAME" \
    --restart no \
    -v "$CONFIG_DIR:/etc/gitlab-runner" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "$IMAGE"
fi

sudo cp "$SERVICE_SOURCE" "$SERVICE_TARGET"
sudo systemctl daemon-reload
sudo systemctl enable gitlab-runner
sudo systemctl start gitlab-runner

echo "GitLab Runner is installed"
