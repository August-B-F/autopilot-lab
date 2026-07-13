<#
Phase 20 -- LAPTOP (VPN-LAPTOP), run ELEVATED. Forward + NAT so WireGuard traffic
(10.200.200.0/24) is masqueraded onto the corporate SSL VPN. Idempotent + reversible.
#>
param(
  [string]$WgPrefix  = '10.200.200.0/24',
  [string]$WgProbeIp = '10.200.200.4',           # identifies the correct WG tunnel adapter
  [string]$CorpMatch = '*SSL VPN*',               # corp VPN adapter: match a substring of its InterfaceDescription
  [string]$NatName   = 'WgToCorpNat'
)
$ErrorActionPreference = 'Stop'
$id=[Security.Principal.WindowsIdentity]::GetCurrent(); $pr=New-Object Security.Principal.WindowsPrincipal($id)
if(-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ throw 'Must run elevated' }

# Resolve interfaces robustly
$wgIp = Get-NetIPAddress -IPAddress $WgProbeIp -AddressFamily IPv4 -ErrorAction Stop
$wgIdx = $wgIp.InterfaceIndex
$wgAlias = (Get-NetAdapter -InterfaceIndex $wgIdx).Name
$corp = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like $CorpMatch -and $_.Status -eq 'Up' } | Select-Object -First 1
if(-not $corp){ throw "Corp adapter matching '$CorpMatch' not found/Up" }
Write-Output "WG adapter   : $wgAlias (idx $wgIdx, $WgProbeIp)"
Write-Output "Corp adapter : $($corp.Name) | $($corp.InterfaceDescription) (idx $($corp.ifIndex))"

# Forwarding (effective now; registry flag for persistence across reboot)
Set-NetIPInterface -InterfaceIndex $wgIdx -Forwarding Enabled
Set-NetIPInterface -InterfaceIndex $corp.ifIndex -Forwarding Enabled
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name IPEnableRouter -Value 1

# NAT
$existing = Get-NetNat -ErrorAction SilentlyContinue
$conflict = $existing | Where-Object { $_.InternalIPInterfaceAddressPrefix -eq $WgPrefix -and $_.Name -ne $NatName }
if($conflict){ Write-Output "WARNING: pre-existing NAT for $WgPrefix -> $($conflict.Name -join ',')" }
if(-not ($existing | Where-Object Name -eq $NatName)){
  try { New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $WgPrefix -ErrorAction Stop | Out-Null; Write-Output "Created NAT $NatName for $WgPrefix" }
  catch { Write-Output "ERROR creating NAT: $($_.Exception.Message)"; throw }
} else { Write-Output "NAT $NatName already present" }

Write-Output "=== VERIFY ==="
Get-NetNat | Select-Object Name,InternalIPInterfaceAddressPrefix,Active | Format-Table -Auto | Out-String -Width 200
Get-NetIPInterface -InterfaceIndex $wgIdx,$corp.ifIndex -AddressFamily IPv4 | Select-Object InterfaceAlias,Forwarding | Format-Table -Auto | Out-String -Width 200

# ---- ROLLBACK ----
# Remove-NetNat -Name WgToCorpNat -Confirm:$false
# Set-NetIPInterface -InterfaceIndex <wg>,<corp> -Forwarding Disabled
