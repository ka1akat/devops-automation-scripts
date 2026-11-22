#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
DATA=../common/data
PSQL="docker exec -i citus_coordinator psql -U movies_admin -d movies -v ON_ERROR_STOP=1"

$PSQL -c "\copy movie FROM STDIN CSV HEADER"               < $DATA/movie.csv
$PSQL -c "\copy \"user\" FROM STDIN CSV HEADER"            < $DATA/user.csv
$PSQL -c "\copy user_recommendation FROM STDIN CSV HEADER" < $DATA/user_recommendation.csv
$PSQL -c "\copy reaction FROM STDIN CSV HEADER"            < $DATA/reaction.csv

$PSQL -c "ANALYZE;"
