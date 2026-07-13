# Network design

## Objective
Give a throwaway Hyper-V VM on the tower **line-of-sight to the Contoso domain
controllers** (required for Autopilot Hybrid Azure AD Join) without giving the VM any corporate
credentials or VPN client of its own. The corporate SSL VPN lives on the Site B laptop;
the VM reaches the DCs by routing **only** corp DC subnets through the WireGuard mesh to that laptop.

## Constraints discovered
- Tower (Site A) and laptop (Site B) are both behind NAT — neither has a public endpoint, so the
  existing **VPS hub** (VPS_PUBLIC_IP) must relay spoke↔spoke. WireGuard already works for
  10.200.200.0/24.
- WireGuard routes strictly by `AllowedIPs` (crypto-key routing) in both directions: a destination
  is only routed to a peer if it's in that peer's AllowedIPs, and an inbound packet is only accepted
  if its **source** is in the sending peer's AllowedIPs.
- The corp side has overlapping RFC1918 space (e.g. corp has 192.168.1.0/24, which is also the
  tower's LAN). So we route **only specific DC /24s**, never broad supernets.

## Topology and data path
```
VM 10.0.20.0/24 ──(tower NAT->10.200.200.2)──▶ WG "tower" .2
        │ default route                                   │
        ▼ (direct internet: MS OOBE/Intune/Entra)         ▼ WG
   tower's Ethernet 192.168.1.91                     VPS hub wg0 10.200.200.1
                                                          │ forwards (ip_forward=1, FORWARD ACCEPT)
                                                          ▼ WG
                              laptop WG "conection" .4 ──(laptop NAT->10.0.30.135)──▶ corporate VPN ──▶ DCs
```

## Per-node changes (all reversible)

### VPS hub (`scripts/30-vps-wireguard.sh`)
- Add DC subnets to the **Laptop** peer's `AllowedIPs` (currently `10.200.200.4/32`):
  `wg set wg0 peer U0FNUExFLUxBUFRPUC1XRy1QVUJLRVktbm90LXJlYWw= allowed-ips 10.200.200.4/32,<DCsubnets>`
  and persist the same line in `/etc/wireguard/wg0.conf` (backup first).
- No NAT, no forwarding change needed (already on). Other peers untouched.
- **Rollback:** `wg set wg0 peer <laptop> allowed-ips 10.200.200.4/32` + restore conf backup.

### Laptop (`scripts/20-laptop-network.ps1`, run elevated on the laptop)
- Resolve interfaces robustly: WG side = the WireGuard tunnel holding 10.200.200.4 ("conection");
  corp side = the adapter whose description matches "corporate SSL VPN".
- Enable IPv4 forwarding on both interfaces; set `IPEnableRouter=1` for persistence.
- `New-NetNat -InternalIPInterfaceAddressPrefix 10.200.200.0/24` -> masquerades VM/tower traffic
  onto the corporate VPN IP (10.0.30.135). DCs already permit that source (it's the laptop's VPN IP).
- **Rollback:** `Remove-NetNat`, disable forwarding.

### Tower (`scripts/10-tower-network.ps1`, run elevated on the tower)
- Create **internal** vSwitch `AutopilotLab`; assign host IP `10.0.20.1/24` (VM gateway).
- Enable forwarding on the vSwitch host vNIC and the WG "tower" interface.
- `New-NetNat -InternalIPInterfaceAddressPrefix 10.0.20.0/24` -> one NAT masquerades VM traffic
  to 192.168.1.91 for default/internet flows and to 10.200.200.2 for WG/DC flows (egress-IP based).
- Add DC subnets to the hub peer's AllowedIPs at runtime (`wg set tower peer <hub> allowed-ips ...`)
  and add on-link routes for each DC subnet via the "tower" interface.
  `-Persist` switch rebuilds the tunnel config so it survives a tunnel/host restart.
- **Rollback:** `Remove-NetNat`, `Remove-NetRoute`, `wg set tower peer <hub> allowed-ips 10.200.200.0/24`,
  `Remove-VMSwitch AutopilotLab`.

## AllowedIPs after change
| Node | Peer | AllowedIPs |
|------|------|-----------|
| Tower | hub (VPS) | `10.200.200.0/24` **+ DcSubnets** |
| VPS | Laptop | `10.200.200.4/32` **+ DcSubnets** |
| VPS | Tower | `10.200.200.2/32` (unchanged) |
| Laptop | hub (VPS) | unchanged (already covers 10.200.200.2) |

`DcSubnets = 10.0.10.0/24, 10.0.11.0/24, 10.0.12.0/24, 10.0.13.0/24, 10.0.14.0/24`

## DNS strategy
VM DNS = `10.0.10.1, 10.0.10.2` (DC01/02). These resolve `corp.example.com` and SRV
records, and forward internet names (same as the laptop does). DNS thus traverses the tunnel; data to
Microsoft cloud goes direct via the VM's default route. This is the standard hybrid-join-over-VPN model.

## Why split tunnel (not full tunnel)
Routing all VM traffic through the double-hop would push every Autopilot/Intune/Entra OOBE call through
Site B and the corporate VPN VPN — slow and a likely failure point (corp proxy/SSL inspection). Sending only
the DC subnets through the tunnel keeps the heavy cloud OOBE traffic on the tower's fast local internet.

## Autopilot Hybrid Join requirements (must hold)
- Device reaches a DC: DNS(53), Kerberos(88), LDAP(389), LDAPS(636), SMB(445), RPC(135+dynamic),
  GC(3268), NTP(123). Verified open from the laptop to 10.0.10.1/.2.
- Autopilot profile **"Skip AD connectivity check = Yes"** (off-prem/VPN). Verify on the CLIENT profile.
- On-prem **Intune Connector for AD (ODJ connector)** present (Contoso side) — creates the
  computer object in `OU=Computers,OU=HQ,OU=Contoso,DC=corp,DC=example,DC=com` and the ODJ blob.
