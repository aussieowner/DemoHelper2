param
  (
    [Parameter(Mandatory=$true)]  [string] $User,
    [Parameter(Mandatory=$true)]  [string] $Server,
    [Parameter(Mandatory=$true)]  [string] $Role,
    [Parameter(Mandatory=$false)] [string] $EndAt,
    [Parameter(Mandatory=$false)] [string] $EndInMinutes
  )


$CdmManagedComputer = Get-CdmManagedComputer -Name $Server
$CdmRole = Get-CdmRole -Zone $CdmManagedComputer.Zone -Name $Role
$ADUser = Get-ADUser $User

If ($EndAt)
{
  $EndTime = $EndAt
}

If ($EndInMinutes)
{
  $EndTime = $(Get-Date).AddMinutes($EndInMinutes)
}

[Void](New-CdmRoleAssignment -Computer $CdmManagedComputer -ADTrustee $ADUser -Role $CdmRole -EndTime $EndTime)


  