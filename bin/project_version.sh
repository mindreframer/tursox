#!/usr/bin/env bash
set -euo pipefail
awk '/@version "/ {gsub(/"/, "", $2); print $2; exit}' mix.exs
