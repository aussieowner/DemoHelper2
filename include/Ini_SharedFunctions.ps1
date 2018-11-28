Function Get-IniContent
{  
    
  [CmdletBinding()]  
  Param
    (  
      [ValidateNotNullOrEmpty()]  
      [ValidateScript({(Test-Path $_) -and ((Get-Item $_).Extension -eq ".ini")})]  
      [Parameter(ValueFromPipeline=$True,Mandatory=$True)]  
      [string]$FilePath  
    )  
  
  Begin  
    {Write-Verbose "$($MyInvocation.MyCommand.Name):: Function started"}  
      
  Process  
  {  
    Write-Verbose "$($MyInvocation.MyCommand.Name):: Processing file: $Filepath"  
          
    $ini = @{}  
    switch -regex -file $FilePath  
    {  
      "^\[(.+)\]$" # Section  
      {  
        $section = $matches[1].trim()  
        $ini[$section] = @{}  
        $CommentCount = 0  
      }  

      "^(;.*)$" # Comment  
      {  
        if (!($section))  
        {  
          $section = "No-Section"  
          $ini[$section] = @{}  
        }  
        $value = $matches[1].trim()  
        $CommentCount = $CommentCount + 1  
        $name = "Comment" + $CommentCount  
        $ini[$section][$name] = $value  
      }   

      "(.+?)\s*=\s*(.*)" # Key  
      {  
        if (!($section))  
        {  
          $section = "No-Section"  
          $ini[$section] = @{}  
        }  
        $name,$value = $matches[1..2]  
        $ini[$section][$name] = $value.trim()  
      }  
    }  
      Write-Verbose "$($MyInvocation.MyCommand.Name):: Finished Processing file: $FilePath"  
      Return $ini  
  }  
        
  End  
  {Write-Verbose "$($MyInvocation.MyCommand.Name):: Function ended"}  
} 
