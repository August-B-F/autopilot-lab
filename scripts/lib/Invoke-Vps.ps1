<#
.SYNOPSIS  Run a command on the VPS WireGuard hub over SSH (password auth via paramiko).
.EXAMPLE   .\Invoke-Vps.ps1 -Command "wg show"
#>
param(
    [Parameter(Mandatory)][string]$Command,
    [int]$TimeoutSec = 120
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\..\secrets\secrets.ps1"

$py = "$env:USERPROFILE\miniconda3\python.exe"
if (-not (Test-Path $py)) { throw "Python not found at $py" }

$env:VPS_HOST = $Secrets.VpsHost
$env:VPS_USER = $Secrets.VpsUser
$env:VPS_PASS = $Secrets.VpsPass
$env:VPS_PORT = $Secrets.VpsPort
try {
    # base64-wrap so newlines/quotes/$vars survive PowerShell->python->ssh arg passing
    $script = ($Command -replace "`r`n", "`n")
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    & $py "$PSScriptRoot\vps_ssh.py" "echo $b64 | base64 -d | bash" $TimeoutSec
} finally {
    Remove-Item Env:VPS_PASS -ErrorAction SilentlyContinue
}
