#!/usr/bin/env bash
# Fake tailscale — emits a fixed JSON status with self + 3 peers.
case "$*" in
  *"status"*"--json"*)
    cat <<'EOF'
{
  "BackendState": "Running",
  "Self": {
    "ID": "self",
    "HostName": "kh-headless",
    "DNSName": "kh-headless.tail-mock.ts.net.",
    "TailscaleIPs": ["100.64.1.10"],
    "Online": true
  },
  "ExitNodeStatus": null,
  "Peer": {
    "peer1": {
      "ID": "peer1",
      "HostName": "laptop",
      "DNSName": "laptop.tail-mock.ts.net.",
      "TailscaleIPs": ["100.64.2.21"],
      "Online": true,
      "ExitNode": false,
      "ExitNodeOption": false
    },
    "peer2": {
      "ID": "peer2",
      "HostName": "phone",
      "DNSName": "phone.tail-mock.ts.net.",
      "TailscaleIPs": ["100.64.3.42"],
      "Online": true,
      "ExitNode": false,
      "ExitNodeOption": false
    },
    "peer3": {
      "ID": "peer3",
      "HostName": "exit-node-eu",
      "DNSName": "exit-node-eu.tail-mock.ts.net.",
      "TailscaleIPs": ["100.64.4.99"],
      "Online": true,
      "ExitNode": false,
      "ExitNodeOption": true
    }
  }
}
EOF
    ;;
  *"up"*|*"down"*)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
