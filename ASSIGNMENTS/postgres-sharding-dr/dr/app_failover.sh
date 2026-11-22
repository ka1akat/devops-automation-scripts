#!/usr/bin/env bash
# Failover / rejoin / switchback for one shard of the application-level variant.
# Usage: ./dr/app_failover.sh <shard0|shard1> <status|crash|failover|rejoin|switchback>
set -euo pipefail
cd "$(dirname "$0")/../app-sharding"

NODE=$1
ACTION=$2
PRIMARY=app_$NODE
REPLICA=app_${NODE}_replica
PRIMARY_VOL=app-sharding_${NODE}_data
REPLICA_VOL=app-sharding_${NODE}_replica_data
BOUNCER=pgbouncer${NODE#shard}                       # shard0 -> pgbouncer0
HOST_VAR=$(echo "$NODE" | tr a-z A-Z)_HOST           # shard0 -> SHARD0_HOST
DC="docker compose -f docker-compose.yml -f docker-compose.dr.yml"
SQL="psql -U movies_admin -d movies -v ON_ERROR_STOP=1 -tAc"

mkdir -p ../dr/logs
exec > >(tee -a "../dr/logs/app_${NODE}.log") 2>&1
log() { echo "$(date +%T) [$NODE $ACTION] $*"; }

reclone() {   # $1 = data volume to rebuild, $2 = host of the current primary
  docker run --rm --network app-sharding_default -u postgres -v "$1":/var/lib/postgresql/data postgres:17 \
    bash -c "rm -rf /var/lib/postgresql/data/* && pg_basebackup -h $2 -U movies_admin -D /var/lib/postgresql/data -R -X stream && chmod 700 /var/lib/postgresql/data"
}

repoint() {   # $1 = new host: point this shard's PgBouncer to it
  env "$HOST_VAR=$1" $DC up -d --no-deps "$BOUNCER"
}

case "$ACTION" in
  status)
    for c in "$PRIMARY" "$REPLICA"; do
      if docker exec "$c" true 2>/dev/null; then
        log "$c in_recovery(replica)=$(docker exec "$c" $SQL 'SELECT pg_is_in_recovery();') \
replicas=[$(docker exec "$c" $SQL "SELECT string_agg(client_addr::text || ' ' || state, ', ') FROM pg_stat_replication;")]"
      else
        log "$c is DOWN"
      fi
    done
    ;;
  crash)
    log "simulating crash: docker kill $PRIMARY"
    docker kill "$PRIMARY"
    ;;
  failover)
    log "promoting $REPLICA"
    docker exec "$REPLICA" $SQL "SELECT pg_promote();"
    log "repointing $BOUNCER -> ${NODE}_replica"
    repoint "${NODE}_replica"
    log "failover done"
    ;;
  rejoin)
    log "re-cloning $PRIMARY_VOL from ${NODE}_replica (pg_basebackup -R)"
    reclone "$PRIMARY_VOL" "${NODE}_replica"
    docker start "$PRIMARY"
    sleep 5
    log "rejoin done"
    ;;
  switchback)
    if [ "$(docker exec "$PRIMARY" $SQL 'SELECT pg_is_in_recovery();' 2>/dev/null)" != "t" ]; then
      log "ABORT: $PRIMARY is not running as a replica yet - run rejoin first"
      exit 1
    fi
    log "lag check: primary lsn=$(docker exec "$REPLICA" $SQL 'SELECT pg_current_wal_lsn();') \
replica replay lsn=$(docker exec "$PRIMARY" $SQL 'SELECT pg_last_wal_replay_lsn();')"
    docker stop "$REPLICA"
    log "promoting $PRIMARY"
    docker exec "$PRIMARY" $SQL "SELECT pg_promote();"
    repoint "$NODE"
    log "re-cloning $REPLICA as a replica again"
    reclone "$REPLICA_VOL" "$NODE"
    docker start "$REPLICA"
    sleep 5
    log "switchback done"
    ;;
esac
