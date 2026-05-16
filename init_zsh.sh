#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_USER="${SUDO_USER:-$USER}"
INSTALL_CHSH="1"
UPDATE_BASHRC="1"
UPDATE_PROFILE="1"
UPDATE_SYSTEM_PROFILE="1"
KEEP_ZSHRC="1"

OMZ_REPO="https://github.com/ohmyzsh/ohmyzsh.git"
AUTOSUGGESTIONS_REPO="https://github.com/zsh-users/zsh-autosuggestions.git"
SYNTAX_HIGHLIGHTING_REPO="https://github.com/zsh-users/zsh-syntax-highlighting.git"
COMPLETIONS_REPO="https://github.com/zsh-users/zsh-completions.git"

info() { echo "==> $*"; }
warn() { echo "WARN: $*" >&2; }
error() { echo "ERROR: $*" >&2; }

usage() {
  cat <<EOF
Usage:
  $0 [options]

Options:
  --user USER       Install and configure zsh for this user. Default: ${TARGET_USER}
  --no-chsh         Do not change the user's default shell.
  --no-bashrc       Do not add the bash-to-zsh startup block to ~/.bashrc.
  --no-profile      Do not add the shell startup block to ~/.profile.
  --no-system       Do not add the fallback block to /etc/profile.d.
  --replace-zshrc   Replace existing ~/.zshrc instead of keeping a backup.
  -h, --help        Show this help message and exit.

Description:
  Install zsh, Oh My Zsh, and common plugins:
  zsh-autosuggestions, zsh-syntax-highlighting, and zsh-completions.

Examples:
  sudo $0
  sudo $0 --user deploy
  sudo $0 --no-chsh
  sudo $0 --no-bashrc
  sudo $0 --no-profile
  sudo $0 --no-system
EOF
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --user)
        if [[ "${2:-}" == "" ]]; then
          error "$1 requires a user value."
          exit 1
        fi
        TARGET_USER="$2"
        shift 2
        ;;
      --no-chsh)
        INSTALL_CHSH="0"
        shift
        ;;
      --no-bashrc)
        UPDATE_BASHRC="0"
        shift
        ;;
      --no-profile)
        UPDATE_PROFILE="0"
        shift
        ;;
      --no-system)
        UPDATE_SYSTEM_PROFILE="0"
        shift
        ;;
      --replace-zshrc)
        KEEP_ZSHRC="0"
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

user_cmd() {
  if [[ "$(id -u)" -eq 0 ]]; then
    if [[ "$TARGET_USER" == "$(id -un)" ]]; then
      "$@"
    else
      runuser -u "$TARGET_USER" -- "$@"
    fi
  elif [[ "$TARGET_USER" == "$USER" ]]; then
    "$@"
  else
    sudo -H -u "$TARGET_USER" "$@"
  fi
}

require_sudo_if_needed() {
  if [[ "$(id -u)" -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
    error "sudo is required when running as a non-root user."
    exit 1
  fi
}

require_target_user() {
  if ! id "$TARGET_USER" >/dev/null 2>&1; then
    error "User does not exist: ${TARGET_USER}"
    exit 1
  fi
}

target_home() {
  getent passwd "$TARGET_USER" | cut -d: -f6
}

target_group() {
  id -gn "$TARGET_USER"
}

install_packages() {
  info "Installing required packages..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo_cmd apt-get update
    sudo_cmd apt-get install -y zsh git curl ca-certificates passwd util-linux
  else
    warn "apt-get not found, skipping package install."
  fi
}

install_oh_my_zsh() {
  local user_home omz_dir
  user_home="$(target_home)"
  omz_dir="${user_home}/.oh-my-zsh"

  if [[ -z "$user_home" ]]; then
    error "Could not find the home directory for ${TARGET_USER}."
    exit 1
  fi

  if [[ -d "$omz_dir/.git" ]]; then
    info "Updating Oh My Zsh..."
    user_cmd git -C "$omz_dir" pull --ff-only
  else
    info "Installing Oh My Zsh..."
    user_cmd git clone --depth=1 "$OMZ_REPO" "$omz_dir"
  fi
}

install_plugin() {
  local name="$1"
  local repo="$2"
  local user_home plugin_dir

  user_home="$(target_home)"
  plugin_dir="${user_home}/.oh-my-zsh/custom/plugins/${name}"

  if [[ -d "$plugin_dir/.git" ]]; then
    info "Updating plugin: ${name}"
    user_cmd git -C "$plugin_dir" pull --ff-only
  else
    info "Installing plugin: ${name}"
    user_cmd git clone --depth=1 "$repo" "$plugin_dir"
  fi
}

install_plugins() {
  install_plugin "zsh-autosuggestions" "$AUTOSUGGESTIONS_REPO"
  install_plugin "zsh-syntax-highlighting" "$SYNTAX_HIGHLIGHTING_REPO"
  install_plugin "zsh-completions" "$COMPLETIONS_REPO"
}

write_zshrc() {
  local user_home user_group zshrc timestamp
  user_home="$(target_home)"
  user_group="$(target_group)"
  zshrc="${user_home}/.zshrc"
  timestamp="$(date +%Y%m%d%H%M%S)"

  if [[ "$KEEP_ZSHRC" == "1" && -f "$zshrc" ]]; then
    info "Backing up existing .zshrc..."
    sudo_cmd cp "$zshrc" "${zshrc}.bak.${timestamp}"
    sudo_cmd chown "${TARGET_USER}:${user_group}" "${zshrc}.bak.${timestamp}" 2>/dev/null || true
  fi

  info "Writing zsh config: ${zshrc}"
  sudo_cmd tee "$zshrc" >/dev/null <<EOF
export ZSH="${user_home}/.oh-my-zsh"

ZSH_THEME="robbyrussell"

fpath+=("\${ZSH_CUSTOM:-\$ZSH/custom}/plugins/zsh-completions/src")

plugins=(
  git
  zsh-completions
  zsh-autosuggestions
  zsh-syntax-highlighting
)

autoload -U compinit && compinit

source "\$ZSH/oh-my-zsh.sh"
EOF

  sudo_cmd chown "${TARGET_USER}:${user_group}" "$zshrc" 2>/dev/null || true
}

update_bashrc() {
  local user_home user_group bashrc
  user_home="$(target_home)"
  user_group="$(target_group)"
  bashrc="${user_home}/.bashrc"

  if [[ "$UPDATE_BASHRC" != "1" ]]; then
    warn "Skipping bash startup update."
    return
  fi

  info "Writing bash-to-zsh startup block: ${bashrc}"
  sudo_cmd touch "$bashrc"
  sudo_cmd sed -i '/^# >>> server_utils zsh >>>$/,/^# <<< server_utils zsh <<<$/{d;}' "$bashrc"
  sudo_cmd tee -a "$bashrc" >/dev/null <<'EOF'

# >>> server_utils zsh >>>
if [[ $- == *i* ]] && command -v zsh >/dev/null 2>&1 && [[ -z "${ZSH_VERSION:-}" ]]; then
  exec zsh -l
fi
# <<< server_utils zsh <<<
EOF
  sudo_cmd chown "${TARGET_USER}:${user_group}" "$bashrc" 2>/dev/null || true
}

update_profile() {
  local user_home user_group profile
  user_home="$(target_home)"
  user_group="$(target_group)"
  profile="${user_home}/.profile"

  if [[ "$UPDATE_PROFILE" != "1" ]]; then
    warn "Skipping profile startup update."
    return
  fi

  info "Writing shell startup block: ${profile}"
  sudo_cmd touch "$profile"
  sudo_cmd sed -i '/^# >>> server_utils zsh >>>$/,/^# <<< server_utils zsh <<<$/{d;}' "$profile"
  sudo_cmd tee -a "$profile" >/dev/null <<'EOF'

# >>> server_utils zsh >>>
if [ -t 0 ] && [ -t 1 ] && command -v zsh >/dev/null 2>&1 && [ -z "${ZSH_VERSION:-}" ]; then
  exec zsh -l
fi
# <<< server_utils zsh <<<
EOF
  sudo_cmd chown "${TARGET_USER}:${user_group}" "$profile" 2>/dev/null || true
}

update_system_profile() {
  local profile_d
  profile_d="/etc/profile.d/server-utils-zsh.sh"

  if [[ "$UPDATE_SYSTEM_PROFILE" != "1" ]]; then
    warn "Skipping system profile update."
    return
  fi

  info "Writing system shell startup block: ${profile_d}"
  sudo_cmd tee "$profile_d" >/dev/null <<EOF
if [ "\${USER:-}" = "${TARGET_USER}" ] && [ -t 0 ] && [ -t 1 ] && command -v zsh >/dev/null 2>&1 && [ -z "\${ZSH_VERSION:-}" ]; then
  exec zsh -l
fi
EOF
  sudo_cmd chmod 644 "$profile_d"
}

change_default_shell() {
  local zsh_path

  if [[ "$INSTALL_CHSH" != "1" ]]; then
    warn "Skipping default shell change."
    return
  fi

  zsh_path="$(command -v zsh || true)"
  if [[ -z "$zsh_path" ]]; then
    error "zsh was not found on PATH."
    exit 1
  fi

  if [[ -f /etc/shells ]] && ! grep -Fxq "$zsh_path" /etc/shells; then
    info "Adding ${zsh_path} to /etc/shells..."
    echo "$zsh_path" | sudo_cmd tee -a /etc/shells >/dev/null
  fi

  info "Changing default shell for ${TARGET_USER} to ${zsh_path}..."
  if ! sudo_cmd chsh -s "$zsh_path" "$TARGET_USER"; then
    warn "chsh failed, falling back to usermod."
    sudo_cmd usermod -s "$zsh_path" "$TARGET_USER"
  fi

  local current_shell
  current_shell="$(getent passwd "$TARGET_USER" | cut -d: -f7)"
  if [[ "$current_shell" != "$zsh_path" ]]; then
    warn "Default shell is still ${current_shell}. The profile startup block will still enter zsh for login shells."
  fi
}

show_result() {
  local user_home
  user_home="$(target_home)"

  cat <<EOF

Done.

User:
  ${TARGET_USER}

Config file:
  ${user_home}/.zshrc

Bash startup:
  ${user_home}/.bashrc

Login shell startup:
  ${user_home}/.profile

System login startup:
  /etc/profile.d/server-utils-zsh.sh

Oh My Zsh:
  ${user_home}/.oh-my-zsh

Next steps:
  zsh
  exec zsh

EOF
}

main() {
  parse_args "$@"

  info "zsh and Oh My Zsh setup"
  echo

  require_sudo_if_needed
  require_target_user
  install_packages
  install_oh_my_zsh
  install_plugins
  write_zshrc
  update_bashrc
  update_profile
  update_system_profile
  change_default_shell
  show_result
}

main "$@"
