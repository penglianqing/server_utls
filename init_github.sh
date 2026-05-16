#!/usr/bin/env bash
set -Eeuo pipefail

KEY_FILE="$HOME/.ssh/id_ed25519"
PUB_FILE="${KEY_FILE}.pub"
EMAIL="${1:-}"

echo "==> GitHub SSH Key setup for Debian"
echo

if [[ -z "$EMAIL" ]]; then
  EMAIL="$(git config --global user.email 2>/dev/null || true)"
fi

if [[ -z "$EMAIL" ]]; then
  read -rp "Enter your GitHub email: " EMAIL
fi

if [[ -z "$EMAIL" ]]; then
  echo "ERROR: Email is required."
  exit 1
fi

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

echo "==> Installing required packages..."
if command -v apt-get >/dev/null 2>&1; then
  $SUDO apt-get update
  $SUDO apt-get install -y git openssh-client
else
  echo "WARN: apt-get not found, skipping package install."
fi

echo
echo "==> Preparing ~/.ssh directory..."
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

touch "$HOME/.ssh/known_hosts"
chmod 644 "$HOME/.ssh/known_hosts"

echo
echo "==> Checking SSH key..."

if [[ -f "$KEY_FILE" ]]; then
  echo "SSH private key already exists:"
  echo "  $KEY_FILE"
else
  echo "Generating new SSH key:"
  echo "  $KEY_FILE"
  ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY_FILE" -N ""
fi

echo
echo "==> Fixing permissions..."
chmod 700 "$HOME/.ssh"
chmod 600 "$KEY_FILE"

if [[ -f "$PUB_FILE" ]]; then
  chmod 644 "$PUB_FILE"
fi

chown "$(id -un):$(id -gn)" "$HOME/.ssh" "$KEY_FILE" 2>/dev/null || true

if [[ -f "$PUB_FILE" ]]; then
  chown "$(id -un):$(id -gn)" "$PUB_FILE" 2>/dev/null || true
fi

echo
echo "==> Checking public key..."

if [[ ! -f "$PUB_FILE" ]] || ! ssh-keygen -l -f "$PUB_FILE" >/dev/null 2>&1; then
  echo "Public key missing or invalid, regenerating from private key..."
  ssh-keygen -y -f "$KEY_FILE" > "$PUB_FILE"
  chmod 644 "$PUB_FILE"
fi

echo
echo "==> Public key fingerprint:"
ssh-keygen -l -f "$PUB_FILE"

echo
echo "==> Starting ssh-agent..."
eval "$(ssh-agent -s)" >/dev/null

echo "==> Adding private key to ssh-agent..."
ssh-add "$KEY_FILE"

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