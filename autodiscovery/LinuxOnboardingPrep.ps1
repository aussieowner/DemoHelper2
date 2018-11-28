
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

WriteToLog "Starting"

$Username = $Ini["CentrifyCloud"]["CloudAdmin"]
$Password = $Ini["CentrifyCloud"]["CloudAdminPassword"]
$CloudFriendlyName = $Ini["CentrifyCloud"]["CloudFriendlyName"]
$Uri = "https://$CloudFriendlyName.centrify.com"

$AuthToken = GetAuthToken -Username $Username -Password $Password -Uri $Uri


$SecretName = $Ini["AutoOnboarding"]["SecretName"]
$TargetServerName = $Ini["AutoOnboarding"]["TargetServerName"]
$TargetAccountName = $Ini["AutoOnboarding"]["TargetAccountName"]
$TargetAccountInitialPassword = $Ini["AutoOnboarding"]["TargetAccountInitialPassword"]

$Api = "RedRock/Query"

$Sql =  "SELECT ID "
$Sql += "FROM   DataVault "
$Sql += "WHERE  SecretName = '$SecretName' "

$Request = "{""Script"":""$Sql"",""Args"":{""Caching"":-1}}"
$Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
$Results = $Response.Results | Select-Object -ExpandProperty Row | Select ID 

foreach ($Result in $Results)
  {
    $DataVaultID = $Result.ID
  }
  
$Api = "ServerManage/RetrieveDataVaultItemContents"
$Request = "{""ID"":""$DataVaultID""}"
$Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
$SecretText = $Response.SecretText

If ((-not $SecretText) -or ($SecretText.Trim() -eq "")) 
{ 
  $Api = "ServerManage/UpdateDataVaultItem"
  $Request = "{'SecretText' : '" + $TargetServerName + ":" + $TargetAccountName + ":" + $TargetAccountInitialPassword + "','SecretName' : 'UnixOnboarding', 'Type' : 'Text' , 'ID' : '$DataVaultID'}"
  $Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
}


WriteToLog "Done"


