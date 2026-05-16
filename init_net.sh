#!/usr/bin/env bash
set -Eeuo pipefail

NIC="eth0"
PREFIX="24"
GATEWAY="192.168.1.1"
DNS1="192.168.1.1"
DNS2="8.8.8.8"
NEW_IP="${NEW_IP:-}"

info() { echo "==> $*"; }
error() { echo "ERROR: $*" >&2; }

usage() {
  cat <<EOF
Usage:
  $0 [options] <ipv4-address>

Options:
  -h, --help    Show this help message and exit.

Environment:
  NEW_IP         IPv4 address to configure when no positional IP is provided.

Defaults:
  NIC=${NIC}
  PREFIX=${PREFIX}
  GATEWAY=${GATEWAY}
  DNS=${DNS1}, ${DNS2}

Examples:
  $0 192.168.1.211
  NEW_IP=192.168.1.211 $0
EOF
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
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
        if [[ -n "$NEW_IP" ]]; then
          error "Only one IPv4 address can be provided."
          usage
          exit 1
        fi
        NEW_IP="$1"
        shift
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

validate_ip() {
  local ip="$1"
  if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    error "Invalid IPv4 address: $ip"
    exit 1
  fi

  IFS='.' read -r o1 o2 o3 o4 <<<"$ip"
  for o in "$o1" "$o2" "$o3" "$o4"; do
    if (( o < 0 || o > 255 )); then
      error "IPv4 octet out of range: $ip"
      exit 1
    fi
  done
}

backup_config() {
  if [[ -f /etc/systemd/network/${NIC}.network ]]; then
    cp /etc/systemd/network/${NIC}.network /etc/systemd/network/${NIC}.network.bak.$(date +%Y%m%d%H%M%S)
    info "Backed up existing network config."
  fi
}

write_config() {
  info "Writing static IP config: ${NEW_IP}/${PREFIX}"
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
  info "Restarting systemd-networkd..."
  systemctl restart systemd-networkd

  info "Flushing old IPv4 addresses..."
  ip -4 addr flush dev "${NIC}" scope global
  ip addr add "${NEW_IP}/${PREFIX}" dev "${NIC}"
  ip route replace default via "${GATEWAY}" dev "${NIC}"

  info "Restarting systemd-networkd again..."
  systemctl restart systemd-networkd
}

show_result() {
  info "Current addresses:"
  ip -br addr show dev "${NIC}" || true
  info "Current routes:"
  ip route || true
}

main() {
  parse_args "$@"
  require_root

  if [[ -z "${NEW_IP}" ]]; then
    error "IPv4 address is required."
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
