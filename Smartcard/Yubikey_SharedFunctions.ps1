
Function Enroll-NewYubikey()
{

  param
    (
      [Parameter(Mandatory=$true)][string]  $ADUser,
      [Parameter(Mandatory=$true)][string]  $PIN,
      [Parameter(Mandatory=$false)][string] $CertificateTemplate,
      [Parameter(Mandatory=$false)][string] $Slot = "2",
      [Parameter(Mandatory=$true)][string]  $HMAC = ""
    )

  WriteToLog "Enroll-NewYubiKey()"  
  WriteToLog "ADUser = $ADUser"
  WriteToLog "PIN = $PIN"
  WriteToLog "CertificateTemplate = $CertificateTemplate"
  WriteToLog "Slot = $Slot"
  WriteToLog "HMAC = $HMAC"
  
  Import-Module PSPKI

  $fileLog = "$absPath\Smartcard\log.txt"
  $fileEa = "$absPath\Smartcard\enrollmentagent.txt"
  $filePublicKey = "$absPath\Smartcard\public.pem"
  $fileCsr = "$absPath\Smartcard\request.csr"
  $fileCert = "$absPath\Smartcard\cert.crt"
  $fileCA = "$absPath\Smartcard\CertificateAuthority.txt"

  $enrollmentThumbprint = Get-String -FileName $fileEa -FailFast $true
  $mgmKey = Get-StringSecurely -FileName "$absPath\Smartcard\ManagementKey.bin"
  $certificateAuthority = Get-String -FileName $fileCA -FailFast $true
  $newPuk = Generate-RandomString -Length 8

  Display-DoNotRemove

  $id = Yubico-GetDeviceId
  #sleep 5

  If ($id -eq "")
    {
      WriteToLog "YubiKey not operational. Maybe not plugged in?"
      Return $False
    }
  
  WriteToLog "Resetting OPT Slot 2"
  Yubico-ResetOTP -Slot $Slot

  WriteToLog "Writing New OPT Slot 2"
  Yubico-WriteHOTPCertificate -Slot $Slot -HMAC $HMAC

  WriteToLog "Revoking Existing Certificates on CA for Requester: $ADUser, CertificateTemplate: $CertificateTemplate"
  $certs = Get-CertificationAuthority | Get-IssuedRequest -Filter "Request.RequesterName -eq $ADUser", "CertificateTemplate -eq $CertificateTemplate" | ft | out-string
  ForEach ($cert in $certs) {WriteToLog $cert}
  Get-CertificationAuthority | Get-IssuedRequest -Filter "Request.RequesterName -eq $ADUser", "CertificateTemplate -eq $CertificateTemplate" | Revoke-Certificate -Reason "CeaseOfOperation"

  WriteToLog "Resetting YubiKey ID: $id"
  Yubico-ResetDevice

  WriteToLog "Setting Management Key"
  Yubico-SetManagementKey -NewManagementKey $mgmKey

  WriteToLog "Setting CHUID"
  Yubico-SetCHUID -ManagementKey $mgmKey

  WriteToLog "Setting PIN"
  Yubico-SetPin -ManagementKey $mgmKey -NewPin $PIN

  WriteToLog "Setting PUK"
  Yubico-SetPuk -ManagementKey $mgmKey -NewPuk $newPuk

  WriteToLog "Generating new private key"
  Yubico-GenerateKey -ManagementKey $mgmKey -OutputFile $filePublicKey

  WriteToLog "Generating new CSR"

  Yubico-GenerateCSR -Pin $PIN -PublicKey $filePublicKey -RequestFile $fileCsr

  WriteToLog "Signing key"
  Sign-OnBehalfOf -EnrollmentAgentCert $enrollmentThumbprint -User $ADUser -RequestFile $fileCsr -CertificateFile $fileCert -CertificateTemplate $CertificateTemplate -CertificateAuthority $certificateAuthority 

  WriteToLog "Setting cert"
  Yubico-Importcert -ManagementKey $mgmKey -CertificateFile $fileCert

  WriteToLog "Reading cert Serial Number"
  $certObject = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
  $certObject.Import($fileCert)
  $certSerial = $certObject.SerialNumber

  WriteToLog "Logging configuration"

  $line = "ID: $id; User: $ADUser; PUK: $newPuk; SerialNumber: $certSerial"

  [System.IO.File]::AppendAllText($fileLog, "$line`n")
  WriteToLog $line
  
  WriteToLog "Clearing intermediate files"

  Remove-ItemIfExists $filePublicKey
  Remove-ItemIfExists $fileCsr
  Remove-ItemIfExists $fileCert

  Display-MayRemove
  
  Return $True

}

Function Store-String
  {
    param 
      (
        [string] $FileName,
        [string] $Text
      )

    Set-Content -Path $FileName -Value $Text -Force
  }

Function Store-StringSecurely
  {
    param 
      (
        [string] $FileName,
        [string] $Text
      )

    # TODO: Encrypt file
    Set-Content -Path $FileName -Value $Text -Force
  }

Function Get-StringSecurely
  {
    param 
      (
        [string] $FileName
      )

    If (!(Test-Path $FileName))
      {
        throw "File $FileName does not exist. Has it been generated?"
      }

    # TODO: Decrypt file
    Get-Content -Path $FileName
}


Function Generate-RandomString
  {
    # http://www.peterprovost.org/blog/2007/06/22/Quick-n-Dirty-PowerShell-Password-Generator/
    param 
      ( 
        [int] $Length = 12,
        [string] $Characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz012345678"
      )
    
    $bytes = new-object "System.Byte[]" $Length

    $rnd = new-object System.Security.Cryptography.RNGCryptoServiceProvider
    $rnd.GetBytes($bytes)

    $result = ""
    for( $i=0; $i -lt $Length; $i++ )
      {
        $result += $Characters[ $bytes[$i] % $Characters.Length ]	
      }
    $result
}





Function Get-String
  {
    param 
      (
        [string] $FileName,
        [bool] $FailFast = $true
      )

    If (!(Test-Path $FileName))
      {
        If ($FailFast)
          {
            throw "File $FileName does not exist. Has it been generated?"
          }
        
        Return ""
      }

    Get-Content -Path $FileName
  }

Function Generate-RandomStringHex
  {
    param 
    ( 
      [int] $LengthBytes = 12,
      [bool] $UseYubicoHsm = $false
    )

    $bytes = new-object "System.Byte[]" $LengthBytes
    $rnd = new-object System.Security.Cryptography.RNGCryptoServiceProvider
    $rnd.GetBytes($bytes)

    $string = ""
    $bytes | foreach { $string = $string + $_.ToString("x2") }

    $string
  }


Function Yubico-ResetOTP
  {
    param 
    (
      [string] $Slot = "2"
    )

    $Path = "$absPath" + "\smartcard\bin\ykpersonalize"
    $Arguments = "-$Slot -z -y"
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments

  }

function Yubico-WriteHOTPCertificate
  {
    param 
    (
      [string] $Slot = "2",
      [string] $HMAC = ""
    )

    $Path = "$absPath" + "\smartcard\bin\ykpersonalize"
    $Arguments = "-$Slot -y -o oath-hotp -o append-cr -a $HMAC"
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments
    
  }

function Yubico-ResetDevice
  {
    $Path = "$absPath" + "\smartcard\bin\yubico-piv-tool"
    $Arguments = "-a verify-pin -P RNADOMSI"
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments

    $Arguments = "-a change-puk -P RNADOMSI -N RNADOMSI"
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments

    $Arguments = "-a reset"
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments
  }

function Yubico-SetManagementKey
  {
    param 
    (
      [string] $NewManagementKey = "010203040506070801020304050607080102030405060708"
    )

    $Path = "$absPath" + "\smartcard\bin\yubico-piv-tool"
    $Arguments = "-a set-mgm-key -n $NewManagementKey"
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments

  }

function Yubico-SetPin
  {
    param 
    (
      [string] $ManagementKey = "010203040506070801020304050607080102030405060708",
      [string] $OldPin = "123456",
      [string] $NewPin = ""
    )

    $Path = "$absPath" + "\smartcard\bin\yubico-piv-tool"
    $Arguments = "--key=$ManagementKey -a change-pin -P $OldPin -N $NewPin"
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments

  }

function Yubico-SetPuk
  {
    param 
    (
      [string] $ManagementKey = "010203040506070801020304050607080102030405060708",
      [string] $OldPuk = "12345678",
      [string] $NewPuk = ""
    )

    $Path = "$absPath" + "\smartcard\bin\yubico-piv-tool"
    $Arguments = "--key=$ManagementKey -a change-puk -P $OldPuk -N $NewPuk"
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments
    
  }

function Yubico-SetTriesCount
  {
    param 
    (
      [string] $ManagementKey = "010203040506070801020304050607080102030405060708",
      [int] $PinTries = 3,
      [int] $PukTries = 3
    )

    $Path = "$absPath" + "\smartcard\bin\yubico-piv-tool"
    $Arguments = "-v -a pin-retries --pin-retries $PinTries --puk-retries $PukTries"
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments
    
  }

function Yubico-SetCHUID
  {
    param 
    (
      [string] $ManagementKey = "010203040506070801020304050607080102030405060708"
    )

    $Path = "$absPath" + "\smartcard\bin\yubico-piv-tool"
    $Arguments = "--key=$ManagementKey -a set-chuid"
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments

  }

function Yubico-GenerateKey
{
    param 
    (
      [string] $ManagementKey = "010203040506070801020304050607080102030405060708",
      [string] $OutputFile = "public.pem"
    )

    $Path = "$absPath" + "\smartcard\bin\yubico-piv-tool"
    $Arguments = "--key=$ManagementKey -s 9a -a generate -o $OutputFile"
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments

}

function Yubico-GenerateCSR
{
    param 
    (
      [string] $Pin = "123456",
      [string] $PublicKey= "public.pem",
      [string] $RequestFile = "request.csr"
    )

<#    
    $p = Start-Process $absPath\SmartCard\bin\yubico-piv-tool -ArgumentList @"
-a verify-pin -P $Pin -s 9a -a request-certificate -S "/CN=example/O=test/" -i $PublicKey -o $RequestFile
"@ -Wait -NoNewWindow -PassThru

#>
    $Path = "$absPath" + "\smartcard\bin\yubico-piv-tool"
    $Arguments = "-a verify-pin -P $Pin -s 9a -a request-certificate -S ""/CN=example/O=test/"" -i $PublicKey -o $RequestFile"
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments

  }

function Yubico-Importcert
{
    param (
        [string] $ManagementKey = "010203040506070801020304050607080102030405060708",
        [string] $CertificateFile = "cert.crt"
    )

    $Path = "$absPath" + "\smartcard\bin\yubico-piv-tool"
    $Arguments = "--key=$ManagementKey -s 9a -a import-certificate -i $CertificateFile"
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments

}

function Yubico-GetDeviceId
{
    WriteToLog "Executing $absPath\SmartCard\bin\ykinfo -H"
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "$absPath\SmartCard\bin\ykinfo"
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = "-H"

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()
  
    $ExitCode = $p.ExitCode
    If ($ExitCode -ne 0)
    {
      return ""
    }
    else
    {
      $stdout = $p.StandardOutput.ReadLine()
      return $stdout.Split(':')[1].Trim()
    }

}

function Sign-OnBehalfOf
{
    param (
        [string] $EnrollmentAgentCert = "0102030405060708010203040506070801020304",
        [string] $User = "Domain\User",
        [string] $RequestFile = "request.csr",
        [string] $CertificateFile = "cert.crt",
        [string] $CertificateTemplate = "SmartcardLogon",
        [string] $CertificateAuthority = "DC-2016.centrify.vms\centrify-DC-2016-CA"
    )

    $Path = "$absPath" + "\smartcard\bin\EOBOSigner"
    $Arguments = "$EnrollmentAgentCert $User $RequestFile $CertificateFile $CertificateTemplate $CertificateAuthority"
    ExecuteCommandLocallyAndWait -Path $Path -Arguments $Arguments

}


function Display-DoNotRemove
{
    WriteToLog "**************************************"
    WriteToLog  "***    Do not remove the Yubikey   ***"
    WriteToLog "**************************************"
}

function Display-MayRemove
{
    WriteToLog "**************************************"
    WriteToLog "***   You may remove the Yubikey   ***"
    WriteToLog "**************************************"
}