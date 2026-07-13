<#
Phase 90 -- verify the enrollment end-state via Microsoft Graph (Intune + Entra + Autopilot + LAPS)
and (optionally) the on-prem AD computer object via LDAP.

Interactive Graph sign-in as an admin of contoso.onmicrosoft.com. Microsoft.Graph.Authentication only.
For the AD OU / LAPS-in-AD checks pass -DcCredential (a domain account).
#>
param(
  [string]$DeviceName = 'CLIENT-AP-TEST01',
  [string]$GroupName  = 'CLIENT_Autopilot_HybridJoin',
  [string]$TargetOU   = 'OU=Computers,OU=HQ,OU=Contoso,DC=corp,DC=example,DC=com',
  [string]$Dc         = '10.0.10.1',
  [pscredential]$DcCredential
)
$ErrorActionPreference = 'Continue'
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
if(-not (Get-MgContext)){ Connect-MgGraph -Scopes 'DeviceManagementManagedDevices.Read.All','Device.Read.All','Directory.Read.All','DeviceManagementServiceConfig.Read.All','DeviceLocalCredential.Read.All' -NoWelcome -UseDeviceCode }

function GraphGet($u){ try { (Invoke-MgGraphRequest -Method GET -Uri $u) } catch { Write-Output "  GraphGet error: $($_.Exception.Message)"; $null } }

Write-Output "=================== INTUNE MANAGED DEVICE ==================="
$md = (GraphGet "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=deviceName eq '$DeviceName'").value | Select-Object -First 1
if($md){
  $md | Select-Object deviceName,managedDeviceOwnerType,enrolledDateTime,complianceState,managementAgent,
        @{n='joinType';e={$_.joinType}},azureADRegistered,lastSyncDateTime,operatingSystem,osVersion,userPrincipalName |
        Format-List | Out-String
} else { Write-Output "  No Intune managedDevice named $DeviceName yet." }

Write-Output "=================== ENTRA DEVICE (trustType = hybrid?) ==================="
$dev = (GraphGet "https://graph.microsoft.com/v1.0/devices?`$filter=displayName eq '$DeviceName'").value | Select-Object -First 1
if($dev){
  $dev | Select-Object displayName,deviceId,trustType,isCompliant,isManaged,
        @{n='onPremSyncEnabled';e={$_.onPremisesSyncEnabled}},profileType,operatingSystemVersion |
        Format-List | Out-String
  Write-Output "  trustType 'ServerAd' = Hybrid Azure AD joined; 'AzureAd' = Entra joined; 'Workplace' = registered."
} else { Write-Output "  No Entra device named $DeviceName yet." }

Write-Output "=================== AUTOPILOT DEVICE ==================="
$ap = (GraphGet "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(deviceName,'$DeviceName') or contains(displayName,'$DeviceName')").value | Select-Object -First 1
if(-not $ap){ $ap = (GraphGet "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities").value | Select-Object -First 5 }
$ap | Select-Object serialNumber,enrollmentState,deploymentProfileAssignmentStatus,azureActiveDirectoryDeviceId | Format-Table -Auto | Out-String

Write-Output "=================== GROUP MEMBERSHIP ($GroupName) ==================="
$grp = (GraphGet "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$GroupName'").value | Select-Object -First 1
if($grp -and $dev){
  $mem = (GraphGet "https://graph.microsoft.com/v1.0/groups/$($grp.id)/members?`$select=id,displayName").value | Where-Object { $_.id -eq $dev.id }
  Write-Output ("  Device in group: " + [bool]$mem)
}

Write-Output "=================== WINDOWS LAPS (Entra) ==================="
if($dev){
  $laps = GraphGet "https://graph.microsoft.com/v1.0/directory/deviceLocalCredentials/$($dev.deviceId)?`$select=deviceName,credentials"
  if($laps){ Write-Output "  LAPS record present. Accounts: $(@($laps.credentials).accountName -join ', ')" } else { Write-Output "  No Entra LAPS record (or insufficient rights). Check on the VM directly." }
}

Write-Output "=================== ON-PREM AD COMPUTER OBJECT (LDAP) ==================="
if($DcCredential){
  try {
    $de = New-Object DirectoryServices.DirectoryEntry("LDAP://$Dc/$TargetOU", $DcCredential.UserName, $DcCredential.GetNetworkCredential().Password)
    $ds = New-Object DirectoryServices.DirectorySearcher($de)
    $ds.Filter = "(&(objectClass=computer)(cn=$DeviceName))"
    [void]$ds.PropertiesToLoad.Add('distinguishedName'); [void]$ds.PropertiesToLoad.Add('whenCreated')
    $res = $ds.FindOne()
    if($res){ Write-Output ("  FOUND: " + $res.Properties['distinguishedname'][0]) } else { Write-Output "  Computer object NOT found in $TargetOU" }
  } catch { Write-Output "  LDAP error: $($_.Exception.Message)" }
} else { Write-Output "  (pass -DcCredential to check the OU object over LDAP)" }

Write-Output "=================== ON-VM CHECKS (run these inside the VM) ==================="
@'
  Get-LocalUser                                  # expect client-admin present; LocalAdmin absent
  dsregcmd /status                               # AzureAdJoined=YES, DomainJoined=YES, EnterpriseJoined
  Get-ComputerInfo CsDomain                       # = corp.example.com
  Get-MpComputerStatus | ...                      # if baseline applied
  IME logs: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\  (scripts, LAPS, ESP apps)
  Event log: Microsoft-Windows-User Device Registration/Admin ; Provisioning-Diagnostics
'@ | Write-Output
Write-Output 'DONE phase 90.'
