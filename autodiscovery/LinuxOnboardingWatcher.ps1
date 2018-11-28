
#main()  

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

$PidFile = $absPath + "\" + $Ini["AutoOnboarding"]["OnboardingPIDFile"] 
"$scriptPid" | Out-File $PidFile -Force

If ($Ini["AutoOnboarding"]["OnboardingDebug"] -eq "True") {$Debug = $True} Else {$Debug = $False} 

If ($Debug) {WriteToLog "Starting"}

<# Get credentials for cloud #>
If ($Debug) {WriteToLog "Getting Auth token from cloud service"}
$Username = $Ini["CentrifyCloud"]["CloudAdmin"]
$Password = $Ini["CentrifyCloud"]["CloudAdminPassword"]
$CloudFriendlyName = $Ini["CentrifyCloud"]["CloudFriendlyName"]
$Uri = "https://$CloudFriendlyName.centrify.com"

$AuthToken = GetAuthToken -Username $Username -Password $Password -Uri $Uri

<# Get autodiscovery parameters #>
If ($Debug) {WriteToLog "Getting autodiscovery parms from .ini file"}
$SecretName = $Ini["AutoOnboarding"]["SecretName"]
$RunCommandLocalPath = $Ini["AutoOnboarding"]["RunCommandLocalPath"]
$RunCommandRemotePath = $Ini["AutoOnboarding"]["RunCommandRemotePath"]
$PscpCommand = $Ini["AutoOnboarding"]["PscpPath"]
$AuthorizedRole = $Ini["AutoOnboarding"]["AuthorizedRole"]


<# Get ID for SecretName from Cloud #>
If ($Debug) {WriteToLog "Getting secret named $SecretName from cloud service"}
$Api = "RedRock/Query"

$Sql =  "SELECT ID "
$Sql += "FROM   DataVault "
$Sql += "WHERE  SecretName = '$SecretName' "

$Request = "{""Script"":""$Sql"",""Args"":{""Caching"":-1}}"
$Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
$Results = $Response.Results | Select-Object -ExpandProperty Row | Select ID 

<# If more/less than 1 row returned, then we have a problem #>
If ($Debug) {WriteToLog "Checking number of rows returned"}
If ($Response.Count -eq 1)
  {
    $DataVaultID = $Results[0].ID  
  }
  Else
  {
    If ($Debug) {WriteToLog "Query to cloud service failed to return only 1 row."}
    If ($Debug) {WriteToLog "SQL = $Sql"}
    If ($Debug) {WriteToLog "Response = $Response"}
    If ($Debug) {WriteToLog "Exiting"}
    Remove-ItemIfExists -Path $PidFile
    Exit -1 
  }

  
<# Read the contents of the secret #>
If ($Debug) {WriteToLog "Retrieve Content of Secret"}
$Api = "ServerManage/RetrieveDataVaultItemContents"
$Request = "{""ID"":""$DataVaultID""}"
$Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
$SecretText = $Response.SecretText

<# If it blank, then we are done #>
If ($Debug) {WriteToLog "Checking number of rows retrieved"}
If ((-not $SecretText) -or ($SecretText.Trim() -eq "")) 
{ 
  If ($Debug) {WriteToLog "Secret: $SecretName is blank"}
  If ($Debug) {WriteToLog "Exiting"}
  Remove-ItemIfExists -Path $PidFile
  Exit -1 
}

<# Now that we have the value, lets blank it out in the cloud in prep for next time #>
If ($Debug) {WriteToLog "Zeroing out content of secret"}
$Api = "ServerManage/UpdateDataVaultItem"
$Request = "{""SecretText"":"""",""SecretName"":""UnixOnboarding"",""Type"":""Text"",""ID"":""$DataVaultID""}"
$Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri

<# Lets get the ID of the Role that we intend to give rights for access #>
If ($Debug) {WriteToLog "Get the RoleID of the Role we intend to give permissions"}
$Api = "RedRock/Query"

$Sql =  "SELECT ID "
$Sql += "FROM   Role "
$Sql += "WHERE  Name = '$AuthorizedRole'"

$Request = "{""Script"":""$Sql"",""Args"":{""Caching"":-1}}"
$Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
$Results = $Response.Results | Select-Object -ExpandProperty Row | Select ID 


<# If count is more/less than 1, the we have a problem #>
If ($Debug) {WriteToLog "Checking Count of rows returned"}
If ($Response.Count -eq 1)
  {
    $RoleID = $Results[0].ID  
  }
  Else
  {
    If ($Debug) {WriteToLog "Query to cloud service failed to return only 1 row."}
    If ($Debug) {WriteToLog "SQL = $Sql"}
    If ($Debug) {WriteToLog "Response = $Response"}
    If ($Debug) {WriteToLog "Exiting"}
    Remove-ItemIfExists -Path $PidFile
    Exit -1 
  }

  
<# The secret may have multiple lines#>
If ($Debug) {WriteToLog "Parse the lines of the secret text"}
$Lines = $SecretText.Split([Environment]::NewLine) 

ForEach ($line In $Lines)
{
  $line = $line.Trim()

  If ($line -ne "")
  {
    <# The format we expect is "ServerFQDN:userid:password" #>
    If ($Debug) {WriteToLog "Parse the fields of each line"}
    $Resource = $line.Split(":")
    $Server = $Resource[0]
    $Account = $Resource[1]
    $Password = $Resource[2]
    If ($Debug) {WriteToLog "$Server,$Account,$Password"}
    
    If (!(Test-Connection -computer $Server -count 1 -quiet))
    {
      If ($Debug) 
      {
        WriteToLog "Server: $Server is not online. Skipping"
        Exit 0
      }
    }
    
    <# Add the resource as a Unix/ssh system #>
    If ($Debug) {WriteToLog "Add the server: $Server to the cloud service"}
    $Api = "ServerManage/AddResource"
    $Request = "{""Name"": ""$Server"", `
                 ""FQDN"": ""$Server"", `
                 ""ComputerClass"": ""Unix"", `
                 ""SessionType"": ""Ssh""}"
    $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
    $ResourceID = $Response

    <# Make a quick SSH connection to Accept the Host key (just in case) #>
    <# Otherwise all ssh (putty, scp, etc) hang waiting on user input to accept the ssh host key #>
    If ($Debug) {WriteToLog "Add the HostKey - make quick SSH connection and exit"}
    ExecuteCommandOnRemoteHost -FailFast `
                               -AcceptHostKey `
                               -RemoteServer $Server `
                               -RemoteUserid $Account `
                               -RemotePassword $Password 

    <# build the pscp command to copy the .sh file to do the account discovery #>
    $PscpArguments = "-pw $Password " + `
                     "$RunCommandLocalPath " + `
                     $Account + "@" + $Server + ":" + $RunCommandRemotePath

    <# copy the .sh file#>
    If ($Debug) {WriteToLog "scp the file to the target servers"}
    ExecuteCommandLocallyAndWait -Path $PscpCommand `
                                 -Arguments $PscpArguments

    <# Now that we have copied the file to the target server, we need to make it executable #>
    If ($Debug) {WriteToLog "chmod +x on the file"}
    $RemoteCommand = "chmod +x $RunCommandRemotePath"
    ExecuteCommandOnRemoteHost -FailFast `
                               -RemoteServer $Server `
                               -RemoteUserid $Account `
                               -RemotePassword $Password `
                               -RemoteCommand $RemoteCommand

    <# Generate a Random String to set as the temporary password  #>
    <# Note: we rotate the password immediatly following so this password gets updated automatically  #>
    If ($Debug) {WriteToLog "create Random string"}
    $RandomString = GenerateRandomString -Length 15
    $StdOut = ExecuteCommandOnRemoteHost -FailFast `
                                         -ReturnStdOut `
                                         -RemoteServer $Server `
                                         -RemoteUserid $Account `
                                         -RemotePassword $Password `
                                         -RemoteCommand "$RunCommandRemotePath $RandomString"

                                         
    <# Get the list of users we found that had passwords  #>
    If ($Debug) {WriteToLog "parse list of users that were found in /etc/shadow"}
    $Lines = $StdOut.Split([Environment]::NewLine) 
    ForEach ($Line In $Lines)
    {
      $Line = $Line.Trim()
      If (($Line -ne "") -and ($Line.StartsWith("USERNAME=")))
      {
        <# Get the username that comes back in the format "USERNAME=abc" #>
        $Username=$Line.Split("=")[1]
        
        <# Add the account to the cloud service #>
        If ($Debug) {WriteToLog "Add user: $Username to cloud service"}
        $Api = "ServerManage/AddAccount"
        $Request = "{""Host"": ""$ResourceID"", `
                     ""User"": ""$Username"", `
                     ""Password"": ""$RandomString"", `
                     ""IsManaged"": ""True""}"
        $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
        $VaultID = $Response

        <# Give the target role the appropriate righs on the newly created system #>
        If ($Debug) {WriteToLog "Give permissions to target role"}
        $Api = "ServerManage/SetAccountPermissions"
        $Request = "{""Grants"":[{""Principal"":""$AuthorizedRole"",
                                  ""PType"":""Role"",
                                  ""Rights"":""View,Login,UserPortalLogin"",
                                  ""PrincipalId"":""$RoleID""}],
                     ""ID"":""$VaultID"",
                     ""PVID"":""$VaultID""}"
        $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri

        <# Now rotate the password and overwrite the temporary password #>
        If ($Debug) {WriteToLog "Rotate the password for $Username"}
        $Api = "ServerManage/RotatePassword"
        $Request = "{""ID"": ""$VaultID""}"
        $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
        
      }
    }      

    
    <# Remove the script that we copied over #>
    If ($Debug) {WriteToLog "Remove the autodiscovery script that we copied to the server"}
    ExecuteCommandOnRemoteHost -FailFast `
                               -RemoteServer $Server `
                               -RemoteUserid $Account `
                               -RemotePassword $Password `
                               -RemoteCommand "rm -f $RunCommandRemotePath"

    <# Now lets vault the account that we used to connect #>
    If ($Debug) {WriteToLog "Adding account: $Account to cloud service"}
    $Api = "ServerManage/AddAccount"
    $Request = "{""Host"": ""$ResourceID"", `
                 ""User"": ""$Account"", `
                 ""Password"": ""$Password"", `
                 ""IsManaged"": ""True""}"
    $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
    $RootVaultID = $Response
    
    <# Lets give the AuthorizedRole permission on this account #>
    If ($Debug) {WriteToLog "Give target Role permission for this account"}
    $Api = "ServerManage/SetAccountPermissions"
    $Request = "{""Grants"":[{""Principal"":""$AuthorizedRole"",
                              ""PType"":""Role"",
                              ""Rights"":""View,Login,UserPortalLogin"",
                              ""PrincipalId"":""$RoleID""}],
                 ""ID"":""$RootVaultID"",
                 ""PVID"":""$RootVaultID""}"
    $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri

    <# Now lets rotate the password #>
    If ($Debug) {WriteToLog "Rotate the password for account: $Account"}
    $Api = "ServerManage/RotatePassword"
    $Request = "{""ID"": ""$RootVaultID""}"
    $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
   
  }
}

If ($Debug) {WriteToLog "Exiting"}
Remove-ItemIfExists -Path $PidFile



