#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=en_US.UTF-8

DB="$(pwd)/$1"

duckdb "$DB" -readonly -s "
  SELECT b.name, max(recorded_on) AS last_recording, arg_max(amount, recorded_on) AS last_amount
  FROM milages m JOIN bikes b ON b.id = m.bike_id
  WHERE b.decommissioned_on IS NULL
  GROUP BY ALL
  ORDER BY name ASC
"
