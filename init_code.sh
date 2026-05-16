#!/usr/bin/env bash
set -Eeuo pipefail

info() { echo "==> $*"; }
error() { echo "ERROR: $*" >&2; }

SERVICE_USER="${SUDO_USER:-$USER}"

usage() {
  cat <<EOF
Usage:
  $0 [options]

Options:
  -h, --help    Show this help message and exit.

Description:
  Install code-server, configure password authentication, and enable the
  systemd service for the current sudo user.

Examples:
  sudo $0
  sudo bash $0
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

require_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    error "sudo is required."
    exit 1
  fi
}

prompt_password() {
  local p1 p2
  while true; do
    read -r -s -p "Enter the code-server password: " p1
    echo
    read -r -s -p "Confirm the code-server password: " p2
    echo

    if [[ -z "$p1" ]]; then
      error "Password is required."
      continue
    fi

    if [[ "$p1" != "$p2" ]]; then
      error "Passwords do not match. Try again."
      continue
    fi

    CODE_SERVER_PASSWORD="$p1"
    break
  done
}

install_code_server() {
  info "Installing code-server..."
  tmp_script="$(mktemp)"
  wget -O "$tmp_script" https://code-server.dev/install.sh
  chmod +x "$tmp_script"
  bash "$tmp_script"
  rm -f "$tmp_script"
}

write_config() {
  local user_home
  user_home="$(getent passwd "$SERVICE_USER" | cut -d: -f6)"

  if [[ -z "${user_home}" ]]; then
    error "Could not find the home directory for ${SERVICE_USER}."
    exit 1
  fi

  local config_dir="${user_home}/.config/code-server"
  local config_file="${config_dir}/config.yaml"

  info "Writing config: ${config_file}"
  mkdir -p "$config_dir"

  cat >"$config_file" <<EOF
bind-addr: 0.0.0.0:8080
auth: password
password: ${CODE_SERVER_PASSWORD}
cert: false
EOF

  chmod 600 "$config_file"
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "${user_home}/.config"
}

enable_service() {
  info "Enabling and starting code-server@${SERVICE_USER}..."
  systemctl enable --now "code-server@${SERVICE_USER}"
}

show_result() {
  local user_home
  user_home="$(getent passwd "$SERVICE_USER" | cut -d: -f6)"

  cat <<EOF

Done.

Service user:
  ${SERVICE_USER}

Config file:
  ${user_home}/.config/code-server/config.yaml

Access URL:
  http://<server-ip>:8080

Check status:
  systemctl status code-server@${SERVICE_USER}

EOF
}

main() {
  parse_args "$@"
  require_sudo
  prompt_password
  install_code_server
  write_config
  enable_service
  show_result
}

main "$@"
