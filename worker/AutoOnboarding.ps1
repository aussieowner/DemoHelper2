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

$PidFile = "$absPath" + "\" + $Ini["Global"]["WorkerScriptPIDPath"] + "\$scriptName.pid" 
"$scriptPid" | Out-File $PidFile -Force


 # Heartbeat
<# Setup timer event to fire for heartbeat #>
$HeartbeatIncrements = $Ini["Global"]["HeartbeatIncrements"]

$Code = ""
$Code = $Code + '$scriptPath = "' + $scriptPath + '"' + "`n"
$Code = $Code + '$scriptName = "' + $scriptName + '"' + "`n"
$Code = $Code + '$scriptPid = ' + $scriptPid + "`n"
$Code = $Code + '$absPath = "' + $absPath + '"' + "`n"
$Code = $Code + "`n"
$Code = $Code + '. $absPath\include\Generic_SharedFunctions.ps1' + "`n"
$Code = $Code + '. $absPath\include\Ini_SharedFunctions.ps1' + "`n"
$Code = $Code + '. $absPath\include\RestApi_SharedFunctions.ps1' + "`n"
$Code = $Code + "`n"
$Code = $Code + '$Ini = Get-IniContent "$absPath\CentrifyDemoHelper.ini"' + "`n"
$Code = $Code + 'WriteToLog "Heartbeat - $scriptName"' + "`n"
$Code = $Code + "`n"

$ScriptBlock = [scriptblock]::Create($Code)

$heartbeatTimer = New-Object System.Timers.Timer
WriteToLog "Creating TimerEvent for Heartbeat at $heartbeatIncrements seconds"
$LogLine = Register-ObjectEvent -InputObject $heartbeatTimer -EventName Elapsed -Action $ScriptBlock | out-string
WriteToLog "$LogLine"

$heartbeatTimer.Interval = ([int]$HeartbeatIncrements * 1000) 
$heartbeatTimer.AutoReset = $true
$heartbeatTimer.Enabled = $true



 # Onboarding Check
<# Setup timer for Onboarding Check#>
  
$OnboardingCheckIncrements = $Ini["AutoOnboarding"]["OnboardingCheckIncrements"]

$Code = ""
$Code = $Code + '$scriptPath = "' + $scriptPath + '"' + "`n"
$Code = $Code + '$scriptName = "' + $scriptName + '"' + "`n"
$Code = $Code + '$scriptPid = ' + $scriptPid + "`n"
$Code = $Code + '$absPath = "' + $absPath + '"' + "`n"
$Code = $Code + "`n"
$Code = $Code + '. $absPath\include\Generic_SharedFunctions.ps1' + "`n"
$Code = $Code + '. $absPath\include\Ini_SharedFunctions.ps1' + "`n"
$Code = $Code + '. $absPath\include\RestApi_SharedFunctions.ps1' + "`n"
$Code = $Code + "`n"
$Code = $Code + '$Ini = Get-IniContent "$absPath\CentrifyDemoHelper.ini"' + "`n"
$Code = $Code + 'WriteToLog "AutoOnboarding starting"' + "`n"
$Code = $Code + "`n"
$Code = $Code + '$PidFile = $absPath + "\" + $Ini["AutoOnboarding"]["OnboardingPIDFile"]' + "`n"
$Code = $Code + 'If (Test-Path $PidFile)' + "`n"
$Code = $Code + '{' + "`n"
$Code = $Code + '  $FileCreationDate = [DateTime](Get-ChildItem $PidFile).CreationTime' + "`n"
$Code = $Code + '  $LinuxOnboardingScriptPid = Get-Content $PidFile' + "`n"
$Code = $Code + '' + "`n"
$Code = $Code + '  If (($FileCreationDate.AddSeconds($Ini["AutoOnboarding"]["OnboardingWatcherScriptTimeout"])) -lt (Get-Date))' + "`n"
$Code = $Code + '  {' + "`n"
$Code = $Code + '    WriteToLog "LinuxOnboarding script is already running. Killing Process: $LinuxOnboardingScriptPid"' + "`n"
$Code = $Code + '    Stop-Process -id $LinuxOnboardingScriptPid' + "`n"
$Code = $Code + '    Remove-ItemIfExists -Path $PidFile' + "`n"        
$Code = $Code + '  }' + "`n"
$Code = $Code + '}' + "`n"
$Code = $Code + '' + "`n"
$Code = $Code + '$TargetHost = $Ini["AutoOnboarding"]["TargetServerName"]' + "`n"
$Code = $Code + 'If (Test-Connection -computer $TargetHost -count 1 -quiet)' + "`n"
$Code = $Code + '{' + "`n"
$Code = $Code + '  # Start the Linux Onboarding Script' + "`n"  
$Code = $Code + '  WriteToLog "Starting LinuxOnboardingWatcher"' + "`n"
$Code = $Code + '  $ArgumentList = $absPath + "\" + $Ini["AutoOnboarding"]["OnboardingScriptName"]' + "`n"
$Code = $Code + '  $p = Start-Process -FilePath "powershell" -WindowStyle Minimized -ArgumentList $ArgumentList' + "`n"
$Code = $Code + '}' + "`n"
$Code = $Code + 'Else' + "`n"
$Code = $Code + '{' + "`n"
$Code = $Code + '  WriteToLog "AutoOnboarding skipped. $TargetHost is not online"' + "`n"
$Code = $Code + '}' + "`n"
$Code = $Code + 'WriteToLog "AutoOnboarding ending"' + "`n"

$ScriptBlock = [scriptblock]::Create($Code)

$AutoOnboardingTimer = New-Object System.Timers.Timer
WriteToLog "Creating TimerEvent for AutoOnboarding at $OnboardingCheckIncrements seconds"
$LogLine = Register-ObjectEvent -InputObject $AutoOnboardingTimer -EventName Elapsed -Action $ScriptBlock | out-string
WriteToLog "$LogLine"

$AutoOnboardingTimer.Interval = ([int]$OnboardingCheckIncrements * 1000) 
$AutoOnboardingTimer.AutoReset = $true
$AutoOnboardingTimer.Enabled = $true


 