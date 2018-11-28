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
. $absPath\SmartCard\Yubikey_SharedFunctions.ps1
. $absPath\include\HandleEvents_Functions.ps1

$Ini = Get-IniContent "$absPath\CentrifyDemoHelper.ini"

If ($EventHandlerIsMutex -eq "True") 
{
  $mutex = new-object System.Threading.Mutex $false,$scriptName
  $mutex.WaitOne() > $null
}

WriteToLog "EventID $EventID fired"

If ($Ini["Global"]["UseInternet"] -eq "True") 
{
  If (Test-Connection -computer $Ini["Global"]["InternetHostToCheck"] -count 1 -quiet)
  {
    $InternetIsAvailable = $true
    WriteToLog "Internet is up"
  } 
  Else 
  {
    $InternetIsAvailable = $false
    WriteToLog "Internet is down"
  } 
} 
Else 
{
  WriteToLog "UseInternet set to False"
  $InternetIsAvailable = $false
  WriteToLog "Internet is down"
}

Switch ($EventID)
{
  {($_ -eq $AD_MemberAddedToGlobalSecurityGroup) -or ($_ -eq $AD_MemberRemovedFromGlobalSecurityGroup) -or ($_ -eq $AD_MemberAddedToLocalSecurityGroup)  -or ($_ -eq $AD_MemberRemovedFromLocalSecurityGroup) }  
  {
    Handle_SecurityGroupWasModified
  }

  $AD_UserAccountCreation
  {
    Handle_UserAccountCreation
  }
  
  $AD_UserAccountDeletion
  {
    Handle_UserAccountDeletion
  }

  $AD_ComputerAccountCreation
  {
    WriteToLog "- ComputerAcccountDeleteion was fired"
    Handle_ComputerAccountCreation
  }
  
  $AD_ComputerAccountDeletion
  {
    WriteToLog "- ComputerAcccountDeleteion was fired"
    Handle_ComputerAccountDeletion
  }

  $AD_AnOperationWasPerformedOnAnObject
  {
    WriteToLog "- AnOperationWasPerformedOnAnObject was fired"
    Handle_AnOperationWasPerformedOnAnObject
  }

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

  
  