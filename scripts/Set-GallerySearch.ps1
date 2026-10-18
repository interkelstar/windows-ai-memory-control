#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param([ValidateSet('Status','Disable','Restore')][string]$Mode='Status')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
$path=Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.AIDevGallery_8wekyb3d8bbwe\LocalState\state.json'
$backupDir=Join-Path $env:LOCALAPPDATA 'WindowsAIMemoryControl'
$backup=Join-Path $backupDir 'gallery-original.json'
if(-not(Test-Path -LiteralPath $path)){@{Status='AI Gallery state not found';Changed=$false}|ConvertTo-Json;exit 0}
$bytes=[IO.File]::ReadAllBytes($path)
if($bytes.Length -ge 2 -and (($bytes[0] -eq 255 -and $bytes[1] -eq 254) -or ($bytes[0] -eq 254 -and $bytes[1] -eq 255))){throw 'Unexpected Gallery file encoding; use the Gallery Settings UI.'}
$hasBom=($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)
$text=[IO.File]::ReadAllText($path);$data=$text|ConvertFrom-Json
if(-not($data.PSObject.Properties.Name -contains 'IsAppContentSearchEnabled')){throw 'Unknown AI Gallery schema; use its Settings UI.'}
if($Mode -eq 'Status'){@{Enabled=$data.IsAppContentSearchEnabled;GuiPath='Settings > App Content Search > Enable app content search'}|ConvertTo-Json;exit 0}
if(Get-Process AIDevGallery -ErrorAction SilentlyContinue){throw 'Close AI Dev Gallery before modifying its saved preference.'}
$desired=$false
if($Mode -eq 'Restore'){
 if(-not(Test-Path -LiteralPath $backup)){throw 'No preference baseline saved by this tool.'}
 $old=Get-Content -LiteralPath $backup -Raw|ConvertFrom-Json
 if($old.Schema -ne 1 -or $old.Enabled -isnot [bool]){throw 'Invalid preference backup.'}
 $desired=$old.Enabled
}
$replacement=Convert-WamGalleryPreference $text $desired
if($PSCmdlet.ShouldProcess('AI Gallery own semantic sample search',$Mode)){
 $saveOriginal=-not(Test-Path -LiteralPath $backup)
 if(-not $saveOriginal){$prior=Get-Content -LiteralPath $backup -Raw|ConvertFrom-Json;if($prior.PSObject.Properties.Name -contains 'Restored'){$saveOriginal=[bool]$prior.Restored}}
 if($Mode -eq 'Disable' -and $saveOriginal){
  New-Item -ItemType Directory -Path $backupDir -Force|Out-Null
  Write-WamAtomicText $backup (@{Schema=1;Enabled=[bool]$data.IsAppContentSearchEnabled;Restored=$false}|ConvertTo-Json) $true
 }
 # Replace only this Boolean, never copy the full preferences (which can hold provider credentials) to a backup.
 Write-WamAtomicText $path $replacement $hasBom
 if($Mode -eq 'Restore'){$old|Add-Member -NotePropertyName Restored -NotePropertyValue $true -Force;Write-WamAtomicText $backup ($old|ConvertTo-Json) $true}
 @{Mode=$Mode;Enabled=$desired;Backup=$backup}|ConvertTo-Json
}
