#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="gitlab-runner"
RUNNER_NAME="karakat-vm-runner"
RUNNER_TAG="karakat-runner"
DEFAULT_JOB_IMAGE="alpine:3.20"
CONFIG_FILE="/srv/gitlab-runner/config/config.toml"
STATE_DIR="/srv/gitlab-runner/state"
STATE_FILE="$STATE_DIR/runner.env"

GROUP_URL="${1:-}"
GROUP_URL="${GROUP_URL%/}"

if [ -z "$GROUP_URL" ]; then
  echo "Usage: $0 <GROUP_URL>" >&2
  exit 1
fi

if [ -z "${GITLAB_TOKEN:-}" ]; then
  echo "Error: GITLAB_TOKEN is not set" >&2
  exit 1
fi

for cmd in curl jq docker sudo; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is not installed" >&2
    exit 1
  fi
done

if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" != "true" ]; then
  echo "Error: container $CONTAINER_NAME is not running. Run install first" >&2
  exit 1
fi

GITLAB_URL="$(echo "$GROUP_URL" | sed -E 's#^(https?://[^/]+).*#\1#')"
GROUP_PATH="${GROUP_URL#"$GITLAB_URL"/}"
API_URL="$GITLAB_URL/api/v4"

if sudo test -f "$STATE_FILE"; then
  RUNNER_ID="$(sudo sed -n 's/^RUNNER_ID=//p' "$STATE_FILE")"
  if curl -fsS -o /dev/null --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$API_URL/runners/$RUNNER_ID" \
    && sudo grep -q "name = \"$RUNNER_NAME\"" "$CONFIG_FILE" 2>/dev/null; then
    echo "Runner $RUNNER_ID is already registered, reusing it"
    exit 0
  fi
  echo "Error: saved state is incomplete. Run cleanup first" >&2
  exit 1
fi

ENCODED_PATH="$(jq -rn --arg path "$GROUP_PATH" '$path | @uri')"

if ! GROUP_JSON="$(curl -fsS --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$API_URL/groups/$ENCODED_PATH")"; then
  echo "Error: cannot find group $GROUP_PATH" >&2
  exit 1
fi
GROUP_ID="$(echo "$GROUP_JSON" | jq -r '.id')"

if ! RUNNER_JSON="$(curl -fsS --request POST \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --data "runner_type=group_type" \
  --data "group_id=$GROUP_ID" \
  --data "description=$RUNNER_NAME" \
  --data "tag_list=$RUNNER_TAG" \
  --data "run_untagged=false" \
  "$API_URL/user/runners")"; then
  echo "Error: cannot create runner. You must be the group Owner" >&2
  exit 1
fi

RUNNER_ID="$(echo "$RUNNER_JSON" | jq -r '.id')"
export CI_SERVER_TOKEN
CI_SERVER_TOKEN="$(echo "$RUNNER_JSON" | jq -r '.token')"

sudo mkdir -p "$STATE_DIR"
printf 'RUNNER_ID=%s\nGITLAB_URL=%s\n' "$RUNNER_ID" "$GITLAB_URL" | sudo tee "$STATE_FILE" >/dev/null
sudo chmod 600 "$STATE_FILE"

docker exec -e CI_SERVER_TOKEN "$CONTAINER_NAME" gitlab-runner register \
  --non-interactive \
  --url "$GITLAB_URL" \
  --name "$RUNNER_NAME" \
  --executor docker \
  --docker-image "$DEFAULT_JOB_IMAGE"

echo "Runner $RUNNER_ID is registered"
