<#
.SYNOPSIS
    Fix permissions on the OpenSSH host key files.

.DESCRIPTION
    OpenSSH host key files must have these permissions exactly:

        NT AUTHORITY\SYSTEM     = Full Control
        BUILTIN\Administrators  = Full Control
        Permissions Inheritance = Disabled

    This script will reset the permissions on the files, if necessary.
    The script assumes all key files are like "ssh_host_*", so only
    file that match this pattern will have their permissions checked.

.PARAMETER SshConfigFolder
    Path to the folder containing the OpenSSH Server host key files.
    Defaults to the factory default of $env:ProgramData\ssh\.

.PARAMETER Verbose
    Displays status messages.  Default is to run silently. 
#> 


Param 
(
    $SshConfigFolder = "$env:ProgramData\ssh",
    [Switch] $Verbose
)

$HostKeys = @( dir -Path $SshConfigFolder -Filter "ssh_host_*" )

if ($HostKeys.Count -eq 0)
{ if ($Verbose)
  { 
    Write-Verbose -Verbose -Message ("No ssh_host_* keys found in " + $SshConfigFolder)
  } 

  Exit
}


ForEach ($KeyFile in $HostKeys)
{
    # Get the current permissions:
    $Perms = Get-Acl -Path $KeyFile.FullName

    # Fix the permissions if they are wrong:
    # Factory original SDDL: 'O:SYG:SYD:P(A;;FA;;;SY)(A;;FA;;;BA)' 
    # sshd starts and runs normally no matter who the 'group owner' is.
    if ($Perms.SDDL -like 'O:SYG:*D:P*(A;;FA;;;SY)(A;;FA;;;BA)')
    {
        if ($Verbose){ Write-Verbose -Verbose -Message ("Permissions correct on " + $KeyFile.FullName) }
    }
    else
    {
        if ($Verbose){ Write-Verbose -Verbose -Message ("Fixing permissions on " + $KeyFile.FullName) } 

        # Take ownership for System:
        icacls.exe $KeyFile.FullName /setowner 'NT AUTHORITY\SYSTEM' | Out-Null

        # Replace all perms with default inherited perms:
        icacls.exe $KeyFile.FullName /reset | Out-Null

        # Grant full control to System and Administrors explicity (do first):
        icacls.exe $KeyFile.FullName /grant:r 'BUILTIN\Administrators:(F)' /grant:r 'NT AUTHORITY\SYSTEM:(F)' | Out-Null 

        # Remove all other inherited perms and disable inheritance (do afterwards):
        icacls.exe $KeyFile.FullName /inheritance:r | Out-Null
    
        # Get the (new) permissions again:
        $Perms = Get-Acl -Path $KeyFile.FullName

        # Check the permissions again and fail if still wrong:
        if ($Perms.SDDL -like 'O:SYG:*D:P*(A;;FA;;;SY)(A;;FA;;;BA)')
        {
            if ($Verbose){ Write-Verbose -Verbose -Message ("Permissions correct on " + $KeyFile.FullName) } 
        }
        else
        {
            Throw ("ERROR: Failed to set necessary permissions on " + $KeyFile.FullName)
        }
    }

}

