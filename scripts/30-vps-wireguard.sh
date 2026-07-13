#!/usr/bin/env bash
# Phase 30 -- VPS WireGuard hub: add corp DC subnets to the LAPTOP peer's AllowedIPs.
# Idempotent + reversible. Touches ONLY the laptop peer. Run on the VPS (root).
set -euo pipefail

IFACE="wg0"
CONF="/etc/wireguard/wg0.conf"
LAPTOP_PUBKEY="U0FNUExFLUxBUFRPUC1XRy1QVUJLRVktbm90LXJlYWw="
BASE_IP="10.200.200.4/32"
DC_SUBNETS="10.0.10.0/24,10.0.11.0/24,10.0.12.0/24,10.0.13.0/24,10.0.14.0/24"
ALLOWED="${BASE_IP},${DC_SUBNETS}"

echo "== BEFORE =="; wg show "$IFACE" allowed-ips | grep -i "$LAPTOP_PUBKEY" || true

# Runtime apply (immediate; only the laptop peer is affected)
wg set "$IFACE" peer "$LAPTOP_PUBKEY" allowed-ips "$ALLOWED"

# Add kernel routes for the DC subnets via wg0. A runtime `wg set` updates cryptokey
# routing but does NOT add the kernel route the box needs to forward packets out wg0
# (wg-quick adds these from AllowedIPs only at (re)start).
IFS=',' read -ra _subs <<< "$DC_SUBNETS"
for s in "${_subs[@]}"; do ip route replace "$s" dev "$IFACE"; done

# Persist in conf (backup first); replace AllowedIPs only inside the matching peer block
ts="$(date +%Y%m%d-%H%M%S)"
cp -a "$CONF" "${CONF}.bak-${ts}"
awk -v key="$LAPTOP_PUBKEY" -v ips="$ALLOWED" '
  /^[[:space:]]*\[Peer\]/ { inpeer=1; ismatch=0 }
  inpeer && index($0,"PublicKey") && index($0,key) { ismatch=1 }
  inpeer && ismatch && $0 ~ /AllowedIPs[[:space:]]*=/ { sub(/AllowedIPs[[:space:]]*=.*/, "AllowedIPs = " ips); ismatch=0 }
  { print }
' "$CONF" > "${CONF}.new" && mv "${CONF}.new" "$CONF"
chmod 600 "$CONF"

echo "== AFTER (runtime) =="; wg show "$IFACE" allowed-ips | grep -i "$LAPTOP_PUBKEY" || true
echo "== CONF (laptop peer) =="; grep -A2 -i 'Laptop' "$CONF" || true
echo "DONE  (backup: ${CONF}.bak-${ts})"

# ---- ROLLBACK ----
# wg set wg0 peer U0FNUExFLUxBUFRPUC1XRy1QVUJLRVktbm90LXJlYWw= allowed-ips 10.200.200.4/32
# cp ${CONF}.bak-<ts> ${CONF}
