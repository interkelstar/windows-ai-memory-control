#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param(
 [ValidateSet('Status','Apply','Restore','Unload')][string]$Action='Status',
 [switch]$AllowExperimental,[switch]$AllowUntestedSystem,[switch]$Notify
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
$skipPath='SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkloadManager\SkipLanguageModelPreload'
$stateDir=Join-Path $env:ProgramData 'WindowsAIMemoryControl'
$stateFile=Join-Path $stateDir 'state.json'
$programFiles64=if($env:ProgramW6432){$env:ProgramW6432}else{$env:ProgramFiles}
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$operationLock=$null
function Open-Registry {return [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)}
function Read-Snapshot {
 $base=Open-Registry;$r=[ordered]@{}
 try {
  foreach($s in Get-WamSpecs){
   $key=$base.OpenSubKey($s.Path)
   try {$exists=$key -and ($key.GetValueNames() -contains $s.Name);$r[$s.Id]=[pscustomobject]@{Exists=[bool]$exists;Kind=$(if($exists){$key.GetValueKind($s.Name).ToString()}else{$null});Value=$(if($exists){$key.GetValue($s.Name)}else{$null})}}finally{if($key){$key.Close()}}
  }
  $skip=$base.OpenSubKey($skipPath)
  $r.PreloadSkip=[bool]$skip;$r.PreloadNonempty=[bool]($skip -and ($skip.ValueCount -gt 0 -or $skip.SubKeyCount -gt 0))
  if($skip){$skip.Close()}
 }finally{$base.Close()}
 return [pscustomobject]$r
}
function New-ProtectedDirectory([string]$Path,[switch]$LocalService) {
 if(Test-Path -LiteralPath $Path){
  $item=Get-Item -LiteralPath $Path
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Refusing a reparse-point state directory.'}
  $owner=(Get-Acl -LiteralPath $Path).GetOwner([Security.Principal.SecurityIdentifier]).Value
  if($owner -notin @('S-1-5-18','S-1-5-32-544')){throw 'Existing state directory is not owned by SYSTEM/Administrators. Inspect it before using privileged backups.'}
 }else{New-Item -ItemType Directory -Path $Path|Out-Null}
 $acl=New-Object Security.AccessControl.DirectorySecurity
 $acl.SetAccessRuleProtection($true,$false)
 $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
 foreach($sid in @('S-1-5-18','S-1-5-32-544')){
  $id=New-Object Security.Principal.SecurityIdentifier($sid)
  $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($id,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
 }
 $readers=New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')
 $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($readers,'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')))
 if($LocalService){$id=New-Object Security.Principal.SecurityIdentifier('S-1-5-19');$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($id,'Modify','ContainerInherit,ObjectInherit','None','Allow')))}
 Set-Acl -LiteralPath $Path -AclObject $acl
}
function Write-State($State) {Write-WamAtomicText $stateFile ($State|ConvertTo-Json -Depth 8) $true}
function Write-Result($Result) {
 $text=$Result|ConvertTo-Json -Depth 8
 $text|Set-Content -LiteralPath (Join-Path $stateDir 'last-operation.json') -Encoding UTF8
 Write-Output $text
}
function Set-PreloadKey([bool]$Present) {
 # No ownership/ACL changes to Windows registry keys. One short-lived LOCAL SERVICE task.
 $task='WindowsAIMemory-OneShot-'+[guid]::NewGuid().ToString('N')
 $dir=Join-Path $stateDir ('job-'+[guid]::NewGuid().ToString('N'))
 New-ProtectedDirectory $dir -LocalService
 $helper=Join-Path $dir 'helper.ps1';$result=Join-Path $dir 'result.json';$registered=$false
 try {
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PreloadKey-LocalService.ps1') -Destination $helper
  $mode=if($Present){'Create'}else{'Remove'}
  $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$helper+'" -Mode '+$mode+' -ResultPath "'+$result+'"'
  $a=New-ScheduledTaskAction -Execute $exe -Argument $arguments
  $p=New-ScheduledTaskPrincipal -UserId 'S-1-5-19' -LogonType ServiceAccount
  $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
  Register-ScheduledTask -TaskName $task -Action $a -Principal $p -Settings $settings|Out-Null;$registered=$true
  Start-ScheduledTask -TaskName $task
  $deadline=(Get-Date).AddSeconds(45)
  while(-not(Test-Path -LiteralPath $result) -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 250}
  if(-not(Test-Path -LiteralPath $result)){throw 'Preload helper timed out; inspect task cleanup and backup.'}
  $answer=Get-Content -LiteralPath $result -Raw|ConvertFrom-Json
  if(-not $answer.Success){throw $answer.Error}
 }finally {
  if($registered){Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue;Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction Stop;if(Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue){throw 'Temporary helper task could not be removed.'}}
  $full=[IO.Path]::GetFullPath($dir)
  if([IO.Path]::GetDirectoryName($full) -ne [IO.Path]::GetFullPath($stateDir) -or [IO.Path]::GetFileName($full) -notmatch '^job-[a-f0-9]{32}$'){throw 'Cleanup target validation failed.'}
  foreach($file in @($helper,$result)){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file -Force}}
  if(Test-Path -LiteralPath $full){if(@(Get-ChildItem -LiteralPath $full -Force).Count){Write-Warning ('Unexpected helper files preserved at '+$full)}else{Remove-Item -LiteralPath $full -Force}}
 }
}
function Set-Entry([string]$Id,$State) {
 if($Id -eq 'PreloadSkip'){Set-PreloadKey ([bool]$State);return}
 $spec=@(Get-WamSpecs|Where-Object Id -eq $Id)
 if($spec.Count -ne 1){throw 'Unknown registry setting identifier.'}
 $s=$spec[0];$base=Open-Registry
 try {
  if($State.Exists){
   if($State.Kind -ne 'DWord' -or [int64]$State.Value -notin @(0,1)){throw 'Only original Boolean DWORD values are supported.'}
   $key=$base.CreateSubKey($s.Path)
   try{$key.SetValue($s.Name,[int]$State.Value,[Microsoft.Win32.RegistryValueKind]::DWord)}finally{$key.Close()}
  }else{$key=$base.OpenSubKey($s.Path,$true);if($key){try{$key.DeleteValue($s.Name,$false)}finally{$key.Close()}}}
 }finally{$base.Close()}
}
function Get-Status {
 $os=Get-CimInstance Win32_OperatingSystem
 $hosts=@(foreach($p in Get-Process WorkloadsSessionHost -ErrorAction SilentlyContinue){
  $modules=@();$read=$false;$path=$null
  try{$path=$p.Path;$modules=@($p.Modules|Where-Object ModuleName -match 'Session.dll$|phiapi'|Select-Object -ExpandProperty ModuleName);$read=($modules.Count -gt 0)}catch{}
  [pscustomobject]@{Id=$p.Id;PathVerified=(Test-WamWorkloadPath $path $programFiles64);SessionModules=$modules;ModulesReadable=$read}
 })
 [pscustomobject]@{Time=(Get-Date).ToString('o');BootTime=$os.LastBootUpTime.ToString('o');AvailableGiB=[math]::Round($os.FreePhysicalMemory/1MB,2);TotalUsableGiB=[math]::Round($os.TotalVisibleMemorySize/1MB,2);Settings=(Read-Snapshot);Services=@(Get-CimInstance Win32_Service -Filter "Name='WSearch' OR Name='WSAIFabricSvc'"|Select-Object Name,State,StartMode);SystemModelHosts=$hosts;AdapterMemory=@(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory|Select-Object Name,SharedUsage);Note='Adapter IDs change after reboot. Shared accelerator memory is part of system RAM. A module-read failure is not proof that no model is loaded.'}
}
try {
 if($Action -eq 'Status'){Get-Status|ConvertTo-Json -Depth 8;exit 0}
 if($Action -eq 'Apply' -and -not $AllowExperimental){throw 'Apply requires -AllowExperimental: two controls are internal Windows implementation details.'}
 if($Action -eq 'Unload' -and -not $WhatIfPreference){
  if(Get-Process AIDevGallery -ErrorAction SilentlyContinue){throw 'Close AI Dev Gallery and finish other Windows AI requests before unloading.'}
  if(-not(Get-Process WorkloadsSessionHost -ErrorAction SilentlyContinue)){
   if($Notify){Add-Type -AssemblyName System.Windows.Forms;[Windows.Forms.MessageBox]::Show('No Windows AI model sessions are running.','Windows AI Memory Control')|Out-Null}
   @{Action='Unload';Stopped=@();AlreadyClear=$true}|ConvertTo-Json;exit 0
  }
 }
 if($WhatIfPreference){$null=$PSCmdlet.ShouldProcess('Windows AI settings/sessions', $Action);Write-Output 'Preview only: no changes or elevation. Run Status to inspect current state.';exit 0}
 if(-not $admin){
  $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Action '+$Action
  foreach($flag in @('AllowExperimental','AllowUntestedSystem','Notify')){if((Get-Variable $flag -ValueOnly)){$arguments+=' -'+$flag}}
  $window=if($Notify){'Hidden'}else{'Normal'}
  $elevationStarted=Get-Date
  $child=Start-Process $exe -Verb RunAs -WindowStyle $window -ArgumentList $arguments -Wait -PassThru
  $last=Join-Path $stateDir 'last-operation.json'
  if(Test-Path -LiteralPath $last){$report=Get-Content -LiteralPath $last -Raw|ConvertFrom-Json;if($report.Action -eq $Action -and [datetime]$report.Time -ge $elevationStarted){$report|ConvertTo-Json -Depth 8}}
  exit $child.ExitCode
 }
 New-ProtectedDirectory $stateDir
 $operationLock=[IO.File]::Open((Join-Path $stateDir 'operation.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 if($Action -eq 'Unload'){
  $stopped=@();$skipped=@()
  foreach($p in Get-Process WorkloadsSessionHost -ErrorAction SilentlyContinue){
   if(-not(Test-WamWorkloadPath $p.Path $programFiles64)){$skipped+=$p.Id;continue}
   if($PSCmdlet.ShouldProcess("Verified Windows AI session host PID $($p.Id)",'Terminate session and release model memory')){Stop-Process -Id $p.Id -Force;$stopped+=$p.Id}
  }
  if($skipped.Count){throw 'Some workload-host paths were unrecognized. They were left running.'}
  Start-Sleep -Seconds 2
  if($Notify){Add-Type -AssemblyName System.Windows.Forms;[Windows.Forms.MessageBox]::Show(('Stopped Windows AI model sessions: '+$stopped.Count+'. Your own NPU runtimes were not stopped.'),'Windows AI Memory Control')|Out-Null}
  Write-Result @{Time=(Get-Date).ToString('o');Action='Unload';Stopped=$stopped;RemainingHostCount=@(Get-Process WorkloadsSessionHost -ErrorAction SilentlyContinue).Count};exit 0
 }
 if($Action -eq 'Apply'){
  $v=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
  $cpu=(Get-CimInstance Win32_Processor|Select-Object -First 1).Name
  if(($v.CurrentBuild -ne '26300' -or $v.UBR -ne 9711 -or $cpu -notmatch 'AMD Ryzen AI 7 445') -and -not $AllowUntestedSystem){throw 'Untested build/hardware. Review the documented controls; -AllowUntestedSystem is an explicit opt-in, not a compatibility guarantee.'}
  $base=Open-Registry;$key=$base.OpenSubKey('SOFTWARE\Microsoft\Windows Search\SemanticIndexer');if(-not $key){$base.Close();throw 'SemanticIndexer key is absent. No changes made.'};$key.Close();$base.Close()
  $requiredServices=@(Get-CimInstance Win32_Service -Filter "Name='WSearch' OR Name='WSAIFabricSvc'")
  if($requiredServices.Count -ne 2){throw 'Required Search/AI Fabric service is absent. No Windows settings changed.'}
  foreach($svc in $requiredServices){if($svc.State -ne 'Running' -or $svc.StartMode -ne 'Auto'){throw 'Search/AI Fabric must already be Running/Automatic. This tool does not repair or disable services.'}}
  $before=Read-Snapshot
  foreach($spec in Get-WamSpecs){$old=$before.($spec.Id);if($old.Exists -and ($old.Kind -ne 'DWord' -or [int64]$old.Value -notin @(0,1))){throw 'Unexpected registry value type/content. Inspect manually.'}}
  if(-not $PSCmdlet.ShouldProcess('Windows AI background loading','Save original values and apply the memory profile')){exit 0}
  if(Test-Path -LiteralPath $stateFile){
   $state=Get-Content -LiteralPath $stateFile -Raw|ConvertFrom-Json
   if($state.Schema -ne 1){throw 'Unknown backup schema.'}
   if(-not $state.Restored){
    if($before.SemanticIndexing.Exists -and $before.SemanticIndexing.Value -eq 0 -and $before.SettingsAgent.Exists -and $before.SettingsAgent.Value -eq 1 -and $before.PreloadSkip){Write-Result @{Time=(Get-Date).ToString('o');Action='Apply';AlreadyApplied=$true;Backup=$stateFile;Settings=$before};exit 0}
    throw 'An existing baseline is present but settings differ. Use Status/Restore; never overwrite the original backup.'
   }
   Copy-Item -LiteralPath $stateFile -Destination (Join-Path $stateDir ('restored-'+[guid]::NewGuid().ToString('N')+'.json'))
  }
  $state=[pscustomobject]@{Schema=1;Created=(Get-Date).ToString('o');Build=($v.CurrentBuild+'.'+$v.UBR);Original=$before;Restored=$false;Applied=$false;LastError=$null}
  Write-State $state
  try {
   foreach($spec in Get-WamSpecs){Set-Entry $spec.Id ([pscustomobject]@{Exists=$true;Kind='DWord';Value=$spec.Desired})}
   if(-not $before.PreloadSkip){Set-PreloadKey $true}
   Restart-Service WSearch -Force
   $after=Read-Snapshot
   if($after.SemanticIndexing.Value -ne 0 -or $after.SettingsAgent.Value -ne 1 -or -not $after.PreloadSkip){throw 'Post-write verification failed.'}
   $state.Applied=$true;Write-State $state
  }catch{
   $state.LastError=$_.Exception.Message;Write-State $state
   try{foreach($entry in @(New-WamRestorePlan $state.Original (Read-Snapshot))){Set-Entry $entry.Id $entry.State};$state.Restored=$true;Write-State $state}catch{Write-Warning ('Automatic rollback incomplete; preserve backup: '+$_.Exception.Message)}
   throw
  }
 }else{
  if(-not(Test-Path -LiteralPath $stateFile)){throw 'No baseline from this tool. Do not guess factory defaults.'}
  $state=Get-Content -LiteralPath $stateFile -Raw|ConvertFrom-Json
  if($state.Schema -ne 1){throw 'Unknown backup schema.'}
  $plan=@(New-WamRestorePlan $state.Original (Read-Snapshot))
  if($PSCmdlet.ShouldProcess('Original saved Windows AI values','Restore')){
   foreach($entry in $plan){Set-Entry $entry.Id $entry.State}
   Restart-Service WSearch -Force
   $remaining=@(New-WamRestorePlan $state.Original (Read-Snapshot));if($remaining.Count){throw 'Restore verification failed.'}
   $state.Restored=$true;Write-State $state
  }
 }
 Write-Result @{Time=(Get-Date).ToString('o');Action=$Action;Backup=$stateFile;RebootRecommended=$true;Settings=(Read-Snapshot);Note='No session was forcibly unloaded. Reboot or use Unload after closing Windows AI clients.'}
}catch{
 if($Notify){Add-Type -AssemblyName System.Windows.Forms;[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Windows AI Memory Control')|Out-Null}
 Write-Error $_.Exception.Message -ErrorAction Continue
 exit 1
}finally{if(Get-Variable operationLock -ErrorAction SilentlyContinue){if($operationLock){$operationLock.Dispose()}}}
