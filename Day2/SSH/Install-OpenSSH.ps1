########################################################
#.SYNOPSIS
#  Installs OpenSSH service from a GitHub release.
#
#.DESCRIPTION
#  This script installs the OpenSSH server using a
#  release from GitHub.  This is *not* how OpenSSH is 
#  installed when using Add-WindowsCapability. Get
#  the latest release zip and extract it into a folder
#  named \OpenSSH-Win64 somewhere:
#
#     https://github.com/PowerShell/Win32-OpenSSH/releases
#
#.PARAMETER SourceFiles
#  Path to the folder which contains the GitHub files for
#  installing OpenSSH.  This folder will probably be 
#  named "OpenSSH-Win64" and must have sshd.exe inside it.
#
#.NOTES
#  This script deletes any existing OpenSSH service files
#  located in $env:ProgramFiles\OpenSSH, but it does not
#  delete any settings files from $env:ProgramData\ssh.
#
#  Last Updated: 7.Nov.2019 
########################################################

Param ($SourceFiles = "C:\SANS\Tools\OpenSSH\OpenSSH-Win64") 

# Note the current directory in order to return to it later:
$CurrentDir = $PWD


# Confirm the presence of sshd.exe:
if (-not (Test-Path -Path "$SourceFiles\sshd.exe"))
{ 
    "Could not find sshd.exe in $SourceFiles"
    Exit
} 


# Stop the sshd and ssh-agent services, if they exist:
Stop-Service -Name sshd -ErrorAction SilentlyContinue
Stop-Service -Name ssh-agent -ErrorAction SilentlyContinue


# Delete inbound firewall allow rules named like *OpenSSH*, if any:
Get-NetFirewallRule -Name "*OpenSSH*" |
Where { ($_.Direction -eq 'Inbound') -and ($_.Action -eq 'Allow') } |
Remove-NetFirewallRule 


# Delete the C:\Program Files\OpenSSH folder, if it exists:
Remove-Item -Path "$env:ProgramFiles\OpenSSH\" -Recurse -Force -ErrorAction SilentlyContinue


# Create a new, empty C:\Program Files\OpenSSH folder:
New-Item -Path "$env:ProgramFiles\OpenSSH\" -ItemType Directory -Force | Out-Null 


# Copy the OpenSSH binaries into this folder:
Copy-Item -Path "$SourceFiles\*" -Destination "$env:ProgramFiles\OpenSSH\" -Force -Recurse


# Ensure files are not read-only, especially openssh-events.man:
dir -File -Path $env:ProgramFiles\OpenSSH\ | ForEach { $_.IsReadOnly = $False } 


# Move into the $env:ProgramFiles\OpenSSH folder to run the official installer script:
cd $env:ProgramFiles\OpenSSH\

if ($PWD.Path -notlike "*Files\OpenSSH")
{ 
    "Not in the $env:ProgramFiles\OpenSSH folder!"
    Exit 
} 


# Run the official OpenSSH installer script:
.\Install-SSHD.ps1


# Create a new inbound firewall rule to allow TCP/22 for SSH traffic:
New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH SSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null


# Start the OpenSSH Agent (ssh-agent) service first, before sshd:
Start-Service -Name ssh-agent


# Start the OpenSSH Server (sshd) service, which also creates the $env:ProgramData\ssh files:
Start-Service -Name sshd


# Configure the OpenSSH Server service to start automatically:
Set-Service -Name sshd -StartupType Automatic 


# Configure OpenSSH Agent service to start automatically:
Set-Service -Name ssh-agent -StartupType Automatic 


# Change PATH environment variable:
$NewPath = @()
$FoundOne = $false #Assume PATH does not have an OpenSSH folder.

[Environment]::GetEnvironmentVariable("Path", "Machine") -split ';' |
ForEach { if ($_ -like '*OpenSSH*'){ $FoundOne = $true; $NewPath += "$env:ProgramFiles\OpenSSH" } else { $NewPath += $_ } } 

# Add the folder if none currently exist:
if ($FoundOne -eq $false){ $NewPath += "$env:ProgramFiles\OpenSSH" } 

# Suppress any duplicate folders in PATH:
$NewPath = ($NewPath | Select-Object -Unique) -join ';'

# Update permanent PATH variable for the machine:
[Environment]::SetEnvironmentVariable("Path", $NewPath, "Machine")

# Update PATH for the current user, which isn't normally necessary, except
# that we don't want to have to reboot the VM in the lab right now:
[Environment]::SetEnvironmentVariable("Path", $NewPath, "User")

# Update the $env:Path variable for this posh session (dot-sourcing):
$env:Path = $NewPath

# Return to previous directory:
cd $CurrentDir



# Remember, you cannot use ssh.exe in PowerShell ISE, you must
# use powershell.exe, pwsh.exe or Windows Terminal:
#
#   ssh.exe testing\administrator@127.0.0.1         #Domain Account (backslash)
#   ssh.exe administrator@testing.local@127.0.0.1   #Domain Account (two @'s)
#   ssh.exe kate@127.0.0.1                          #Local Account
#

