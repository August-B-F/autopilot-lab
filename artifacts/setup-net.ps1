# Static IP for the lab NIC, applied during the answer-file specialize pass (SYSTEM, no UI focus needed).
# Persists into OOBE so the VM can reach Autopilot + the DCs without DHCP.
$ErrorActionPreference = 'SilentlyContinue'
$xfer = (Get-Volume | Where-Object FileSystemLabel -eq 'XFER' | Select-Object -First 1).DriveLetter
$log  = if($xfer){ "${xfer}:\setup-net.log" } else { "$env:TEMP\setup-net.log" }
$a = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notlike '*Loopback*' } | Select-Object -First 1
if($a){
  $i = $a.ifIndex
  Remove-NetIPAddress -InterfaceIndex $i -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
  Remove-NetRoute -InterfaceIndex $i -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue
  New-NetIPAddress -InterfaceIndex $i -IPAddress 10.0.20.10 -PrefixLength 24 -DefaultGateway 10.0.20.1 -ErrorAction SilentlyContinue | Out-Null
  Set-DnsClientServerAddress -InterfaceIndex $i -ServerAddresses 10.0.10.1,10.0.10.2 -ErrorAction SilentlyContinue
  Add-Content $log ("[{0}] set static 10.0.20.10/24 gw .1 dns .210.1/.2 on ifIndex {1} ({2})" -f (Get-Date), $i, $a.Name)
} else {
  Add-Content $log ("[{0}] no Up adapter found" -f (Get-Date))
}
