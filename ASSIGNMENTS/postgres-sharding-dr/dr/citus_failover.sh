#!/usr/bin/env bash
# Failover / rejoin / switchback for one Citus node.
# Usage: ./dr/citus_failover.sh <worker1|worker2|coordinator> <status|crash|failover|rejoin|switchback>
set -euo pipefail
cd "$(dirname "$0")/../citus"

NODE=$1
ACTION=$2
PRIMARY=citus_$NODE                 # container of the original primary
REPLICA=citus_${NODE}_replica       # container of its replica
PRIMARY_VOL=citus_${NODE}_data
REPLICA_VOL=citus_${NODE}_replica_data
DC="docker compose -f docker-compose.yml -f docker-compose.dr.yml"
SQL="psql -U movies_admin -d movies -v ON_ERROR_STOP=1 -tAc"

mkdir -p ../dr/logs
exec > >(tee -a "../dr/logs/citus_${NODE}.log") 2>&1
log() { echo "$(date +%T) [$NODE $ACTION] $*"; }

# Rebuild an old primary as a replica of the current primary:
# wipe its data directory and clone it again with pg_basebackup -R
reclone() {   # $1 = data volume to rebuild, $2 = host of the current primary
  docker run --rm --network citus_default -u postgres -v "$1":/var/lib/postgresql/data citus-arm:13.2 \
    bash -c "rm -rf /var/lib/postgresql/data/* && pg_basebackup -h $2 -U movies_admin -D /var/lib/postgresql/data -R -X stream && chmod 700 /var/lib/postgresql/data"
}

# Point Citus / PgBouncer to the new primary
repoint() {   # $1 = old host, $2 = new host, $3 = container of the new primary
  if [ "$NODE" = coordinator ]; then
    docker exec "$3" $SQL "SELECT citus_set_coordinator_host('$2', 5432);"
    COORD_HOST=$2 $DC up -d --no-deps pgbouncer
  else
    docker exec citus_coordinator $SQL \
      "SELECT citus_update_node(nodeid, '$2', 5432, force := true) FROM pg_dist_node WHERE nodename = '$1';"
  fi
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
    log "repointing ${NODE} -> ${NODE}_replica"
    repoint "$NODE" "${NODE}_replica" "$REPLICA"
    log "failover done"
    ;;
  rejoin)
    log "re-cloning $PRIMARY_VOL from ${NODE}_replica (pg_basebackup -R)"
    reclone "$PRIMARY_VOL" "${NODE}_replica"
    log "starting $PRIMARY as a replica"
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
    log "clean stop of $REPLICA (sends all WAL to the replica first)"
    docker stop "$REPLICA"
    log "promoting $PRIMARY"
    docker exec "$PRIMARY" $SQL "SELECT pg_promote();"
    repoint "${NODE}_replica" "$NODE" "$PRIMARY"
    log "re-cloning $REPLICA as a replica again"
    reclone "$REPLICA_VOL" "$NODE"
    docker start "$REPLICA"
    sleep 5
    log "switchback done"
    ;;
esac