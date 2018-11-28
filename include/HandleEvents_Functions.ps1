set-variable -name AD_UserAccountCreation -value 4720 -option constant
set-variable -name AD_UserAccountDeletion -value 4726 -option constant

set-variable -name AD_ComputerAccountCreation -value 4741 -option constant
set-variable -name AD_ComputerAccountDeletion -value 4743 -option constant

set-variable -name AD_MemberAddedToGlobalSecurityGroup -value 4728 -option constant
set-variable -name AD_MemberRemovedFromGlobalSecurityGroup -value 4729 -option constant

set-variable -name AD_MemberAddedToLocalSecurityGroup -value 4732 -option constant
set-variable -name AD_MemberRemovedFromLocalSecurityGroup -value 4733 -option constant

set-variable -name AD_AnOperationWasPerformedOnAnObject -value 4662 -option constant

<#--------------------------------------------#>
<#                                            #>
<# Function: MemberRemovedFromSmartcardGroup  #>
<#                                            #>
<#--------------------------------------------#>
Function MemberRemovedFromSmartcardGroup()
{
  param
    (
      [Parameter(Mandatory=$false)] [string] $SamAccountName,
      [Parameter(Mandatory=$false)] [string] $Upn,
      [Parameter(Mandatory=$false)] [string] $UserFullName,
      [Parameter(Mandatory=$false)] [string] $GroupName
    )

  If ($InternetIsAvailable)
  {
    $Username = $Ini["CentrifyCloud"]["CloudAdmin"]
    $Password = $Ini["CentrifyCloud"]["CloudAdminPassword"]
    $CloudFriendlyName = $Ini["CentrifyCloud"]["CloudFriendlyName"]
    $Uri = "https://$CloudFriendlyName.centrify.com"

    $AuthToken = GetAuthToken -Username $Username -Password $Password -Uri $Uri

    $Api = "RedRock/Query"
    $Request = "{""Script"":""SELECT UUID FROM OathToken WHERE AccountName = '$UserFullName'""}"
    $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
    $Results = $Response.Results | Select-Object -ExpandProperty Row | Select UUID 

    foreach ($Result in $Results)
      {
        $UUID = $Result.UUID
      }
      
    $Api = "Oath/DeleteProfiles"
    $Request = "{""Uuids"":[""$UUID""]}"
    $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
  }
    
  <# Revoke the certificates that may have been issued for this user #>
  $ShortDomainName = (Get-ADDomain -Current LocalComputer).NetBIOSName
  $ADUser = $ShortDomainName + "\" + $SamAccountName    
  $CertificateTemplate = $Ini["PKI"]["CertificateTemplate"]

  WriteToLog "Revoking Existing Certificates on CA for Requester: $ADUser, CertificateTemplate: $CertificateTemplate"
  $certs = Get-CertificationAuthority | Get-IssuedRequest -Filter "Request.RequesterName -eq $ADUser", "CertificateTemplate -eq $CertificateTemplate" | ft | out-string
  ForEach ($cert in $certs) {WriteToLog "$cert"}
  Get-CertificationAuthority | Get-IssuedRequest -Filter "Request.RequesterName -eq $ADUser", "CertificateTemplate -eq $CertificateTemplate" | Revoke-Certificate -Reason "CeaseOfOperation"
  
  <# Update Smartcard Status file #>
  Remove-ItemIfExists -Path $Ini["PKI"]["TargetFilename-Smartcard"]
  
}

<#--------------------------------------------#>
<#                                            #>
<# Function: MemberAddedToSmartcardGroup      #>
<#                                            #>
<#--------------------------------------------#>
Function MemberAddedToSmartcardGroup()
{
  param
    (
      [Parameter(Mandatory=$false)] [string] $SamAccountName,
      [Parameter(Mandatory=$false)] [string] $Upn,
      [Parameter(Mandatory=$false)] [string] $UserFullName,
      [Parameter(Mandatory=$false)] [string] $GroupName
    )

  Remove-ItemIfExists -Path $Ini["PKI"]["TargetFilename-Smartcard"]
  $HMAC = Generate-RandomStringHex -Length 20 

  If ($InternetIsAvailable)
  {
    $Username = $Ini["CentrifyCloud"]["CloudAdmin"]
    $Password = $Ini["CentrifyCloud"]["CloudAdminPassword"]
    $CloudFriendlyName = $Ini["CentrifyCloud"]["CloudFriendlyName"]
    $Uri = "https://$CloudFriendlyName.centrify.com"

    $AuthToken = GetAuthToken -Username $Username -Password $Password -Uri $Uri

    $Api = "Oath/addorupdateprofile"
    $Request = ""
    $Request = $Request + "{""UserPrincipalName"":""" + $Upn + ""","
    $Request = $Request + " ""AccountName"":""" + $UserFullName + ""","
    $Request = $Request + " ""SecretKey"":""" + $HMAC + ""","
    $Request = $Request + " ""Issuer"":""" + $Ini["CentrifyCloud"]["DomainName"] + """," 
    $Request = $Request + " ""Algorithm"":""Sha1""," 
    $Request = $Request + " ""Digits"":""6""," 
    $Request = $Request + " ""Type"":""Hotp""," 
    $Request = $Request + " ""Period"":""30""," 
    $Request = $Request + " ""Counter"":""0"""
    $Request = $Request + "}"
    $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
  }
    
  $CertificateTemplate = $Ini["PKI"]["CertificateTemplate"]
  $ShortDomainName = (Get-ADDomain -Current LocalComputer).NetBIOSName
  $PIN = $Ini["PKI"]["PIN"]

  $Success = Enroll-NewYubikey  -ADUser "$ShortDomainName\$SamAccountName" `
                                -PIN  $PIN `
                                -HMAC $HMAC `
                                -CertificateTemplate $CertificateTemplate

  <# Copy the Smarcard status file #>
  If ($Success)
  {
    Copy-ItemIfExists -SourcePath $Ini["PKI"]["SourceFilename-Smartcard"] -DestinationPath $Ini["PKI"]["TargetFilename-Smartcard"]
  }
}

<#--------------------------------------------#>
<#                                            #>
<# Function: MemberAddedToO365Group           #>
<#                                            #>
<#--------------------------------------------#>
Function MemberAddedToO365Group()
{
  param
    (
      [Parameter(Mandatory=$false)] [string] $SamAccountName,
      [Parameter(Mandatory=$false)] [string] $Upn,
      [Parameter(Mandatory=$false)] [string] $UserFullName,
      [Parameter(Mandatory=$false)] [string] $GroupName
    )

<# Log on to Centrify Cloud Service  #>
  $Username = $Ini["CentrifyCloud"]["CloudAdmin"]
  $Password = $Ini["CentrifyCloud"]["CloudAdminPassword"]
  $CloudFriendlyName = $Ini["CentrifyCloud"]["CloudFriendlyName"]
  $Uri = "https://$CloudFriendlyName.centrify.com"

  $AuthToken = GetAuthToken -Username $Username -Password $Password -Uri $Uri

<# Get UUID for new user  #>
  $Api = "RedRock/Query"
  $Request = "{""Script"":""SELECT InternalName as 'ID' FROM DsUsers WHERE SystemName LIKE '" + $SamAccountName + "%'"",""Args"":{""Caching"":""-1""}}"
  $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
  $Results = $Response.Results | Select-Object -ExpandProperty Row | Select ID 

  ForEach ($Result IN $Results)
  {
    $UserID = $Result.ID
  }

  If (($UserID) -and ($UserID -ne "")) 
  {
    WriteToLog "UserID = $UserID"
  }
  Else
  {
    WriteToLog "Could not retrieve UUID from cloud for SamAccountName=$SamAccountName. Check that CloudConnector is functioning."
    Copy-ItemIfExists -SourcePath $Ini["O365"]["CloudPostFailSourceFile"] -DestinationPath $Ini["O365"]["WorkstationTargetFile"]
    Return -1
  }

<# Get UUID for O365RoleName  #>
  $O365RoleName = $Ini["CentrifyCloud"]["O365RoleName"]
  $Api = "RedRock/Query"
  $Request = "{""Script"":""SELECT ID FROM Role WHERE name = '$O365RoleName'""}"
  $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
  $Results = $Response.Results | Select-Object -ExpandProperty Row | Select ID 

  foreach ($Result in $Results)
  {
    $O365RoleID = $Result.ID
    WriteToLog "O365RoleID = $O365RoleID"
  }

<# Add new user to O365Role  #>
  $Api = "saasManage/AddUsersAndGroupsToRole"
  $Request = "{""Users"":[""$UserID""],""Groups"":[],""Roles"":[],""Name"":""$O365RoleID""}"
  $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
  
  $Api = "Provisioning/SyncUser"
  $Request = "{""ID"":""$UserID""}"
  $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri

<# Indicate we are done with Post to Centrify Cloud Service  #>
  Copy-ItemIfExists -SourcePath $Ini["O365"]["CloudPostSuccessSourceFile"] -DestinationPath $Ini["O365"]["WorkstationTargetFile"]

<# If O365Utility program is already running, kill it  #>
  $PidFile = $absPath + "\" + $Ini["O365"]["O365PidFilename"] 
  If (Test-Path $PidFile) 
  {
    $UtilityScriptPid = Get-Content $PidFile
    WriteToLog "O365UtilityScript is running. Killing Process: $UtilityScriptPid"
    Stop-Process -id $UtilityScriptPid
    Remove-ItemIfExists -Path $PidFile        
  }

<# Start the O365Utility to Wait for O365 user/mailbox creation  #>
  $ArgumentList = "$absPath\" + $Ini["O365"]["O365UtilityScriptFilename"] + " -Action CheckIfMailboxExists " +
                                                                               " -O365User " + $SamAccountName + "@" + $Ini["CentrifyCloud"]["DomainName"]  

  $p = Start-Process -FilePath "powershell" -WindowStyle Minimized -ArgumentList $ArgumentList

}    

<#--------------------------------------------#>
<#                                            #>
<# Function: MemberRemovedFromO365Group       #>
<#                                            #>
<#--------------------------------------------#>
Function MemberRemovedFromO365Group()
{
  param
    (
      [Parameter(Mandatory=$false)] [string] $SamAccountName,
      [Parameter(Mandatory=$false)] [string] $Upn,
      [Parameter(Mandatory=$false)] [string] $UserFullName,
      [Parameter(Mandatory=$false)] [string] $GroupName
    )


  Remove-ItemIfExists -Path $Ini["O365"]["WorkstationTargetFile"]

  <# Log on to Centrify Cloud Service  #>
  $Username = $Ini["CentrifyCloud"]["CloudAdmin"]
  $Password = $Ini["CentrifyCloud"]["CloudAdminPassword"]
  $CloudFriendlyName = $Ini["CentrifyCloud"]["CloudFriendlyName"]
  $Uri = "https://$CloudFriendlyName.centrify.com"

  $AuthToken = GetAuthToken -Username $Username -Password $Password -Uri $Uri

  <# Get UUID for O365RoleName  #>
  $O365RoleName = $Ini["CentrifyCloud"]["O365RoleName"]
  $Api = "RedRock/Query"
  $Request = "{""Script"":""SELECT ID FROM Role WHERE name = '$O365RoleName'""}"
  $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
  $Results = $Response.Results | Select-Object -ExpandProperty Row | Select ID 

  foreach ($Result in $Results)
  {
    $O365RoleID = $Result.ID
  }
    
  <# Get UUID for the user  #>
  $SQL = "SELECT ID, Username FROM User WHERE Username = '" + $SamAccountName + "@" + $Ini["CentrifyCloud"]["DomainName"] + "'"
  $Api = "RedRock/Query"
  $Request = "{""Script"":""$SQL"", ""Args"": {""Caching"":""-1""}}"
  $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
  $Results = $Response.Results | Select-Object -ExpandProperty Row | Select ID, Username

  ForEach ($Result in $Results)
  {
    $ID = $Result.ID

    $Api = "saasManage/RemoveUsersAndGroupsFromRole"
    $Request = "{""Users"":[""$ID""],""Name"":""$O365RoleID""}"
    $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri

    $Api = "/UserMgmt/RemoveUsers"
    $Request = "{""Users"":[""$ID""]}"
    $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
  }

<# If O365Utility program is already running, kill it  #>
  $PidFile = $absPath + "\" + $Ini["O365"]["O365PidFilename"] 
  If (Test-Path $PidFile) 
  {
    $UtilityScriptPid = Get-Content $PidFile
    WriteToLog "O365UtilityScript is running. Killing Process: $UtilityScriptPid"
    Stop-Process -id $UtilityScriptPid
    Remove-ItemIfExists -Path $PidFile        
  }
  Else
  {
    WriteToLog "O365Utility - Pid file: $PidFile was not found"
  }
    
<# Start the O365Utility to Wait for O365 user/mailbox creation  #>
  $ArgumentList = "$absPath\" + $Ini["O365"]["O365UtilityScriptFilename"] + " -Action DeleteO365User " +
                                                                               " -O365User " + $SamAccountName + "@" + $Ini["CentrifyCloud"]["DomainName"]  

  $p = Start-Process -FilePath "powershell" -WindowStyle Minimized -ArgumentList $ArgumentList
}

<#--------------------------------------------#>
<#                                            #>
<# Function: DirectSecureGroupWasModifed      #>
<#                                            #>
<#--------------------------------------------#>
Function DirectSecureGroupWasModifed()
{
  param
    (
      [Parameter(Mandatory=$false)] [string] $SamAccountName,
      [Parameter(Mandatory=$false)] [string] $Upn,
      [Parameter(Mandatory=$false)] [string] $UserFullName,
      [Parameter(Mandatory=$false)] [string] $GroupName
    )
    
  <# Execute adflush and rm home dir on list of Unix Servers #>
  $Servers = $Ini["Global"]["UnixServers"]
  $RunAsUser = $Ini["Global"]["RunAsUser"]
  $ADFlushCommand = $Ini["Putty"]["*nix_adflush"]
  $ADGpupdateCommand = $Ini["Putty"]["*nix_adgpupdate"]
  
  ForEach ($Server In $Servers.Split(","))
  {
    ExecuteCommandOnRemoteHost -RemoteServer $Server -RemoteCommand $ADFlushCommand -RemoteUserid $RunAsUser -UseKerberos
    ExecuteCommandOnRemoteHost -RemoteServer $Server -RemoteCommand $ADGpupdateCommand -RemoteUserid $RunAsUser -UseKerberos
  }
}

<#--------------------------------------------#>
<#                                            #>
<# Function: OtherGroupWasModifed             #>
<#                                            #>
<#--------------------------------------------#>
Function OtherGroupWasModifed()
{
  param
    (
      [Parameter(Mandatory=$false)] [string] $SamAccountName,
      [Parameter(Mandatory=$false)] [string] $Upn,
      [Parameter(Mandatory=$false)] [string] $UserFullName,
      [Parameter(Mandatory=$false)] [string] $GroupName
    )

  <# Run ZPA to sync with Centrify Zone  #>
  $Path = $Ini["ZoneProvisioningAgent"]["Path"]
  $Arguments = $Ini["ZoneProvisioningAgent"]["Arguments"]
  ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments

  ExecuteADFlushAndAdgpupdate
}    


<#--------------------------------------------#>
<#                                            #>
<# Function: Handle_SecurityGroupWasModified  #>
<#                                            #>
<#--------------------------------------------#>
Function Handle_SecurityGroupWasModified()
{
  WriteToLog "Group Modification was fired, EventID = $EventID"
  
  UpdateStatus -Busy

  <# Parse the GroupName from the EventMsg #>
  $GroupName = ParseEventMsg -EventMsg $EventMsg -Section "Group:" -Keyword "Group Name:"

  <# Parse DN from EventMsg, then get SamAccount and name from ADUser  #>
  $DN = ParseEventMsg -EventMsg $EventMsg -Section "Member:" -Keyword "Account Name:"
  $ADUser = Get-ADUser $DN -Properties *

  $SamAccountName = $ADUser.SamAccountName
  $Upn = $ADUser.UserPrincipalName
  $UserFullName = $ADUser.GivenName + " " + $ADUser.Surname
  
  WriteToLog "GroupName = $GroupName"
  WriteToLog "UPN = $Upn"
  WriteToLog "FullName = $UserFullName"
  WriteToLog "SamAccountName = $SamAccountName"


  Switch ($GroupName)
  {
    <# ********************************************** #>
    <# GroupName is SmartCard group                   #>
    <# Action is Remove from an AD Group              #>
    <# ********************************************** #>
    {(($_ -eq $Ini["PKI"]["TargetADGroup"]) -and (($EventID -eq $AD_MemberRemovedFromGlobalSecurityGroup) -or ($EventID -eq $AD_MemberRemovedFromLocalSecurityGroup)))}
    {
      If ($Ini["PKI"]["DoSmartcardEnrollment"] -ne "True")
      {
        Return 0
      }

      MemberRemovedFromSmartcardGroup -SamAccountName $SamAccountName -Upn $Upn -UserFullName $UserFullName -GroupName $GroupName
    }  

    <# ********************************************** #>
    <# GroupName is Smartcard group                   #>
    <# Action is Remove from an AD Group              #>
    <# ********************************************** #>
    {(($_ -eq $Ini["PKI"]["TargetADGroup"]) -and (($EventID -eq $AD_MemberAddedToGlobalSecurityGroup) -or ($EventID -eq $AD_MemberAddedToLocalSecurityGroup)))}
    {
      If ($Ini["PKI"]["DoSmartcardEnrollment"] -ne "True")
      {
        Return 0
      }

      MemberAddedToSmartcardGroup -SamAccountName $SamAccountName -Upn $Upn -UserFullName $UserFullName -GroupName $GroupName
    }
    
    <# ********************************************** #>
    <# If GroupName is O365 group, then take action   #>
    <# Action is Remove from an AD Group              #>
    <# ********************************************** #>
    {(($_ -eq $Ini["O365"]["GroupName"]) -and (($EventID -eq $AD_MemberRemovedFromGlobalSecurityGroup) -or ($EventID -eq $AD_MemberRemovedFromLocalSecurityGroup)))}
    {
      If ($Ini["O365"]["ProvisionO365"] -ne "True")
      {
        Return 0
      }

      If (! $InternetIsAvailable)
      {
        WriteToLog "Internet is not available. Skipping O365 Provisioning"
        Return 0
      }
      
      MemberRemovedFromO365Group -SamAccountName $SamAccountName -Upn $Upn -UserFullName $UserFullName -GroupName $GroupName
    }
    
    <# ********************************************** #>
    <# GroupName is O365 group, then take action      #>
    <# Action is Add from an AD Group                 #>
    <# ********************************************** #>
    {(($_ -eq $Ini["O365"]["GroupName"]) -and (($EventID -eq $AD_MemberAddedToGlobalSecurityGroup) -or ($EventID -eq $AD_MemberAddedToLocalSecurityGroup)))}
    {
      If ($Ini["O365"]["ProvisionO365"] -ne "True")
      {
        Return 0
      }

      If (! $InternetIsAvailable)
      {
        WriteToLog "Internet is not available. Skipping O365 Provisioning"
        Return 0
      }
      
      MemberAddedToO365Group -SamAccountName $SamAccountName -Upn $Upn -UserFullName $UserFullName -GroupName $GroupName
    }

    <# ************************************************* #>
    <# GroupName is DirectSecure group, then take action #>
    <# Action is Add/Remove from an AD Group             #>
    <# ************************************************* #>
    $Ini["DirectSecure"]["GroupName"]
    {
      DirectSecureGroupWasModifed -SamAccountName $SamAccountName -Upn $Upn -UserFullName $UserFullName -GroupName $GroupName
    }

    
    <# ************************************************* #>
    <# GroupName is Other, then take action              #>
    <# Action is Add/Remove from an AD Group             #>
    <# ************************************************* #>
    default 
    {
      OtherGroupWasModifed -SamAccountName $SamAccountName -Upn $Upn -UserFullName $UserFullName -GroupName $GroupName
    }

  }
  
    <#
     ******************************************************************************
     ******************************************************************************
      Skipping the Oracle, and CPS stuff for now. Maybe add it later
     ******************************************************************************
     ******************************************************************************
    #>
  
  UpdateStatus -Done

}

<#-----------------------------------------------------#>
<#                                                     #>
<# Function: Handle_AnOperationWasPerformedOnAnObject  #>
<#                                                     #>
<#-----------------------------------------------------#>
Function Handle_AnOperationWasPerformedOnAnObject()
{

}

<#-----------------------------------------------------#>
<#                                                     #>
<# Function: Handle_ComputerAccountCreation            #>
<#                                                     #>
<#-----------------------------------------------------#>
Function Handle_ComputerAccountCreation()
{

}

<#-----------------------------------------------------#>
<#                                                     #>
<# Function: Handle_ComputerAccountDeletion            #>
<#                                                     #>
<#-----------------------------------------------------#>
Function Handle_ComputerAccountDeletion()
{
  WriteToLog "EventID = $EventID, Computer Account Creation"
  Return 0   

  <# Are we suppose to do new computer discovery? #>
  If ($Ini["NewComputerDiscovery"]["DoNewComputerDiscovery"] -ne "True")
  {
    Return 0
  }

  <# Get SamAccount from EventMsg #>
  $ComputerName = ParseEventMsg -EventMsg $EventMsg -Section "New Computer Account" -Keyword "Account Name:"
  $ComputerName = $ComputerName -Replace "\$",""

  <# Does new computer name match Target name? #>
  $TargetComputerName = $Ini["NewComputerDiscovery"]["TargetComputerName"]
  If ($ComputerName.ToLower() -ne $TargetComputerName.ToLower())
  {
    Return 0
  }
  
  UpdateStatus -Busy

  WriteToLog "Computer: $ComputerName created"

  <# Create centrify.repo file on new computer  #>
  $SourceFile = $Ini["NewComputerDiscovery"]["RepoConfigFileSource"]
  $TargetFile = $Ini["NewComputerDiscovery"]["RepoConfigFileTarget"]
  $RepoKey = $Ini["NewComputerDiscovery"]["RepoKey"]
  $RepoKeyReplacementString = $Ini["NewComputerDiscovery"]["RepoKeyReplacementString"]
  $LoginAccount = $Ini["NewComputerDiscovery"]["LoginAccount"]
  $LoginPassword = $Ini["NewComputerDiscovery"]["LoginPassword"]

  WriteToLog "SourceFile = $SourceFile"
  WriteToLog "TargetFile = $TargetFile"
  WriteToLog "RepoKey = $RepoKey"
  WriteToLog "RepoKeyReplacementString = $RepoKeyReplacementString"
  WriteToLog "LoginAccount = $LoginAccount"
  WriteToLog "SourceFile = $SourceFile"
  
  $Command = "> $TargetFile"
  ExecuteCommandOnRemoteHost -FailFast -RemoteServer $TargetComputerName -RemoteCommand $Command -RemoteUserid $LoginAccount -RemotePassword $LoginPassword
  
  $Lines =Get-Content $SourceFile
  ForEach ($Line In $Lines)
  {
    $Line -Replace $RepoKeyReplacementString,$RepoKey
    $Command = "echo $Line > $TargetFile"
    ExecuteCommandOnRemoteHost -FailFast -RemoteServer $TargetComputerName -RemoteCommand $Command -RemoteUserid $LoginAccount -RemotePassword $LoginPassword
  }
  
  <# Indicate taht we are done working on task #>
  UpdateStatus -Done
}

<#-----------------------------------------------------#>
<#                                                     #>
<# Function: Handle_UserAccountCreation                #>
<#                                                     #>
<#-----------------------------------------------------#>
Function Handle_UserAccountCreation()
{
  WriteToLog "EventID = $EventID, User Account Creation/Deletion"
  
  <# Indicate we are working on the task #>
  UpdateStatus -Busy

  <# Get SamAccount from EventMsg #>
  $SamAccountName = ParseEventMsg -EventMsg $EventMsg -Section "New Account" -Keyword "Account Name"
  WriteToLog "User: $SamAccountName created"

  <# Set the Email address and UPN to new values  #>
  $ADUser = Get-ADUser $SamAccountName -Properties *
  $Upn = $ADUser.UserPrincipalName
  $NewUPN = $Upn.Split("@")[0] + "@" + $Ini["CentrifyCloud"]["DomainName"]
  $NewEmail = $ADUser.GivenName + "." + $ADUser.Surname + "@" + $Ini["CentrifyCloud"]["DomainName"]
  $ADUser | Set-ADUser -EmailAddress $NewEmail
  $ADUser | Set-ADUser -UserPrincipalName $NewUPN
  $Upn = $NewUPN
  $UserFullName = $ADUser.GivenName + " " + $ADUser.Surname
    
  <# Is Group AutoAdd turned on for O365 Group group #>
  If ($Ini["O365"]["AutomaticallyAddNewUserToGroup"] -eq "True") 
    {
      <# Automatically add user to O365 group #>
      WriteToLog "Automatically adding user to group: $GroupName"
      MemberAddedToO365Group -SamAccountName $SamAccountName -Upn $Upn -UserFullName $UserFullName -GroupName ($Ini["O365"]["GroupName"])
    }

  <# Is Group AutoAdd turned on for Smartcard group #>
  If ($Ini["PKI"]["AutomaticallyAddNewUserToGroup"] -eq "True") 
  {
    <# Automatically add user to Smartcard group #>
    MemberAddedToSmartcardGroup -SamAccountName $SamAccountName -GroupName ($Ini["O365"]["TargetADGroup"])
    WriteToLog "Automatically adding user to group: $GroupName"
  }
  
  ExecuteADFlushAndRmHome

  <# Indicate taht we are done working on task #>
  UpdateStatus -Done
}
    
<#-----------------------------------------------------#>
<#                                                     #>
<# Function: Handle_UserAccountDeletion                #>
<#                                                     #>
<#-----------------------------------------------------#>
Function Handle_UserAccountDeletion()
{
  WriteToLog "EventID = $EventID, User Account Deletion"
  
  <# Indicate we are working on the task #>
  UpdateStatus -Busy

  <# Get the SamAccountName #>
  $SamAccountName = ParseEventMsg -EventMsg $EventMsg -Section "Target Account" -Keyword "Account Name"
  WriteToLog "User: $SamAccountName deleted"

  <# Is Group AutoRemove turned on for O365 group #>
  If ($Ini["O365"]["AutomaticallyRemoveUserFromGroup"] -eq "True") 
  {
    <# Automatically delete user from O365 group #>
    WriteToLog "Automatically removing user from O365"
    MemberRemovedFromO365Group -SamAccountName $SamAccountName -GroupName ($Ini["O365"]["GroupName"])
  }

  ExecuteADFlushAndRmHome
  <# Remove the Smartcard status indicator file #>
  Remove-ItemIfExists -Path $Ini["PKI"]["TargetFilename-Smartcard"]
  <# Indicate that we are done working on task #>
  UpdateStatus -Done
  
}
    
