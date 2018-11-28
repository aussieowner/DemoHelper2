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



 # Expired Role Check
<# Setup timer for Expired Role Check#>
$ExpiredRoleCheckIncrements = $Ini["ExpiredRoleCheck"]["ExpiredRoleCheckIncrements"]

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
$Code = $Code + 'WriteToLog "Checking for expired roles in DirectAuthorize"' + "`n"
$Code = $Code + "`n"
$Code = $Code + '$TargetServer = $Ini["DirectAuthorize"]["TargetServer"]' + "`n"
$Code = $Code + '$TargetRole = $Ini["DirectAuthorize"]["TargetRole"]' + "`n"
$Code = $Code + '$LocalListedRole = $Ini["DirectAuthorize"]["LocalListedRole"]' + "`n"
$Code = $Code + '' + "`n"
$Code = $Code + '$CdmManagedComputer = Get-CdmManagedComputer -Name $TargetServer' + "`n"
$Code = $Code + '$RoleAssignments = Get-CdmRoleAssignment -Computer $CdmManagedComputer' + "`n"
$Code = $Code + '' + "`n"
$Code = $Code + 'ForEach ($RoleAssignment In $RoleAssignments)' + "`n"
$Code = $Code + '{' + "`n"
$Code = $Code + '  $Role = $RoleAssignment.Role.Name' + "`n"
$Code = $Code + '  If ($Role.StartsWith($LocalListedRole))' + "`n"
$Code = $Code + '  {' + "`n"
$Code = $Code + '    $TargetLocalUser = $RoleAssignment.LocalTrustee' + "`n"
$Code = $Code + '    $LocalUserProfile = Get-CdmLocalUserProfile -Computer $CdmManagedComputer -Name $TargetLocalUser' + "`n"
$Code = $Code + '    If (-not $LocalUserProfile)' + "`n"
$Code = $Code + '    {' + "`n"
$Code = $Code + '      WriteToLog "Removing Role: $Role from Server: $TargetServer"' + "`n"
$Code = $Code + '      $RoleAssignment | Remove-CdmRoleAssignment' + "`n"
$Code = $Code + '      Continue' + "`n"
$Code = $Code + '    }' + "`n"
$Code = $Code + '  }' + "`n"
$Code = $Code + '' + "`n"        
$Code = $Code + '  If (($RoleAssignment.EndTime -lt $(Get-Date)) -and ($Role.StartsWith($TargetRole)))' + "`n"
$Code = $Code + '  {' + "`n"
$Code = $Code + '    WriteToLog "Removing Role: $Role from Server: $TargetServer"' + "`n"
$Code = $Code + '    $RoleAssignment | Remove-CdmRoleAssignment' + "`n"
$Code = $Code + '    Continue' + "`n"
$Code = $Code + '  }' + "`n"
$Code = $Code + '}' + "`n"
$Code = $Code + '' + "`n"
$Code = $Code + 'WriteToLog "Finished checking for expired roles in DirectAuthorize"' + "`n"

$ScriptBlock = [scriptblock]::Create($Code)

$ExpiredRolesTimer = New-Object System.Timers.Timer
WriteToLog "Creating TimerEvent for DirectAuthorize ExpiredRoles at $ExpiredRoleCheckIncrements seconds"
$LogLine = Register-ObjectEvent -InputObject $ExpiredRolesTimer -EventName Elapsed -Action $ScriptBlock | out-string
WriteToLog "$LogLine"

$ExpiredRolesTimer.Interval = ([int]$ExpiredRoleCheckIncrements * 1000) 
$ExpiredRolesTimer.AutoReset = $true
$ExpiredRolesTimer.Enabled = $true




