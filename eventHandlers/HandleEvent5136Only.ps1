param  
(
  [string]$EventID,
  [string]$EventMsgFilename,
  [string]$EventHandlerIsMutex
)  

$EventMsg = Get-Content $EventMsgFilename -Raw
Remove-Item $EventMsgFilename

<# Get the path,name and PID to the actual script #>
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$scriptName = split-path -leaf $MyInvocation.MyCommand.Definition
$scriptPid = $Pid
Try {. $scriptPath\abspath.ps1} Catch {$absPath = $scriptPath}

. $absPath\include\Generic_SharedFunctions.ps1
. $absPath\include\RestAPI_SharedFunctions.ps1
. $absPath\include\Ini_SharedFunctions
. $absPath\include\HandleEvent_5136_Functions.ps1


$Ini = Get-IniContent "$absPath\CentrifyDemoHelper.ini"

If ($EventHandlerIsMutex -eq "True") 
{
  $mutex = new-object System.Threading.Mutex $false,$scriptName
  $mutex.WaitOne() > $null
}

Switch ($EventID)
{
  $AD_ADirectoryServiceObjectWasModified
  {
    Handle_ADirectoryServiceObjectWasModifed
  }
    
  default 
  {
  }

}    

If ($EventHandlerIsMutex -eq "True") 
{
  $mutex.ReleaseMutex()
}  
