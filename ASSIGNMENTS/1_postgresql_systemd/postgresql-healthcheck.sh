#!/bin/bash
COUNTER_FILE=/run/postgresql-health-failures

if ! systemctl is-active --quiet postgresql; then
  echo 0 > "$COUNTER_FILE"
  exit 0
fi

if timeout 5 docker exec postgresql psql -h 127.0.0.1 -U appuser -d appdb -c "SELECT 1" > /dev/null 2>&1; then
  echo 0 > "$COUNTER_FILE"
  exit 0
fi

FAILS=$(cat "$COUNTER_FILE" 2>/dev/null)
FAILS=$((FAILS + 1))
echo "$FAILS" > "$COUNTER_FILE"
echo "Health check failed ($FAILS in a row)" >&2

if [ "$FAILS" -ge 3 ]; then
  echo "Health check failed 3 times in a row, restarting postgresql" >&2
  echo 0 > "$COUNTER_FILE"
  systemctl try-restart postgresql
fi
