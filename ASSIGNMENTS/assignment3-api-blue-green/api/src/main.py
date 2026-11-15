import asyncio
import os

import asyncpg
from fastapi import FastAPI, HTTPException

app = FastAPI()
DATABASE_URL = os.environ["DATABASE_URL"]


async def fetch_value(sql: str):
    try:
        async with asyncio.timeout(5):
            connection = await asyncpg.connect(DATABASE_URL)
            try:
                return await connection.fetchval(sql)
            finally:
                await connection.close(timeout=1)
    except (asyncpg.PostgresError, asyncpg.InterfaceError, OSError):
        raise HTTPException(503, "Database unavailable") from None


@app.get("/health/live")
async def live():
    return {"status": "alive", "version": "2"}


@app.get("/health/ready")
async def ready():
    await fetch_value("SELECT 1")
    return {"status": "ready"}


@app.get("/db-time")
async def db_time():
    return {"db_time": await fetch_value("SELECT NOW()")}
