<#
Headless Hyper-V console control: screenshots (thumbnail framebuffer) + keyboard injection,
via the root\virtualization\v2 WMI API. No guest agent / network needed. Run ELEVATED.

  . .\HyperVConsole.ps1
  Get-VMScreenshot -VMName CLIENT-AP-TEST01 -OutPath C:\tmp\s.png
  Send-VMText  -VMName CLIENT-AP-TEST01 -Text 'hello'
  Send-VMKey   -VMName CLIENT-AP-TEST01 -Vk 0x0D            # Enter
  Send-VMCombo -VMName CLIENT-AP-TEST01 -Mods 0x10 -Vk 0x79 # Shift+F10
#>
Add-Type -AssemblyName System.Drawing
$script:Ns = 'root\virtualization\v2'

function Get-VMCsi([string]$VMName){
  Get-CimInstance -Namespace $script:Ns -ClassName Msvm_ComputerSystem -Filter "ElementName='$VMName'"
}
function Get-VMSsd($csi){
  Get-CimAssociatedInstance -InputObject $csi -ResultClassName Msvm_VirtualSystemSettingData -Association Msvm_SettingsDefineState
}

function Get-VMScreenshot {
  param([string]$VMName,[string]$OutPath,[int]$Width,[int]$Height)
  $csi = Get-VMCsi $VMName
  if(-not $csi){ throw "VM '$VMName' not found" }
  if(-not $Width){
    $vh = Get-CimInstance -Namespace $script:Ns -ClassName Msvm_VideoHead -Filter "SystemName='$($csi.Name)'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if($vh -and $vh.CurrentHorizontalResolution){ $Width=[int]$vh.CurrentHorizontalResolution; $Height=[int]$vh.CurrentVerticalResolution }
    else { $Width=1024; $Height=768 }
  }
  if($Width % 2){ $Width++ }
  $ssd  = Get-VMSsd $csi
  $vmms = Get-CimInstance -Namespace $script:Ns -ClassName Msvm_VirtualSystemManagementService
  $r = Invoke-CimMethod -InputObject $vmms -MethodName GetVirtualSystemThumbnailImage -Arguments @{ TargetSystem=$ssd; WidthPixels=[uint16]$Width; HeightPixels=[uint16]$Height }
  if($r.ReturnValue -ne 0 -or -not $r.ImageData){ throw "thumbnail failed (rv=$($r.ReturnValue))" }
  $bytes=$r.ImageData
  $bmp = New-Object Drawing.Bitmap($Width,$Height,[Drawing.Imaging.PixelFormat]::Format16bppRgb565)
  $rect= New-Object Drawing.Rectangle(0,0,$Width,$Height)
  $bd  = $bmp.LockBits($rect,[Drawing.Imaging.ImageLockMode]::WriteOnly,[Drawing.Imaging.PixelFormat]::Format16bppRgb565)
  [Runtime.InteropServices.Marshal]::Copy($bytes,0,$bd.Scan0,[Math]::Min($bytes.Length,$bd.Stride*$Height))
  $bmp.UnlockBits($bd)
  $bmp.Save($OutPath,[Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  "$OutPath ($Width x $Height, $($bytes.Length) bytes)"
}

function Get-VMKbd([string]$VMName){
  $csi = Get-VMCsi $VMName
  Get-CimAssociatedInstance -InputObject $csi -ResultClassName Msvm_Keyboard
}
function Send-VMText { param([string]$VMName,[string]$Text)
  $kb=Get-VMKbd $VMName; $r=Invoke-CimMethod -InputObject $kb -MethodName TypeText -Arguments @{ asciiText=$Text }; $r.ReturnValue }
function Send-VMKey  { param([string]$VMName,[int]$Vk)
  $kb=Get-VMKbd $VMName; $r=Invoke-CimMethod -InputObject $kb -MethodName TypeKey -Arguments @{ keyCode=[uint32]$Vk }; $r.ReturnValue }
function Send-VMCombo { param([string]$VMName,[int[]]$Mods,[int]$Vk)
  $kb=Get-VMKbd $VMName
  foreach($m in $Mods){ Invoke-CimMethod -InputObject $kb -MethodName PressKey -Arguments @{ keyCode=[uint32]$m } | Out-Null }
  Invoke-CimMethod -InputObject $kb -MethodName PressKey   -Arguments @{ keyCode=[uint32]$Vk } | Out-Null
  Start-Sleep -Milliseconds 60
  Invoke-CimMethod -InputObject $kb -MethodName ReleaseKey -Arguments @{ keyCode=[uint32]$Vk } | Out-Null
  foreach($m in ($Mods | Sort-Object -Descending)){ Invoke-CimMethod -InputObject $kb -MethodName ReleaseKey -Arguments @{ keyCode=[uint32]$m } | Out-Null }
}
# Common virtual-key codes: Enter=0x0D Tab=0x09 Esc=0x1B Space=0x20 Back=0x08
#  Left=0x25 Up=0x26 Right=0x27 Down=0x28  Shift=0x10 Ctrl=0x11 Alt=0x12  F10=0x79
