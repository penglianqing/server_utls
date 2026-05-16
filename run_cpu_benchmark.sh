#!/usr/bin/env bash
set -Eeuo pipefail

# Standardized CPU benchmark runner for Linux x86_64.
# Default: Geekbench 6.7.1, verified reachable from the official CDN on 2026-05-14.

GB_VERSION="${GB_VERSION:-6.7.1}"
WORKDIR="${WORKDIR:-$HOME/benchmarks/geekbench6}"
TARBALL="Geekbench-${GB_VERSION}-Linux.tar.gz"
URL="${GB_URL:-https://cdn.geekbench.com/${TARBALL}}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_DIR="${WORKDIR}/results"
LOG_FILE="${LOG_DIR}/geekbench6-cpu-${RUN_ID}.log"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    echo "Install it first, for example: apt-get update && apt-get install -y curl tar gzip ca-certificates" >&2
    exit 1
  fi
}

case "$(uname -m)" in
  x86_64|amd64) ;;
  *)
    echo "This script is for Linux x86_64/amd64. Detected: $(uname -m)" >&2
    exit 1
    ;;
esac

for cmd in curl tar gzip tee awk sed date uname; do
  require_cmd "$cmd"
done

mkdir -p "$WORKDIR" "$LOG_DIR"
cd "$WORKDIR"

echo "== CPU =="
lscpu 2>/dev/null | sed -n 's/^Model name:[[:space:]]*//p; s/^CPU(s):[[:space:]]*//p; s/^Thread(s) per core:[[:space:]]*//p; s/^Core(s) per socket:[[:space:]]*//p; s/^Socket(s):[[:space:]]*//p' || true
echo

if [[ ! -f "$TARBALL" ]]; then
  echo "Downloading ${URL}"
  curl -fL --retry 3 --retry-delay 2 -o "$TARBALL" "$URL"
else
  echo "Using existing tarball: ${WORKDIR}/${TARBALL}"
fi

if [[ ! -d "Geekbench-${GB_VERSION}-Linux" ]]; then
  echo "Extracting ${TARBALL}"
  tar -xzf "$TARBALL"
fi

GB_BIN="${WORKDIR}/Geekbench-${GB_VERSION}-Linux/geekbench6"
if [[ ! -x "$GB_BIN" ]]; then
  echo "Geekbench binary not found or not executable: ${GB_BIN}" >&2
  exit 1
fi

echo
echo "Running Geekbench ${GB_VERSION} CPU benchmark..."
echo "Log: ${LOG_FILE}"
echo

"$GB_BIN" --cpu 2>&1 | tee "$LOG_FILE"

echo
echo "== Summary =="
awk '
  /Single-Core Score/ { single=$NF }
  /Multi-Core Score/ { multi=$NF }
  /https:\/\/browser\.geekbench\.com\/v6\/cpu\// { url=$0 }
  END {
    if (single) print "Single-Core Score: " single;
    if (multi) print "Multi-Core Score: " multi;
    if (url) print "Result URL: " url;
  }
' "$LOG_FILE"
echo "Saved log: ${LOG_FILE}"
