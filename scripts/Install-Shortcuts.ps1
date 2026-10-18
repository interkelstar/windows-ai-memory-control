#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param([string]$ShortcutName='Free Windows AI memory')
$ErrorActionPreference='Stop'
if($ShortcutName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0){throw 'Invalid shortcut name.'}
$destination=Join-Path $env:LOCALAPPDATA 'WindowsAIMemoryControl\Tools'
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
$menu=Join-Path ([Environment]::GetFolderPath('Programs')) 'Windows AI Memory Control'
if($PSCmdlet.ShouldProcess('Current-user Desktop and Start Menu','Install stable Windows AI memory command and shortcuts')){
 New-Item -ItemType Directory -Path $destination,$menu -Force|Out-Null
 foreach($name in @('WindowsAIMemory.ps1','Core.ps1','PreloadKey-LocalService.ps1')){
  $source=Join-Path $PSScriptRoot $name;$target=Join-Path $destination $name
  if([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($target)){Copy-Item -LiteralPath $source -Destination $target -Force}
  if((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $target).Hash){throw 'Installed script verification failed.'}
 }
 $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $destination 'WindowsAIMemory.ps1')+'" -Action Unload -Notify'
 $shell=New-Object -ComObject WScript.Shell
 $links=@((Join-Path $desktop ($ShortcutName+'.lnk')),(Join-Path $menu ($ShortcutName+'.lnk')))
 foreach($link in $links){$s=$shell.CreateShortcut($link);$s.TargetPath=$exe;$s.Arguments=$arguments;$s.WorkingDirectory=$destination;$s.Description='Release Windows AI model sessions after closing AI apps. Does not stop your own NPU runtimes.';$s.IconLocation=(Join-Path $env:SystemRoot 'System32\shell32.dll')+',238';$s.Save()}
 $command='@echo off'+"`r`n"+'"'+$exe+'" -NoProfile -ExecutionPolicy Bypass -File "%~dp0WindowsAIMemory.ps1" -Action Unload %*'+"`r`n"
 [IO.File]::WriteAllText((Join-Path $destination 'Free-WindowsAI-Memory.cmd'),$command,[Text.Encoding]::ASCII)
 @{InstalledTo=$destination;Shortcuts=$links;Command=(Join-Path $destination 'Free-WindowsAI-Memory.cmd');Note='No autorun, persistent scheduled task, service, PATH edit, or UAC bypass installed.'}|ConvertTo-Json
}
