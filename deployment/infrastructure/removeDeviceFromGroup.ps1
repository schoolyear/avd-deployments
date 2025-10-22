using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Configuration
$maxRetries = 3
$secondsDelayBetweenRetries = 5

# Get access token using the managed identity
$resourceUri = "https://graph.microsoft.com"
$tokenAuthUri = $env:IDENTITY_ENDPOINT + "?resource=" + $resourceUri + "&api-version=2019-08-01"
$retryCount = 0

while ($retryCount -lt $maxRetries) {
  $retryCount++

  try {
    $tokenResponse = Invoke-RestMethod -Method Get -Headers @{"X-IDENTITY-HEADER" = "$env:IDENTITY_HEADER" } -Uri $tokenAuthUri
    break
  }
  catch {
    if ($retryCount -ge $maxRetries) {
      Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
          StatusCode = [HttpStatusCode]::InternalServerError
          Body       = @{
            error     = "Failed to request access token from Azure (after $maxRetries attempts): $_"
            errorCode = 1
          } | ConvertTo-Json
          Headers    = @{ "Content-Type" = "application/json" }
        })
      return
    }
    Start-Sleep $secondsDelayBetweenRetries
  }
}

$accessToken = $tokenResponse.access_token

# Read the deviceName from the request
$deviceName = $Request.Query.deviceName
if ([String]::IsNullOrEmpty($deviceName)) {
  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
      StatusCode = [HttpStatusCode]::BadRequest
      Body       = @{
        error     = "query param 'deviceName' cannot be empty"
        errorCode = 2
      } | ConvertTo-Json
      Headers    = @{ "Content-Type" = "application/json" }
    })
  return
}

# Find device by name
$searchUri = "https://graph.microsoft.com/v1.0/devices?`$filter=displayName eq '$deviceName'"
$retryCount = 0

while ($retryCount -lt $maxRetries) {
  $retryCount++

  try {
    $deviceResponse = Invoke-RestMethod -Uri $searchUri -Headers @{ 'Authorization' = "Bearer $accessToken" } -Method Get
    break
  }
  catch {
    if ($retryCount -ge $maxRetries) {
      Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
          StatusCode = [HttpStatusCode]::InternalServerError
          Body       = @{
            error     = "failed to find device by name (after $maxRetries attempts): $_"
            errorCode = 3
          } | ConvertTo-Json
          Headers    = @{ "Content-Type" = "application/json" }
        })
      return
    }
    Start-Sleep $secondsDelayBetweenRetries
  }
}

# If device not found, consider it successfully removed (idempotent)
if ($deviceResponse.value.Count -eq 0) {
  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
      StatusCode = [HttpStatusCode]::OK
      Body       = @{
        message = "Device not found (already removed or never existed)"
      } | ConvertTo-Json
      Headers    = @{ "Content-Type" = "application/json" }
    })
  return
}

$deviceId = $deviceResponse.value[0].id

# Remove device from group
$groupId = $env:TARGET_GROUP_ID
$uri = "https://graph.microsoft.com/v1.0/groups/$groupId/members/$deviceId/`$ref"
$headers = @{ 
  'Authorization' = "Bearer $accessToken"
}

$retryCount = 0
$deviceNotInGroup = $false

while ($retryCount -lt $maxRetries) {
  $retryCount++

  try {
    Invoke-RestMethod -Uri $uri -Headers $headers -Method Delete
    break
  }
  catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    $errorMessage = ""
    
    # Try to get the error message from the response
    try {
      $errorDetails = $_.ErrorDetails.Message | ConvertFrom-Json
      $errorMessage = $errorDetails.error.message
    }
    catch {
      $errorMessage = $_.Exception.Message
    }
    
    # Check if device is not in the group (404 - idempotent, consider it success)
    if ($statusCode -eq 404) {
      $deviceNotInGroup = $true
      break
    }
    
    # For other errors, retry
    if ($retryCount -ge $maxRetries) {
      Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
          StatusCode = [HttpStatusCode]::InternalServerError
          Body       = @{
            error     = "Failed to remove device from group (after $maxRetries attempts): $errorMessage"
            errorCode = 5
          } | ConvertTo-Json
          Headers    = @{ "Content-Type" = "application/json" }
        })
      return
    }
    
    Start-Sleep $secondsDelayBetweenRetries
  }
}

# Success (either removed or wasn't in group)
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body       = @{
      message = if ($deviceNotInGroup) { 
        "Device not in group (already removed)" 
      } else { 
        "Successfully removed device from group" 
      }
    } | ConvertTo-Json
    Headers    = @{ "Content-Type" = "application/json" }
  })