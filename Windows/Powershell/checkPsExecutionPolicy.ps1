
Get-ExecutionPolicy -List

# The Bypass policy disables all restrictions and suppresses all warnings or prompts for downloaded scripts. This is the closest setting to "completely disabled."
Set-ExecutionPolicy Bypass -Force

# Applies to the entire machine
Set-ExecutionPolicy Bypass -Scope LocalMachine -Force

# Applies to your current logged-in user profile
Set-ExecutionPolicy Bypass -Scope CurrentUser -Force

# change it back to the Windows default secure state
Set-ExecutionPolicy RemoteSigned -Force

<#
        Scope ExecutionPolicy
        ----- ---------------
MachinePolicy       Undefined
   UserPolicy       Undefined
      Process       Undefined
  CurrentUser       Undefined
 LocalMachine       Undefined
 #>