<#
$Api = "RedRock/Query"

$Sql =  "SELECT Vaultaccount.ID As ID "
$Sql += "FROM   Vaultaccount, Server "
$Sql += "WHERE  Server.ID = Vaultaccount.host "
$Sql += "AND    Server.name = '$TargetServer' "
$Sql += "AND    Vaultaccount.user = '$TargetAccount' "

Write-Host "SQL = $SQL"

$Request = "{""Script"":""$Sql""}"
$Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
$Results = $Response.Results | Select-Object -ExpandProperty Row | Select ID 

foreach ($Result in $Results)
  {
    $VaultID = $Result.ID
  }
  
Write-Host "ValueID = $VaultID"
  
  
$Api = "ServerManage/CheckoutPassword"
$Request = "{""ID"":""$VaultID"",""Lifetime"":10}"
$Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
$CheckOutID = $Response.COID
$CheckedOutPassword = $Response.Password
 
Write-Host "CheckOutID = $CheckOutID"
Write-Host "CheckoutPassword = $CheckedOutPassword"


$Api = "ServerManage/CheckinPassword"
$Request = "{""ID"":""$CheckOutID""}"
$Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
  
$Api = "ServerManage/UpdateAccount"
$Request = "{""ID"":""$VaultID"",""IsManaged"":""True""}"
$Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri

$Api = "ServerManage/RotatePassword"
$Request = "{""ID"":""$VaultID"",""IsManaged"":""True""}"
$Response = DoHttpPost -Auth $AuthToken -Api $Api -Request $Request -Uri $Uri
#>
  
  
