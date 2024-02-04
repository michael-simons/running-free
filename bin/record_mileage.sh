#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=en_US.UTF-8

DB="$(pwd)/$1"
BIKE="$2"
MILEAGE="$3"

case $MILEAGE in
  ''|*[!0-9.]*) echo "invalid mileage '$MILEAGE'"; exit 1 ;;
esac

duckdb "$DB" -s "
  WITH hlp AS (
    SELECT max(recorded_on) + INTERVAL 1 MONTH AS recorded_on, m.bike_id, last(amount) AS last_amount
    FROM milages m JOIN bikes b ON b.id = m.bike_id
    WHERE b.name = '$BIKE'
    GROUP BY ALL
    ORDER BY ALL
  )
  INSERT INTO milages BY NAME
  SELECT hlp.* EXCLUDE(last_amount), $MILEAGE AS amount, date_trunc('second', now()) AS created_at
  FROM hlp
  WHERE hlp.last_amount <= $MILEAGE
"
