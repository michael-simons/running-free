#!/usr/bin/env bash

#
# Needs https://github.com/michael-simons/garmin-babel on the path
#

set -euo pipefail
export LC_ALL=en_US.UTF-8

DB="$(pwd)/$1"
GARMIN_ARCHIVE=$2
GARMIN_USER=$3

garmin-babel "$GARMIN_ARCHIVE" dump-activities --user-name="$GARMIN_USER" |
duckdb "$DB" -s "
  INSERT INTO garmin_activities BY NAME (
  SELECT * EXCLUDE(avg_speed, max_speed) REPLACE(coalesce(name, 'n/a') AS name)
  FROM read_csv_auto('/dev/stdin'))
  ON CONFLICT DO NOTHING
"
