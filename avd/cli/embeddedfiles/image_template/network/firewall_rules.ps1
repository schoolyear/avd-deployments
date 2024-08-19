# You only have to add firewall exceptions that open new ports
# Closing down the firewall is already done

# example
# New-NetFirewallRule -DisplayName "Allow squid (pip proxy)" -Direction Outbound -Program "C:\Squid\bin\squid.exe" -Action Allow | Out-Null