<#
Return a fresh Microsoft Graph access token using the saved refresh token (silent).
Run scripts/60-autopilot-import.ps1 once first to perform the interactive device-code sign-in.
#>
param(
  [string]$Tenant      = 'contoso.onmicrosoft.com',
  [string]$RefreshFile = "$PSScriptRoot\..\..\secrets\graph_refresh.txt"
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'   # Microsoft Graph Command Line Tools (public client)
if(-not (Test-Path $RefreshFile)){ throw "No refresh token at $RefreshFile. Sign in via 60-autopilot-import.ps1 first." }
$rt = (Get-Content $RefreshFile -Raw).Trim()
$tok = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token" -Body @{
  grant_type    = 'refresh_token'
  client_id     = $ClientId
  refresh_token = $rt
  scope         = 'https://graph.microsoft.com/.default offline_access'
}
if($tok.refresh_token){ Set-Content -Path $RefreshFile -Value $tok.refresh_token -Encoding UTF8 }
$tok.access_token
