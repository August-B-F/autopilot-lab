<#
Creates a small VHDX containing an offline hardware-hash extractor. Attach it to the VM,
run extract-hash.ps1 from OOBE (Shift+F10), then dismount + read hash.csv on the host.
No network, no credentials, no external scripts needed inside the VM. Run ELEVATED.
#>
param([string]$VhdPath = 'C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\xfer.vhdx')
$ErrorActionPreference = 'Stop'
if(Test-Path $VhdPath){ Dismount-VHD -Path $VhdPath -ErrorAction SilentlyContinue; Remove-Item $VhdPath -Force }

$vhd  = New-VHD -Path $VhdPath -SizeBytes 256MB -Dynamic
$disk = Mount-VHD -Path $VhdPath -Passthru | Get-Disk
Initialize-Disk -Number $disk.Number -PartitionStyle MBR -ErrorAction SilentlyContinue | Out-Null
$part = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
Format-Volume -Partition $part -FileSystem FAT32 -NewFileSystemLabel 'XFER' -Confirm:$false | Out-Null
$drv  = (Get-Partition -DiskNumber $disk.Number | Where-Object DriveLetter).DriveLetter

# Offline extractor: reads the Autopilot hardware hash straight from WMI (MDM_DevDetail_Ext01)
$extract = @'
$ErrorActionPreference = "SilentlyContinue"
$serial = (Get-CimInstance Win32_BIOS).SerialNumber
$hash   = (Get-CimInstance -Namespace root/cimv2/mdm/dmmap -ClassName MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'").DeviceHardwareData
$dir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$csv = Join-Path $dir 'hash.csv'
Set-Content -Path $csv -Encoding Ascii -Value ("Device Serial Number,Windows Product ID,Hardware Hash`r`n{0},,{1}" -f $serial, $hash)
Write-Host ("WROTE {0}  serial={1}  hashLen={2}" -f $csv, $serial, $hash.Length)
'@
Set-Content -Path ("{0}:\extract-hash.ps1" -f $drv) -Value $extract -Encoding Ascii

Dismount-VHD -Path $VhdPath
Write-Output "Transfer disk ready: $VhdPath (label XFER, extract-hash.ps1 inside)."
Write-Output "Attach:  Add-VMHardDiskDrive -VMName <vm> -Path '$VhdPath'"
Write-Output "At OOBE: Shift+F10 -> powershell -ep bypass -File <drv>:\extract-hash.ps1"
Write-Output "Then:    Dismount from VM, Mount-VHD '$VhdPath', read hash.csv."
