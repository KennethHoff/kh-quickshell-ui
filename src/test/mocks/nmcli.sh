#!/usr/bin/env bash
# Fake nmcli — only handles `-t -f DEVICE,TYPE,STATE dev`, the one call the
# bar's EthernetPanel makes. Always reports eth0 connected.
case "$*" in
  *"-f DEVICE,TYPE,STATE"*"dev"*)
    echo "eth0:ethernet:connected"
    echo "lo:loopback:unmanaged"
    ;;
  *)
    exit 0
    ;;
esac
