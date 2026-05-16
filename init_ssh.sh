#!/usr/bin/env bash
set -Eeuo pipefail

info() { echo "==> $*"; }
error() { echo "ERROR: $*" >&2; }

usage() {
  cat <<EOF
Usage:
  $0 [options]

Options:
  -h, --help    Show this help message and exit.

Description:
  Install and configure OpenSSH server for root password login.

The script will:
  1. Install openssh-server and common utility packages.
  2. Prompt for a new root password.
  3. Enable root login and password authentication in sshd_config.
  4. Fix SSH host key permissions.
  5. Prepare /run/sshd and restart sshd.

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

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    error "Please run this script as root."
    exit 1
  fi
}

get_password() {
  read -r -s -p "Enter the new root password: " PASSWORD
  echo
  if [[ -z "${PASSWORD}" ]]; then
    error "Password is required."
    exit 1
  fi
}

install_packages() {
  info "Installing required packages..."
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y openssh-server
  DEBIAN_FRONTEND=noninteractive apt install -y curl ripgrep htop tree wget
}

set_root_password() {
  info "Setting root password..."
  echo "root:${PASSWORD}" | chpasswd
}

fix_ssh_host_keys() {
  info "Fixing SSH host key permissions..."
  if ! compgen -G "/etc/ssh/ssh_host_*_key" >/dev/null; then
    ssh-keygen -A
  fi
  chmod 600 /etc/ssh/ssh_host_*_key
  chmod 644 /etc/ssh/ssh_host_*_key.pub
  chown root:root /etc/ssh/ssh_host_*_key*
}

configure_sshd() {
  local sshd_config="/etc/ssh/sshd_config"
  info "Configuring sshd policy..."

  sed -i 's/^[#[:space:]]*PermitRootLogin[[:space:]].*/PermitRootLogin yes/' "${sshd_config}"
  sed -i 's/^[#[:space:]]*PasswordAuthentication[[:space:]].*/PasswordAuthentication yes/' "${sshd_config}"

  grep -Eq '^PermitRootLogin[[:space:]]+yes$' "${sshd_config}" || echo 'PermitRootLogin yes' >> "${sshd_config}"
  grep -Eq '^PasswordAuthentication[[:space:]]+yes$' "${sshd_config}" || echo 'PasswordAuthentication yes' >> "${sshd_config}"

  if [[ ! -d /run/sshd ]]; then
    mkdir -p /run/sshd
  fi
  chmod 755 /run/sshd

  /usr/sbin/sshd -t
}

start_ssh_service() {
  info "Starting SSH service..."

  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q ssh.service; then
    systemctl restart ssh || /usr/sbin/sshd
  else
    pkill -x sshd >/dev/null 2>&1 || true
    /usr/sbin/sshd
  fi
}

prepare_sshd_runtime() {
  info "Preparing /run/sshd..."
  mkdir -p /run/sshd
  chmod 755 /run/sshd

  if [[ ! -f /etc/tmpfiles.d/sshd.conf ]]; then
    echo 'd /run/sshd 0755 root root -' >/etc/tmpfiles.d/sshd.conf
  fi

  systemd-tmpfiles --create || true
}

main() {
  parse_args "$@"
  require_root
  get_password
  install_packages
  set_root_password
  fix_ssh_host_keys
  configure_sshd
  prepare_sshd_runtime
  start_ssh_service
  echo
  echo "Done."
  echo
  echo "Next steps"
  echo "============================================================"
  echo
  echo "1. Test root SSH login:"
  echo
  echo "   ssh root@<server-ip>"
  echo
  echo "2. If SSH reports REMOTE HOST IDENTIFICATION HAS CHANGED, run:"
  echo
  echo "   ssh-keygen -R <server-ip>"
}

main "$@"
