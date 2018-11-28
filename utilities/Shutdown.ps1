<# Get the path,name and PID to the actual script #>
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$scriptName = split-path -leaf $MyInvocation.MyCommand.Definition
$scriptPid = $Pid
Try {. $scriptPath\abspath.ps1} Catch {$absPath = $scriptPath}

<# Copy runbooks #>
. $absPath\include\Generic_SharedFunctions.ps1
. $absPath\include\Ini_SharedFunctions.ps1
. $absPath\include\RestApi_SharedFunctions.ps1

<# Read INI file #>
$Ini = Get-IniContent "$absPath\CentrifyDemoHelper.ini"

$ShutdownFile = $absPath + "\" + $Ini["Global"]["ShutdownFilename"]
"Shutdown" | Out-File $ShutdownFile -Force

WriteToLog "Shutdown.ps1 - Shutdown command sent to CentrifyDemoHelper Service"

