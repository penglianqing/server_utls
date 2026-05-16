#!/usr/bin/env bash
set -Eeuo pipefail

GB_VERSION="${GB_VERSION:-6.7.1}"
WORKDIR="${WORKDIR:-$HOME/benchmarks/geekbench6}"
TARBALL="Geekbench-${GB_VERSION}-Linux.tar.gz"
URL="${GB_URL:-https://cdn.geekbench.com/${TARBALL}}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_DIR="${WORKDIR}/results"
LOG_FILE="${LOG_DIR}/geekbench6-cpu-${RUN_ID}.log"

info() { echo "==> $*"; }
error() { echo "ERROR: $*" >&2; }

usage() {
  cat <<EOF
Usage:
  $0 [options]

Options:
  -h, --help    Show this help message and exit.

Environment:
  GB_VERSION    Geekbench version to run. Default: ${GB_VERSION}
  GB_URL        Download URL. Default: https://cdn.geekbench.com/Geekbench-\${GB_VERSION}-Linux.tar.gz
  WORKDIR       Working directory. Default: ${WORKDIR}

Description:
  Download Geekbench for Linux x86_64 if needed, run the CPU benchmark,
  save the full output log, and print a short score summary.

Examples:
  $0
  GB_VERSION=6.7.1 $0
  WORKDIR=/tmp/geekbench6 $0
EOF
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Missing required command: $1"
    echo "Install it first, for example: apt-get update && apt-get install -y curl tar gzip ca-certificates" >&2
    exit 1
  fi
}

check_platform() {
  case "$(uname -m)" in
    x86_64|amd64) ;;
    *)
      error "This script is for Linux x86_64/amd64. Detected: $(uname -m)"
      exit 1
      ;;
  esac
}

check_dependencies() {
  for cmd in curl tar gzip tee awk sed date uname; do
    require_cmd "$cmd"
  done
}

prepare_workdir() {
  mkdir -p "$WORKDIR" "$LOG_DIR"
  cd "$WORKDIR"
}

show_cpu_info() {
  echo "== CPU =="
  lscpu 2>/dev/null | sed -n 's/^Model name:[[:space:]]*//p; s/^CPU(s):[[:space:]]*//p; s/^Thread(s) per core:[[:space:]]*//p; s/^Core(s) per socket:[[:space:]]*//p; s/^Socket(s):[[:space:]]*//p' || true
  echo
}

download_geekbench() {
  if [[ ! -f "$TARBALL" ]]; then
    info "Downloading ${URL}"
    curl -fL --retry 3 --retry-delay 2 -o "$TARBALL" "$URL"
  else
    info "Using existing tarball: ${WORKDIR}/${TARBALL}"
  fi
}

extract_geekbench() {
  if [[ ! -d "Geekbench-${GB_VERSION}-Linux" ]]; then
    info "Extracting ${TARBALL}"
    tar -xzf "$TARBALL"
  fi
}

run_benchmark() {
  local gb_bin="${WORKDIR}/Geekbench-${GB_VERSION}-Linux/geekbench6"
  if [[ ! -x "$gb_bin" ]]; then
    error "Geekbench binary not found or not executable: ${gb_bin}"
    exit 1
  fi

  echo
  info "Running Geekbench ${GB_VERSION} CPU benchmark..."
  echo "Log: ${LOG_FILE}"
  echo

  "$gb_bin" --cpu 2>&1 | tee "$LOG_FILE"
}

show_summary() {
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
}

main() {
  parse_args "$@"
  check_platform
  check_dependencies
  prepare_workdir
  show_cpu_info
  download_geekbench
  extract_geekbench
  run_benchmark
  show_summary
}

main "$@"
