# SQL & Migrations: movie recommendations

Student: Zhaslan Karakat

## Repository structure

```
/
├── docker-compose.yml        PostgreSQL 17 + PgBouncer
├── .gitlab-ci.yml            root pipeline: stages + include of environment pipelines
├── production/
│   ├── conf/flyway.toml      Flyway config for movies_prod
│   ├── sql/                  migrations V1..V4
│   └── .gitlab-ci.yml        validate/migrate jobs, run only on changes in production/
├── test/
│   ├── conf/flyway.toml      Flyway config for movies_test
│   ├── sql/                  migrations V1..V4
│   └── .gitlab-ci.yml        validate/migrate jobs, run only on changes in test/
├── bench/                    pgbench scripts
└── results/                  raw output of every EXPLAIN ANALYZE and pgbench run
```

## How to run

```bash
docker compose up -d
docker exec -it movies_pg psql -U movies_admin -d movies_prod -c 'CREATE DATABASE movies_test;'
docker exec -i movies_pg psql -U movies_admin -d movies_prod < production/sql/V1__baseline.sql
docker exec -i movies_pg psql -U movies_admin -d movies_test < test/sql/V1__baseline.sql
```

After that, migrations V2..V4 are applied by Flyway (manually or by the GitLab pipeline).

---

# Task 1. Optimized queries

## Functions

Both functions return the user's recommendations that are active now (`period @> NOW()`) and exclude movies that already have a reaction from this device / user.

- `get_recommendations_by_device_id(device_id)`: user is found by `device_id`, reactions are checked by `device_id`.
- `get_recommendations_by_user_id(user_id)`: user is found by `user_id`, reactions are checked by `user_id`.

`user_recommendation` has no `user_id`, so the link is `user.iin = user_recommendation.iin`.

## Test environment and method

- Everything runs in one Vagrant VM (Ubuntu): PostgreSQL 17 and PgBouncer in Docker, pgbench inside the Postgres container.
- `bench/by_device.sql` and `bench/by_user.sql` call the functions with a random user from the helper table `bench_ids` (1000 users that have a recommendation). Both scripts run together, 50/50.
- Load: `pgbench -c 50 -j 4 -T 30 -R <rate>`, where `-R 1000` and `-R 10000` simulate 1000 / 10 000 RPS.
- Single-query cost: `EXPLAIN ANALYZE`.

## Note about the baseline data

In the baseline script the subquery `SELECT movie_id FROM movie ORDER BY random() LIMIT 1` inside `CROSS JOIN LATERAL` does not reference the outer row, so PostgreSQL executes it once: every user gets the same recommended movie. The same happens in the reaction loop: the scalar subquery is evaluated once per INSERT, so reactions reference only about 100 different movies. This does not affect the performance comparison, but the result of each function is usually 0 or 1 movie.

## Step 0. Baseline (V2: naive functions)

Migration `V2__create_recommendation_functions.sql`: PL/pgSQL functions with `NOT IN (SELECT ... FROM reaction ...)`. No indexes, no primary keys.

EXPLAIN ANALYZE (`results/before_explain.txt`): execution time 38 ms. Every table is read with Seq Scan: 9 999 of 10 000 users and 99 950 of 100 000 reactions are read and thrown away, and because of `NOT IN` the whole `movie` table (100 000 rows) is scanned to return one movie.

Load (`results/before_1000rps.txt`, `results/before_10000rps.txt`):
- target 1000 RPS: real throughput 260 tps, average latency 11 429 ms;
- target 10 000 RPS: real throughput 260 tps, average latency 14 594 ms.

260 tps is the maximum of the database. Requests wait in a queue, latency grows every second. The service would not work under this load.

## Change 1. Indexes (V3) - big improvement

Migration `V3__add_indexes.sql`:
- `user(device_id)`, `user(user_id)`: find one user without scanning the table;
- `user_recommendation(iin)`: join user to recommendations;
- `movie(movie_id)`: join recommendation to movie;
- `reaction(device_id, movie_id)`, `reaction(user_id, movie_id)`: composite indexes, they answer "did this device/user react to this movie" directly from the index (Index Only Scan, Heap Fetches: 0);
- `ANALYZE` to refresh planner statistics.

Why it helps: a B-tree index finds the needed row in a few steps instead of reading the whole table.

Result (`results/v3_indexes_*`):
- EXPLAIN ANALYZE: 38 ms → 0.78 ms (about 50 times faster), all Seq Scans became Index Scans;
- 1000 RPS: 260 → 1009 tps, latency 11 429 ms → 0.91 ms. The target load is fully handled.

## Change 2. Rewritten functions (V4) - faster single query, no visible effect at 1000 RPS

Migration `V4__optimize_recommendation_functions.sql`:
- `NOT IN` → `NOT EXISTS`. `NOT IN` has special NULL semantics, so the planner could not turn it into an anti-join and built a hashed list of all reacted movies. `NOT EXISTS` becomes a Nested Loop Anti Join: one index lookup in `reaction` per candidate movie.
- `LANGUAGE plpgsql` → `LANGUAGE sql STABLE`. A simple SQL function can be inlined into the calling query, so the planner optimizes it as a normal SELECT (the plan is now visible in EXPLAIN). `STABLE` tells the planner the function does not modify data.
- `CREATE OR REPLACE`, so the migration can be re-run safely.

Result (`results/v4_functions_*`):
- EXPLAIN ANALYZE: 0.78 ms → 0.32 ms;
- 1000 RPS: 995 tps, average latency 2.18 ms. This is not better than V3 (0.91 ms). The standard deviation was 11.8 ms and maximum lag 178 ms: a few short stalls of the virtual machine. At 1000 RPS the gain of 0.5 ms per query is hidden by this noise;
- 10 000 RPS: 10 014 tps, average latency 0.78 ms. The target load is fully handled.

## Change 3. PgBouncer (connection pooler) - protects PostgreSQL, but slower for new connections

Added to `docker-compose.yml` (image `edoburu/pgbouncer`): `POOL_MODE=transaction`, `MAX_CLIENT_CONN=1000`, `DEFAULT_POOL_SIZE=20`, port 6432.

Why: every PostgreSQL connection is a separate process (fork, authentication, memory), and the default limit is 100 connections. PgBouncer accepts many client connections and serves them through a small pool of 20 real connections.

Test A, new connection for every request (`pgbench -C`, like an application without its own pool):
- direct to PostgreSQL, 1000 RPS: 1001 tps, latency 161 ms (`results/direct_newconn_1000rps.txt`);
- through PgBouncer, 1000 RPS: 811 tps, latency 2 930 ms (`results/pgbouncer_newconn_1000rps.txt`);
- through PgBouncer, 10 000 RPS: 715 tps, latency 14 341 ms (`results/pgbouncer_newconn_10000rps.txt`).

This is NOT an improvement. Reasons: PgBouncer is single-threaded, and SCRAM-SHA-256 password authentication (intentionally expensive hashing) runs for every new connection on its only CPU core. PostgreSQL authenticates in many processes on all cores. Also pgbench, PostgreSQL and PgBouncer share the same small VM.

Test B, 200 simultaneous clients (more than `max_connections = 100`):
- direct to PostgreSQL: error `FATAL: sorry, too many clients already` (`results/direct_200clients.txt`);
- through PgBouncer, 1000 RPS: 996 tps, latency 1.41 ms, 0 errors (`results/pgbouncer_200clients.txt`);
- through PgBouncer, 10 000 RPS: 9 975 tps, latency 2.65 ms, 0 errors.

Conclusion: PgBouncer does not make a single query faster, its value is that the database survives many more clients than its connection limit. In production the applications should keep long-lived connections to PgBouncer (or use their own pool), so the authentication cost is paid once.

## Considered, not applied

- `postgresql.conf`. After the indexes one query takes 0.3 ms and the whole data set (about 30 MB) fits into the default `shared_buffers` (128 MB), so memory settings would not change the result. Increasing `max_connections` is the wrong fix for the connection problem, because every connection is a process; the pooler solves it instead.
- Partitioning. Tables have 10 000–100 000 rows; with indexes every lookup is already a few index pages. Partitioning would only add planning overhead. It becomes useful for `reaction` when it grows to tens of millions of rows (for example, partition by `reaction_date`).
- Cache (e.g. Redis in front of the database). Can reduce the load further, but the cache must be invalidated on every new reaction, otherwise the user sees a movie he already disliked. Not needed for the current load.
- Primary keys. Indexes were added with `CREATE INDEX IF NOT EXISTS` to keep migrations re-runnable; adding primary keys would also guarantee uniqueness.

---

# Task 2. Flyway and GitLab CI

## Migrations

- `V1__baseline.sql`: the given baseline script.
- `V2__create_recommendation_functions.sql`: naive functions.
- `V3__add_indexes.sql`: indexes.
- `V4__optimize_recommendation_functions.sql`: optimized functions.

Both databases already existed with the baseline tables, so `flyway.toml` uses `baselineOnMigrate = true` and `baselineVersion = "1"`: Flyway marks the existing state as version 1 and applies V2..V4. All migrations are re-runnable (`CREATE OR REPLACE`, `IF NOT EXISTS`). `ignoreMigrationPatterns = ["*:pending"]` lets the validate stage pass before new migrations are applied.

## Pipeline

- Root `.gitlab-ci.yml` defines stages `validate` and `migrate` and includes `production/.gitlab-ci.yml` and `test/.gitlab-ci.yml`.
- Each environment has two jobs, `validate_<env>` and `migrate_<env>`, with `rules: changes: <env>/**/*`, so a change in `production/` runs only the production pipeline and a change in `test/` only the test pipeline.
- Jobs run on a project runner inside the same VM (tag `bluegreen`), because the databases are not reachable from GitLab shared runners.
- Each job runs the official `flyway/flyway` image: `docker create` → `docker cp <env>/.` into the container → `docker start -a` (the exit code of Flyway becomes the result of the job), `after_script` removes the container.
