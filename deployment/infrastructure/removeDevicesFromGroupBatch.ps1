using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Configuration
$maxRetries = 3
$secondsDelayBetweenRetries = 5
$groupId = $env:TARGET_GROUP_ID

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

# Read deviceNames from the request body
$deviceNames = $Request.Body.deviceNames

# Validate devices, cannot be null/empty
if ($null -eq $deviceNames -or $deviceNames.Count -eq 0) {
  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
      StatusCode = [HttpStatusCode]::BadRequest
      Body       = @{
        error     = "Request body must contain 'deviceNames' array"
        errorCode = 2
      } | ConvertTo-Json
      Headers    = @{ "Content-Type" = "application/json" }
    })
  return
}

# Nor can it be more than 20 (max Microsoft Graph Batch size)
if ($deviceNames.Count -gt 20) {
  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
      StatusCode = [HttpStatusCode]::BadRequest
      Body       = @{
        error     = "deviceNames array cannot contain more than 20 items"
        errorCode = 3
      } | ConvertTo-Json
      Headers    = @{ "Content-Type" = "application/json" }
    })
  return
}

# Helper function to execute batch requests
function Invoke-GraphBatch {
  param (
    [array]$Requests,
    [string]$AccessToken
  )
    
  $headers = @{
    "Authorization" = "Bearer $AccessToken"
    "Content-Type"  = "application/json"
  }
    
  $batchUrl = "https://graph.microsoft.com/v1.0/`$batch"
    
  $batchBody = @{
    requests = $Requests
  } | ConvertTo-Json -Depth 10
    
  $response = Invoke-RestMethod -Method Post -Uri $batchUrl -Headers $headers -Body $batchBody
  return $response.responses
}

# Batch fetch device IDs
$fetchRequests = @()
$requestId = 1

foreach ($deviceName in $deviceNames) {
  $fetchRequests += @{
    id     = "$requestId"
    method = "GET"
    url    = "/devices?`$filter=displayName eq '$deviceName'"
  }

  $requestId++
}

$retryCount = 0
while ($retryCount -lt $maxRetries) {
  $retryCount++

  try {
    $fetchResponses = Invoke-GraphBatch -Requests $fetchRequests -AccessToken $accessToken
    break
  }
  catch {
    if ($retryCount -ge $maxRetries) {
      Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
          StatusCode = [HttpStatusCode]::InternalServerError
          Body       = @{
            error     = "Failed to fetch device IDs (after $maxRetries attempts): $_"
            errorCode = 4
          } | ConvertTo-Json
          Headers    = @{ "Content-Type" = "application/json" }
        })
      return
    }

    Start-Sleep $secondsDelayBetweenRetries
  }
}

# Build device map (devices not found are considered successfully removed)
$deviceMap = @{}
$index = 0
foreach ($response in $fetchResponses) {
  $deviceName = $deviceNames[$index]
    
  if ($response.status -eq 200 -and $response.body.value.Count -gt 0) {
    $deviceMap[$deviceName] = $response.body.value[0].id
  }
    
  $index++
}

# If no devices found, consider it success
if ($deviceMap.Count -eq 0) {
  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
      StatusCode = [HttpStatusCode]::OK
      Body       = @{
        message = "Successfully removed devices from group"
      } | ConvertTo-Json
      Headers    = @{ "Content-Type" = "application/json" }
    })
  return
}

# Batch remove devices from group
$removeRequests = @()
$requestId = 1
$deviceNamesList = @($deviceMap.Keys)

foreach ($deviceName in $deviceNamesList) {
  $deviceId = $deviceMap[$deviceName]
  $removeRequests += @{
    id     = "$requestId"
    method = "DELETE"
    url    = "/groups/$groupId/members/$deviceId/`$ref"
  }

  $requestId++
}

$retryCount = 0
while ($retryCount -lt $maxRetries) {
  $retryCount++

  try {
    $removeResponses = Invoke-GraphBatch -Requests $removeRequests -AccessToken $accessToken
    break
  }
  catch {
    if ($retryCount -ge $maxRetries) {
      Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
          StatusCode = [HttpStatusCode]::InternalServerError
          Body       = @{
            error     = "Failed to remove devices from group (after $maxRetries attempts): $_"
            errorCode = 5
          } | ConvertTo-Json
          Headers    = @{ "Content-Type" = "application/json" }
        })
      return
    }
    Start-Sleep $secondsDelayBetweenRetries
  }
}

# Process results - only track actual failures
$failedRemovals = @()
$index = 0

foreach ($response in $removeResponses) {
  $deviceName = $deviceNamesList[$index]
    
  # 204 = success, 404 = not in group (considered success)
  if ($response.status -ne 204 -and $response.status -ne 404) {
    $failedRemovals += @{
      deviceName = $deviceName
      status     = $response.status
      error      = $response.body.error.message
    }
  }
    
  $index++
}

# Return response 200 for full success and 207 for partial success
if ($failedRemovals.Count -gt 0) {
  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
      StatusCode = [HttpStatusCode]::MultiStatus
      Body       = @{
        message = "Some devices failed to be removed"
        failed  = $failedRemovals
      } | ConvertTo-Json -Depth 10
      Headers    = @{ "Content-Type" = "application/json" }
    })
}
else {
  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
      StatusCode = [HttpStatusCode]::OK
      Body       = @{
        message = "Successfully removed devices from group"
      } | ConvertTo-Json
      Headers    = @{ "Content-Type" = "application/json" }
    })
}