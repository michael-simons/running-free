#!/usr/bin/env bash

#
# Needs https://github.com/michael-simons/garmin-babel on the path
#

set -euo pipefail
export LC_ALL=en_US.UTF-8

DB="$(pwd)/$1"
GARMIN_ARCHIVE=$2
GARMIN_USER=$3
TARGET="$(pwd)/$4/f.csv"
TARGET_DIR="$(pwd)/$4"

START_DATE=$(duckdb "$DB" -noheader -list -readonly -c "select max(started_on::date) + INTERVAL 1 day FROM garmin_activities")

garmin-babel --start-date="$START_DATE" "$GARMIN_ARCHIVE" dump-activities --user-name="$GARMIN_USER" --sport-type=RUNNING --min-distance=10 --download=gpx "$TARGET"
garmin-babel --start-date="$START_DATE" "$GARMIN_ARCHIVE" dump-activities --user-name="$GARMIN_USER" --sport-type=RUNNING --min-distance=10 --download=fit "$TARGET"
garmin-babel --start-date="$START_DATE" "$GARMIN_ARCHIVE" dump-activities --user-name="$GARMIN_USER" \
  --sport-type=CYCLING --activity-type=road_biking,gravel_cycling,cycling,mountain_biking,virtual_ride,indoor_cycling \
  --min-distance=75 --download=gpx "$TARGET"
garmin-babel --start-date="$START_DATE" "$GARMIN_ARCHIVE" dump-activities --user-name="$GARMIN_USER" \
  --sport-type=CYCLING --activity-type=road_biking,gravel_cycling,cycling,mountain_biking,virtual_ride,indoor_cycling \
  --min-distance=75 --download=fit "$TARGET"
rm "$TARGET"

find "$TARGET_DIR" -iname "*.gpx" -exec basename {} .gpx \; |
duckdb "$DB" -s "
  UPDATE garmin_activities SET gpx_available = true
  WHERE garmin_id IN (
    FROM read_csv_auto('/dev/stdin')
  )
"
