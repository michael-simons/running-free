#!/usr/bin/env bash

#
# Creates a backup of the database.
# The backup will be a compressed file with data in CSV, as loading geometry columns
# from Parquet won't work. Also, the schema might references functions in views that
# are most likely not yet defined. This means the backup needs most likely be loaded
# in a way that first create_or_update_database.sh is used to create an empty database,
# than just the generated load.sql file.
#

set -euo pipefail
export LC_ALL=en_US.UTF-8

DB="$(pwd)/$1"
BASENAME=$(date +'%Y-%m-%d')

mkdir -p backup
duckdb "$DB" \
   -s "INSTALL spatial" \
   -s "LOAD spatial" \
   -s "EXPORT DATABASE 'backup/$BASENAME'"

(cd backup && zip -r "$BASENAME".zip "$BASENAME")
rm -rf backup/"$BASENAME"
