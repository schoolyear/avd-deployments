# The files in this folder (000_name.ps1) are executed for each user session starting on a session host
# The files are executed from the SYSTEM account and have admin priviledges
# All files must exit without an error for the VDI Browser to start up properly

#The line below disables the "Windows firewall has blockes some features of this app" pop-up as it pops up when running code the first time, because VSCode tries to access the internet.
Set-NetFirewallProfile -Profile Domain,Private,Public -NotifyOnListen False
