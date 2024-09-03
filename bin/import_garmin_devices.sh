#!/usr/bin/env bash

#
# Needs https://github.com/michael-simons/garmin-babel on the path
# Also configure
# export GARMIN_JWT=jwt_token_from_your_cookie_store_for_garmin
# export GARMIN_BACKEND_TOKEN=long_gibberish_token_from_one_of_the_requests
#

set -euo pipefail
export LC_ALL=en_US.UTF-8

DB="$(pwd)/$1"
GARMIN_ARCHIVE=$2

garmin-babel "$GARMIN_ARCHIVE" dump-devices |
duckdb "$DB" -s "
  INSERT INTO garmin_devices BY NAME (
    SELECT * FROM read_csv_auto('/dev/stdin')
  )
  ON CONFLICT DO NOTHING
"
