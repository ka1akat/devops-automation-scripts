import asyncio
import json
import os
import uuid

import asyncpg
from fastapi import FastAPI
from pydantic import BaseModel

from sharding import shard_for

MODE = os.environ.get("MODE", "app")              # "citus" or "app"
ROUTING_FILE = os.environ.get("ROUTING_FILE")     # app mode: {"active": N, "dsns": [...]}, re-read when changed

app = FastAPI()
_cfg = {"mtime": None, "dsns": os.environ.get("DSNS", "").split(",")}
_cfg["active"] = len(_cfg["dsns"])
_pools = {}
_lock = asyncio.Lock()

REC_USER = "SELECT movie_id, title FROM get_recommendations_by_user_id($1)"
REC_DEVICE = "SELECT movie_id, title FROM get_recommendations_by_device_id($1)"
INSERT_REACTION = ("INSERT INTO reaction (user_id, device_id, movie_id, reaction_type) "
                   "VALUES ($1, $2, $3, $4)")


def routing():
    """Current shard map. Reloaded from ROUTING_FILE when the file changes (no restart needed)."""
    if ROUTING_FILE:
        mtime = os.stat(ROUTING_FILE).st_mtime
        if mtime != _cfg["mtime"]:
            with open(ROUTING_FILE) as f:
                c = json.load(f)
            _cfg.update(mtime=mtime, active=c["active"], dsns=c["dsns"])
    return _cfg


async def pool(i):
    """Connection pool for shard i, created on first use."""
    dsn = routing()["dsns"][i]
    if dsn not in _pools:
        async with _lock:
            if dsn not in _pools:
                # statement_cache_size=0 is required behind PgBouncer in transaction mode
                _pools[dsn] = await asyncpg.create_pool(dsn, min_size=2, max_size=20,
                                                        statement_cache_size=0)
    return _pools[dsn]


def as_list(records):
    return [{"movie_id": str(r["movie_id"]), "title": r["title"]} for r in records]


@app.get("/rec/user/{user_id}")
async def rec_by_user(user_id: uuid.UUID):
    if MODE == "citus":
        rows = await (await pool(0)).fetch(REC_USER, user_id)
        return {"routed_to": "citus coordinator", "items": as_list(rows)}
    s = shard_for(user_id, routing()["active"])               # ROUTING in the app
    rows = await (await pool(s)).fetch(REC_USER, user_id)
    return {"routed_to": f"shard{s}", "items": as_list(rows)}


@app.get("/rec/device/{device_id}")
async def rec_by_device(device_id: uuid.UUID):
    if MODE == "citus":
        rows = await (await pool(0)).fetch(REC_DEVICE, device_id)
        return {"routed_to": "citus coordinator (fan-out to all workers)", "items": as_list(rows)}
    # no sharding key -> ask ALL shards in parallel (scatter) and merge (gather) in the app
    pools = [await pool(i) for i in range(routing()["active"])]
    results = await asyncio.gather(*(p.fetch(REC_DEVICE, device_id) for p in pools))
    seen, merged = set(), []
    for rows in results:                       # dedupe: during a migration a user can exist on 2 shards
        for item in as_list(rows):
            if item["movie_id"] not in seen:
                seen.add(item["movie_id"])
                merged.append(item)
    return {"routed_to": "all shards (scatter-gather in app)", "items": merged}


class Reaction(BaseModel):
    user_id: uuid.UUID
    device_id: uuid.UUID | None = None
    movie_id: uuid.UUID
    reaction_type: str


@app.post("/reaction")
async def add_reaction(r: Reaction):
    s = 0 if MODE == "citus" else shard_for(r.user_id, routing()["active"])
    await (await pool(s)).execute(INSERT_REACTION, r.user_id, r.device_id, r.movie_id, r.reaction_type)
    return {"ok": True}