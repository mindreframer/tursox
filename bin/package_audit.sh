#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
audit="$root/_build/package_audit"
rm -rf "$audit"
mkdir -p "$audit"
mix hex.build --unpack --output "$audit/package"

test -f "$audit/package/native/tursox_nif/Cargo.lock"
test -f "$audit/package/LICENSE"
test -f "$audit/package/SECURITY.md"
if find "$audit/package" -type d \( -name _build -o -name target -o -name .git -o -name @meta \) | grep -q .; then
  echo "forbidden generated/private directory in package" >&2
  exit 1
fi
if grep -R -F "$HOME/Desktop/work" "$audit/package" >/dev/null 2>&1; then
  echo "absolute sibling path leaked into package" >&2
  exit 1
fi

mkdir -p "$audit/consumer"
cat >"$audit/consumer/mix.exs" <<'EOF'
defmodule TursoxAudit.MixProject do
  use Mix.Project
  def project, do: [app: :tursox_audit, version: "0.0.0", elixir: "~> 1.20", deps: [{:tursox, path: "../package"}]]
  def application, do: [extra_applications: [:logger]]
end
EOF
(
  cd "$audit/consumer"
  MIX_ENV=prod TURSOX_BUILD=1 mix deps.get
  MIX_ENV=prod TURSOX_BUILD=1 mix compile --warnings-as-errors
  MIX_ENV=prod TURSOX_BUILD=1 mix run --no-start "$root/bin/smoke_precompiled_consumer.exs"
)
printf 'Package audit passed: %s\n' "$audit/package"
