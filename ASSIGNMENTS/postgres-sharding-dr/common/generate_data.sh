#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p data

docker run -d --name datagen -e POSTGRES_PASSWORD=gen -v "$PWD:/common" postgres:17

until docker exec datagen pg_isready -h 127.0.0.1 -U postgres; do
  sleep 1
done

docker exec datagen psql -U postgres -v ON_ERROR_STOP=1 -f /common/sql/V1__baseline.sql

docker exec datagen psql -U postgres -c "\copy \"user\" TO '/common/data/user.csv' CSV HEADER"
docker exec datagen psql -U postgres -c "\copy movie TO '/common/data/movie.csv' CSV HEADER"
docker exec datagen psql -U postgres -c "\copy reaction (user_id, device_id, movie_id, reaction_type, reaction_date) TO '/common/data/reaction.csv' CSV HEADER"
docker exec datagen psql -U postgres -c "\copy (SELECT u.user_id, ur.iin, ur.movie_id, ur.period FROM user_recommendation ur JOIN \"user\" u ON u.iin = ur.iin) TO '/common/data/user_recommendation.csv' CSV HEADER"

docker rm -f datagen
wc -l data/*.csv
