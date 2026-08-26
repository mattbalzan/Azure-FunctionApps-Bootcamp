<#
.SYNOPSIS
    Demo 01 | Hello World Function
    Smoke-test HTTP-triggered function that proves a new Function App can run.

.DESCRIPTION
    The "does it even run?" function. Writes a greeting plus useful invocation
    context (UTC time, PowerShell version, instance name) and demonstrates the
    Information, Verbose and Warning streams, each of which lands in Application
    Insights `traces` with a different severity level.

    This is the `run.ps1` body for an HTTP-triggered function. Pair it with a
    `function.json` alongside it:

        {
          "bindings": [
            { "authLevel": "function", "type": "httpTrigger", "direction": "in",
              "name": "Request", "methods": [ "get", "post" ] },
            { "type": "http", "direction": "out", "name": "Response" }
          ]
        }

    Runs on the Consumption plan on PowerShell 7.2 and requires no identity, so
    it is the fastest way to confirm a new Function App is healthy before
    building anything complicated on top of it.

.PARAMETER Request
    Supplied automatically by the Azure Functions host. Query string or JSON
    body may contain a `name` property to greet.

.EXAMPLE
    Invoke-RestMethod "https://func-bootcamp.azurewebsites.net/api/Demo-HelloWorld?code=<functionKey>&name=Matt"

    Calls the function over HTTP with a custom greeting.

.NOTES
    Author  : Matt Balzan | mattbalzan.github.io/My-Site
    Runs on : Consumption plan (PowerShell 7.2)
    Identity: None required
#>

using namespace System.Net

param
(
    [Parameter(Mandatory = $true)]
    $Request,

    $TriggerMetadata
)

$ErrorActionPreference = 'Stop'

$name = $Request.Query.Name
if (-not $name -and $Request.Body) { $name = $Request.Body.name }
if (-not $name) { $name = 'Bootcamp' }

Write-Host "Hello, $name!"

# Useful context to log on every invocation
Write-Host "UTC time        : $((Get-Date).ToUniversalTime().ToString('u'))"
Write-Host "PS version      : $($PSVersionTable.PSVersion)"
Write-Host "Instance        : $env:WEBSITE_INSTANCE_ID"

# Each stream lands in Application Insights `traces` with a different severity
Write-Verbose "Verbose stream (enable 'Detailed error logging' to see this)" -Verbose
Write-Warning "Warning stream - shows up as SeverityLevel 2 in traces"

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body       = "Hello, $name! Function App is healthy."
})
