<#
Phase 10 -- TOWER (Hyper-V host), run ELEVATED. Internal vSwitch + NAT + forwarding +
WireGuard AllowedIPs/routes so the VM reaches corp DC subnets through the tunnel.
Idempotent + reversible. Use -Persist to make the WG change survive a tunnel restart.
#>
param([switch]$Persist)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\config\environment.ps1"
$id=[Security.Principal.WindowsIdentity]::GetCurrent(); $pr=New-Object Security.Principal.WindowsPrincipal($id)
if(-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ throw 'Must run elevated' }

$sw=$Lab.Vm.SwitchName; $gw=$Lab.Vm.LabGateway; $pfx=$Lab.Vm.LabPrefix; $lab=$Lab.Vm.LabSubnet
$wg=$Lab.Tower.WgIface; $hub=$Lab.Tower.WgHubPeerPubKey; $dc=$Lab.Corp.DcSubnets
$wgExe='C:\Program Files\WireGuard\wg.exe'

# 1) internal vSwitch + host IP (= VM gateway)
if(-not (Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue)){ New-VMSwitch -Name $sw -SwitchType Internal | Out-Null; Write-Output "Created vSwitch $sw" } else { Write-Output "vSwitch $sw exists" }
$hostAlias = "vEthernet ($sw)"
if(-not (Get-NetIPAddress -InterfaceAlias $hostAlias -IPAddress $gw -ErrorAction SilentlyContinue)){ New-NetIPAddress -InterfaceAlias $hostAlias -IPAddress $gw -PrefixLength $pfx | Out-Null; Write-Output "Assigned $gw/$pfx to $hostAlias" } else { Write-Output "$gw already on $hostAlias" }

# 2) forwarding
Set-NetIPInterface -InterfaceAlias $hostAlias -Forwarding Enabled
Set-NetIPInterface -InterfaceAlias $wg -Forwarding Enabled -ErrorAction SilentlyContinue
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name IPEnableRouter -Value 1

# 3) NAT for the lab subnet (one NAT serves both internet + WG egress)
if(-not (Get-NetNat -ErrorAction SilentlyContinue | Where-Object InternalIPInterfaceAddressPrefix -eq $lab)){ New-NetNat -Name 'AutopilotLabNat' -InternalIPInterfaceAddressPrefix $lab | Out-Null; Write-Output "Created NAT for $lab" } else { Write-Output "NAT for $lab exists" }

# 4) WireGuard AllowedIPs (runtime) + on-link routes for each DC subnet
$allowed = (@($Lab.Vps.WgSubnet) + $dc) -join ','
& $wgExe set $wg peer $hub allowed-ips $allowed
Write-Output "tower hub-peer allowed-ips = $allowed"
foreach($s in $dc){
  if(-not (Get-NetRoute -DestinationPrefix $s -InterfaceAlias $wg -ErrorAction SilentlyContinue)){ New-NetRoute -DestinationPrefix $s -InterfaceAlias $wg -NextHop 0.0.0.0 | Out-Null; Write-Output "route + $s via $wg" } else { Write-Output "route exists $s" }
}

# 5) optional persistence (rebuilds + reinstalls the tunnel service; brief reconnect)
if($Persist){
  $tmp = Join-Path $env:TEMP 'tower-autopilot.conf'
  $cfg = (& $wgExe showconf $wg) -replace '(?m)^AllowedIPs\s*=.*$', "AllowedIPs = $allowed"
  Set-Content -Path $tmp -Value $cfg -Encoding ASCII
  & 'C:\Program Files\WireGuard\wireguard.exe' /installtunnelservice $tmp
  Remove-Item $tmp -ErrorAction SilentlyContinue
  Write-Output "Persisted WG config (tunnel reinstalled)"
}

Write-Output "=== VERIFY ==="
Get-VMSwitch -Name $sw | Select-Object Name,SwitchType | Format-Table -Auto | Out-String
Get-NetNat | Select-Object Name,InternalIPInterfaceAddressPrefix,Active | Format-Table -Auto | Out-String -Width 200
& $wgExe show $wg allowed-ips
Get-NetRoute -InterfaceAlias $wg -AddressFamily IPv4 | Select-Object DestinationPrefix | Format-Table -Auto | Out-String

# ---- ROLLBACK ----
# Remove-NetNat -Name AutopilotLabNat -Confirm:$false
# $dc | % { Remove-NetRoute -DestinationPrefix $_ -InterfaceAlias tower -Confirm:$false }
# & 'C:\Program Files\WireGuard\wg.exe' set tower peer <hub> allowed-ips 10.200.200.0/24
# Remove-VMSwitch AutopilotLab -Force
