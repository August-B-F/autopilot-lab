<#
Phase 40 -- create the Windows 11 test VM on the tower. Run ELEVATED.
Gen2 (UEFI), Secure Boot ON, vTPM (TPM 2.0), on the AutopilotLab internal switch.
#>
param([string]$IsoPath)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\config\environment.ps1"
$idn=[Security.Principal.WindowsIdentity]::GetCurrent(); $pr=New-Object Security.Principal.WindowsPrincipal($idn)
if(-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ throw 'Must run elevated' }

$v = $Lab.Vm
if(-not $IsoPath){ $IsoPath = $v.IsoPath }
if(-not (Test-Path $IsoPath)){ throw "ISO not found: $IsoPath" }
$name = $v.Name

if(Get-VM -Name $name -ErrorAction SilentlyContinue){ Write-Output "VM '$name' already exists -- nothing to do."; return }

# VHDX
$vhd = $v.VhdPath
$vhdDir = Split-Path $vhd
if(-not (Test-Path $vhdDir)){ New-Item -ItemType Directory -Force -Path $vhdDir | Out-Null }
if(Test-Path $vhd){ Remove-Item $vhd -Force }
New-VHD -Path $vhd -SizeBytes ($v.DiskGB*1GB) -Dynamic | Out-Null

# VM
New-VM -Name $name -Generation 2 -MemoryStartupBytes ($v.MemoryGB*1GB) -VHDPath $vhd -SwitchName $v.SwitchName | Out-Null
Set-VM -Name $name -ProcessorCount $v.Cpu -DynamicMemory -MemoryMinimumBytes 2GB -MemoryMaximumBytes ($v.MemoryGB*1GB) -AutomaticCheckpointsEnabled $false

# DVD + ISO, boot from DVD first
Add-VMDvdDrive -VMName $name -Path $IsoPath
$dvd = Get-VMDvdDrive -VMName $name
Set-VMFirmware -VMName $name -FirstBootDevice $dvd -EnableSecureBoot On -SecureBootTemplate 'MicrosoftWindows'

# vTPM via local key protector (no Host Guardian needed on a standalone host)
Set-VMKeyProtector -VMName $name -NewLocalKeyProtector
Enable-VMTPM -VMName $name

Enable-VMIntegrationService -VMName $name -Name 'Guest Service Interface' -ErrorAction SilentlyContinue

Write-Output "Created VM '$name': Gen2, $($v.Cpu) vCPU, $($v.MemoryGB)GB max dyn, $($v.DiskGB)GB, vTPM+SecureBoot, switch '$($v.SwitchName)'."
Get-VM -Name $name | Select-Object Name,State,Generation,ProcessorCount | Format-Table -Auto | Out-String
Get-VMFirmware -VMName $name | Select-Object @{n='SecureBoot';e={$_.SecureBoot}},SecureBootTemplate | Format-Table -Auto | Out-String
Get-VMSecurity -VMName $name | Select-Object TpmEnabled | Format-Table -Auto | Out-String

# ---- ROLLBACK ----  Stop-VM $name -TurnOff; Remove-VM $name -Force; Remove-Item <vhd>
