# Offline Autopilot hardware-hash extractor. Run at OOBE (Shift+F10) or via autounattend.
# Writes hash.csv to the XFER-labelled volume. No network / credentials needed.
$ErrorActionPreference = 'SilentlyContinue'
$drv = (Get-Volume | Where-Object FileSystemLabel -eq 'XFER' | Select-Object -First 1).DriveLetter
if(-not $drv){ $drv = (Split-Path -Qualifier $MyInvocation.MyCommand.Definition).TrimEnd(':') }
$serial = (Get-CimInstance Win32_BIOS).SerialNumber
$hash   = (Get-CimInstance -Namespace root/cimv2/mdm/dmmap -ClassName MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'").DeviceHardwareData
Set-Content -Path ("{0}:\hash.csv" -f $drv) -Encoding Ascii -Value ("Device Serial Number,Windows Product ID,Hardware Hash`r`n{0},,{1}" -f $serial, $hash)
Write-Host ("WROTE {0}:\hash.csv  serial={1}  hashLen={2}" -f $drv, $serial, $hash.Length)
