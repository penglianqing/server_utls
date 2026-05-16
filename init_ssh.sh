#!/usr/bin/env bash
set -euo pipefail

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "请使用 root 运行此脚本。"
    exit 1
  fi
}

get_password() {
  echo -n "[PROMPT] 请输入 root 的新密码: "
  read -s PASSWORD
  echo "" 
  if [[ -z "${PASSWORD}" ]]; then
    err "密码不能为空！"
    exit 1
  fi
}

install_packages() {
  log "检查并安装 SSH..."
  apt update && DEBIAN_FRONTEND=noninteractive apt install -y openssh-server
  DEBIAN_FRONTEND=noninteractive apt install -y curl ripgrep htop tree wget
}

set_root_password() {
  log "设置 root 用户密码..."
  echo "root:${PASSWORD}" | chpasswd
}

fix_ssh_host_keys() {
  log "修正 SSH 密钥文件权限..."
  if ! compgen -G "/etc/ssh/ssh_host_*_key" >/dev/null; then
    ssh-keygen -A
  fi
  chmod 600 /etc/ssh/ssh_host_*_key
  chmod 644 /etc/ssh/ssh_host_*_key.pub
  chown root:root /etc/ssh/ssh_host_*_key*
}

configure_sshd() {
  local sshd_config="/etc/ssh/sshd_config"
  log "配置 SSH 策略..."

  # 确保配置项存在并正确
  sed -i 's/^[#[:space:]]*PermitRootLogin[[:space:]].*/PermitRootLogin yes/' "${sshd_config}"
  sed -i 's/^[#[:space:]]*PasswordAuthentication[[:space:]].*/PasswordAuthentication yes/' "${sshd_config}"
  
  grep -Eq '^PermitRootLogin[[:space:]]+yes$' "${sshd_config}" || echo 'PermitRootLogin yes' >> "${sshd_config}"
  grep -Eq '^PasswordAuthentication[[:space:]]+yes$' "${sshd_config}" || echo 'PasswordAuthentication yes' >> "${sshd_config}"

  # 预创建权限分离目录（解决你遇到的错误）
  if [ ! -d /run/sshd ]; then
    mkdir -p /run/sshd
  fi
  chmod 755 /run/sshd

  /usr/sbin/sshd -t
}

start_ssh_service() {
  log "启动服务..."
  
  # 兼容 systemd 和直接启动
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q ssh.service; then
    systemctl restart ssh || /usr/sbin/sshd
  else
    pkill -x sshd >/dev/null 2>&1 || true
    /usr/sbin/sshd
  fi
}

prepare_sshd_runtime() {
  log "准备 /run/sshd ..."
  mkdir -p /run/sshd
  chmod 755 /run/sshd

  if [[ ! -f /etc/tmpfiles.d/sshd.conf ]]; then
    echo 'd /run/sshd 0755 root root -' >/etc/tmpfiles.d/sshd.conf
  fi

  systemd-tmpfiles --create || true
}

main() {
  require_root
  get_password
  install_packages
  set_root_password
  fix_ssh_host_keys
  configure_sshd
  prepare_sshd_runtime
  start_ssh_service
  log "全部完成！请通过 ssh root@<容器IP> 尝试登录。"
  log "如果报错 REMOTE HOST IDENTIFICATION HAS CHANGED, 执行 ssh-keygen -R <容器IP>。"
}

main
