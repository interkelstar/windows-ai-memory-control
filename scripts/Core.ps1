Set-StrictMode -Version 2

function Get-WamSpecs {
 @(
  [pscustomobject]@{Id='SemanticIndexing';Path='SOFTWARE\Microsoft\Windows Search\SemanticIndexer';Name='EnableSemanticIndexing';Desired=0},
  [pscustomobject]@{Id='SettingsAgent';Path='SOFTWARE\Policies\Microsoft\Windows\WindowsAI';Name='DisableSettingsAgent';Desired=1}
 )
}
function Test-WamValueEqual($A,$B) {
 if([bool]$A.Exists -ne [bool]$B.Exists){return $false}
 if(-not $A.Exists){return $true}
 return ($A.Kind -eq $B.Kind -and [int64]$A.Value -eq [int64]$B.Value)
}
function New-WamRestorePlan($Original,$Current) {
 $plan=@()
 foreach($spec in Get-WamSpecs){
  $old=$Original.($spec.Id);$now=$Current.($spec.Id)
  $desired=[pscustomobject]@{Exists=$true;Kind='DWord';Value=$spec.Desired}
  if(Test-WamValueEqual $old $now){continue}
  if(-not(Test-WamValueEqual $desired $now)){throw "Conflict: $($spec.Id) changed after this tool ran. Refusing to overwrite it."}
  $plan+=[pscustomobject]@{Id=$spec.Id;State=$old}
 }
 if([bool]$Original.PreloadSkip -ne [bool]$Current.PreloadSkip){
  if($Original.PreloadSkip){throw 'Preload key was removed externally; inspect before restoring.'}
  if($Current.PreloadNonempty){throw 'Preload key has other settings; refusing to remove it.'}
  $plan+=[pscustomobject]@{Id='PreloadSkip';State=$false}
 }
 return $plan
}
function Test-WamWorkloadPath([string]$Path,[string]$ProgramFilesRoot) {
 if([string]::IsNullOrWhiteSpace($Path)){return $false}
 $pattern='^'+[regex]::Escape($ProgramFilesRoot.TrimEnd('\'))+'\\WindowsApps\\windowsworkload\.manager\.[0-9]+_[0-9.]+_(x64|arm64|x86)__8wekyb3d8bbwe\\WorkloadsSessionHost\.exe$'
 return [regex]::IsMatch($Path,$pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)
}
function Convert-WamGalleryPreference([string]$Text,[bool]$Enabled) {
 $parsed=$Text|ConvertFrom-Json
 if(-not($parsed.PSObject.Properties.Name -contains 'IsAppContentSearchEnabled')){throw 'Unknown AI Gallery preference schema.'}
 $pattern='("IsAppContentSearchEnabled"\s*:\s*)(true|false)'
 if([regex]::Matches($Text,$pattern).Count -ne 1){throw 'Ambiguous AI Gallery preference; no write performed.'}
 $value=if($Enabled){'true'}else{'false'}
 return [regex]::Replace($Text,$pattern,('${1}'+$value))
}
function Write-WamAtomicText([string]$Path,[string]$Text,[bool]$HasBom) {
 $temp=Join-Path ([IO.Path]::GetDirectoryName($Path)) ('wam-'+[guid]::NewGuid().ToString('N')+'.tmp')
 try {
  [IO.File]::WriteAllText($temp,$Text,[Text.UTF8Encoding]::new($HasBom))
  # Windows PowerShell 5.1 marshals plain $null to an illegal empty backup pathname.
  if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,[NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
 }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}
