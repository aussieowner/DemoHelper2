
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

$PidFile = $absPath + "\" + $Ini["AutoOnboarding"]["OnboardingResetPIDFile"] 
"$scriptPid" | Out-File $PidFile -Force

If ($Ini["AutoOnboarding"]["OnboardingResetDebug"] -eq "True") {$Debug = $True} Else {$Debug = $False} 

If ($Debug) {WriteToLog "Starting"}

<# Get credentials for cloud #>
$Username = $Ini["CentrifyCloud"]["CloudAdmin"]
$Password = $Ini["CentrifyCloud"]["CloudAdminPassword"]
$CloudFriendlyName = $Ini["CentrifyCloud"]["CloudFriendlyName"]
$Uri = "https://$CloudFriendlyName.centrify.com"

$AuthToken = GetAuthToken -Username $Username -Password $Password -Uri $Uri

<# Get autodiscovery parameters #>
If ($Debug) {WriteToLog "Getting autodiscovery parms from .ini file"}
$TargetServerName = $Ini["AutoOnboarding"]["TargetServerName"]
$TargetAccountName = $Ini["AutoOnboarding"]["TargetAccountName"]
$TargetAccountInitialPassword = $Ini["AutoOnboarding"]["TargetAccountInitialPassword"]

<# Get credentials for cloud #>
If ($Debug) {WriteToLog "Get VaultID and ServerID"}
$Api = "RedRock/Query"

$Sql =  "SELECT Vaultaccount.ID As ID, Server.ID as ServerID, Server.Name as ServerName "
$Sql += "FROM   Vaultaccount, Server "
$Sql += "WHERE  Server.ID = Vaultaccount.host "
$Sql += "AND    Server.name = '$TargetServerName' "
$Sql += "AND    Vaultaccount.user = '$TargetAccountName'"


$Request = "{""Script"":""$Sql"",""Args"":{""Caching"":-1}}"

$Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
$Results = $Response.Results | Select-Object -ExpandProperty Row | Select ID, ServerID, ServerName 


<# If more/less than 1 row returned, then we have a problem #>
If ($Debug) {WriteToLog "Checking number of rows returned"}
If ($Response.Count -eq 1)
  {
    $RootVaultID = $Results.ID
    $ServerID = $Results.ServerID
    $ServerName = $Results.ServerName
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

  
<# Checkout the password #>
If ($Debug) {WriteToLog "Checking out the password"}
$Api = "ServerManage/CheckoutPassword"
$Request = "{""ID"":""$RootVaultID"",""Lifetime"":10}"
$Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
$CheckOutID = $Response.COID
$CheckedOutPassword = $Response.Password
 
<# Logging in to the server and changing password back to default #>
If ($Debug) {WriteToLog "Logging in to the server and changing the password back to default"}
$RemoteCommand = "echo " + '"' + $TargetAccountName + ":" + $TargetAccountInitialPassword + '"' + " | chpasswd"
If ($Debug) {WriteToLog "RemoteCommand = $RemoteCommand"}
ExecuteCommandOnRemoteHost -FailFast `
                           -RemoteServer $ServerName `
                           -RemoteUserid "root" `
                           -RemotePassword $CheckedoutPassword `
                           -RemoteCommand $RemoteCommand

<# Delete the TargetAccount account on the cloud service #>
If ($Debug) {WriteToLog "Delete the target account on the cloud service"}
$Api = "ServerManage/DeleteAccount"
$Request = "{""ID"":""$RootVaultID""}"
$Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri


<# Get a list of other account other than targetAccount for the server #>
If ($Debug) {WriteToLog "Get a list of other account for the server"}
$Api = "RedRock/Query"

$Sql =  "SELECT Vaultaccount.ID As ID "
$Sql += "FROM   Vaultaccount, Server "
$Sql += "WHERE  Server.ID = Vaultaccount.host "
$Sql += "AND    Server.name = '$TargetServerName' "
$Sql += "AND    Vaultaccount.user != '$TargetAccountName'"

$Request = "{""Script"":""$Sql"",""Args"":{""Caching"":-1}}"
$Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
$Results = $Response.Results | Select-Object -ExpandProperty Row | Select ID 

foreach ($Result in $Results)
  {
    $VaultID = $Result.ID
    
    $Api = "ServerManage/DeleteAccount"
    $Request = "{""ID"":""$VaultID""}"
    $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
  }
  

<# Remove the server from the cloud service #>
If ($Debug) {WriteToLog "Remove the server from the cloud service"}
$Api = "ServerManage/DeleteResource"
$Request = "{""ID"":""$ServerID""}"
$Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
  
  
If ($Debug) {WriteToLog "Exiting"}
Remove-ItemIfExists -Path $PidFile
  