

<#-----------------------------------------------------#>
<#                                                     #>
<# Function: GenerateRandomString                      #>
<#                                                     #>
<#-----------------------------------------------------#>
Function UpdateStatus()
{
  param 
  (
    [Switch] $Done,
    [Switch] $Busy
  )

  If ($Done)
  {
    $LogLine = "Updating status to NotBusy. Writing file: " + $Ini["Global"]["SourceFilename"] + " to " + $Ini["Global"]["TargetFilename"]  
    WriteToLog "$LogLine"
    Copy-ItemIfExists -SourcePath $Ini["Global"]["SourceFilename"] -DestinationPath $Ini["Global"]["TargetFilename"] 
  }
  
  If ($Busy)
  {
    $LogLine = "Updating status to Busy. Removing file: " + $Ini["Global"]["TargetFilename"]  
    WriteToLog "$LogLine"
    Remove-ItemIfExists $Ini["Global"]["TargetFilename"]
  }

}


<#-----------------------------------------------------#>
<#                                                     #>
<# Function: GenerateRandomString                      #>
<#                                                     #>
<#-----------------------------------------------------#>
Function GenerateRandomString($Length = 15)
{
  $Puncuation = 46..46
  $Digits = 48..57
  $Letters = 65..90 + 97..122

  $RandomString = Get-Random -count $Length `
                             -input ($Punctulation + $Digits + $Letters) |
                           % -begin { $aa = $null } `
                             -process {$aa += [char]$_} `
                             -end {$aa}

  return $RandomString
}


<#-----------------------------------------------------#>
<#                                                     #>
<# Function: IfNull                                    #>
<#                                                     #>
<#-----------------------------------------------------#>
Function IfNull($string) { if ($string -eq $null) { Return "" } Else { Return $string } }

<#-----------------------------------------------------#>
<#                                                     #>
<# Function: IIf                                       #>
<#                                                     #>
<#-----------------------------------------------------#>
Function IIf($If, $Right, $Wrong) {If ($If) {$Right} Else {$Wrong}}

<#-----------------------------------------------------#>
<#                                                     #>
<# Function: Copy-ItemIfExists                         #>
<#                                                     #>
<#-----------------------------------------------------#>
Function Copy-ItemIfExists
{
  param 
  (
    [String] $SourcePath,
    [String] $DestinationPath
  )

  If (Test-Path $SourcePath) 
  {
    Copy-Item $SourcePath $DestinationPath -Force
  }
}

<#-----------------------------------------------------#>
<#                                                     #>
<# Function: Remove-ItemIfExists                       #>
<#                                                     #>
<#-----------------------------------------------------#>
Function Remove-ItemIfExists
{
  param 
  (
    [String] $Path
  )

  $LogLine = "Removing $Path"  
  WriteToLog "$LogLine"

  If (Test-Path $Path) 
  {
    Remove-Item $Path 
    
    If ($?)
    {
      $LogLine = "File: $Path was successfully deleted" 
      WriteToLog "$LogLine"
    }
    Else 
    { 
      $LogLine = $_
      WriteToLog $LogLine
    }
  }
  Else
  {
    $LogLine = "File: $Path was not found" 
    WriteToLog "$LogLine" 
  }
}

<#-----------------------------------------------------#>
<#                                                     #>
<# Function: ExecuteADFlushAndKillExpiredSessions      #>
<#                                                     #>
<#-----------------------------------------------------#>
Function ExecuteADFlushAndKillExpiredSessions()
{

 <# Execute adflush and rm home dir on list of Unix Servers #>
  $Servers = IfNull($Ini["Global"]["UnixServers"])
  If ($Servers) 
  {
    $RunAsUser = $Ini["Global"]["RunAsUser"]
    $ADFlushCommand = $Ini["Putty"]["*nix_adflush"]
    $KillExpiredSessions = $Ini["Putty"]["*nix_killexpiredsessions"]
    
    ForEach ($Server In $Servers.Split(","))
    {
      ExecuteCommandOnRemoteHost -FailFast -RemoteServer $Server -RemoteCommand $ADFlushCommand -RemoteUserid $RunAsUser -UseKerberos
      ExecuteCommandOnRemoteHost -FailFast -RemoteServer $Server -RemoteCommand $KillExpiredSessions -RemoteUserid $RunAsUser -UseKerberos 
    }
  }
}

<#-----------------------------------------------------#>
<#                                                     #>
<# Function: ExecuteADFlushAndRmHome                   #>
<#                                                     #>
<#-----------------------------------------------------#>
Function ExecuteADFlushAndRmHome()
{

 <# Execute adflush and rm home dir on list of Unix Servers #>
  $Servers = IfNull($Ini["Global"]["UnixServers"])
  If ($Servers) 
  {
    $RunAsUser = $Ini["Global"]["RunAsUser"]
    $ADFlushCommand = $Ini["Putty"]["*nix_adflush"]
    $RmHomeDirCommand = $Ini["Putty"]["*nix_rmhome"]
    $RmHomeDirCommand = $RmHomeDirCommand.Replace('$SamAccountName',$SamAccountName)
    $Command = $ADFlushCommand + " ; " + $RmHomeDirCommand
    
    ForEach ($Server In $Servers.Split(","))
    {
      ExecuteCommandOnRemoteHost -FailFast -RemoteServer $Server -RemoteCommand $Command -RemoteUserid $RunAsUser -UseKerberos
    }
  }

  <# Execute adflush and rm home dir on list of Macs #>
  $Servers = IfNull($Ini["Global"]["Mac"])
  If ($Servers) 
  {
    $RunAsUser = $Ini["Putty"]["Mac_login"]
    $RunAsUserPassword = $Ini["Putty"]["Mac_password"]
    $ADFlushCommand = $Ini["Putty"]["Mac_adflush"]
    $RmHomeDirCommand = $Ini["Putty"]["Mac_adflush"]
    $RmHomeDirCommand = $RmHomeDirCommand.Replace('$SamAccountName',$SamAccountName)
    $Command = $ADFlushCommand + " ; " + $RmHomeDirCommand
    
    ForEach ($Server In $Servers.Split(","))
    {
      ExecuteCommandOnRemoteHost -FailFast -RemoteServer $Server -RemoteCommand $Command -RemoteUserid $RunAsUser -RemotePassword $RunAsUserPassword
    }
  }
   
  <# Execute adflush and rm home dir on list of Ubuntu workstations #>
  $Servers = IfNull($Ini["Global"]["Ubuntu"])
  If ($Servers) 
  {
    $RunAsUser = $Ini["Putty"]["Ubuntu_login"]
    $RunAsUserPassword = $Ini["Putty"]["Ubuntu_password"]
    $ADFlushCommand = $Ini["Putty"]["Ubuntu_adflush"]
    $RmHomeDirCommand = $Ini["Putty"]["Ubuntu_adflush"]
    $RmHomeDirCommand = $RmHomeDirCommand.Replace('$SamAccountName',$SamAccountName)
    $Command = $ADFlushCommand + " ; " + $RmHomeDirCommand
    
    ForEach ($Server In $Servers.Split(","))
    {
      ExecuteCommandOnRemoteHost -FailFast -RemoteServer $Server -RemoteCommand $Command -RemoteUserid $RunAsUser -$UseKerberos
    }
  }
}

<#-----------------------------------------------------#>
<#                                                     #>
<# Function: ExecuteADFlushAndAdgpupdate               #>
<#                                                     #>
<#-----------------------------------------------------#>
Function ExecuteADFlushAndAdgpupdate()
{

 <# Execute adflush and rm home dir on list of Unix Servers #>
  $Servers = IfNull($Ini["Global"]["UnixServers"])
  If ($Servers) 
  {
    $RunAsUser = $Ini["Global"]["RunAsUser"]
    $ADFlushCommand = $Ini["Putty"]["*nix_adflush"]
    $ADGPUpdateCommand = $Ini["Putty"]["*nix_adgpupdate"]
    $Command = $ADFlushCommand + " ; " + $ADGPUpdateCommand
    
    ForEach ($Server In $Servers.Split(","))
    {
      ExecuteCommandOnRemoteHost -FailFast -RemoteServer $Server -RemoteCommand $Command -RemoteUserid $RunAsUser -UseKerberos
    }
  }

  <# Execute adflush and rm home dir on list of Macs #>
  $Servers = IfNull($Ini["Global"]["Mac"])
  If ($Servers) 
  {
    $RunAsUser = $Ini["Putty"]["Mac_login"]
    $RunAsUserPassword = $Ini["Putty"]["Mac_password"]
    $ADFlushCommand = $Ini["Putty"]["Mac_adflush"]
    $ADGPUpdateCommand = $Ini["Putty"]["Mac_adgpupdate"]
    $Command = $ADFlushCommand + " ; " + $ADGPUpdateCommand
    
    ForEach ($Server In $Servers.Split(","))
    {
      ExecuteCommandOnRemoteHost -FailFast -RemoteServer $Server -RemoteCommand $Command -RemoteUserid $RunAsUser -RemotePassword $RunAsUserPassword
    }
  }
   
  <# Execute adflush and rm home dir on list of Ubuntu workstations #>
  $Servers = IfNull($Ini["Global"]["Ubuntu"])
  If ($Servers) 
  {
    $RunAsUser = $Ini["Putty"]["Ubuntu_login"]
    $RunAsUserPassword = $Ini["Putty"]["Ubuntu_password"]
    $ADFlushCommand = $Ini["Putty"]["Ubuntu_adflush"]
    $ADGPUpdateCommand = $Ini["Putty"]["Ubuntu_adgpupdate"]
    $Command = $ADFlushCommand + " ; " + $ADGPUpdateCommand
    
    ForEach ($Server In $Servers.Split(","))
    {
      ExecuteCommandOnRemoteHost -FailFast -RemoteServer $Server -RemoteCommand $Command -RemoteUserid $RunAsUser -$UseKerberos
    }
  }
}

<#-----------------------------------------------------#>
<#                                                     #>
<# Function: ExecuteADFlush                            #>
<#                                                     #>
<#-----------------------------------------------------#>
Function ExecuteADFlush()
{

 <# Execute adflush and rm home dir on list of Unix Servers #>
  $Servers = IfNull($Ini["Global"]["UnixServers"])
  If ($Servers) 
  {
    $RunAsUser = $Ini["Global"]["RunAsUser"]
    $ADFlushCommand = $Ini["Putty"]["*nix_adflush"]
    
    ForEach ($Server In $Servers.Split(","))
    {
      ExecuteCommandOnRemoteHost -FailFast -RemoteServer $Server -RemoteCommand $ADFlushCommand -RemoteUserid $RunAsUser -UseKerberos
    }
  }

  <# Execute adflush and rm home dir on list of Macs #>
  $Servers = IfNull($Ini["Global"]["Mac"])
  If ($Servers) 
  {
    $RunAsUser = $Ini["Putty"]["Mac_login"]
    $RunAsUserPassword = $Ini["Putty"]["Mac_password"]
    $ADFlushCommand = $Ini["Putty"]["Mac_adflush"]
    
    ForEach ($Server In $Servers.Split(","))
    {
      ExecuteCommandOnRemoteHost -FailFast -RemoteServer $Server -RemoteCommand $ADFlushCommand -RemoteUserid $RunAsUser -RemotePassword $RunAsUserPassword
    }
  }
   
  <# Execute adflush and rm home dir on list of Ubuntu workstations #>
  $Servers = IfNull($Ini["Global"]["Ubuntu"])
  If ($Servers) 
  {
    $RunAsUser = $Ini["Putty"]["Ubuntu_login"]
    $RunAsUserPassword = $Ini["Putty"]["Ubuntu_password"]
    $ADFlushCommand = $Ini["Putty"]["Ubuntu_adflush"]
    
    ForEach ($Server In $Servers.Split(","))
    {
      ExecuteCommandOnRemoteHost -FailFast -RemoteServer $Server -RemoteCommand $ADFlushCommand -RemoteUserid $RunAsUser -$UseKerberos
    }
  }

  
}<#-----------------------------------------------------#>
<#                                                     #>
<# Function: ExecuteCommandLocallyAndWait              #>
<#                                                     #>
<#-----------------------------------------------------#>
Function ExecuteCommandLocallyAndWait()
{
  param
    (
      [Parameter(Mandatory=$true)] [string] $Path,
      [Parameter(Mandatory=$true)] [string] $Arguments
    )

  $LogLine = "Executing: $Path $Arguments"  
  WriteToLog "$LogLine"
  
  $pinfo = New-Object System.Diagnostics.ProcessStartInfo
  $pinfo.FileName = $Path
  $pinfo.RedirectStandardError = $true
  $pinfo.RedirectStandardOutput = $true
  $pinfo.UseShellExecute = $false
  $pinfo.Arguments = $Arguments

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $pinfo
  $p.Start() | Out-Null
  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()

  $Filename = ($Path.Split("\")) | Select-Object -Last 1
  ForEach ($Line In $stdout.Split([Environment]::NewLine))
    {
      $LogLine = "$Filename - stdout - " + $Line
      WriteToLog "$LogLine"
    }

  ForEach ($Line In $stderr.Split([Environment]::NewLine))
    {
      $LogLine = "$Filename - stderr - " + $Line
      WriteToLog "$LogLine"
    }

  $LogLine = "$Filename - Exit Code: " + $p.ExitCode
  WriteToLog "$LogLine"
}

<#-----------------------------------------------------#>
<#                                                     #>
<# Function: ExecuteCommandOnRemoteHost                #>
<#                                                     #>
<#-----------------------------------------------------#>
Function ExecuteCommandOnRemoteHost()
{
  param
    (
      [Parameter(Mandatory=$true)]  [string] $RemoteServer,
      [Parameter(Mandatory=$false)] [string] $RemoteCommand,
      [Parameter(Mandatory=$false)] [string] $RemoteUserid,
      [Parameter(Mandatory=$false)] [string] $RemotePassword,
      [Parameter(Mandatory=$false)] [switch] $UseKerberos = $False,
      [Parameter(Mandatory=$false)] [switch] $FailFast = $False,
      [Parameter(Mandatory=$false)] [switch] $Simulated = $False,
      [Parameter(Mandatory=$false)] [switch] $ReturnStdOut = $False,
      [Parameter(Mandatory=$false)] [switch] $AcceptHostKey = $False
      
    )

  $LogLine = "RemoteServer = $RemoteServer, UseKerberos = $UseKerberos, FailFast = $FailFast, RemoteUserid = $RemoteUserid, RemoteCommand = $RemoteCommand, ReturnStdOut = $ReturnStdOut, AcceptHostKey = $AcceptHostKey"    
    
  WriteToLog "ExecuteCommandOnRemoteHost: $LogLine"

  If ($Simulated) 
  {
    WriteToLog "ExecuteCommandOnRemoteHost: Simulated execution"
    Return
  }
  
  If (($FailFast) -and (-not (Test-Connection -computer $RemoteServer -count 1 -quiet)))
  {
    WriteToLog "ExecuteCommandOnRemoteHost: $RemoteServer is offline"
    Return
  }

  If ($AcceptHostKey) 
  {
    WriteToLog "ExecuteCommandOnRemoteHost: Accept Host Key"
    $PlinkPath = $Ini["Putty"]["PlinkPath"]
    $PlinkArguments = "-pw " + $RemotePassword + " -ssh -noagent " + $RemoteUserid + "@" + $RemoteServer + " " + "exit"
    $PlinkCommand  = [string]::Format('echo y | & "{0}" {1} 2>$null', $PlinkPath, $PlinkArguments)
    WriteToLog "ExecuteCommandOnRemoteHost: PlinkCommand = $PlinkCommand"
    $Output = Invoke-Expression $PlinkCommand
    WriteToLog "ExecuteCommandOnRemoteHost: Output = $Output"
    Return
  }
    
  $pinfo = New-Object System.Diagnostics.ProcessStartInfo
  $pinfo.FileName = $Ini["Putty"]["PlinkPath"]
  $pinfo.RedirectStandardError = $true
  $pinfo.RedirectStandardOutput = $true
  $pinfo.UseShellExecute = $false
  
  If ($UseKerberos)
  {
    $pinfo.Arguments = "-k -ssh -noagent " + $RemoteUserid + "@" + $RemoteServer + " " + $RemoteCommand
  }
  Else
  {
    $pinfo.Arguments = "-pw " + $RemotePassword + " -ssh -noagent " + $RemoteUserid + "@" + $RemoteServer + " " + $RemoteCommand
  }

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $pinfo
  $p.Start() | Out-Null

  $RemoteCommandTimeoutSeconds = $Ini["Putty"]["RemoteCommandTimeoutSeconds"]
  $FinishedInAlottedTime = $p.WaitForExit($RemoteCommandTimeoutSeconds)
  if (!$FinishedInAlottedTime) 
  {
    WriteToLog "ExecuteCommandOnRemoteHost: Command timed out"
    $p.Kill()
    WriteToLog "ExecuteCommandOnRemoteHost: Process was killed"
  }

  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  
  $Filename = (($pinfo.FileName).Split("\")) | Select-Object -Last 1
  ForEach ($Line In $stdout.Split([Environment]::NewLine))
    {
      $LogLine = "$Filename - stdout - " + $Line
      WriteToLog "$LogLine"
    }

  ForEach ($Line In $stderr.Split([Environment]::NewLine))
    {
      $LogLine = "$Filename - stderr - " + $Line
      WriteToLog "$LogLine"
    }

  $LogLine = "$Filename - Exit Code: " + $p.ExitCode
  WriteToLog "$LogLine"
  
  If ($ReturnStdOut) {Return $stdout}
}

<#-----------------------------------------------------#>
<#                                                     #>
<# Function: WriteToLog                                #>
<#                                                     #>
<#-----------------------------------------------------#>
Function WriteToLog()
{
<# Use this command to view log in real time: Get-Content ./log.log -Wait -Tail 10 #>
  param
  (
    [Parameter(Mandatory=$false)][switch] $NewLog = $false,
    [Parameter(Mandatory=$false,Position=0)] [string] $LogMsg
  )

  $mutex = new-object System.Threading.Mutex $false,'CentrifyDemoHelper-WriteToLog'
  $mutex.WaitOne() > $null

  $LogFilename = "$absPath\" + $Ini["Global"]["LogFileName"]

  If ($NewLog)
    {
      $NewLogMsg = "================= New Log started " + $(Get-Date) + " ================="  
      "" | Out-File $LogFilename -Force -Append
      $NewLogMsg | Out-File $LogFilename -Force -Append 
    }
  Else
    {
      $Source = $scriptName + "(" + $scriptPid + ")"
      $Source = $Source.PadRight(26)
      $Line = "$(Get-Date)" + ":" + $Source + " : " + $LogMsg
      $Line | Out-File $LogFilename -Force -Append
    }

  $mutex.ReleaseMutex()

}

<#-----------------------------------------------------#>
<#                                                     #>
<# Function: ParseEventMsg                             #>
<#                                                     #>
<#-----------------------------------------------------#>
Function ParseEventMsg()
{
  param 
  (
    [String] $EventMsg,
    [String] $Section,
    [String] $Keyword
  )

  $Lines = $EventMsg.Split([Environment]::NewLine) 
  $SectionFound = $False
  ForEach ($Line In $Lines)
  {
    $Line = $Line.Trim()
    $Line = $Line.Replace("`t","")

    If ($SectionFound)
    {
      If ($Line.StartsWith($Keyword))
      {
        $ReturnValue = $Line.Split(":")[1]
        Return $ReturnValue
      }
    }
    
    If ($Line.StartsWith($Section)) 
    {
      $SectionFound=$True
      Continue
    }
  }
}

<#-----------------------------------------------------#>
<#                                                     #>
<# Function: Select-WriteHost                          #>
<#                                                     #>
<#-----------------------------------------------------#>
Function Select-WriteHost
{
# This is an intersting function i ran across in the Google
# Basically, it allows you to run a script (that uses Write-Host) and
# capture this output as you would stdout/stderr. Normally, the Write-Host command
# cannot be capture programatically. It writes directly to the console. This programatically
# does some tricks by creating (at run time) an Alias for "Write-Host" and instead writes the output
# to a "grab-able" place.
# Use this to run .ps1 to capture Write-Host 
# Select-WriteHost { .\MyScript.ps1 } | Out-File .\ExecutionLog.log
   [CmdletBinding(DefaultParameterSetName = 'FromPipeline')]
   param(
     [Parameter(ValueFromPipeline = $true, ParameterSetName = 'FromPipeline')]
     [object] $InputObject,

     [Parameter(Mandatory = $true, ParameterSetName = 'FromScriptblock', Position = 0)]
     [ScriptBlock] $ScriptBlock,

     [switch] $Quiet
   )

   begin
   {
     function Cleanup
     {
       # clear out our proxy version of write-host
       remove-item function:write-host -ea 0
     }

     function ReplaceWriteHost([switch] $Quiet, [string] $Scope)
     {
         # create a proxy for write-host
         $metaData = New-Object System.Management.Automation.CommandMetaData (Get-Command 'Microsoft.PowerShell.Utility\Write-Host')
         $proxy = [System.Management.Automation.ProxyCommand]::create($metaData)

         # change its behavior
         $content = if($quiet)
                    {
                       # in quiet mode, whack the entire function body, simply pass input directly to the pipeline
                       $proxy -replace '(?s)\bbegin\b.+', '$Object' 
                    }
                    else
                    {
                       # in noisy mode, pass input to the pipeline, but allow real write-host to process as well
                       $proxy -replace '($steppablePipeline.Process)', '$Object; $1'
                    }  

         # load our version into the specified scope
         Invoke-Expression "function ${scope}:Write-Host { $content }"
     }

     Cleanup

     # if we are running at the end of a pipeline, need to immediately inject our version
     #    into global scope, so that everybody else in the pipeline uses it.
     #    This works great, but dangerous if we don't clean up properly.
     if($pscmdlet.ParameterSetName -eq 'FromPipeline')
     {
        ReplaceWriteHost -Quiet:$quiet -Scope 'global'
     }
   }

   process
   {
      # if a scriptblock was passed to us, then we can declare
      #   our version as local scope and let the runtime take it out
      #   of scope for us.  Much safer, but it won't work in the pipeline scenario.
      #   The scriptblock will inherit our version automatically as it's in a child scope.
      if($pscmdlet.ParameterSetName -eq 'FromScriptBlock')
      {
        . ReplaceWriteHost -Quiet:$quiet -Scope 'local'
        & $scriptblock
      }
      else
      {
         # in pipeline scenario, just pass input along
         $InputObject
      }
   }

   end
   {
      Cleanup
   }  
}

