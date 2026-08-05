#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${project_root}"

stage() { printf '\n[qa/%s] %s\n' "$1" "$2"; }

stage deps "locked Elixir and Rust dependencies"
MIX_ENV=test mix deps.get --check-locked
cargo +1.91.0 metadata --format-version 1 --manifest-path native/tursox_nif/Cargo.toml --locked --no-deps >/dev/null

stage format "Elixir and Rust formatting"
mix format --check-formatted
cargo +1.91.0 fmt --manifest-path native/tursox_nif/Cargo.toml --all -- --check

stage compile "Elixir compilation with warnings denied"
MIX_ENV=test TURSOX_BUILD=1 mix compile --warnings-as-errors

stage test "ExUnit"
MIX_ENV=test TURSOX_BUILD=1 mix test --no-compile --trace

stage rust "cargo check, Clippy, and tests"
cargo +1.91.0 check --manifest-path native/tursox_nif/Cargo.toml --locked --all-targets
cargo +1.91.0 clippy --manifest-path native/tursox_nif/Cargo.toml --locked --all-targets -- -D warnings
cargo +1.91.0 test --manifest-path native/tursox_nif/Cargo.toml --locked --all-targets

stage ok "all checks passed"
