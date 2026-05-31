#!/usr/bin/env bash
set -Eeuo pipefail

apt-get install sysbench -y

sysbench cpu --threads=$(nproc) --cpu-max-prime=20000 --time=10 run
