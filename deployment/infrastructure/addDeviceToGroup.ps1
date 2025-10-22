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

if ($deviceResponse.value.Count -eq 0) {
  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
      StatusCode = [HttpStatusCode]::NotFound
      Body       = @{
        error     = "Device with name '$deviceName' not found"
        errorCode = 4
      } | ConvertTo-Json
      Headers    = @{ "Content-Type" = "application/json" }
    })
  return
}

$deviceId = $deviceResponse.value[0].id

# Add device to group
$groupId = $env:TARGET_GROUP_ID
$uri = "https://graph.microsoft.com/v1.0/groups/$groupId/members/`$ref"
$headers = @{ 
  'Authorization' = "Bearer $accessToken"
  'Content-Type'  = 'application/json'
}

$body = @{
  "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$deviceId"
} | ConvertTo-Json

$retryCount = 0
$deviceAlreadyExists = $false

while ($retryCount -lt $maxRetries) {
  $retryCount++

  try {
    Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $body
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
    
    # Check if it's a "already exists" error (idempotent - consider it success)
    if ($statusCode -eq 400 -and ($errorMessage -like "*already exist*" -or $errorMessage -like "*One or more added object references already exist*")) {
      $deviceAlreadyExists = $true
      break
    }
    
    # For other errors, retry
    if ($retryCount -ge $maxRetries) {
      Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
          StatusCode = [HttpStatusCode]::InternalServerError
          Body       = @{
            error     = "Failed to add device to group (after $maxRetries attempts): $errorMessage"
            errorCode = 5
          } | ConvertTo-Json
          Headers    = @{ "Content-Type" = "application/json" }
        })
      return
    }
    
    Start-Sleep $secondsDelayBetweenRetries
  }
}

# Success (either added or already exists)
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body       = @{
      message = if ($deviceAlreadyExists) { 
        "Device already in group" 
      } else { 
        "Successfully added device to group" 
      }
    } | ConvertTo-Json
    Headers    = @{ "Content-Type" = "application/json" }
  })