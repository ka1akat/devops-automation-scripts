import uuid


def shard_for(user_id, num_shards: int) -> int:
    """Shard number for a user: UUID as a big number, modulo number of shards."""
    return uuid.UUID(str(user_id)).int % num_shards
