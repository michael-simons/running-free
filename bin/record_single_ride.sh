#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=en_US.UTF-8

DB="$(pwd)/$1"
COVERED_ON="$(gdate -d $2 +'%Y-%m-%d')"
DISTANCE="$3"

case $DISTANCE in
  ''|*[!0-9.]*) echo "invalid distance '$DISTANCE'"; exit 1 ;;
esac

duckdb "$DB" -s "
  INSERT INTO assorted_trips (covered_on, distance)
  VALUES ('$COVERED_ON', $DISTANCE)
"
