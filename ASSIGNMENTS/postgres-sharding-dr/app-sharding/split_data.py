import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "api"))
from sharding import shard_for  # same rule as the API

NUM_SHARDS = int(sys.argv[1]) if len(sys.argv) > 1 else 2
SRC = os.path.join(HERE, "..", "common", "data")
DST = os.path.join(HERE, "data")

for table in ["user", "user_recommendation", "reaction"]:
    files, writers = [], []
    for s in range(NUM_SHARDS):
        os.makedirs(f"{DST}/shard{s}", exist_ok=True)
        f = open(f"{DST}/shard{s}/{table}.csv", "w", newline="")
        files.append(f)
        writers.append(csv.writer(f))
    with open(f"{SRC}/{table}.csv", newline="") as src:
        reader = csv.reader(src)
        header = next(reader)
        for w in writers:
            w.writerow(header)
        col = header.index("user_id")
        counts = [0] * NUM_SHARDS
        for row in reader:
            s = shard_for(row[col], NUM_SHARDS)
            writers[s].writerow(row)
            counts[s] += 1
    for f in files:
        f.close()
    print(table, "rows per shard:", counts)
