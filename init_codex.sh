#!/usr/bin/env bash
set -Eeuo pipefail

PACKAGE="@openai/codex"
VERSION="${CODEX_VERSION:-latest}"
INSTALL_NODE="1"
MIN_NODE_MAJOR=16
NODE_MAJOR_VERSION="${NODE_MAJOR_VERSION:-22}"
CLEAN="1"

info() { echo "==> $*"; }
warn() { echo "WARN: $*" >&2; }
error() { echo "ERROR: $*" >&2; }

usage() {
  cat <<EOF
Usage:
  $0 [options]

Options:
  --version VERSION     Install a specific Codex package version. Default: ${VERSION}
  --no-node-install     Do not install nodejs/npm automatically.
  --no-clean            Do not uninstall an existing global Codex package first.
  -h, --help            Show this help message and exit.

Environment:
  CODEX_VERSION         Codex package version to install. Default: latest
  NODE_MAJOR_VERSION    Node.js major version to install with apt. Default: ${NODE_MAJOR_VERSION}

Description:
  Install the OpenAI Codex CLI globally with npm.

Examples:
  $0
  $0 --version latest
  CODEX_VERSION=x.y.z $0
  $0 --no-node-install
EOF
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --version)
        if [[ "${2:-}" == "" ]]; then
          error "$1 requires a version value."
          exit 1
        fi
        VERSION="$2"
        shift 2
        ;;
      --no-node-install)
        INSTALL_NODE="0"
        shift
        ;;
      --no-clean)
        CLEAN="0"
        shift
        ;;
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

sudo_cmd() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

require_sudo_if_needed() {
  if [[ "$(id -u)" -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
    error "sudo is required when running as a non-root user."
    exit 1
  fi
}

install_node_packages() {
  local node_major=""

  if command -v node >/dev/null 2>&1; then
    node_major="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || true)"
  fi

  if [[ -n "$node_major" && "$node_major" -ge "$MIN_NODE_MAJOR" ]] && command -v npm >/dev/null 2>&1; then
    return
  fi

  if [[ "$INSTALL_NODE" != "1" ]]; then
    error "Node.js ${MIN_NODE_MAJOR}+ and npm are required. Install them first or rerun without --no-node-install."
    exit 1
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    error "apt-get was not found. Install Node.js ${MIN_NODE_MAJOR}+ and npm manually, then rerun this script."
    exit 1
  fi

  info "Installing Node.js ${NODE_MAJOR_VERSION}.x and npm..."
  sudo_cmd apt-get update
  sudo_cmd apt-get install -y ca-certificates curl gnupg

  # Remove distro packages that commonly conflict with NodeSource's nodejs.
  sudo_cmd apt-get remove -y npm libnode-dev nodejs-doc || true

  local setup_script
  setup_script="$(mktemp)"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR_VERSION}.x" -o "$setup_script"
  sudo_cmd bash "$setup_script"
  rm -f "$setup_script"

  sudo_cmd apt-get install -y nodejs

  node_major="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || true)"
  if [[ -z "$node_major" || "$node_major" -lt "$MIN_NODE_MAJOR" ]] || ! command -v npm >/dev/null 2>&1; then
    error "Node.js ${MIN_NODE_MAJOR}+ and npm are still not available after installation."
    exit 1
  fi
}

clean_codex() {
  if [[ "$CLEAN" != "1" ]]; then
    return
  fi

  if command -v npm >/dev/null 2>&1; then
    info "Cleaning existing Codex CLI install..."
    sudo_cmd npm uninstall -g "$PACKAGE" >/dev/null 2>&1 || true
    sudo_cmd npm config delete optional >/dev/null 2>&1 || true
    sudo_cmd npm config delete omit >/dev/null 2>&1 || true
    sudo_cmd npm cache verify >/dev/null 2>&1 || true
  fi
}

install_codex() {
  local package_spec="${PACKAGE}@${VERSION}"

  info "Installing Codex CLI: ${package_spec}"
  sudo_cmd npm install -g --include=optional "$package_spec"
}

install_missing_platform_package() {
  local output="$1"
  local platform_package="@openai/codex-linux-x64"
  local package_json optional_spec global_root

  if [[ "$output" != *"Missing optional dependency ${platform_package}"* ]]; then
    return 1
  fi

  global_root="$(npm root -g)"
  package_json="${global_root}/@openai/codex/package.json"
  if [[ ! -f "$package_json" ]]; then
    return 1
  fi

  optional_spec="$(node -e '
const fs = require("fs");
const pkg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const spec = pkg.optionalDependencies && pkg.optionalDependencies[process.argv[2]];
if (!spec) process.exit(1);
console.log(spec);
' "$package_json" "$platform_package")" || return 1

  info "Installing missing Codex platform package..."
  sudo_cmd npm install -g --include=optional "${platform_package}@${optional_spec}"
}

show_result() {
  echo
  info "Checking Codex CLI..."
  if command -v codex >/dev/null 2>&1; then
    local output
    if ! output="$(codex --version 2>&1)"; then
      echo "$output" >&2
      install_missing_platform_package "$output"
      output="$(codex --version 2>&1)"
    fi
    echo "$output"
  else
    warn "codex was installed, but it is not available on PATH in this shell."
  fi

  cat <<EOF

Done.

Next steps:
  codex
  codex --help

EOF
}

main() {
  parse_args "$@"

  info "OpenAI Codex CLI setup"
  echo

  require_sudo_if_needed
  install_node_packages
  clean_codex
  install_codex
  show_result
}

main "$@"
