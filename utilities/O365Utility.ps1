Param  
(
  [string]$Action,
  [string]$O365AdminUser,
  [string]$O365AdminPassword,
  [string]$O365User,
  [string]$TimeoutInMinutes,
  [string]$DestinationFile,
  [string]$UserCreateSuccessSourceFile,
  [string]$UserCreateFailSourceFile,
  [string]$MailboxCreateSuccessSourceFile,
  [string]$MailboxCreateFailSourceFile,
  [string]$UserDeleteSuccessSourceFile,
  [string]$UserDeleteFailSourceFile,
  [string]$UsersToIgnore
)  

  
<# Get the path,name and PID to the actual script #>
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$scriptName = split-path -leaf $MyInvocation.MyCommand.Definition
$scriptPid = $Pid
Try {. $scriptPath\abspath.ps1} Catch {$absPath = $scriptPath}

. $absPath\include\Generic_SharedFunctions.ps1
. $absPath\include\Ini_SharedFunctions.ps1

$Ini = Get-IniContent "$absPath\CentrifyDemoHelper.ini"

$PidFile = "$absPath" + "\" + $Ini["O365"]["O365PidFilename"] 
"$scriptPid" | Out-File $PidFile -Force

WriteToLog "Starting"
Import-Module MSOnline

If (!$O365AdminUser) { $O365AdminUser = $Ini["O365"]["O365Admin"] }
If (!$O365AdminPassword) { $O365AdminPassword = $Ini["O365"]["O365AdminPassword"] }

If (!$TimeoutInMinutes) { $TimeoutInMinutes = $Ini["O365"]["MailboxCheckTimeout"] }
If (!$DestinationFile) { $DestinationFile = $Ini["O365"]["WorkstationTargetFile"] }
If (!$UsersToIgnore) { $UsersToIgnore = $Ini["CentrifyCloud"]["UsersToIgnore"] }

If (!$UserCreateSuccessSourceFile) { $UserCreateSuccessSourceFile = $Ini["O365"]["UserCreateSuccessSourceFile"] }
If (!$UserCreateFailSourceFile) { $UserCreateFailSourceFile = $Ini["O365"]["UserCreateFailSourceFile"] }

If (!$MailboxCreateSuccessSourceFile) { $MailboxCreateSuccessSourceFile = $Ini["O365"]["MailboxCreateSuccessSourceFile"] }
If (!$MailboxCreateFailSourceFile) { $MailboxCreateFailSourceFile = $Ini["O365"]["MailboxCreateFailSourceFile"] }

If (!$UserDeleteSuccessSourceFile) { $UserDeleteSuccessSourceFile = $Ini["O365"]["UserDeleteSuccessSourceFile"] }
If (!$UserDeleteFailSourceFile) { $UserDeleteFailSourceFile = $Ini["O365"]["UserDeleteFailSourceFile"] }



$Password = ConvertTo-SecureString $O365AdminPassword -AsPlainText -Force
$TenantCredentials = new-object -typename System.Management.Automation.PSCredential -argumentlist $O365AdminUser, $Password
$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://ps.outlook.com/powershell/ -Credential $TenantCredentials -Authentication Basic -AllowRedirection
If (-not $?)
{
  WriteToLog "Failed to connect"
  Remove-PSSession $Session
  Remove-ItemIfExists -Path $PidFile
  Copy-Item -Path $UserDeleteFailSourceFile -Destination $DestinationFile -Force
  Exit -1
}

Import-PSSession $Session -AllowClobber
WriteToLog "Connecting to O365Tenant - $O365AdminUser"
Connect-MsolService -Credential $TenantCredentials

If (-not $?)
{
  WriteToLog "Connection failed"
  Remove-PSSession $Session
  Remove-ItemIfExists -Path $PidFile
  Copy-Item -Path $UserDeleteFailSourceFile -Destination $DestinationFile -Force
  Exit -1
}
Else
{
  WriteToLog "Connected Successfully"
}

   
Switch ($Action) 
{
  "DeleteO365User" 
  {
    WriteToLog "Delete O365 User - $O365User"
    Get-MSoluser -All |? {$_.UserPrincipalName -eq $O365User} | remove-msoluser -Force | remove-msoluser -RemoveFromRecycleBin -Force

    Get-MSoluser -UserPrincipalName $O365User -ErrorAction SilentlyContinue
    Get-MSoluser -ReturnDeletedUsers | Remove-MSoluser -RemoveFromRecycleBin -Force
    $exist = [bool](Get-MSoluser -UserPrincipalName $O365User -ErrorAction SilentlyContinue)

    If ($exist)
    {
      WriteToLog "Failed to Delete O365 User $O365User"
      Copy-Item -Path $UserDeleteFailSourceFile -Destination $DestinationFile -Force
    } 
    Else
    {
      WriteToLog "O365 User $O365User was deleted (or did not exist)"
      Copy-Item -Path $UserDeleteSuccessSourceFile -Destination $DestinationFile -Force
    }
  }
  
  "DeleteAllDeletedO365Users"
  {
    WriteToLog "Deleting all Deleted O365 Users"
    Get-MSoluser -ReturnDeletedUsers | Remove-MSoluser -RemoveFromRecycleBin -Force
    WriteToLog "Done Deleting all Deleted O365 Users"
  }

  "DeleteAllO365Users" 
  {
    WriteToLog "Deleting all O365 User except $UsersToIgnore"
    WriteToLog "Not deleting any onmicrosoft.com accounts"
    $WhereClause = '$_.LastDirSyncTime -ne $Null -and '

    $MyUsersToIgnore = $UsersToIgnore.Split(",")
    For ($i=0; $i -lt $MyUsersToIgnore.Count; $i++) {$MyUsersToIgnore[$i] = '$_.UserPrincipalName -notlike "' + $MyUsersToIgnore[$i] + '*"'}
    $MyUsersToIgnore = $MyUsersToIgnore -join " -and "
    $WhereClause = $WhereClause + $MyUsersToIgnore
    $WhereClause = [scriptblock]::Create($WhereClause)

     
    WriteToLog "Deleting O365 Users:"
    $O365UsersToBeDeleted = Get-MSoluser -All | Where $WhereClause
    ForEach ($O365UserToBeDeleted in $O365UsersToBeDeleted) {WriteToLog "$O365UserToBeDeleted"}


    Get-MSoluser -All | Where $WhereClause | Remove-MSoluser -Force | Remove-MSoluser -RemoveFromRecycleBin -Force
    Get-MSoluser -ReturnDeletedUsers | Remove-MSoluser -RemoveFromRecycleBin -Force
    Copy-Item -Path $UserDeleteSuccessSourceFile -Destination $DestinationFile -Force
    WriteToLog "Done Deleting all O365 Users except $UsersToIgnore"
  }

  "CheckIfMailboxExists" 
  {
    WriteToLog "Checking status of O365 User $O365User"
  
    $timeout = new-timespan -Minutes $TimeoutInMinutes
    $sw = [diagnostics.stopwatch]::StartNew()
    While ($sw.elapsed -lt $timeout)
    {
      $UserExists = [bool](Get-MSoluser -UserPrincipalName $O365User -ErrorAction SilentlyContinue)
      WriteToLog "User $O365User exists: $UserExists"

      if ($UserExists)
      {
        WriteToLog "Found User: $O365User"
        Copy-Item -Path $UserCreateSuccessSourceFile -Destination $DestinationFile -Force
        break
      }
   
      start-sleep -seconds 10
    }
     
    If (!$UserExists)
    {
      Copy-Item -Path $UserCreateFailSourceFile -Destination $DestinationFile -Force
      WriteToLog "Timed out waiting for User"
    }
    
    If ($UserExists)
    {
      $timeout = new-timespan -Minutes $TimeoutInMinutes
      $sw = [diagnostics.stopwatch]::StartNew()
      While ($sw.elapsed -lt $timeout)
      {
        $MailboxExists = [bool](Get-mailbox -Identity $O365User -erroraction SilentlyContinue)
        WriteToLog "Mailbox for User $O365User exists: $MailboxExists"

        if ($MailboxExists)
        {
          WriteToLog "Found mailbox belonging to $O365User"
          Set-MailboxRegionalConfiguration -Identity $O365User -Language "en-US" -TimeZone "Pacific Standard Time" -DateFormat "M/d/yyyy"
          Copy-Item -Path $MailboxCreateSuccessSourceFile -Destination $DestinationFile -Force
          break
        }

        start-sleep -seconds 10
      }
 
      if (!$MailboxExists)
      {
        Copy-Item -Path $MailboxCreateFailSourceFile -Destination $DestinationFile -Force
        WriteToLog "Timed out waiting for mailbox"
      }
    }
  }

  default 
    {
      WriteToLog "Invalid Action Specified $Action"
    }
}  
  
WriteToLog "Execution Complete"
Remove-PSSession $Session
Remove-ItemIfExists -Path $PidFile
    

  
  
  
  



