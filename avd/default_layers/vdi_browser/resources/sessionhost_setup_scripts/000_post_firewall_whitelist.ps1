# set the default network profile to public
Set-NetConnectionProfile -NetworkCategory Public

# todo: edit for other environments
$syExamsFolder = "C:\Program Files (x86)\Schoolyear\Schoolyear Browser Development (confidential)"
$syExamsExe = "$syExamsFolder\shell\Schoolyear Exams.exe"
$syVDIServiceExe = "$syExamsFolder\schoolyear-vdi-service.exe"
$avdTokenProviderExe = "$syExamsFolder\shell\resources\avd_token_provider.exe"

# Allow the VDI browser
New-NetFirewallRule -DisplayName "Allow Schoolyear Browser outbound" -Program $syExamsExe -Direction Outbound -Action Allow -Profile Any | Out-Null
# Allow the background service
New-NetFirewallRule -DisplayName "Allow Schoolyear VDI service" -Program $syVDIServiceExe -Direction Outbound -Action Allow -Profile Any | Out-Null

# Allow the token provider
New-NetFirewallRule -DisplayName "Allow AVD token provider" -Program $avdTokenProviderExe -Direction Outbound -Action Allow -Profile Any | Out-Null

# Allow communication to the AVD services
# This rule should be changed if you change the subnet in the deployment template
New-NetFirewallRule -DisplayName "Allow all outbound to azure services 10.0.16.0/20" -Direction Outbound -RemoteAddress 10.0.16.0/20 -Action Allow -Profile Any | Out-Null

# Allow hardcoded IP addresses used by Azure
New-NetFirewallRule -DisplayName "Allow metadata service outbound" -RemoteAddress 169.254.169.254 -Direction Outbound -Action Allow -Profile Any | Out-Null
New-NetFirewallRule -DisplayName "Allow health service monitor outbound" -RemoteAddress 168.63.129.16 -Direction Outbound -Action Allow -Profile Any | Out-Null

# Block all other outgoing network connections
Set-NetFirewallProfile -Name Domain -DefaultOutboundAction Block
Set-NetFirewallProfile -Name Private -DefaultOutboundAction Block
Set-NetFirewallProfile -Name Public -DefaultOutboundAction Block
