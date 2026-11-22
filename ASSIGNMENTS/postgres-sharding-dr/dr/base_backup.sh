#!/usr/bin/env bash
# Usage: ./dr/base_backup.sh <container>:<name> [<container>:<name> ...]
# Example: ./dr/base_backup.sh citus_coordinator:coordinator citus_worker1:worker1 citus_worker2:worker2
set -euo pipefail
TS=$(date +%Y%m%d_%H%M%S)
for pair in "$@"; do
  container=${pair%%:*}
  name=${pair##*:}
  echo "$(date +%T) base backup of $container -> /backup/$name/base/$TS"
  docker exec -u postgres "$container" pg_basebackup -U movies_admin -D "/backup/$name/base/$TS" -Ft -z -X stream -c fast
done
echo "$(date +%T) done"
