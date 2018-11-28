set-variable -name AD_ADirectoryServiceObjectWasModified -value 5136 -option constant

#-----------------------------------------------------#
#                                                     #
# Function: CheckInternetStatus                       #
#                                                     #
#-----------------------------------------------------#
Function CheckInternetStatus()
{
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
}

#-----------------------------------------------------#
#                                                     #
# Function: Handle_ADirectoryServiceObjectWasModifed  #
#                                                     #
#-----------------------------------------------------#
Function Handle_ADirectoryServiceObjectWasModifed()
{
  # Get DN from EventMsg #
  $DN = ParseEventMsg -EventMsg $EventMsg -Section "Object:" -Keyword "DN:"

  # Get sAMAccountName from EventMsg #
  $sAMAccountName = ParseEventMsg -EventMsg $EventMsg -Section "Subject:" -Keyword "Account Name:"

  # Get Class: in Object section from EventMsg #
  $Class = ParseEventMsg -EventMsg $EventMsg -Section "Object:" -Keyword "Class:"

  # Get Type: in Operation section from EventMsg #
  $Type = ParseEventMsg -EventMsg $EventMsg -Section "Operation:" -Keyword "Type:"
  
  # Get Value: in Attribue section from EventMsg #
  $Value = ParseEventMsg -EventMsg $EventMsg -Section "Attribute:" -Keyword "Value:"

  # Get LdapDisplayName: in Attribue section from EventMsg #
  $LdapDisplayName = ParseEventMsg -EventMsg $EventMsg -Section "Attribute:" -Keyword "LDAP Display Name:"


	# User Mobile Phone attribute was updated
  If ($Class -eq "user" -and $Type -eq "Value Added" -and $LdapDisplayName -eq "mobile" -and $Value -ne "")
  {
    # Should we throttle this event #
    If (Throttle5136Events) {Return 0}

    # Indicate we are working on the task #
    UpdateStatus -Busy

    CheckInternetStatus

    WriteToLog "ADirectoryServiceObjectWasModified was fired - User mobile number updated"
    WriteToLog "Class: $Class, Type: $Type, LDAPDisplayName: $LDAPDisplayName, sAMAccountName: $sAMAccountName, Value: $Value"

    $AllNumbers= $Value -replace "[()\s+-]", ""
    $Last4Digits = $AllNumbers.Substring($AllNumbers.Get_Length()-4)
    WriteToLog "AllNumbers: $AllNumbers, Last4Digits: $Last4Digits"

    $ADUser = Get-ADUser $DN -Properties *
    $Upn = $ADUser.UserPrincipalName

    $Username = $Ini["CentrifyCloud"]["CloudAdmin"]
    $Password = $Ini["CentrifyCloud"]["CloudAdminPassword"]
    $CloudFriendlyName = $Ini["CentrifyCloud"]["CloudFriendlyName"]
    $Uri = "https://$CloudFriendlyName.centrify.com"
    $AuthToken = GetAuthToken -Username $Username -Password $Password -Uri $Uri

    $Api = "UserMgmt/SetSecurityQuestion"
    $Request = "{'ID':'$Upn','securityquestion':'Last 4 digits of mobile phone number?','questionanswer':'$Last4Digits'}"
    $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri

    # Indicate Task is done  #
    UpdateStatus -Done
  }

	# A group policy was updated so we need to do adflush and gpupdate
  If ($Class -eq "groupPolicyContainer" -and $Type -eq "Value Added" -and $LdapDisplayName -eq "versionNumber")
  {
    # Should we throttle this event #
    If (Throttle5136Events) {Return 0}
  
    # Indicate we are working on the task #
    UpdateStatus -Busy

    CheckInternetStatus
    
    WriteToLog "ADirectoryServiceObjectWasModified was fired"
    WriteToLog "Class: $Class, Type: $Type, LDAPDisplayName: $LDAPDisplayName"

    # Run ADFlush and Adgpupdate on the collection#
    ExecuteADFlushAndAdgpupdate

    # Indicate Task is done  #
    UpdateStatus -Done
  }


	# LocalUsers or LocalGroups CN was updated via DirectControl console
	# We need to do adflush to make sure remote machines pick up this change in AD  
  If (($DN.Contains("CN=LocalUsers")) -or ($DN.Contains("CN=LocalGroups")))
  {
    If ($Class -eq "serviceConnectionPoint" -and $Type -eq "Value Added" -and (($LdapDisplayName -eq "objectClass") -or ($LdapDisplayName -eq "keywords")) )
    {
      # Should we throttle this event #
      If (Throttle5136Events) {Return 0}

      # Indicate we are working on the task #
      UpdateStatus -Busy

      CheckInternetStatus

      WriteToLog "ADirectoryServiceObjectWasModified was fired"
      WriteToLog "DN: $DN"
      WriteToLog "Class: $Class, Type: $Type, Value: $Value"

      # Run ADFlush on the collection#
      ExecuteADFlush

      # Indicate Task is done  #
      UpdateStatus -Done
    }
  }

<# 24Jun18 - Commented this out. I need to look at this more

	# LocalUsers or LocalGroups CN was updated via DirectControl console
  $TargetValue = "CN=role-" + $Ini["DirectAuthorize"]["suToRootRole"]
  If ($Value.StartsWith($TargetValue))
  {
    If ($Class -eq "msDS-AzRole" -and $Type -eq "Value Added" -and $LdapDisplayName -eq "msDS-TasksForAzRole")
    {
      # Should we throttle this event #
      If (Throttle5136Events) {Return 0}

      # Indicate we are working on the task
      UpdateStatus -Busy

      CheckInternetStatus

      WriteToLog "ADirectoryServiceObjectWasModified was fired"
      WriteToLog "Class: $Class, Type: $Type, Value: $Value, LdapDisplayName: $LdapDisplayName"

      # Run ADFlush on the collection #
      ExecuteADFlush

      # Indicate Task is done  #
      UpdateStatus -Done
    }
  }

  If ($Value.StartsWith("roletime="))
  {
    If ($Class -eq "msDS-AzAdminManager" -and $Type -eq "Value Added" -and $LdapDisplayName -eq "msDS-AzApplicationData")
    {
      # Indicate we are working on the task #
      UpdateStatus -Busy

      CheckInternetStatus

      WriteToLog "ADirectoryServiceObjectWasModified was fired"
      WriteToLog "Class: $Class, Type: $Type, Value: $Value, LdapDisplayName: $LdapDisplayName"

      # Run ADFlush and KillExpiredSessions on the collection#
      ExecuteADFlushAndKillExpiredSessions
      
      # Indicate Task is done  #
      UpdateStatus -Done
    }
  }
  #>
  
  
}

#-----------------------------------------------------#
#                                                     #
# Function: Throttle5136Events                        #
#                                                     #
#-----------------------------------------------------#
Function Throttle5136Events()
{
  $MyFilename = $absPath + "\" + $Ini["WMI"]["5136EventLastOccuredFile"]
  $MaxTimeIntervalInSeconds = $Ini["WMI"]["MaxTimeIntervalFor5136EventsInSeconds"]

  If (Test-Path $MyFilename) 
  {
    [DateTime] $LastEventOccuredAt = Get-Content $MyFilename -Raw
    Remove-Item $MyFilename
    $TargetTime = $LastEventOccuredAt.AddSeconds($MaxTimeIntervalInSeconds)

    $TimeNow = [DateTime]::Now
    $TimeNow | Out-File $MyFilename -Force

    If ($TargetTime -lt $TimeNow)
    {
      Return $False
    }
    Else
    {
      WriteToLog "5136 Event Throttled"
      Return $True
    }
  }
  Else
  {
    $TimeNow = [DateTime]::Now
    $TimeNow | Out-File $MyFilename -Force
    Return $False
  }
}
