#!/usr/bin/env bash
set -Eeuo pipefail

NIC="${NIC:-}"
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
  -i, --nic IFACE  Network interface to configure.
  -h, --help       Show this help message and exit.

Environment:
  NEW_IP         IPv4 address to configure when no positional IP is provided.
  NIC            Network interface to configure. Auto-detected when unset.

Defaults:
  NIC=${NIC:-auto}
  PREFIX=${PREFIX}
  GATEWAY=${GATEWAY}
  DNS=${DNS1}, ${DNS2}

Examples:
  $0 192.168.1.211
  $0 --nic ens18 192.168.1.211
  NEW_IP=192.168.1.211 $0
EOF
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -i|--nic)
        if [[ "$#" -lt 2 || "$2" == -* ]]; then
          error "Missing interface name for $1."
          usage
          exit 1
        fi
        NIC="$2"
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

detect_nic() {
  if [[ -n "${NIC}" ]]; then
    return
  fi

  NIC="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}')"
  if [[ -n "${NIC}" ]]; then
    info "Detected network interface from default route: ${NIC}"
    return
  fi

  NIC="$(find /sys/class/net -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null \
    | sort \
    | awk '!/^(lo|docker[0-9]*|br-|veth|virbr|tap|tun)/ { print; exit }')"
  if [[ -n "${NIC}" ]]; then
    info "Detected network interface from /sys/class/net: ${NIC}"
    return
  fi

  error "Could not detect network interface. Set NIC=<iface> or pass --nic <iface>."
  exit 1
}

validate_nic() {
  if [[ ! -d "/sys/class/net/${NIC}" ]]; then
    error "Network interface does not exist: ${NIC}"
    exit 1
  fi
}

network_config_file() {
  echo "/etc/systemd/network/00-init-net-${NIC}.network"
}

backup_config() {
  local config_file legacy_config_file timestamp
  config_file="$(network_config_file)"
  legacy_config_file="/etc/systemd/network/${NIC}.network"
  timestamp="$(date +%Y%m%d%H%M%S)"

  for file in "${config_file}" "${legacy_config_file}"; do
    if [[ -f "${file}" ]]; then
      cp "${file}" "${file}.bak.${timestamp}"
      info "Backed up existing network config: ${file}"
    fi
  done
}

write_config() {
  local config_file
  config_file="$(network_config_file)"

  info "Writing static IP config: ${NEW_IP}/${PREFIX}"
  mkdir -p /etc/systemd/network

  cat >"${config_file}" <<EOF
[Match]
Name=${NIC}

[Network]
DHCP=no
Address=${NEW_IP}/${PREFIX}
Gateway=${GATEWAY}
DNS=${DNS1}
DNS=${DNS2}
EOF

  if [[ -f /etc/systemd/network/${NIC}.network ]]; then
    mv "/etc/systemd/network/${NIC}.network" "/etc/systemd/network/${NIC}.network.disabled"
    info "Disabled lower-priority legacy config: /etc/systemd/network/${NIC}.network"
  fi
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
  detect_nic
  validate_nic
  backup_config
  write_config
  apply_config
  show_result
}

main "$@"
