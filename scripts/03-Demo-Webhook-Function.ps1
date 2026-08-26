<#
.SYNOPSIS
    Demo 03 | Webhook Receiver Function
    HTTP-triggered function that receives a webhook payload (Event Grid, GitHub,
    Teams, Power Automate, or any system that can POST JSON).

.DESCRIPTION
    Every HTTP-triggered function is already a webhook endpoint, secured by its
    function key (`?code=...` or `x-functions-key` header). This demo goes one
    step further and validates an optional shared-secret header, parses the
    JSON body and branches on an 'action' property - the same pattern used for
    Event Grid custom topics or generic SaaS webhooks.

    Fire it with 04-Demo-Webhook-Trigger.ps1.

    Security note: the function key *is* the credential. Anyone holding it can
    call this function, so treat it like a password, rotate it periodically,
    and validate a shared secret header as shown below for defence in depth.

    `function.json` for this HTTP-triggered function:

        {
          "bindings": [
            { "authLevel": "function", "type": "httpTrigger", "direction": "in",
              "name": "Request", "methods": [ "post" ] },
            { "type": "http", "direction": "out", "name": "Response" }
          ]
        }

.PARAMETER Request
    Supplied automatically by the Azure Functions host. Body must be JSON.

.EXAMPLE
    Invoke-RestMethod -Method Post `
        -Uri "https://func-bootcamp.azurewebsites.net/api/Demo-WebhookTarget?code=<functionKey>" `
        -Body (@{ message = 'Hi'; action = 'send-report'; target = 'Contoso-Prod' } | ConvertTo-Json)

    Triggers the function and requests the 'send-report' branch.

.NOTES
    Author  : Matt Balzan | mattbalzan.github.io/My-Site
    Runs on : Consumption or Premium plan (PowerShell 7.2)
    Identity: None required for the demo
    Optional: Create an app setting named 'WebhookSharedSecret' (or a Key Vault
              reference) to enable shared-secret validation.
#>

using namespace System.Net

param
(
    [Parameter(Mandatory = $true)]
    $Request,

    $TriggerMetadata
)

$ErrorActionPreference = 'Stop'

function Write-JsonResponse ([int] $StatusCode, [object] $Body) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Headers    = @{ 'Content-Type' = 'application/json' }
        Body       = ($Body | ConvertTo-Json -Depth 5)
    })
}

# 1. Optional shared-secret check (defence in depth on top of the function key)
#    Store the expected value as an app setting - or better, a Key Vault reference.
$expectedSecret = $env:WebhookSharedSecret
if ($expectedSecret) {
    $presented = $Request.Headers.'x-shared-secret'
    if ($presented -ne $expectedSecret) {
        Write-JsonResponse -StatusCode ([HttpStatusCode]::Unauthorized) -Body @{ error = 'invalid or missing x-shared-secret header' }
        return
    }
    Write-Host "Shared secret   : validated"
}

# 2. Parse the payload (Functions already deserializes JSON bodies into $Request.Body)
$payload = $Request.Body
if (-not $payload) {
    Write-JsonResponse -StatusCode ([HttpStatusCode]::BadRequest) -Body @{ error = 'request body was empty or not valid JSON' }
    return
}

Write-Host "Message         : $($payload.message)"
Write-Host "Environment     : $($payload.environment)"
Write-Host "Requested by    : $($payload.requestedBy)"

# 3. Do the work
$outcome = switch ($payload.action) {
    'restart-service' { "Would restart service '$($payload.target)'" }
    'send-report'     { "Would generate report for '$($payload.target)'" }
    default           { 'No action requested - payload logged only.' }
}

Write-JsonResponse -StatusCode ([HttpStatusCode]::OK) -Body @{
    outcome     = $outcome
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}
