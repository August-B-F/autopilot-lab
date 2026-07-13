<#
Phase 60 -- import the VM hardware hash into Windows Autopilot (tenant contoso.onmicrosoft.com),
wait for completion, trigger a sync, and add the device to CLIENT_Autopilot_HybridJoin.

Uses a manual OAuth 2.0 device-code flow (raw REST) so it works in a headless/background host
(Connect-MgGraph's device-code loop fails there). Saves the refresh token so later phases
(group add after registration, verification) need no second sign-in.
#>
param(
  [Parameter(Mandatory)][string]$HashCsv,
  [string]$GroupName   = 'CLIENT_Autopilot_HybridJoin',
  [string]$GroupTag    = '',
  [string]$Tenant      = 'contoso.onmicrosoft.com',
  [string]$CodeFile    = "$PSScriptRoot\..\artifacts\devicecode.txt",
  [string]$RefreshFile = "$PSScriptRoot\..\secrets\graph_refresh.txt"
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
$scopes = 'https://graph.microsoft.com/DeviceManagementServiceConfig.ReadWrite.All https://graph.microsoft.com/DeviceManagementManagedDevices.ReadWrite.All https://graph.microsoft.com/Group.ReadWrite.All https://graph.microsoft.com/Device.Read.All https://graph.microsoft.com/Directory.Read.All offline_access'

# 1) request device code
$dc = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/devicecode" -Body @{ client_id=$ClientId; scope=$scopes }
$msg = "URL: $($dc.verification_uri)`r`nCODE: $($dc.user_code)`r`nEXPIRES_IN_SEC: $($dc.expires_in)"
Set-Content -Path $CodeFile -Value $msg -Encoding UTF8
Write-Output "DEVICECODE_BEGIN`r`n$msg`r`nDEVICECODE_END"

# 2) poll for token
$interval = [int]$dc.interval; if($interval -lt 3){ $interval = 3 }
$deadline = (Get-Date).AddSeconds([int]$dc.expires_in)
$access = $null
while((Get-Date) -lt $deadline){
  Start-Sleep -Seconds $interval
  try {
    $tok = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token" -Body @{ grant_type='urn:ietf:params:oauth:grant-type:device_code'; client_id=$ClientId; device_code=$dc.device_code }
    $access = $tok.access_token
    if($tok.refresh_token){ Set-Content -Path $RefreshFile -Value $tok.refresh_token -Encoding UTF8 }
    break
  } catch {
    $e = $null; try { $e = ($_.ErrorDetails.Message | ConvertFrom-Json).error } catch {}
    if($e -eq 'authorization_pending'){ continue }
    elseif($e -eq 'slow_down'){ $interval += 5; continue }
    else { throw "device-code token error: $e" }
  }
}
if(-not $access){ throw "device code flow timed out" }
$H = @{ Authorization = "Bearer $access" }
$me = Invoke-RestMethod -Headers $H -Uri 'https://graph.microsoft.com/v1.0/me?$select=userPrincipalName,id'
Write-Output ("AUTH OK - signed in as " + $me.userPrincipalName)

# 3) import the hash
$row = Import-Csv $HashCsv | Select-Object -First 1
$serial = $row.'Device Serial Number'; $hash = $row.'Hardware Hash'; $pk = $row.'Windows Product ID'
$body = @{ '@odata.type'='#microsoft.graph.importedWindowsAutopilotDeviceIdentity'; serialNumber=$serial; productKey=$pk; hardwareIdentifier=$hash; groupTag=$GroupTag } | ConvertTo-Json
$imp = Invoke-RestMethod -Headers $H -Method POST -Uri 'https://graph.microsoft.com/v1.0/deviceManagement/importedWindowsAutopilotDeviceIdentities' -Body $body -ContentType 'application/json'
Write-Output ("import submitted id=" + $imp.id + " serial=" + $serial)
do {
  Start-Sleep -Seconds 15
  $st = Invoke-RestMethod -Headers $H -Uri "https://graph.microsoft.com/v1.0/deviceManagement/importedWindowsAutopilotDeviceIdentities/$($imp.id)"
  Write-Output ("  import status: " + $st.state.deviceImportStatus)
} while($st.state.deviceImportStatus -in @('unknown','pending'))
Write-Output ("import result: " + $st.state.deviceImportStatus + "  err=" + $st.state.deviceErrorCode + "/" + $st.state.deviceErrorName)
if($st.state.deviceImportStatus -ne 'complete'){ throw "import not complete: $($st.state.deviceErrorName)" }

# 4) sync
try { Invoke-RestMethod -Headers $H -Method POST -Uri 'https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotSettings/sync' | Out-Null; Write-Output 'Autopilot sync triggered' } catch { Write-Output ("sync note: " + $_.Exception.Message) }

# 5) wait for the Autopilot device identity
$ap = $null
for($i=0; $i -lt 60 -and -not $ap; $i++){
  Start-Sleep -Seconds 15
  $r = Invoke-RestMethod -Headers $H -Uri "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$serial')"
  $ap = $r.value | Select-Object -First 1
  if(-not $ap){ Write-Output "  waiting for Autopilot device to appear... ($i)" }
}
if(-not $ap){ throw "Autopilot device not visible for serial $serial (sync can take ~15 min)" }
Write-Output ("Autopilot device: id=" + $ap.id + "  azureAdDeviceId=" + $ap.azureActiveDirectoryDeviceId + "  enrollmentState=" + $ap.enrollmentState)
Set-Content -Path "$PSScriptRoot\..\artifacts\autopilot-device.txt" -Value ($ap | ConvertTo-Json -Depth 5) -Encoding UTF8

# 6) add the Entra device object to the group (if it exists yet)
$grp = (Invoke-RestMethod -Headers $H -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$GroupName'").value | Select-Object -First 1
if(-not $grp){ throw "group '$GroupName' not found" }
$az = $ap.azureActiveDirectoryDeviceId
$dir = $null
if($az -and $az -ne '00000000-0000-0000-0000-000000000000'){ $dir = (Invoke-RestMethod -Headers $H -Uri "https://graph.microsoft.com/v1.0/devices?`$filter=deviceId eq '$az'").value | Select-Object -First 1 }
if(-not $dir){
  Write-Output "NOTE: Entra device object not present yet (azureAdDeviceId is empty until the device registers during OOBE). Re-run scripts/65-add-to-group.ps1 after the device checks in."
} else {
  $ref = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($dir.id)" } | ConvertTo-Json
  try { Invoke-RestMethod -Headers $H -Method POST -Uri "https://graph.microsoft.com/v1.0/groups/$($grp.id)/members/`$ref" -Body $ref -ContentType 'application/json'; Write-Output ("added device " + $dir.displayName + " to " + $GroupName) }
  catch { if($_.Exception.Message -match 'already exist|references already'){ Write-Output 'device already a member' } else { Write-Output ("group add error: " + $_.Exception.Message) } }
}
Write-Output 'DONE phase 60'
