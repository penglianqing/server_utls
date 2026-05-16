#!/usr/bin/env bash
set -euo pipefail

# 用法:
#   ./init_net.sh 192.168.1.211

NIC="eth0"
PREFIX="24"
GATEWAY="192.168.1.1"
DNS1="192.168.1.1"
DNS2="8.8.8.8"
NEW_IP="${NEW_IP:-${1:-}}"

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }

usage() {
  cat <<EOF
用法:
  $0 <IPv4地址>
示例:
  $0 192.168.1.211
  NEW_IP=192.168.1.211 $0
EOF
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "请用 root 运行。"
    exit 1
  fi
}

validate_ip() {
  local ip="$1"
  if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    err "IP 格式不正确: $ip"
    exit 1
  fi

  IFS='.' read -r o1 o2 o3 o4 <<<"$ip"
  for o in "$o1" "$o2" "$o3" "$o4"; do
    if (( o < 0 || o > 255 )); then
      err "IP 段超出范围: $ip"
      exit 1
    fi
  done
}

backup_config() {
  if [[ -f /etc/systemd/network/${NIC}.network ]]; then
    cp /etc/systemd/network/${NIC}.network /etc/systemd/network/${NIC}.network.bak.$(date +%Y%m%d%H%M%S)
    log "已备份原配置。"
  fi
}

write_config() {
  log "写入静态 IP 配置: ${NEW_IP}/${PREFIX}"
  mkdir -p /etc/systemd/network

  cat >/etc/systemd/network/${NIC}.network <<EOF
[Match]
Name=${NIC}

[Network]
DHCP=no
Address=${NEW_IP}/${PREFIX}
Gateway=${GATEWAY}
DNS=${DNS1}
DNS=${DNS2}
EOF
}

apply_config() {
  log "重启 systemd-networkd ..."
  systemctl restart systemd-networkd

  log "清理旧 DHCP 地址 ..."
  ip -4 addr flush dev "${NIC}" scope global
  ip addr add "${NEW_IP}/${PREFIX}" dev "${NIC}"
  ip route replace default via "${GATEWAY}" dev "${NIC}"

  log "再次重启 systemd-networkd ..."
  systemctl restart systemd-networkd
}

show_result() {
  log "当前地址："
  ip -br addr show dev "${NIC}" || true
  log "当前路由："
  ip route || true
}

main() {
  require_root

  if [[ -z "${NEW_IP}" ]]; then
    usage
    exit 1
  fi

  validate_ip "${NEW_IP}"
  backup_config
  write_config
  apply_config
  show_result
}

main "$@"
