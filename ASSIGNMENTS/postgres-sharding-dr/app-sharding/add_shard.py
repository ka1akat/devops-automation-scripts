"""Online migration from 2 to 3 shards (application-level sharding).
Usage: python add_shard.py <status|copy|catchup|cutover|cleanup>"""
import asyncio
import json
import os
import sys
from datetime import datetime

import asyncpg

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "api"))
from sharding import shard_for  # same rule as the API

DSNS = [f"postgresql://movies_admin:movies_pass@127.0.0.1:{p}/movies" for p in (6441, 6442, 6443)]
OLD, NEW = 2, 3
TABLES = ["user", "user_recommendation", "reaction"]
ROUTING = os.path.join(HERE, "routing", "routing.json")
STATE = os.path.join(HERE, "data", "migration_t0.txt")   # when the copy started


def q(t):
    return '"user"' if t == "user" else t


def log(*a):
    print(datetime.now().strftime("%H:%M:%S"), *a, flush=True)


async def status(c):
    for s in range(NEW):
        log(f"shard{s}: users={await c[s].fetchval('SELECT count(*) FROM \"user\"')} "
            f"reactions={await c[s].fetchval('SELECT count(*) FROM reaction')}")


async def copy(c):
    t0 = await c[0].fetchval("SELECT now()")
    with open(STATE, "w") as f:
        f.write(t0.isoformat())
    for t in TABLES:
        for s in range(OLD):
            rows = await c[s].fetch(f"SELECT * FROM {q(t)}")
            moves = {}
            for r in rows:
                d = shard_for(r["user_id"], NEW)
                if d != s:
                    moves.setdefault(d, []).append(tuple(r.values()))
            for d, recs in moves.items():
                await c[d].copy_records_to_table(t, records=recs, columns=list(rows[0].keys()))
                log(f"copy {t}: shard{s} -> shard{d}: {len(recs)} rows")


async def catchup(c):
    with open(STATE) as f:
        t0 = datetime.fromisoformat(f.read()).replace(tzinfo=None)
    for s in range(OLD):
        rows = await c[s].fetch("SELECT * FROM reaction WHERE reaction_date >= $1", t0)
        n = 0
        for r in rows:
            d = shard_for(r["user_id"], NEW)
            if d == s:
                continue
            res = await c[d].execute(
                "INSERT INTO reaction (user_id, device_id, movie_id, reaction_type, reaction_date) "
                "SELECT $1::uuid, $2::uuid, $3::uuid, $4::varchar, $5::timestamp "
                "WHERE NOT EXISTS (SELECT 1 FROM reaction WHERE user_id = $1 AND movie_id = $3 "
                "AND reaction_type = $4 AND reaction_date = $5)",
                r["user_id"], r["device_id"], r["movie_id"], r["reaction_type"], r["reaction_date"])
            n += res.endswith(" 1")
        log(f"catchup reactions written on shard{s} since {t0}: {n} new rows copied")


def cutover():
    with open(ROUTING) as f:
        cfg = json.load(f)
    cfg["active"] = NEW
    tmp = ROUTING + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cfg, f, indent=2)
    os.replace(tmp, ROUTING)          # atomic switch, the API picks it up on the next request
    log(f"routing switched to {NEW} shards")


async def cleanup(c):
    for t in TABLES:
        for s in range(OLD):
            ids = [r["user_id"] for r in await c[s].fetch(f"SELECT DISTINCT user_id FROM {q(t)}")
                   if shard_for(r["user_id"], NEW) != s]
            res = await c[s].execute(f"DELETE FROM {q(t)} WHERE user_id = ANY($1::uuid[])", ids)
            log(f"cleanup {t} on shard{s}: {res}")
    for s in range(NEW):
        await c[s].execute("ANALYZE")


async def main():
    phase = sys.argv[1]
    if phase == "cutover":
        cutover()
        return
    c = [await asyncpg.connect(d, statement_cache_size=0) for d in DSNS]
    await {"status": status, "copy": copy, "catchup": catchup, "cleanup": cleanup}[phase](c)


asyncio.run(main())
