Function GetAuthToken()
{
  param
  (
    [Parameter(Mandatory=$true)] $Username,
    [Parameter(Mandatory=$true)] $Password,
    [Parameter(Mandatory=$true)] $Uri
  )

  If ($Ini["Global"]["RestAPIDebug"] -eq "True") {WriteToLog "GetAuthToken: $Uri : $Username"} 

  $LoginJson = "{user:'$Username', password:'$Password'}"
  $LoginHeader = @{"X-CENTRIFY-NATIVE-CLIENT"="1"}
  $Login = Invoke-RestMethod -Method Post -Uri "$Uri/security/login" -Body $LoginJson -ContentType "application/json"  -Headers $LoginHeader -SessionVariable WebSession
  
  If ($Login.success -eq $true) 
  {
    If ($Ini["Global"]["RestAPIDebug"] -eq "True") {WriteToLog "GetAuthToken: Success = True"}
  } 
  Else
  {
    WriteToLog "GetAuthToken: $Uri : $Username"
    WriteToLog "GetAuthToken: Success = False"
    WriteToLog "GetAuthToken: json = $Login"
  }

  $Cookies = $WebSession.Cookies.GetCookies("$Uri/security/login")
  $ASPXAuth = $Cookies[".ASPXAUTH"].Value
  Return $ASPXAuth
}

Function DoHttpPost()
{
  param
    (
      [Parameter(Mandatory=$true)] $Auth,
      [Parameter(Mandatory=$true)] $Api,
      [Parameter(Mandatory=$true)] $Request,
      [Parameter(Mandatory=$true)] $Uri
    )

  If ($Ini["Global"]["RestAPIDebug"] -eq "True") {WriteToLog "DoHttpPost: $Uri/$Api : $Request"} 
  

  $QueryHeaders = @{"X-CENTRIFY-NATIVE-CLIENT"="1";"Authorization" = "Bearer " + $Auth}
  $Query = Invoke-RestMethod -Method Post -Uri "$Uri/$Api" -ContentType "application/json" -Body $Request -Headers $QueryHeaders

  If ($Query.Success -eq $true) 
  {
    If ($Ini["Global"]["RestAPIDebug"] -eq "True") {WriteToLog "DoHttpPost: Success = True"}
  } 
  Else
  {
    WriteToLog "DoHttpPost: $Uri/$Api : $Request" 
    WriteToLog "DoHttpPost: Success = False"
    WriteToLog "DoHttpPost: json = $Query"
  }
  
  Return $Query.Result
}
  
