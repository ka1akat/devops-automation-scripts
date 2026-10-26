#!/bin/bash
DEADLINE=$((SECONDS + 60))

while [ $SECONDS -lt $DEADLINE ]; do
  if timeout 5 docker exec postgresql psql -h 127.0.0.1 -U appuser -d appdb -c "SELECT 1" > /dev/null 2>&1; then
    echo "PostgreSQL is ready"
    exit 0
  fi
  sleep 2
done

echo "PostgreSQL did not become ready in 60 seconds" >&2
exit 1
