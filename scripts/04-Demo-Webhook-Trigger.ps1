<#
.SYNOPSIS
    Demo 04 | Trigger a Function Webhook
    Triggers an Azure Function by POSTing a JSON payload with its function key.

.DESCRIPTION
    Client-side companion to 03-Demo-Webhook-Function.ps1. Builds a JSON
    payload, optionally attaches a shared-secret header, POSTs it to the
    function URL (including the `?code=` function key) and prints the result.

    Unlike an Automation webhook, a function key is NOT single-use and can be
    retrieved again at any time from the portal, Azure CLI, or the
    `listkeys` REST API - but it should still be treated as a secret and never
    committed to source control.

.PARAMETER FunctionUri
    The full function URL including the `?code=<functionKey>` query string.
    Falls back to $env:FUNC_WEBHOOK_URI.

.PARAMETER SharedSecret
    Optional value sent as the 'x-shared-secret' header and validated inside
    the function. Falls back to $env:FUNC_WEBHOOK_SECRET.

.EXAMPLE
    .\04-Demo-Webhook-Trigger.ps1

    Uses $env:FUNC_WEBHOOK_URI to fire the function.

.EXAMPLE
    .\04-Demo-Webhook-Trigger.ps1 -FunctionUri $uri -SharedSecret 'S3cr3t!'

    Fires the function with an explicit URL and shared-secret header.

.NOTES
    Author  : Matt Balzan | mattbalzan.github.io/My-Site
    Runs on : Your machine, a build agent, Power Automate - anything that can POST
#>

param
(
    # Falls back to an environment variable so the URL + key never land in source control
    [Parameter(Mandatory = $false)]
    [string] $FunctionUri = $env:FUNC_WEBHOOK_URI,

    [Parameter(Mandatory = $false)]
    [string] $SharedSecret = $env:FUNC_WEBHOOK_SECRET
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($FunctionUri)) {
    throw "No function URI. Pass -FunctionUri or set `$env:FUNC_WEBHOOK_URI."
}

# 1. Build the payload
$payload = @{
    message     = "Hello from the other side!"
    action      = "send-report"
    target      = "Contoso-Prod"
    environment = "prod"
    requestedBy = $env:USERNAME
    timestamp   = (Get-Date).ToUniversalTime().ToString('o')
}

$body = $payload | ConvertTo-Json -Depth 5

# 2. Optional shared-secret header, validated inside the function
$headers = @{ 'Content-Type' = 'application/json' }
if ($SharedSecret) { $headers['x-shared-secret'] = $SharedSecret }

# 3. POST it - the function key travels in the URI's ?code= query string
$response = Invoke-RestMethod -Method Post -Uri $FunctionUri -Headers $headers -Body $body

# 4. Functions respond synchronously (unlike an Automation webhook's 202/queued model)
Write-Host "Function responded:" -ForegroundColor Green
$response | ConvertTo-Json -Depth 5

Write-Host "`nCheck live execution logs with:" -ForegroundColor Cyan
Write-Host "  func azure functionapp logstream <functionAppName>"
