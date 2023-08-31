#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=en_US.UTF-8

DB="$(pwd)/$1"

# Loading does not (yet) work, see
# https://github.com/duckdb/duckdb/issues/8496
# and
# https://github.com/duckdb/duckdb/pull/8619

mkdir -p backup
duckdb "$DB" -s "
  EXPORT DATABASE 'backup/$(date +'%Y-%m-%d')' (FORMAT PARQUET, COMPRESSION ZSTD);
"
