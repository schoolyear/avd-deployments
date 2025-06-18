$url = "http://169.254.169.254/metadata/instance/compute/userData?api-version=2021-01-01&format=text"
$headers = @{
  "Metadata" = "true"
}

try {
  $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
} catch {
  Write-Error "Could not make request to metadata endpoint (userData): $_"
  exit 1
}

# decode userData string blob (base64) and parse as json
$userData = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($response)) | ConvertFrom-Json

# Find version, we need to decide if this is managed or unmanaged version
$version = $userData.version
if (![string]::IsNullOrEmpty($version)) {
  # Managed version
  # Find proxy LB private IP address to whitelist
  $proxyLoadBalancerPrivateIpAddress = $userData.proxyLoadBalancerPrivateIpAddress
  if ([string]::IsNullOrEmpty($proxyLoadBalancerPrivateIpAddress)) {
    Write-Error "proxyLoadBalancerPrivateIpAddress is empty"
    exit 1
  }

  # Find AVD Endpoints ip range to whitelist
  $avdEndpointsIpRange = $userData.avdEndpointsIpRange
  if ([string]::IsNullOrEmpty($avdEndpointsIpRange)) {
    Write-Error "avdEndpointsIpRange is empty"
    exit 1
  }

  # set the default network profile to public
  Set-NetConnectionProfile -NetworkCategory Public

  # Allow communication to the AVD services
  New-NetFirewallRule -DisplayName "Allow all outbound to azure proxy LB $proxyLoadBalancerPrivateIpAddress" -Direction Outbound -RemoteAddress $proxyLoadBalancerPrivateIpAddress -Action Allow -Profile Any | Out-Null
  # Allow communication to the AVD endpoints subnet
  New-NetFirewallRule -DisplayName "Allow all outbound to azure AVD endpoints $avdEndpointsIpRange" -Direction Outbound -RemoteAddress $avdEndpointsIpRange -Action Allow -Profile Any | Out-Null

  # Allow hardcoded IP addresses used by Azure
  New-NetFirewallRule -DisplayName "Allow metadata service outbound" -RemoteAddress 169.254.169.254 -Direction Outbound -Action Allow -Profile Any | Out-Null
  New-NetFirewallRule -DisplayName "Allow health service monitor outbound" -RemoteAddress 168.63.129.16 -Direction Outbound -Action Allow -Profile Any | Out-Null

  # Block all other outgoing network connections
  Set-NetFirewallProfile -Name Domain -DefaultOutboundAction Block
  Set-NetFirewallProfile -Name Private -DefaultOutboundAction Block
  Set-NetFirewallProfile -Name Public -DefaultOutboundAction Block

  exit 0
}

# Unmanaged version, use hardcoded IP ranges
# set the default network profile to public
Set-NetConnectionProfile -NetworkCategory Public

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