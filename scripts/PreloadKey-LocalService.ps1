param([ValidateSet('Create','Remove')][string]$Mode,[Parameter(Mandatory=$true)][string]$ResultPath)
$ErrorActionPreference='Stop'
$r=@{Success=$false}
try {
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){throw 'This helper only runs as LOCAL SERVICE.'}
 $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
 $parent=$base.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkloadManager',$true)
 if(-not $parent){throw 'WorkloadManager registry parent not available.'}
 try {
  $key=$parent.OpenSubKey('SkipLanguageModelPreload')
  if($Mode -eq 'Create') {if($key){$key.Close()}else{$new=$parent.CreateSubKey('SkipLanguageModelPreload');$new.Close()}}
  elseif($key){
   try {if($key.ValueCount -ne 0 -or $key.SubKeyCount -ne 0){throw 'Refusing to remove a nonempty preload key.'}}finally{$key.Close()}
   $parent.DeleteSubKey('SkipLanguageModelPreload',$false)
  }
 }finally{$parent.Close();$base.Close()}
 $r.Success=$true
}catch{$r.Error=$_.Exception.Message}
$r|ConvertTo-Json|Set-Content -LiteralPath $ResultPath -Encoding UTF8
if(-not $r.Success){exit 1}
