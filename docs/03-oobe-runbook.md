# OOBE / Autopilot runbook (the GUI part — via Parsec)

The VM has **no DHCP** on the isolated AutopilotLab switch, so OOBE gets a **static IP**.
The hardware hash is pulled **offline** via the XFER transfer disk (no creds/network needed).

## A. Install Windows to OOBE
1. Connect to the tower with Parsec; open **Hyper-V Manager → CLIENT-AP-TEST01 → Connect**.
2. Start the VM; press a key to boot the Win11 ISO. Click through Setup:
   region/keyboard → **Install now** → "I don't have a product key" → **Windows 11 Pro** →
   accept EULA → **Custom** → select the disk → Next. Let it install and reboot.
   *(For hands-off reproduction, inject `artifacts/autounattend.xml` instead — automates these.)*
3. It reboots into **OOBE** (the "Is this the right country/region?" screen). Stop here.

## B. Extract the hardware hash (offline)
On the host (elevated): build + attach the transfer disk, then:
```
scripts/lib/New-HashTransferDisk.ps1
Add-VMHardDiskDrive -VMName CLIENT-AP-TEST01 -Path 'C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\xfer.vhdx'
```
In the VM at the OOBE region screen: **Shift+F10** → `cmd` opens →
```
powershell -ExecutionPolicy Bypass -Command "Get-Volume | ft DriveLetter,FileSystemLabel"   # find XFER's letter
powershell -ExecutionPolicy Bypass -File <X>:\extract-hash.ps1                                # writes <X>:\hash.csv
```
Then on the host: detach the disk, mount it, copy the CSV:
```
Remove-VMHardDiskDrive -VMName CLIENT-AP-TEST01 -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1
Mount-VHD 'C:\...\xfer.vhdx'; copy <mounted>\hash.csv artifacts\hash.csv ; Dismount-VHD 'C:\...\xfer.vhdx'
```

## C. Register with Autopilot + assign profile
On the host: `scripts/60-autopilot-import.ps1 -HashCsv artifacts\hash.csv`
(device-code Graph sign-in as a contoso.onmicrosoft.com admin; imports hash, syncs, adds to
`CLIENT_Autopilot_HybridJoin`). Wait until the Autopilot device shows the profile **Assigned**.

## D. Run Autopilot (Hybrid Join)
1. In the VM OOBE: **Shift+F10** → set the static IP so the device can reach Autopilot + the DCs:
   ```
   netsh interface ip set address name="Ethernet" static 10.0.20.10 255.255.255.0 10.0.20.1
   netsh interface ip set dns    name="Ethernet" static 10.0.10.1
   netsh interface ip add dns    name="Ethernet" 10.0.10.2 index=2
   ```
   Verify: `ping 10.0.10.1` and `nltest /dsgetdc:corp.example.com` should succeed.
2. Restart OOBE so the Autopilot profile is detected: `exit` then close, and from the host
   `Restart-VM CLIENT-AP-TEST01 -Force` (the static IP persists). At the first OOBE screen the
   Autopilot **Hybrid Join** branding should appear.
3. Select region/keyboard, then it shows the **org sign-in** → enter an AD user
   (`user@contoso.onmicrosoft.com` / on-prem creds). The device registers, the **ODJ connector**
   creates the computer object in `OU=Computers,OU=HQ,OU=Contoso,DC=corp,DC=example,DC=com`,
   the device applies the offline-domain-join blob (needs DC line-of-sight — that's our tunnel),
   and reboots.
4. **ESP** (Enrollment Status Page) runs: Device prep → Device setup → Account setup.
   Apps/policies/scripts install (incl. LAPS `client-admin`, LocalAdmin-removal script).
5. At the end, sign in with the AD account. Hybrid join completes after the next Entra Connect sync.

## E. Verify
Host: `scripts/90-verify-enrollment.ps1 -DcCredential (Get-Credential)`.
In VM: `dsregcmd /status` (AzureAdJoined=YES, DomainJoined=YES), `Get-LocalUser` (client-admin present,
LocalAdmin absent), IME logs under `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs`.

## Notes / gotchas
- "Skip AD connectivity check = Yes" must be set on the CLIENT Autopilot profile (off-prem/VPN).
- If the device can't find a DC during join, re-check the static DNS = 10.0.10.1/.2 and that
  `ping 10.0.10.1` works from the VM (the whole tunnel must be up).
- The static IP set at OOBE persists across the ESP reboots; if a reboot ever loses it, re-apply via Shift+F10.
