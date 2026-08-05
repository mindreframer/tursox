#!/usr/bin/env bash
set -euo pipefail

version="${1:-$(bin/project_version.sh)}"
nif_version=2.16
base="https://github.com/mindreframer/tursox/releases/download/v${version}"
out="checksum-Elixir.Tursox.Native.exs"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

targets=(
  aarch64-apple-darwin
  aarch64-unknown-linux-gnu
  aarch64-unknown-linux-musl
  x86_64-apple-darwin
  x86_64-unknown-linux-gnu
  x86_64-unknown-linux-musl
  x86_64-pc-windows-msvc
)

printf '%%{\n' >"$tmp/checksum"
for target in "${targets[@]}"; do
  if [[ "$target" == x86_64-pc-windows-msvc ]]; then
    name="tursox_nif-v${version}-nif-${nif_version}-${target}.dll.tar.gz"
  else
    name="libtursox_nif-v${version}-nif-${nif_version}-${target}.so.tar.gz"
  fi
  curl --fail --location --silent --show-error "$base/$name" --output "$tmp/$name"
  digest="$(shasum -a 256 "$tmp/$name" | awk '{print $1}')"
  printf '  "%s" => "sha256:%s",\n' "$name" "$digest" >>"$tmp/checksum"
done
printf '}\n' >>"$tmp/checksum"
mv "$tmp/checksum" "$out"
printf 'Generated %s only from published v%s assets\n' "$out" "$version"
