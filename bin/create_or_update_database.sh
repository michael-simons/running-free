#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=en_US.UTF-8

DIR="$(dirname "$(realpath "$0")")"
DB="$(pwd)/$1"

duckdb "$DB" < "$DIR/../schema/base_tables.sql"
duckdb "$DB" < "$DIR/../schema/functions.sql"
duckdb "$DB" < "$DIR/../schema/shared_views.sql"
duckdb "$DB" < "$DIR/../schema/api.sql"
