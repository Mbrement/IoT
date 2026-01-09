#!/usr/bin/env bash
#
# This script overload the part3 installation script using local
# gitlab repository as bootstrap source.

P3_DIR="$PWD/../../p3"

export MANIFEST_URL="https://gitlab.example.com/root/iot-42-cluster-conf/-/raw/main/bootstrap.yml"

exec $P3_DIR/scripts/install.sh