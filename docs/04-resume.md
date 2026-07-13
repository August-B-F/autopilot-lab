# Resume procedure (after the Site B laptop is back online)

## State at pause (2026-06-29)
- **Hash imported to Autopilot.** serial `0000-0000-0000-0000-0000-0000-00`; AP device id `11111111-1111-1111-1111-111111111111`; Entra placeholder device `22222222-2222-2222-2222-222222222222` (displayName = serial, accountEnabled=False until it registers).
- **Group membership done.** `CLIENT_Autopilot_HybridJoin` is a **dynamic** group (rule `device.devicePhysicalIds -any (_ -startsWith "[ZTDID]")`); the device matched and is a member automatically.
- **Profile assignment was still computing** at pause (`deploymentProfileAssignmentStatus` empty, `enrollmentState=notContacted`). It finishes cloud-side while the laptop is off.
- **VM `CLIENT-AP-TEST01` is OFF**, DVDs removed, first boot = hard disk → a plain Start-VM boots straight into **OOBE** (Autopilot will trigger once the profile is assigned).
- **VM network is static + persistent:** 10.0.20.10/24, gw 10.0.20.1, DNS 10.0.10.1/.2.
- **Tower + VPS changes persist** across a laptop power-cycle. The **laptop** forwarding flags may reset on reboot, so re-apply them.
- A Graph **refresh token** is saved (`secrets/graph_refresh.txt`) — no second tenant sign-in needed for cloud checks. (Token lifetime ~90 days inactivity; if it expires, re-run phase 60 sign-in.)

## Resume steps
1. **Laptop**: reconnect the Contoso **corporate VPN** corp VPN; ensure the WireGuard `conection` tunnel to the VPS is up. From the tower, `ssh labadmin@10.200.200.4 hostname` should succeed.
2. **Re-apply laptop forwarding + NAT** (forwarding can reset on reboot): push `scripts/20-laptop-network.ps1` to the laptop over SSH (base64 → `powershell -EncodedCommand`, as in the build).
3. **Re-verify the path from the tower** — TCP 389/445 to 10.0.10.1 and .2 must be **OPEN**, DNS/SRV resolve. (Only if the *VPS itself* rebooted: re-run `scripts/30-vps-wireguard.sh` to restore its `ip route … dev wg0` runtime routes.)
4. **Confirm profile assigned**: `scripts/lib/Get-GraphToken.ps1` → `GET …/windowsAutopilotDeviceIdentities/<GUID>…` → `deploymentProfileAssignmentStatus` should be `assignedInSync` (or `assigned…`). If still empty, wait/sync.
5. **Start the VM** → it boots into OOBE → Autopilot **Hybrid Join**. Drive OOBE headlessly (region/keyboard/network via keyboard injection to the focused OOBE app). At the **org sign-in**, the operator Parsecs into the tower and authenticates the device (per the agreed plan).
6. **ESP** runs: Device prep → Device setup → Account setup; the on-prem **Intune ODJ connector** creates the computer object in `OU=Computers,OU=HQ,OU=Contoso,DC=corp,DC=example,DC=com` and passes the offline-domain-join blob; the device applies it (needs DC line-of-sight = the tunnel), reboots, completes.
7. **Verify**: `scripts/90-verify-enrollment.ps1` + on-VM `dsregcmd /status` (AzureAdJoined=YES, DomainJoined=YES), `Get-LocalUser` (client-admin present, LocalAdmin absent), IME logs.

To resume from a cold state the operator only needs to reconnect the laptop's corporate VPN and bring the
`conection` WireGuard tunnel back up; everything else on the tower and VPS persists across the pause.
