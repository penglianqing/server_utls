#!/usr/bin/env bash
set -Eeuo pipefail

KEY_FILE="$HOME/.ssh/id_ed25519"
PUB_FILE="${KEY_FILE}.pub"
EMAIL=""

info() { echo "==> $*"; }
warn() { echo "WARN: $*" >&2; }
error() { echo "ERROR: $*" >&2; }

usage() {
  cat <<EOF
Usage:
  $0 [options] [email]

Options:
  -e, --email EMAIL    GitHub email used as the SSH key comment.
  -h, --help           Show this help message and exit.

Description:
  Create or reuse an Ed25519 SSH key for GitHub and add it to ssh-agent.

Examples:
  $0 user@example.com
  $0 --email user@example.com
EOF
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -e|--email)
        if [[ "${2:-}" == "" ]]; then
          error "$1 requires an email value."
          exit 1
        fi
        EMAIL="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        error "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        if [[ -n "$EMAIL" ]]; then
          error "Only one email can be provided."
          usage
          exit 1
        fi
        EMAIL="$1"
        shift
        ;;
    esac
  done
}

resolve_email() {
  if [[ -z "$EMAIL" ]]; then
    EMAIL="$(git config --global user.email 2>/dev/null || true)"
  fi

  if [[ -z "$EMAIL" ]]; then
    read -rp "Enter your GitHub email: " EMAIL
  fi

  if [[ -z "$EMAIL" ]]; then
    error "Email is required."
    exit 1
  fi
}

sudo_cmd() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

install_packages() {
  info "Installing required packages..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo_cmd apt-get update
    sudo_cmd apt-get install -y git openssh-client
  else
    warn "apt-get not found, skipping package install."
  fi
}

prepare_ssh_dir() {
  info "Preparing ~/.ssh directory..."
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  touch "$HOME/.ssh/known_hosts"
  chmod 644 "$HOME/.ssh/known_hosts"
}

ensure_private_key() {
  info "Checking SSH key..."
  if [[ -f "$KEY_FILE" ]]; then
    echo "SSH private key already exists:"
    echo "  $KEY_FILE"
  else
    echo "Generating new SSH key:"
    echo "  $KEY_FILE"
    ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY_FILE" -N ""
  fi
}

fix_permissions() {
  info "Fixing permissions..."
  chmod 700 "$HOME/.ssh"
  chmod 600 "$KEY_FILE"

  if [[ -f "$PUB_FILE" ]]; then
    chmod 644 "$PUB_FILE"
  fi

  chown "$(id -un):$(id -gn)" "$HOME/.ssh" "$KEY_FILE" 2>/dev/null || true

  if [[ -f "$PUB_FILE" ]]; then
    chown "$(id -un):$(id -gn)" "$PUB_FILE" 2>/dev/null || true
  fi
}

ensure_public_key() {
  info "Checking public key..."
  if [[ ! -f "$PUB_FILE" ]] || ! ssh-keygen -l -f "$PUB_FILE" >/dev/null 2>&1; then
    echo "Public key missing or invalid, regenerating from private key..."
    ssh-keygen -y -f "$KEY_FILE" > "$PUB_FILE"
    chmod 644 "$PUB_FILE"
  fi
}

start_agent() {
  info "Starting ssh-agent..."
  eval "$(ssh-agent -s)" >/dev/null

  info "Adding private key to ssh-agent..."
  ssh-add "$KEY_FILE"
}

show_result() {
  echo
  info "Public key fingerprint:"
  ssh-keygen -l -f "$PUB_FILE"

  echo
  echo "============================================================"
  echo "Your GitHub SSH public key:"
  echo "============================================================"
  cat "$PUB_FILE"
  echo
  echo "============================================================"
  echo "Next steps"
  echo "============================================================"
  echo
  echo "1. Add the public key above to GitHub:"
  echo
  echo "   https://github.com/settings/keys"
  echo
  echo "   GitHub -> Settings -> SSH and GPG keys -> New SSH key"
  echo
  echo "   Key type: Authentication Key"
  echo "   Key: copy the full public key printed above"
  echo
  echo "2. After adding the key, test SSH:"
  echo
  echo "   ssh -T git@github.com"
  echo
  echo "3. If you created a new GitHub repo, use SSH remote instead of HTTPS:"
  echo
  echo "   git remote set-url origin git@github.com:YOUR_USERNAME/YOUR_REPO.git"
  echo
  echo "4. Then push:"
  echo
  echo "   git push -u origin main"
  echo
  echo "Done."
}

main() {
  parse_args "$@"

  info "GitHub SSH key setup for Debian"
  echo

  resolve_email
  install_packages
  prepare_ssh_dir
  ensure_private_key
  fix_permissions
  ensure_public_key
  start_agent
  show_result
}

main "$@"
