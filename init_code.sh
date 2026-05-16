#!/usr/bin/env bash
set -euo pipefail

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }

SERVICE_USER="${SUDO_USER:-$USER}"

require_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    err "未找到 sudo。"
    exit 1
  fi
}

prompt_password() {
  local p1 p2
  while true; do
    read -r -s -p "请输入 code-server 密码: " p1
    echo
    read -r -s -p "请再次输入 code-server 密码: " p2
    echo

    if [[ -z "$p1" ]]; then
      err "密码不能为空。"
      continue
    fi

    if [[ "$p1" != "$p2" ]]; then
      err "两次输入不一致，请重试。"
      continue
    fi

    CODE_SERVER_PASSWORD="$p1"
    break
  done
}

install_code_server() {
  log "安装 code-server ..."
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
    err "无法找到用户 ${SERVICE_USER} 的 home 目录。"
    exit 1
  fi

  local config_dir="${user_home}/.config/code-server"
  local config_file="${config_dir}/config.yaml"

  log "写入配置: ${config_file}"
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
  log "启用并启动 code-server@${SERVICE_USER}"
  systemctl enable --now "code-server@${SERVICE_USER}"
}

show_result() {
  local user_home
  user_home="$(getent passwd "$SERVICE_USER" | cut -d: -f6)"

  cat <<EOF

完成。

运行用户:
  ${SERVICE_USER}

配置文件:
  ${user_home}/.config/code-server/config.yaml

访问地址:
  http://<你的IP>:8080

查看状态:
  systemctl status code-server@${SERVICE_USER}

EOF
}

main() {
  require_sudo
  prompt_password
  install_code_server
  write_config
  enable_service
  show_result
}

main "$@"
