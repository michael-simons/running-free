#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=en_US.UTF-8

DB="$(pwd)/$1"
BIKE="$2"
ITEM="$3"
REMOVED="${4:-false}"

duckdb "$DB" -s "
  WITH hlp AS (
    SELECT b.id AS bike_id,
           coalesce(max(pos), 0) + 10 AS pos
    FROM bikes b LEFT OUTER JOIN bike_specs s ON s.bike_id = b.id
    WHERE b.name = '$BIKE'
    GROUP BY ALL
  )
  INSERT INTO bike_specs BY NAME
  SELECT hlp.*, '$ITEM' as item, $REMOVED AS removed
  FROM hlp
"
