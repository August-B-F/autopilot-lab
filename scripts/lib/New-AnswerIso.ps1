<#
Build a tiny ISO containing autounattend.xml at its root (so Windows Setup discovers it).
Uses the built-in IMAPI2 COM filesystem image API. Run on the tower.
#>
param(
  [Parameter(Mandatory)][string]$AnswerFile,
  [Parameter(Mandatory)][string]$IsoPath,
  [string]$Label = 'ANSWER'
)
$ErrorActionPreference = 'Stop'

$tmp = Join-Path $env:TEMP ('iso_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
Copy-Item $AnswerFile (Join-Path $tmp 'autounattend.xml') -Force

$cs = @'
public class ISOFile {
  public unsafe static void Create(string Path, object Stream, int BlockSize, int TotalBlocks) {
    int bytes = 0;
    byte[] buf = new byte[BlockSize];
    var ptr = (System.IntPtr)(&bytes);
    System.IO.FileStream o = System.IO.File.OpenWrite(Path);
    System.Runtime.InteropServices.ComTypes.IStream i =
        Stream as System.Runtime.InteropServices.ComTypes.IStream;
    if (o != null) {
      while (TotalBlocks-- > 0) { i.Read(buf, BlockSize, ptr); o.Write(buf, 0, bytes); }
      o.Flush(); o.Close();
    }
  }
}
'@
if(-not ('ISOFile' -as [type])){
  $cp = New-Object System.CodeDom.Compiler.CompilerParameters
  $cp.CompilerOptions = '/unsafe'
  Add-Type -CompilerParameters $cp -TypeDefinition $cs
}

$fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
$fsi.VolumeName = $Label
$fsi.FileSystemsToCreate = 3   # ISO9660 + Joliet
$fsi.Root.AddTree($tmp, $false)
$img = $fsi.CreateResultImage()
if(Test-Path $IsoPath){ Remove-Item $IsoPath -Force }
[ISOFile]::Create($IsoPath, $img.ImageStream, $img.BlockSize, $img.TotalBlocks)
Remove-Item $tmp -Recurse -Force
Write-Output ("ISO created: {0} ({1} bytes)" -f $IsoPath, (Get-Item $IsoPath).Length)
