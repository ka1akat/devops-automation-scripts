# db-sharding: sharded PostgreSQL for the movie recommendation service

DevOps course assignment (KBTU). Author: Zhaslan Karakat.

This repository continues the previous assignment (`db_sql-migration`): the same movie
recommendation database with the functions `get_recommendations_by_user_id` and
`get_recommendations_by_device_id`, now sharded across independent PostgreSQL primaries
in two ways:

1. `citus/` – with an external tool (Citus) that distributes tables and routes queries.
2. `app-sharding/` – at the application level: shard selection, routing, data distribution
   and result aggregation are implemented in my own code.

Both variants use the same dataset, the same API (`api/`) and the same load test.

## Repository layout

- `common/sql/` – schema, indexes and functions copied from the previous assignment (V1–V4).
- `common/generate_data.sh` – generates the dataset once (runs V1 in a temporary container) and
  exports it to CSV, so both variants load exactly the same rows. CSV files are not committed.
- `common/bench/load.js` – k6 load test (same workload for both variants).
- `api/` – one FastAPI service used by both variants. `MODE=citus` sends every request to the
  Citus coordinator, `MODE=app` chooses the shard itself (`api/sharding.py`).
- `citus/` – variant 1: custom Citus image, docker-compose files (cluster, DR, third worker),
  SQL scripts and results.
- `app-sharding/` – variant 2: docker-compose files (shards, PgBouncers, API, DR, third shard),
  data splitter, loader, online migration script and routing file.
- `dr/` – base backup script, failover/rejoin/switchback scripts and their logs (`dr/logs/`).
- `results/` – load test and disaster recovery results.

## Data model and sharding key

Tables: `user` (10 000 rows), `movie` (100 000), `user_recommendation` (5 008),
`reaction` (100 000).

Sharding key: `user_id`.

- `get_recommendations_by_user_id` receives `user_id`, so it can be routed to exactly one shard.
- `iin` is never sent by a client, so it cannot be used for routing.
- All data of one user (`user`, `user_recommendation`, `reaction`) is stored on the same shard,
  so the recommendation query runs inside one shard without network hops (co-location).
- `user_recommendation` had no `user_id`, only `iin`. I added a `user_id` column (filled from
  `user` by `iin` while exporting the dataset), otherwise its rows could not be placed by the key.
- `movie` is a small, shared, rarely changing catalog that every recommendation joins with, so it
  is fully copied to every shard instead of being split.
- `user_id` became `NOT NULL` in all distributed tables. Reactions without `user_id`
  (device-only "guest" reactions) are therefore not supported. This is a limitation of the chosen key.

Request without the sharding key: `get_recommendations_by_device_id` receives only `device_id`.
The router cannot know which shard holds this device, so the request is sent to all shards and
the results are merged (scatter-gather).

Unique ids: all ids are `UUID` generated with `gen_random_uuid()`. They are random 128-bit values,
so every shard can create ids independently without coordination. I also considered per-shard
sequences (odd/even numbers), but that hard-codes the number of shards into the ids, and a
central sequence server, which becomes a bottleneck and a single point of failure.

## Task 1, variant 1: Citus (`citus/`)

Architecture: client → API (port 8001) → PgBouncer (port 6440) → coordinator → worker1 / worker2.
Only PgBouncer and the API are published to the host. Coordinator and workers are reachable only
inside the Docker network.

The official `citusdata/citus` image is built only for amd64, my VM is arm64 (Apple silicon), and
the Citus package repository has no arm64 packages either. So `citus/Dockerfile` builds Citus
13.2 from source on top of `postgres:17`, following the Debian build instructions in Citus
`CONTRIBUTING.md`.

Steps (`citus/sql/`):
1. `01_cluster_setup.sql` – `citus_set_coordinator_host`, `citus_add_node` for both workers.
2. `02_schema.sql` – tables, `create_reference_table('movie')`, `create_distributed_table` for
   `user`, `user_recommendation`, `reaction` by `user_id`, co-located with `user`
   (32 shards each, 16 per worker, same `colocation_id`).
3. `load_data.sh` – loads the shared CSV through the coordinator. Citus routes every row to its shard.
4. `03_indexes_functions.sql` – indexes and the two recommendation functions.

Data distribution (users per worker): worker1 – 4 956, worker2 – 5 044.

Where routing and aggregation happen: in the coordinator (`citus/results/explain_routing.txt`).
- Request by `user_id`: `Task Count: 1`, one shard on one worker (router query).
- Request by `device_id`: `Task Count: 32`, all shards on both workers, and the coordinator merges
  the results.

Joins, unique ids, transactions (`citus/results/demo_join_ids_tx.txt`):
- A join of co-located tables by `user_id` plus the reference table `movie` works.
- A join by `iin` is rejected: "the query contains a join that requires repartitioning".
- 10 000 users, 10 000 distinct `user_id`. A new user inserted with `gen_random_uuid()` was placed
  on a worker automatically.
- A transaction that writes to worker1 and then fails on worker2 is rolled back on both workers
  (0 rows left). A valid transaction across both workers commits on both (Citus uses two-phase commit).

Query limitations found in Citus:
- Joins between distributed tables must use the distribution column. The functions were changed
  to join `user_recommendation` by `user_id` instead of `iin`.
- SQL-language functions with parameters over distributed tables are not supported
  ("parameterized queries for SQL functions referencing distributed tables are not supported").
  The functions were rewritten in PL/pgSQL, which means losing the inlining optimisation from V4.

## Task 1, variant 2: application-level sharding (`app-sharding/`)

Architecture: client → API (port 8002) → PgBouncer0 (6441) → shard0, PgBouncer1 (6442) → shard1.
The shards are plain PostgreSQL 17 without any extension.

- Shard selection: `api/sharding.py`, `shard = UUID(user_id) as integer % number_of_shards`.
  UUIDs are random, so the distribution is even. The same function is used by the API, the loader
  and the migration script.
- Data distribution: `app-sharding/split_data.py` splits the shared CSV by this rule. `movie` is
  loaded into every shard. Result: users 5 082 / 4 918, recommendations 2 504 / 2 504,
  reactions 52 384 / 47 616.
- Routing: in `api/main.py`. A request with `user_id` goes to one shard, and the response shows
  `"routed_to": "shard1"`.
- Aggregation: a request with `device_id` is sent to all shards in parallel (`asyncio.gather`), and
  the lists are merged (and de-duplicated) in the API
  (`"routed_to": "all shards (scatter-gather in app)"`).
- Functions: the V3 indexes and V4 functions from the previous assignment run unchanged on every
  shard, because all data of a user is local to one shard.
- Joins: every per-user join is local to one shard. `movie` is present on every shard.
  Joins or aggregations across users must be done in the application.
- Transactions: atomic inside one shard (all data of one user). Atomic writes across shards are
  not provided. They would require implementing two-phase commit (`PREPARE TRANSACTION`) or
  compensation logic in the application.

Both variants return the same result for the same user (`curl` on `/rec/user/...` and
`/rec/device/...`), so the behaviour of `get_rec_*` is preserved.

## Task 1: load test

Tool: k6 (`common/bench/load.js`), executor `constant-arrival-rate`, 30 s per run, at most 1 000
virtual users. Mix: 70% recommendations by `user_id`, 20% by `device_id` (without the sharding key),
10% writes (`POST /reaction`). The same API code, dataset and VM (4 vCPU, 5.6 GB RAM) were used.
The other variant was stopped during each run.

Results (`results/citus_*rps.txt`, `results/app_*rps.txt`):
- Citus, target 1 000 RPS: achieved 386 RPS, latency avg 2.37 s, p95 4.16 s, errors 0%.
- Citus, target 10 000 RPS: achieved 515 RPS, latency avg 1.85 s, p95 3.4 s, errors 0%.
- Application-level, target 1 000 RPS: achieved 1 000 RPS, latency avg 4.2 ms, p95 5.6 ms, errors 0%.
- Application-level, target 10 000 RPS: achieved 2 396 RPS, latency avg 405 ms, p95 1.19 s, errors 0%.

Bottlenecks:
- Everything runs on one VM with 4 vCPU: the databases, PgBouncers, the Python API (2 uvicorn
  workers) and the k6 load generator compete for the same CPU. 10 000 RPS is not reachable on this
  hardware for either variant.
- Citus is slower because every request passes through the coordinator (one more network hop and
  distributed planning), the functions are PL/pgSQL (no inlining), and every request without the
  sharding key fans out to all 32 shards, that is 32 sub-queries instead of 2 in variant 2.
  Possible improvements: fewer shards (`citus.shard_count`), delegating the function to workers
  (`create_distributed_function`), more CPU for the coordinator.

## Task 1: comparison

Implementation effort: Citus needed a custom image for arm64 and a few SQL calls, after which
distribution, routing, merging and distributed transactions came out of the box. The application
variant needed my own routing function, a data splitter, a loader and the scatter-gather logic.

Query limitations: Citus restricts queries (joins only by the distribution column, no parameterized
SQL functions), but it supports cross-shard queries and transactions. The application variant keeps
plain SQL on each shard, but anything across shards (joins, aggregation, transactions) must be
written by hand.

Adding a shard: in Citus it is `citus_add_node` plus the online rebalancer, which moves whole shards.
In the application variant the modulo rule changes, so most rows must move, and the migration and
routing switch must be written by me (see Task 3).

Responsibilities. Citus handles: shard placement, routing, scatter-gather and merging, distributed
transactions (2PC), metadata, rebalancing. I implemented myself in variant 2: the sharding function,
data splitting and loading, routing, scatter-gather, connection pools per shard and the migration.
Both variants use PgBouncer as the connection pooler.

## Task 2: Disaster recovery

### Setup (both variants)
- Backup site: a separate Docker volume `dr_backup_site` (outside the primary data volumes),
  one folder per node: `coordinator`, `worker1`, `worker2`, `shard0`, `shard1`.
- WAL archiving: `archive_mode=on`, `archive_command` gzips every finished WAL segment to the
  backup site, `archive_timeout=300` forces a switch at least every 5 minutes.
- Base backups: `dr/base_backup.sh` (`pg_basebackup -Ft -z -X stream`) writes a compressed full
  backup of every node to the backup site (13–14 MB per Citus node). In production it would run
  from cron once a day.
- Replication: every primary (coordinator, worker1, worker2, shard0, shard1) has an
  asynchronous streaming replica, created with `pg_basebackup -R`
  (`citus/docker-compose.dr.yml`, `app-sharding/docker-compose.dr.yml`).
- Why asynchronous: the allowed data loss is 30 minutes. Synchronous replication would add a
  network round trip to every write and would stop all writes if the replica is down.
  With async replication the replica normally lags by less than a second, and the WAL archive
  limits the loss on a full site failure to about 5 minutes.

Targets: RTO 15 minutes, data loss (RPO) 30 minutes.

### Procedures
`dr/citus_failover.sh <node> <action>` and `dr/app_failover.sh <shard> <action>`:
- `crash` – `docker kill` of the primary (sudden failure).
- `failover` – `pg_promote()` on the replica, then route traffic to it: Citus –
  `citus_update_node` for a worker, `citus_set_coordinator_host` + PgBouncer `DB_HOST` for the
  coordinator; app variant – the shard's PgBouncer `DB_HOST` (the API does not change).
- `rejoin` – the failed primary is re-cloned from the new primary with `pg_basebackup -R` and
  started as its replica.
- `switchback` – checks that the old primary is a replica and compares LSNs, stops the
  temporary primary cleanly (it sends all WAL first), promotes the original node, re-points
  traffic and re-clones the temporary primary as a replica again.
Every step is logged with a timestamp in `dr/logs/`.

### Scenarios (under constant load of 100 RPS, k6)

Citus, worker1 failure:
- 12:33:03 crash, 12:33:54 failover done – about 51 s of partial outage (users of worker1 and
  requests without the sharding key).
- Switch back 12:40:24–12:41:46: primary LSN 0/D0F6690 = replica replay LSN 0/D0F6690, no data loss.

Citus, coordinator failure:
- 12:43:01 crash, 12:44:05 failover done – about 64 s of full outage (all requests go through
  the coordinator, it is a single point of failure, so its replica is essential).
- Switch back 12:45:20–12:45:39: LSN 0/A000EF0 on both, no data loss.

Citus load result for the whole DR session (`results/dr_citus_status_codes.txt`,
`results/dr_citus_errors_per_minute.txt`): 85 988 requests, 21 879 errors. The errors
between 12:34 and 12:38 were caused by my first version of the script, not by the failure:
`pg_rewind` failed (stale `postmaster.pid` after the crash and `wal_log_hints` not stored in
the cluster) and the switchback then stopped the working replica. The fix: rejoin by
re-cloning with `pg_basebackup -R`, and switchback now refuses to run if the old primary is not
a replica yet.

Application variant, shard0 failure:
- 12:52:13 crash, 12:56:31 failover done. The failover itself took about 1 s; the rest was the
  operator's waiting time. Only users of shard0 and requests by `device_id` failed, shard1 kept
  working.
- Switch back 12:57:04–12:57:44: LSN 0/90A3878 on both, no data loss.
- Load: 36 001 requests, 16 231 errors, all during the outage window
  (`results/dr_app_errors_per_minute.txt`), plus about 10 s of errors during the switchback while
  PgBouncer was recreated.

Result: recovery time well below 15 minutes and zero data loss on switch back in every scenario.

Lessons and improvements: an automatic failover manager (Patroni or pg_auto_failover) would
cut the outage from minutes to seconds; retries in the API would hide short PgBouncer restarts;
the same procedure applies to worker2 and shard1 (not repeated). A full restore from the base
backup plus WAL archive (point-in-time recovery) is prepared but was not rehearsed.

## Task 3: Adding a third shard without downtime

### Citus (`citus/docker-compose.shard3.yml`, `citus/sql/06_add_shard.sql`)
- `citus_add_node('worker3')`, then `citus_rebalance_start` and `citus_rebalance_wait`.
- 13:03:56–13:04:01: 10 shard moves in 5 s. Shards of `user`: 16/16 → 11/11/10;
  users: 3 401 / 3 461 / 3 138 (`citus/results/task3_citus_rebalance.txt`).
- Load during the rebalance (`results/task3_citus_load.txt`): 23 772 requests, 0% errors,
  p99 3.5 s (writes briefly waited).
- The tables have no primary key, so the non-blocking (logical replication) transfer is not
  possible. I used `shard_transfer_mode := 'block_writes'`: reads continue, writes to a shard
  being moved wait until it is copied. Adding primary keys would make the move fully online.
- Only whole shards move (10 of 32 shard groups), the rows inside them are not re-hashed.

### Application variant (`app-sharding/add_shard.py`, `app-sharding/docker-compose.shard3.yml`)
The rule changes from `uuid % 2` to `uuid % 3`, so users move between all shards, not only to
the new one. Online migration in five phases:
1. `copy` – rows of every moving user are copied to the new shard; the API still routes by `% 2`.
2. `catchup` – reactions written during the copy are copied too.
3. `cutover` – `app-sharding/routing/routing.json` is switched to 3 shards. The API re-reads this
   file on change, so no restart is needed.
4. `catchup` again – picks up writes made just before the switch.
5. `cleanup` – old copies are deleted from the old shards.
While old copies exist, a user may be found on two shards, so the API removes duplicates in
scatter-gather.

Result (under 100 RPS load, `results/task3_app_migration.txt`): 13:21:45–13:21:54 (9 s),
6 707 of 10 000 users moved (67%), final distribution 3 213 / 3 350 / 3 437. The two catchup
phases copied 8 and 1 reactions that were written during the migration. Check for lost writes:
the API accepted 2 413 reactions since the load started, and the three shards contain
816 + 767 + 830 = 2 413 of them, so no write was lost. Load: 24 001 requests, 0% errors,
p99 7 ms (`results/task3_app_load.txt`).

Note: my first run happened right after the load test had already finished, so it was not
under load (0 writes during the migration). I reset the data and repeated it under load.

### Comparison
Citus does placement, copying, routing changes and metadata itself, and moves only about a third
of the data. In my own variant I had to write the migration, the routing switch and the
cleanup, and the modulo rule moved two thirds of the rows. A better design for the application
variant is a fixed number of virtual buckets (for example 256) mapped to servers, or consistent
hashing, so that adding a server moves only its share of buckets.

## How to run

```bash
./common/generate_data.sh                      # dataset -> common/data/*.csv

# Variant 1: Citus
docker build -t citus-arm:13.2 citus/
cd citus && docker compose up -d --build && cd ..
docker exec -i citus_coordinator psql -U movies_admin -d movies < citus/sql/01_cluster_setup.sql
docker exec -i citus_coordinator psql -U movies_admin -d movies < citus/sql/02_schema.sql
./citus/load_data.sh
docker exec -i citus_coordinator psql -U movies_admin -d movies < citus/sql/03_indexes_functions.sql
curl localhost:8001/rec/user/<user_id>

# Variant 2: application level
cd app-sharding && docker compose up -d --build && cd ..
./app-sharding/load_data.sh
curl localhost:8002/rec/user/<user_id>

# Task 2: add DR (replicas + WAL archive) on top of a variant
docker volume create dr_backup_site
cd citus && docker compose -f docker-compose.yml -f docker-compose.dr.yml up -d && cd ..
./dr/base_backup.sh citus_coordinator:coordinator citus_worker1:worker1 citus_worker2:worker2
./dr/citus_failover.sh worker1 status    # crash | failover | rejoin | switchback

# Task 3: third shard
cd citus && docker compose -f docker-compose.yml -f docker-compose.dr.yml -f docker-compose.shard3.yml up -d && cd ..
docker exec -i citus_coordinator psql -U movies_admin -d movies < citus/sql/06_add_shard.sql
```

Note: recommendations in the dataset are valid for 30 days from generation (`period`).
After that, run `generate_data.sh` and the loaders again.

## Status
All three tasks are implemented. Not rehearsed: point-in-time restore from the backup site,
failure of worker2 / shard1 (same procedure).