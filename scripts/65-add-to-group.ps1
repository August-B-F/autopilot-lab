<#
Phase 65 -- add the Autopilot device's Entra object to CLIENT_Autopilot_HybridJoin.
Run this if phase 60 deferred the group-add (Entra device object only exists once the
Autopilot device record is fully synced / the device has registered). Silent auth via the
saved refresh token (no second sign-in).
#>
param(
  [string]$Serial    = '0000-0000-0000-0000-0000-0000-00',
  [string]$GroupName = 'CLIENT_Autopilot_HybridJoin',
  [string]$Tenant    = 'contoso.onmicrosoft.com'
)
$ErrorActionPreference = 'Stop'
$access = & "$PSScriptRoot\lib\Get-GraphToken.ps1" -Tenant $Tenant
$H = @{ Authorization = "Bearer $access" }

$ap = (Invoke-RestMethod -Headers $H -Uri "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$Serial')").value | Select-Object -First 1
if(-not $ap){ throw "No Autopilot device for serial $Serial" }
$az = $ap.azureActiveDirectoryDeviceId
Write-Output ("AP device: serial=$($ap.serialNumber) enrollmentState=$($ap.enrollmentState) azureAdDeviceId=$az")
if(-not $az -or $az -eq '00000000-0000-0000-0000-000000000000'){ Write-Output 'azureAdDeviceId not populated yet -- device has not registered. Retry later.'; return }

$dir = (Invoke-RestMethod -Headers $H -Uri "https://graph.microsoft.com/v1.0/devices?`$filter=deviceId eq '$az'").value | Select-Object -First 1
if(-not $dir){ Write-Output "Entra device object not found for deviceId $az"; return }
$grp = (Invoke-RestMethod -Headers $H -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$GroupName'").value | Select-Object -First 1
if(-not $grp){ throw "Group '$GroupName' not found" }
$ref = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($dir.id)" } | ConvertTo-Json
try {
  Invoke-RestMethod -Headers $H -Method POST -Uri "https://graph.microsoft.com/v1.0/groups/$($grp.id)/members/`$ref" -Body $ref -ContentType 'application/json'
  Write-Output ("Added '" + $dir.displayName + "' to '" + $GroupName + "'")
} catch {
  if($_.Exception.Message -match 'already exist|references already'){ Write-Output 'Device already a member.' } else { throw }
}
