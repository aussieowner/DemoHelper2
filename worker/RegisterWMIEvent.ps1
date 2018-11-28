param  
(
  [string]$Description,
  [string]$EventsToMonitor,
  [string]$EventHandlerPath,
  [string]$EventHandlerIsMutex,
  [string]$TargetComputer
)  

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

$PidFile = "$absPath" + "\" + $Ini["Global"]["WorkerScriptPIDPath"] + "\" + $scriptName + "-" + $Description + ".pid" 
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
$Code = $Code + 'WriteToLog "Heartbeat - ' + $scriptName + "-" + $Description + '"' + "`n"
$Code = $Code + "`n"

$ScriptBlock = [scriptblock]::Create($Code)

$heartbeatTimer = New-Object System.Timers.Timer
WriteToLog "Creating $Description TimerEvent for Heartbeat at $heartbeatIncrements seconds"
$LogLine = Register-ObjectEvent -InputObject $heartbeatTimer -EventName Elapsed -Action $ScriptBlock | out-string
WriteToLog "$LogLine"

$heartbeatTimer.Interval = ([int]$HeartbeatIncrements * 1000) 
$heartbeatTimer.AutoReset = $true
$heartbeatTimer.Enabled = $true



<# Setup WMI SQL query for event monitoring #>
$WMIPollingInterval = $Ini["WMI"]["WMIPollingInterval"]
$SQL = "SELECT * FROM __InstanceCreationEvent WITHIN " + $WMIPollingInterval + " " +  
       "WHERE TargetInstance ISA 'Win32_NTLogEvent' " + 
       "AND ( "

# We need to do some manipulation of the SQL query. Need to explicitly call out the EventID's we are 
# looking for
$EventsToMonitorSplit = $EventsToMonitor.Split(",")
For ($i=0; $i -lt $EventsToMonitorSplit.Count; $i++) {$EventsToMonitorSplit[$i] = "TargetInstance.EventCode = '" + $EventsToMonitorSplit[$i] + "'"}
$EventsToMonitorJoined = $EventsToMonitorSplit -join " OR "
$SQL = $SQL + $EventsToMonitorJoined + ")"

<# Setup code to fire when event occures. Note: This code that fires, does not have access to the rest of the routine. It runs in a vaccuum #>
 # Ok, this is going to be a bit strange but it is the hoops i had to jump thru to use the Async WMI handlers
 # First, the way this works is that you tell WMI which EventID's you want to monitor. Part of this setup
 # is to give it a script block that will be executed as a result of the EventID being created in AD. The script block
 # executes as a separte thread but still attached to "this" process. ie the calling script. The catch is that
 # the script block that is executed DOES NOT have any access to variables or routines that are part of the main
 # process. Becaue of this, the easiest thing that i found to do is to simply start another task and start another
 # powershell script. This allows the code to be multi-threaded because it does not wait for each process to finish, it just starts them
 # The other catch has to do with the $EventMsg. This variable comes back as a string. However, the string contains 
 # CR's and LF's. This ended up making it very difficult (read as near impossible) to deal with this as a simple
 # variable being passed on the command line to another PS script. The very low tech fix to this was to just write the
 # EventMsg out to a tmp file and then pass that file name to the new event handler script. This works quite well
$Code = ""
$Code = $Code + '$EventID = $event.SourceEventArgs.NewEvent.TargetInstance.EventCode' + "`n"
$Code = $Code + '$EventMsg = $event.SourceEventArgs.NewEvent.TargetInstance.Message' + "`n"
$Code = $Code + '$EventMsgFilename = ' + """$absPath\tmp\""" + ' + ([System.IO.Path]::GetRandomFileName())' + "`n"
$Code = $Code + '$EventMsg | Out-File $EventMsgFilename -Force' + "`n"
$Code = $Code + "`n"
$Code = $Code + '$ArgumentList = "' + $absPath + "\" + $EventHandlerPath +
                               ' -EventID $EventID' +
                               ' -EventMsgFilename $EventMsgFilename' + 
                               ' -EventHandlerIsMutex ' + $EventHandlerIsMutex + '"' + "`n"
$Code = $Code + '$p = Start-Process -WindowStyle Minimized -FilePath "powershell" -ArgumentList $ArgumentList' + "`n"

$ScriptBlock = [scriptblock]::Create($Code)

WriteToLog "Creating WmiEvent for Events $EventsToMonitor"
$LogLine = Register-WmiEvent -ComputerName $TargetComputer -Source $scriptName -Query $SQL -Action $ScriptBlock | out-string
WriteToLog "$LogLine"




 