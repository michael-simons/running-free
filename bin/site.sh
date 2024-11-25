#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=en_US.UTF-8

DIR="$(dirname "$(realpath "$0")")"

if [ -f "$DIR"/../.secrets/thunderforest_api_key ]; then
  THUNDERFOREST_API_KEY="$(< "$DIR"/../.secrets/thunderforest_api_key)"
  export THUNDERFOREST_API_KEY
fi

(source ./.venv/bin/activate && python ./generator/app.py "$@")
