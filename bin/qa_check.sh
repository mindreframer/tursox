#!/usr/bin/env bash
set -uo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${project_root}"

log_root="${project_root}/_build/qa/latest"
rm -rf "${log_root}"
mkdir -p "${log_root}"

# Turso 0.7.2 debug MVCC bootstrap needs more dirty-I/O scheduler stack than
# OTP's default. Apply this for local runs as well as CI.
export ERL_FLAGS="${ERL_FLAGS:-} +sssdio 64"

run_stage() {
  local key="$1"
  local label="$2"
  shift 2
  local log="${log_root}/${key}.log"
  local started=$SECONDS

  printf '[qa/%s] %s\n' "$key" "$label"
  if "$@" >"$log" 2>&1; then
    printf '[qa/%s] ok (%ss)\n' "$key" "$((SECONDS - started))"
  else
    local status=$?
    printf '[qa/%s] FAILED (exit %s, %ss)\n' "$key" "$status" "$((SECONDS - started))" >&2
    printf '%s\n' "--- last 40 lines; full log: ${log} ---" >&2
    tail -n 40 "$log" >&2 || true
    exit "$status"
  fi
}

run_live_stage() {
  local key="$1"
  local label="$2"
  shift 2
  local log="${log_root}/${key}.log"
  local started=$SECONDS

  printf '[qa/%s] %s\n' "$key" "$label"
  if "$@" 2>&1 | tee "$log"; then
    printf '[qa/%s] ok (%ss)\n' "$key" "$((SECONDS - started))"
  else
    local status=$?
    printf '[qa/%s] FAILED (exit %s, %ss); full log: %s\n' \
      "$key" "$status" "$((SECONDS - started))" "$log" >&2
    exit "$status"
  fi
}

run_stage deps "verify locked Elixir dependencies" \
  env MIX_ENV=test mix deps.get --check-locked
run_stage cargo-metadata "verify locked Rust dependency graph" \
  cargo +1.91.0 metadata --format-version 1 \
    --manifest-path native/tursox_nif/Cargo.toml --locked --no-deps

run_stage elixir-format "check Elixir formatting" mix format --check-formatted
run_stage rust-format "check Rust formatting" \
  cargo +1.91.0 fmt --manifest-path native/tursox_nif/Cargo.toml --all -- --check

run_stage compile "compile Elixir and native code with warnings denied" \
  env MIX_ENV=test TURSOX_BUILD=1 mix compile --warnings-as-errors
run_live_stage test "run deterministic ExUnit suite" \
  env MIX_ENV=test TURSOX_BUILD=1 mix test --no-compile --seed 0

run_stage clippy "lint the Tursox native crate with warnings denied" \
  cargo +1.91.0 clippy --manifest-path native/tursox_nif/Cargo.toml \
    --locked --all-targets --no-deps -- -D warnings
run_stage rust-test "run native unit tests" \
  cargo +1.91.0 test --manifest-path native/tursox_nif/Cargo.toml --locked --all-targets

printf '[qa/ok] all 8 stages passed; logs: %s\n' "$log_root"
