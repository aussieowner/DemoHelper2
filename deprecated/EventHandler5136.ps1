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

<# Setup WMI SQL query for event monitoring for EventID 5136#>
 # This is the exact same setup, however, this is ESCLUSIVELY for EventID 5136
 # AD generates tons of these events. These events can easily overwhelm the event handler from above
 # The low tech fix for this was to create a separate event handler for just this eventid. 
$WMIPollingInterval = $Ini["WMI"]["WMIPollingInterval"]
$SQL = "SELECT * FROM __InstanceCreationEvent WITHIN " + $WMIPollingInterval + " " +  
       "WHERE TargetInstance ISA 'Win32_NTLogEvent' " + 
       "AND   TargetInstance.EventCode = '5136' "


<# Setup code to fire when event occures. Note: This code that fires, does not have access to the rest of the routine. It runs in a vaccuum #>
$Code = ""
$Code = $Code + '$EventID = $event.SourceEventArgs.NewEvent.TargetInstance.EventCode' + "`n"
$Code = $Code + '$EventMsg = $event.SourceEventArgs.NewEvent.TargetInstance.Message' + "`n"
$Code = $Code + '$EventMsgFilename = ' + """$absPath\tmp\""" + ' + ([System.IO.Path]::GetRandomFileName())' + "`n"
$Code = $Code + '$EventMsg | Out-File $EventMsgFilename -Force' + "`n"
$Code = $Code + "`n"
$Code = $Code + '$ArgumentList = "' + "$absPath\HandleEvent5136.ps1" +
                               ' -EventID $EventID' +
                               ' -EventMsgFilename $EventMsgFilename' + '"' + "`n"
$Code = $Code + '$p = Start-Process -WindowStyle Minimized -FilePath "powershell" -ArgumentList $ArgumentList' + "`n"

$ScriptBlock = [scriptblock]::Create($Code)

WriteToLog "Creating WmiEvent for Event 5136"
$LogLine = Register-WmiEvent -Source $scriptName -Query $SQL -Action $ScriptBlock | out-string
WriteToLog "$LogLine"



 