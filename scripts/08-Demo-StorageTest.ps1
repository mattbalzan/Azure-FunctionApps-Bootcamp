<#
.SYNOPSIS
    Demo 08 | End-to-End Storage Validation
    Proves a Function App can fully use a locked-down storage account
    (public network access disabled) over Private Endpoints + Managed Identity.

.DESCRIPTION
    HTTP-triggered function that runs the full validation matrix documented in
    docs/Storage-Private-Endpoints.md and emits the result as either JSON or a
    rendered HTML report.

    Every data-plane call goes out over Regional VNet Integration and resolves
    to a Private Endpoint IP, and every call authenticates with the Function
    App's System-Assigned Managed Identity - no account keys anywhere. If the
    private endpoints, private DNS zones or RBAC are wrong, the corresponding
    test fails rather than silently falling back to the public endpoint.

    Tests performed:
      1.  Host Startup                    - runtime reached this code at all
      2.  Managed Identity Authentication - token acquired for storage.azure.com
      3.  Blob Upload                     - write a probe blob
      4.  Blob Download                   - read it back and compare content
      5.  Queue Write                     - enqueue a probe message
      6.  Queue Read                      - dequeue and compare content
      7.  Table Insert                    - insert a probe entity
      8.  Table Query                     - retrieve it and compare content
      9.  HTML Report Render              - report generation succeeds
      10. Public Network Access Disabled  - control-plane assertion
      11. Shared Key Access Disabled      - control-plane assertion

    `function.json`:

        {
          "bindings": [
            { "authLevel": "function", "type": "httpTrigger", "direction": "in",
              "name": "Request", "methods": [ "get" ] },
            { "type": "http", "direction": "out", "name": "Response" }
          ]
        }

.PARAMETER Request
    HTTP request object supplied by the Functions runtime. Supported query
    parameters:
      format  - 'html' (default) or 'json'
      cleanup - 'true' (default) to delete probe artefacts after the run

.NOTES
    Author   : Matt Balzan | mattbalzan.github.io/My-Site
    Runs on  : Premium (EP1+), Dedicated or Flex Consumption with Regional
               VNet Integration. Not available on Consumption (Y1).
    Modules  : Az.Accounts, Az.Storage
    Identity : System-Assigned Managed Identity needs, scoped to the storage account:
                 Storage Blob Data Contributor
                 Storage Queue Data Contributor
                 Storage Table Data Contributor
                 Reader (for the control-plane assertions)
    AppSetting: STORAGE_ACCOUNT_NAME must be set to the locked-down account.
#>

using namespace System.Net

param($Request, $TriggerMetadata)

$ErrorActionPreference = 'Stop'

$storageAccountName = $env:STORAGE_ACCOUNT_NAME
$resourceGroup      = $env:STORAGE_RESOURCE_GROUP
$format             = if ($Request.Query.format)  { $Request.Query.format }  else { 'html' }
$cleanup            = if ($Request.Query.cleanup) { $Request.Query.cleanup -ne 'false' } else { $true }

$probeId       = [guid]::NewGuid().ToString('N').Substring(0, 12)
$probeContent  = "functionapps-bootcamp-probe-$probeId"
$containerName = 'validation-probe'
$queueName     = 'validation-probe'
$tableName     = 'validationprobe'

$results = [System.Collections.Generic.List[object]]::new()

function Invoke-Test {
    param([string] $Name, [scriptblock] $Body)

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $detail = $null
    $status = 'PASS'

    try {
        $detail = & $Body
    }
    catch {
        $status = 'FAIL'
        $detail = $_.Exception.Message
    }

    $sw.Stop()

    $results.Add([pscustomobject]@{
        test       = $Name
        result     = $status
        durationMs = [math]::Round($sw.Elapsed.TotalMilliseconds)
        detail     = "$detail"
    })

    Write-Host ("[{0,-4}] {1} ({2} ms)" -f $status, $Name, [math]::Round($sw.Elapsed.TotalMilliseconds))
}

# Table data plane has no first-class AAD cmdlet, so call the REST API directly
# with the Managed Identity token.
function Invoke-TableRest {
    param(
        [string] $Method,
        [string] $Resource,
        [hashtable] $Body,
        [string] $Token
    )

    $headers = @{
        Authorization  = "Bearer $Token"
        'x-ms-version' = '2020-12-06'
        'x-ms-date'    = [DateTime]::UtcNow.ToString('R')
        Accept         = 'application/json;odata=nometadata'
    }

    $uri = "https://$storageAccountName.table.core.windows.net/$Resource"

    if ($Body) {
        Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers `
            -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Compress)
    }
    else {
        Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers
    }
}

Write-Host "=== Storage validation starting ==="
Write-Host "Account         : $storageAccountName"
Write-Host "Instance        : $env:WEBSITE_INSTANCE_ID"
Write-Host "Plan            : $env:WEBSITE_SKU"
Write-Host "VNet route all  : $env:WEBSITE_VNET_ROUTE_ALL"
Write-Host "Content overVNet: $env:WEBSITE_CONTENTOVERVNET"
Write-Host ""

# 1. Host startup - if this line executes, the runtime mounted its content
#    share and started, which is itself the hardest part of a locked-down setup.
Invoke-Test 'Host Startup' {
    if (-not $storageAccountName) { throw 'STORAGE_ACCOUNT_NAME app setting is not configured.' }
    "Runtime online on instance $env:WEBSITE_INSTANCE_ID ($env:WEBSITE_SKU)"
}

# 2. Managed Identity authentication
$ctx   = $null
$token = $null
Invoke-Test 'Managed Identity Authentication' {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null

    # Az.Accounts 5.x returns a SecureString unless -AsPlainText is used.
    $script:token = (Get-AzAccessToken -ResourceUrl 'https://storage.azure.com/' -AsPlainText)
    $script:ctx   = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
    $account      = (Get-AzContext).Account
    "Authenticated as $($account.Id) ($($account.Type))"
}

# 3. Blob upload
Invoke-Test 'Blob Upload' {
    if (-not (Get-AzStorageContainer -Name $containerName -Context $ctx -ErrorAction SilentlyContinue)) {
        New-AzStorageContainer -Name $containerName -Context $ctx -Permission Off | Out-Null
    }

    $tempFile = Join-Path $env:TEMP "$probeId.txt"
    Set-Content -Path $tempFile -Value $probeContent -NoNewline

    Set-AzStorageBlobContent -File $tempFile -Container $containerName `
        -Blob "$probeId.txt" -Context $ctx -Force | Out-Null

    Remove-Item $tempFile -Force
    "Uploaded $probeId.txt to '$containerName'"
}

# 4. Blob download - round-trip proves both directions of the private path
Invoke-Test 'Blob Download' {
    $downloadPath = Join-Path $env:TEMP "$probeId.down.txt"

    Get-AzStorageBlobContent -Container $containerName -Blob "$probeId.txt" `
        -Destination $downloadPath -Context $ctx -Force | Out-Null

    $roundTripped = (Get-Content $downloadPath -Raw).Trim()
    Remove-Item $downloadPath -Force

    if ($roundTripped -ne $probeContent) {
        throw "Content mismatch. Expected '$probeContent', got '$roundTripped'."
    }
    "Round-tripped $($probeContent.Length) bytes intact"
}

# 5. Queue write
Invoke-Test 'Queue Write' {
    $queue = Get-AzStorageQueue -Name $queueName -Context $ctx -ErrorAction SilentlyContinue
    if (-not $queue) { $queue = New-AzStorageQueue -Name $queueName -Context $ctx }

    $queue.QueueClient.SendMessage($probeContent) | Out-Null
    "Enqueued probe message to '$queueName'"
}

# 6. Queue read
Invoke-Test 'Queue Read' {
    $queue    = Get-AzStorageQueue -Name $queueName -Context $ctx
    $received = $queue.QueueClient.ReceiveMessages(1).Value

    if (-not $received) { throw 'No message returned from the queue.' }
    if ($received[0].MessageText -ne $probeContent) {
        throw "Message mismatch. Expected '$probeContent', got '$($received[0].MessageText)'."
    }

    $queue.QueueClient.DeleteMessage($received[0].MessageId, $received[0].PopReceipt) | Out-Null
    "Dequeued and verified probe message"
}

# 7. Table insert
Invoke-Test 'Table Insert' {
    try   { Invoke-TableRest -Method 'POST' -Resource 'Tables' -Body @{ TableName = $tableName } -Token $token | Out-Null }
    catch { if ($_.Exception.Response.StatusCode -ne 409) { throw } }   # 409 = table already exists

    $entity = @{
        PartitionKey = 'validation'
        RowKey       = $probeId
        Content      = $probeContent
        Timestamp    = [DateTime]::UtcNow.ToString('o')
    }

    Invoke-TableRest -Method 'POST' -Resource $tableName -Body $entity -Token $token | Out-Null
    "Inserted entity validation/$probeId"
}

# 8. Table query
Invoke-Test 'Table Query' {
    $entity = Invoke-TableRest -Method 'GET' `
        -Resource "$tableName(PartitionKey='validation',RowKey='$probeId')" -Token $token

    if ($entity.Content -ne $probeContent) {
        throw "Entity mismatch. Expected '$probeContent', got '$($entity.Content)'."
    }
    "Retrieved entity validation/$probeId"
}

# 9 + 10. Control-plane assertions - prove the account really is locked down,
#         so the tests above cannot have passed via the public endpoint.
$account = $null
Invoke-Test 'Public Network Access Disabled' {
    $script:account = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName

    if ($account.PublicNetworkAccess -ne 'Disabled') {
        throw "PublicNetworkAccess is '$($account.PublicNetworkAccess)', expected 'Disabled'."
    }
    'PublicNetworkAccess = Disabled'
}

Invoke-Test 'Shared Key Access Disabled' {
    if ($account.AllowSharedKeyAccess -ne $false) {
        throw "AllowSharedKeyAccess is '$($account.AllowSharedKeyAccess)', expected 'False'."
    }
    'AllowSharedKeyAccess = False'
}

# Cleanup probe artefacts
if ($cleanup) {
    try {
        Remove-AzStorageBlob -Container $containerName -Blob "$probeId.txt" -Context $ctx -Force -ErrorAction SilentlyContinue
        Invoke-TableRest -Method 'DELETE' -Resource "$tableName(PartitionKey='validation',RowKey='$probeId')" -Token $token | Out-Null
    }
    catch { Write-Warning "Cleanup skipped: $($_.Exception.Message)" }
}

# 11. HTML report render
$html = $null
Invoke-Test 'HTML Report Render' {
    $rows = ($results | ForEach-Object {
        $cls = if ($_.result -eq 'PASS') { 'pass' } else { 'fail' }
        $safeDetail = [System.Net.WebUtility]::HtmlEncode($_.detail)
        "      <tr><td>$($_.test)</td><td class='$cls'>$($_.result)</td><td>$($_.durationMs) ms</td><td>$safeDetail</td></tr>"
    }) -join "`n"

    $passed = ($results | Where-Object result -eq 'PASS').Count
    $total  = $results.Count

    $script:html = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Storage Private Endpoint Validation</title>
  <style>
    body   { font-family: Segoe UI, sans-serif; margin: 2rem; background: #faf9f8; color: #201f1e; }
    h1     { margin-bottom: .25rem; }
    .meta  { color: #605e5c; font-size: .9rem; margin-bottom: 1.5rem; }
    table  { border-collapse: collapse; width: 100%; background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,.12); }
    th, td { text-align: left; padding: .6rem .8rem; border-bottom: 1px solid #edebe9; font-size: .9rem; }
    th     { background: #0078d4; color: #fff; }
    .pass  { color: #107c10; font-weight: 600; }
    .fail  { color: #a4262c; font-weight: 600; }
    .summary { margin-top: 1rem; font-weight: 600; }
  </style>
</head>
<body>
  <h1>Storage Private Endpoint Validation</h1>
  <div class="meta">
    Account: <strong>$storageAccountName</strong> &middot;
    Instance: $env:WEBSITE_INSTANCE_ID &middot;
    Plan: $env:WEBSITE_SKU &middot;
    Generated: $([DateTime]::UtcNow.ToString('u'))
  </div>
  <table>
    <thead><tr><th>Test</th><th>Result</th><th>Duration</th><th>Detail</th></tr></thead>
    <tbody>
$rows
    </tbody>
  </table>
  <p class="summary">$passed / $total tests passed.</p>
</body>
</html>
"@

    if ($script:html.Length -lt 100) { throw 'Rendered report was empty.' }
    "Rendered $($script:html.Length) bytes of HTML"
}

$passed  = ($results | Where-Object result -eq 'PASS').Count
$allPass = $passed -eq $results.Count

Write-Host ""
Write-Host "=== Storage validation complete: $passed/$($results.Count) passed ==="

if ($format -eq 'json') {
    $payload = [pscustomobject]@{
        storageAccount      = $storageAccountName
        instanceId          = $env:WEBSITE_INSTANCE_ID
        sku                 = $env:WEBSITE_SKU
        vnetRouteAll        = $env:WEBSITE_VNET_ROUTE_ALL
        contentOverVNet     = $env:WEBSITE_CONTENTOVERVNET
        authMode            = 'ManagedIdentity'
        publicNetworkAccess = $account.PublicNetworkAccess
        allowSharedKeyAccess= $account.AllowSharedKeyAccess
        generatedUtc        = [DateTime]::UtcNow.ToString('u')
        passed              = $passed
        total               = $results.Count
        overall             = if ($allPass) { 'PASS' } else { 'FAIL' }
        tests               = $results
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode  = if ($allPass) { [HttpStatusCode]::OK } else { [HttpStatusCode]::InternalServerError }
        Headers     = @{ 'Content-Type' = 'application/json' }
        Body        = ($payload | ConvertTo-Json -Depth 4)
    })
}
else {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode  = if ($allPass) { [HttpStatusCode]::OK } else { [HttpStatusCode]::InternalServerError }
        Headers     = @{ 'Content-Type' = 'text/html; charset=utf-8' }
        Body        = $html
    })
}
