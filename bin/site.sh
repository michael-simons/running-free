#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=en_US.UTF-8

(source ./.venv/bin/activate && python ./generator/app.py "$@")
