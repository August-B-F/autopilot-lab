# Discovery findings (2026-06-29)

All values verified by live inspection. Source of truth for reuse: `config/environment.ps1`.

## Where the automation runs
- On the **tower** `LAB-HOST`: a generic x64 desktop with TPM 2.0, Windows 10 Pro, WORKGROUP (not
  domain-joined). The VM under test is built locally here.
- The corporate-VPN endpoint is a **separate, remote** machine (the laptop), reachable only over SSH.

## Elevation
- The interactive host account is a local Administrator but sessions are UAC-filtered (medium integrity).
- Hyper-V, WireGuard config, NAT and routing all need a full (elevated) token, obtained once via UAC.

## WireGuard topology
```
tower (spoke)            VPS (hub)                 laptop (spoke, Site B)
iface "tower"            VPS_PUBLIC_IP:51820      iface "conection"
10.200.200.2/24   <===>  10.200.200.0/24    <===>  10.200.200.4/24
```
- Tower has exactly ONE peer = the VPS hub (pubkey `U0FNUExFLVZQUy... (sample)`), `AllowedIPs = 10.200.200.0/24`.
- Tunnel is healthy (handshakes, traffic). `wg show` requires elevation to read.
- **Change required:** add corp DC subnets to AllowedIPs on (a) tower's hub peer and (b) VPS's laptop peer,
  because WireGuard only routes destinations listed in some peer's AllowedIPs.

## Laptop (VPN-LAPTOP) — corp VPN endpoint
- Windows; `labadmin` is **admin over SSH** (full token) — remotely configurable.
- Reached at `labadmin@10.200.200.4` with `~/.ssh/id_ed25519` (alias `siteb`).
- Corp VPN = **corporate SSL VPN** on `Ethernet 3`, IP `10.0.30.135/32`, gateway `10.0.30.136`.
- The corporate VPN client has installed ~40 corp routes (192.168.x.0/24 and 10.x ranges) via the gateway.
- WG side is iface `conection` (10.200.200.4).

## Corp (Contoso) Active Directory
- Domain `corp.example.com`, forest `corp.example.com`, tenant `contoso.onmicrosoft.com`.
- **Corp DNS = 10.0.10.1, 10.0.10.2** (pushed on every interface) = **DC01 / DC02**.
  - `dc01.corp.example.com -> 10.0.10.1`
  - `dc02.corp.example.com -> 10.0.10.2`
- DC locator (`nltest /dsgetdc`) from the laptop returned `DC06 (10.0.11.7)` — the corporate VPN IP maps
  to AD site **Site-B**, so the VM (NAT'd as the laptop) may be steered to a DC in that site, not the
  primary HQ one. Therefore we tunnel that site's DC subnet too.
- DCs found via SRV `_ldap._tcp.dc._msdcs`: dc01–dc08, spread across several AD sites.
- `corp.example.com` A-records resolve to DC IPs across: 10.0.10.1/.2, 10.0.11.7/.4, 10.0.12.1/.2,
  10.0.13.2, 10.0.14.2/.21.
- **Reachability from the laptop (on corp VPN):** to 10.0.10.1 and .2, TCP 389/445/88/53 all = **OPEN**.

### DC subnets to tunnel
`10.0.10.0/24` (HQ, primary), plus `10.0.11.0/24`, `10.0.12.0/24`, `10.0.13.0/24`, `10.0.14.0/24`
(other DC-hosting subnets, for DC-locator robustness). None overlap the tower's local nets or the chosen VM subnet.

## Tower Hyper-V
- No existing VMs. Only "Default Switch" (Internal). No NAT. Host IP forwarding OFF (IPEnableRouter=0).
- VM/VHD default paths: `C:\ProgramData\Microsoft\Windows\Hyper-V` and `...\Virtual Hard Disks`.
- **ISO gap:** only `C:\Users\<USER>\Downloads\Win10_22H2_English_x64v1.iso` (5.72 GB). **No Windows 11 ISO** — must obtain.

## Tooling gaps (tower)
- No `Az`, `Microsoft.Graph`, `WindowsAutopilotIntune`, `Get-WindowsAutopilotInfo`, no `az` CLI, no PowerShell 7.
  Install lean set from PSGallery (CurrentUser) at the Autopilot phase.

## VM subnet choice
- `10.0.20.0/24`, tower gateway `10.0.20.1`. Verified non-overlapping with the corp routes and with every
  interface already present on the host (its LAN, the Hyper-V default switch, the WireGuard range, and any
  other virtual adapters). Overlap here would blackhole either local or corp traffic, so this check matters.
