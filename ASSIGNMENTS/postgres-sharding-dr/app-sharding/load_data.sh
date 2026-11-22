#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

python3 split_data.py 2

for s in 0 1; do
  PSQL="docker exec -i app_shard$s psql -U movies_admin -d movies -v ON_ERROR_STOP=1"
  $PSQL -c "\copy movie FROM STDIN CSV HEADER"               < ../common/data/movie.csv
  $PSQL -c "\copy \"user\" FROM STDIN CSV HEADER"            < data/shard$s/user.csv
  $PSQL -c "\copy user_recommendation FROM STDIN CSV HEADER" < data/shard$s/user_recommendation.csv
  $PSQL -c "\copy reaction FROM STDIN CSV HEADER"            < data/shard$s/reaction.csv
  $PSQL -c "ANALYZE;"
done
