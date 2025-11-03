
using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$schoolyearDeviceNamePrefix = "syvm"

# Read deviceNamePrefix from request
$deviceNamePrefix = $Request.Query.deviceNamePrefix
if (!$deviceNamePrefix.startsWith($schoolyearDeviceNamePrefix)) {
  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
      StatusCode = [HttpStatusCode]::BadRequest
      Body       = @{
        error     = "query param 'deviceNamePrefix' must start with '$schoolyearDeviceNamePrefix'"
        errorCode = 1
      } | ConvertTo-Json
      Headers    = @{ "Content-Type" = "application/json" }
    })
  return
}

# Configuration
$maxRetries = 3
$secondsDelayBetweenRetries = 5

# Get access token using the managed identity
$resourceUri = [uri]::EscapeDataString("https://graph.microsoft.com")
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
            errorCode = 2
          } | ConvertTo-Json
          Headers    = @{ "Content-Type" = "application/json" }
        })
      return
    }

    Start-Sleep $secondsDelayBetweenRetries
  }
}

$accessToken = $tokenResponse.access_token

# Find devices based on prefix
$filterQuery = "startswith(displayName, '$deviceNamePrefix')"
$pageSize = 999
$uri = "https://graph.microsoft.com/v1.0/devices?`$filter=$filterQuery&`$top=$pageSize"
$headers = @{ 'Authorization' = "Bearer $accessToken"; 'Content-Type' = "application/json" }
$allDevices = @()
do {
  $retryCount = 0
  while ($retryCount -lt $maxRetries) {
    $retryCount++

    try {
      $deviceResponse = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
      break
    }
    catch {
      if ($retryCount -ge $maxRetries) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{
              error     = "Failed to fetch device Ids (after $maxRetries attempts): $_"
              errorCode = 3
            }
            Headers    = @{ "Content-Type" = "application/json" }
          })

        return
      }

      Start-Sleep $secondsDelayBetweenRetries
    }
  }

  # Add devices from this page to our collection
  $allDevices += $deviceResponse.value
    
  # Check if there's a next page
  $uri = $deviceResponse.'@odata.nextLink'
} while ($uri)

# Split devices in batches and do Microsoft.Graph Json Batch requests
# to delete all devices
$failedDevices = @()

$batchSize = 20
$deviceIds = $allDevices.Id
$deviceNames = $allDevices.displayName
for ($i = 0; $i -lt $deviceIds.Count; $i += $batchSize) {
  $batchIds = $deviceIds[$i..[Math]::Min($i + $batchSize - 1, $deviceIds.Count - 1)]
  $batchNames = $deviceNames[$i..[Math]::Min($i + $batchSize - 1, $deviceIds.Count - 1)]

  # Create requests batch json
  $requests = @()
  $requestId = 1
  foreach ($deviceId in $batchIds) {
    $requests += @{
      id     = "$requestId"
      method = "DELETE"
      url    = "/devices/$deviceId"
    }
    $requestId++
  }

  $retryCount = 0
  while ($retryCount -lt $maxRetries) {
    $retryCount++

    try {
      $batchBody = @{
        requests = $requests
      } | ConvertTo-Json -Depth 10
      $batchResponse = Invoke-RestMethod -Method Post -Uri "https://graph.microsoft.com/v1.0/`$batch" -Headers $headers -Body $batchBody
      $responses = $batchResponse.responses
      break
    }
    catch {
      if ($retryCount -ge $maxRetries) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{
              error     = "Failed to batch delete devices (after $maxRetries attempts): $_"
              errorCode = 4
            }
            Headers    = @{ "Content-Type" = "application/json" }
          })
        return
      }

      Start-Sleep $secondsDelayBetweenRetries
    }
  }

  foreach ($response in $responses) {
    $status = $response.status
    if ($status -ne 204 -and $status -ne 404) {
      $failedDevices += @{
        id = $batchIds[[int]$response.id - 1]
        name = $batchNames[[int]$response.id - 1]
      }
    }
  }
}

if ($failedDevices.Count -gt 0) {
  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
      StatusCode = [HttpStatusCode]::MultiStatus
      Body       = @{
        message         = "Some devices failed to be deleted"
        failedDevices = $failedDevices
      } | ConvertTo-Json -Depth 10
      Headers    = @{ "Content-Type" = "application/json" }
    })
}
else {
  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
      StatusCode = [HttpStatusCode]::OK
      Body       = @{
        message = "Successfully deleted devices from group"
      } | ConvertTo-Json
      Headers    = @{ "Content-Type" = "application/json" }
    })
}
