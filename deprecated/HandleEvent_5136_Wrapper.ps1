param  
(
  [string]$EventID,
  [string]$EventMsgFilename
)  

$mutex = new-object System.Threading.Mutex $false,"CentrifyDemoHelper-HandleEvent_5136_Wrapper"
$mutex.WaitOne() > $null

<# Get the path,name and PID to the actual script #>
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$scriptName = split-path -leaf $MyInvocation.MyCommand.Definition
$scriptPid = $Pid
Try {. $scriptPath\abspath.ps1} Catch {$absPath = $scriptPath}

. $absPath\include\Ini_SharedFunctions
. $absPath\include\Generic_SharedFunctions.ps1


$Ini = Get-IniContent "$absPath\CentrifyDemoHelper.ini"
WriteToLog "Excuting HandleEvent_5136.ps1, EventID = $EventID, Filename = $EventMsgFilename"


$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName = "Powershell"
$pinfo.RedirectStandardError = $true
$pinfo.RedirectStandardOutput = $true
$pinfo.UseShellExecute = $false
$pinfo.Arguments = "$absPath\HandleEvent_5136.ps1 -EventID $EventID -EventMsgFilename $EventMsgFilename"

$p = New-Object System.Diagnostics.Process
$p.StartInfo = $pinfo

$p.Start() | Out-Null
$stdout = $p.StandardOutput.ReadToEnd()
$stderr = $p.StandardError.ReadToEnd()
$p.WaitForExit()
$Line = "EventWrapper_5136:($EventID):($EventMsgFilename) - Return Code from HandleEvent_5136.ps1: " + $p.ExitCode
WriteToLog $Line

If ($p.ExitCode -ne 0)
{
  ForEach ($Line In $stdout.Split([Environment]::NewLine)) {WriteToLog "EventWrapper:($EventID):($EventMsgFilename) - stdout - $Line"}
  ForEach ($Line In $stderr.Split([Environment]::NewLine)) {WriteToLog "EventWrapper:($EventID):($EventMsgFilename) - stderr - $Line"}
}

$mutex.ReleaseMutex()
