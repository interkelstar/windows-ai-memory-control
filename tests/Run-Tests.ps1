#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\scripts\Core.ps1')
$passed=0
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message};$script:passed++}
function Must-Throw([scriptblock]$Code,[string]$Message){$threw=$false;try{& $Code|Out-Null}catch{$threw=$true};Assert $threw $Message}
function Value([bool]$Exists,$Number){[pscustomobject]@{Exists=$Exists;Kind=$(if($Exists){'DWord'}else{$null});Value=$Number}}
$original=[pscustomobject]@{SemanticIndexing=(Value $true 1);SettingsAgent=(Value $false $null);PreloadSkip=$false;PreloadNonempty=$false}
$applied=[pscustomobject]@{SemanticIndexing=(Value $true 0);SettingsAgent=(Value $true 1);PreloadSkip=$true;PreloadNonempty=$false}
$plan=@(New-WamRestorePlan $original $applied)
Assert ($plan.Count -eq 3) 'Restore must include each changed setting.'
Assert (-not ($plan|Where-Object Id -eq 'SettingsAgent').State.Exists) 'Originally absent policy must be removed, not set to a guessed zero.'
Assert (($plan|Where-Object Id -eq 'SemanticIndexing').State.Value -eq 1) 'Original semantic setting must be restored.'
Assert (-not ($plan|Where-Object Id -eq 'PreloadSkip').State) 'Only a tool-created skip key should be removed.'
Assert (@(New-WamRestorePlan $original $original).Count -eq 0) 'An already restored machine must have no restore writes.'
$existing=[pscustomobject]@{SemanticIndexing=(Value $true 0);SettingsAgent=(Value $true 1);PreloadSkip=$true;PreloadNonempty=$true}
Assert (@(New-WamRestorePlan $existing $existing).Count -eq 0) 'Pre-existing settings must survive a tool round trip.'
$conflict=[pscustomobject]@{SemanticIndexing=(Value $true 2);SettingsAgent=(Value $true 1);PreloadSkip=$true;PreloadNonempty=$false}
Must-Throw {New-WamRestorePlan $original $conflict} 'Restore must reject externally changed values.'
$nonempty=[pscustomobject]@{SemanticIndexing=$applied.SemanticIndexing;SettingsAgent=$applied.SettingsAgent;PreloadSkip=$true;PreloadNonempty=$true}
Must-Throw {New-WamRestorePlan $original $nonempty} 'Restore must not delete a skip key containing someone else''s settings.'
# Partial Apply: a failure after the first write must still produce an appropriate rollback plan.
$partial=[pscustomobject]@{SemanticIndexing=$applied.SemanticIndexing;SettingsAgent=$original.SettingsAgent;PreloadSkip=$false;PreloadNonempty=$false}
Assert (@(New-WamRestorePlan $original $partial).Count -eq 1) 'Rollback must handle a partial Apply.'
$originalZero=[pscustomobject]@{SemanticIndexing=(Value $false $null);SettingsAgent=(Value $true 0);PreloadSkip=$true;PreloadNonempty=$false}
$zeroPlan=@(New-WamRestorePlan $originalZero $applied)
Assert (($zeroPlan|Where-Object Id -eq 'SettingsAgent').State.Value -eq 0) 'Restore must honor an explicitly enabled original Settings agent.'
Assert (-not ($zeroPlan|Where-Object Id -eq 'SemanticIndexing').State.Exists) 'Restore must remove a semantic value that originally did not exist.'
$valid='C:\Program Files\WindowsApps\windowsworkload.manager.1_1.2511.1196.0_x64__8wekyb3d8bbwe\WorkloadsSessionHost.exe'
Assert (Test-WamWorkloadPath $valid 'C:\Program Files') 'Known Microsoft package host should be eligible.'
foreach($unsafe in @('C:\Temp\WorkloadsSessionHost.exe','C:\Program Files\WindowsApps\windowsworkload.manager.1_1.0_x64__evil\WorkloadsSessionHost.exe',($valid -replace 'WorkloadsSessionHost','WorkloadsSessionManager'),'C:\Users\person\flm.exe',($valid+'\..\other.exe'))){Assert (-not(Test-WamWorkloadPath $unsafe 'C:\Program Files')) 'Unknown paths, the manager, and private runtimes must never be terminated.'}
$text='{ "IsAppContentSearchEnabled": true, "providerKey": "do-not-copy-to-backup", "other": [1, 2] }'
$disabled=Convert-WamGalleryPreference $text $false
Assert ($disabled -ceq ($text.Replace('Enabled": true','Enabled": false'))) 'Only the single preference Boolean may change.'
Assert ((Convert-WamGalleryPreference $disabled $true) -ceq $text) 'Gallery preference restoration must preserve unrelated bytes.'
Must-Throw {Convert-WamGalleryPreference '{"differentSchema":true}' $false} 'Unknown Gallery schemas must not be modified.'
Must-Throw {Convert-WamGalleryPreference '{"IsAppContentSearchEnabled":true,"IsAppContentSearchEnabled":false}' $false} 'Duplicate preference keys must not be modified.'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('wam-test-'+[guid]::NewGuid().ToString('N')+'.json')
try {
 Write-WamAtomicText $fixture $text $false
 Assert ([IO.File]::ReadAllText($fixture) -ceq $text) 'An initial baseline must be created atomically without a previous destination.'
 foreach($bom in @($false,$true)){
  [IO.File]::WriteAllText($fixture,$text,[Text.UTF8Encoding]::new($bom));$originalHash=(Get-FileHash -LiteralPath $fixture).Hash
  Write-WamAtomicText $fixture (Convert-WamGalleryPreference $text $false) $bom
  Assert (-not (Get-Content -LiteralPath $fixture -Raw|ConvertFrom-Json).IsAppContentSearchEnabled) 'Atomic file update must work in the actual PowerShell/.NET runtime.'
  Write-WamAtomicText $fixture $text $bom
  Assert ((Get-FileHash -LiteralPath $fixture).Hash -eq $originalHash) 'File round trip must preserve bytes, including BOM choice.'
 }
}finally{if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Force}}
foreach($script in Get-ChildItem (Join-Path $PSScriptRoot '..\scripts') -Filter '*.ps1'){$errors=$null;$tokens=$null;[Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$errors)|Out-Null;Assert ($errors.Count -eq 0) ('Parse failure: '+$script.Name)}
Write-Output ("PASS: $passed assertions; no Windows settings/processes modified.")
