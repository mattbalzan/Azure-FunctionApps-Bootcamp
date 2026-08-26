<#
.SYNOPSIS
    Demo 02 | Start / Stop VMs by Tag
    Starts or stops every VM carrying a given tag, using a Managed Identity.

.DESCRIPTION
    The classic Azure cost-saver, as an HTTP-triggered function. Authenticates
    with the Function App's System-Assigned Managed Identity (no secrets,
    nothing to rotate), finds all VMs matching a tag name/value pair, and
    starts or deallocates them.

    VMs already in the requested power state are skipped, and every action is
    returned as a JSON summary in the response body. Pair it with a Timer
    trigger function (or two schedules) - one calling with `Action=Start` at
    07:00 and one with `Action=Stop` at 19:00.

    `function.json` for this HTTP-triggered function:

        {
          "bindings": [
            { "authLevel": "function", "type": "httpTrigger", "direction": "in",
              "name": "Request", "methods": [ "post" ] },
            { "type": "http", "direction": "out", "name": "Response" }
          ]
        }

.PARAMETER Request
    Supplied automatically by the Azure Functions host. Expects a JSON body:
    `{ "action": "Start|Stop", "tagName": "AutoShutdown", "tagValue": "true", "whatIf": false }`.

.EXAMPLE
    Invoke-RestMethod -Method Post `
        -Uri "https://func-bootcamp.azurewebsites.net/api/Demo-StartStopVMs?code=<functionKey>" `
        -Body (@{ action = 'Stop' } | ConvertTo-Json) -ContentType 'application/json'

    Deallocates every VM tagged AutoShutdown=true.

.NOTES
    Author  : Matt Balzan | mattbalzan.github.io/My-Site
    Runs on : Consumption or Premium plan (PowerShell 7.2)
    Modules : Az.Accounts, Az.Compute (declared in requirements.psd1)
    Identity: System-Assigned Managed Identity with 'Virtual Machine Contributor'
              on the target scope.
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

$action   = $Request.Body.action
$tagName  = if ($Request.Body.tagName)  { $Request.Body.tagName }  else { 'AutoShutdown' }
$tagValue = if ($Request.Body.tagValue) { $Request.Body.tagValue } else { 'true' }
$whatIf   = [bool]$Request.Body.whatIf

if ($action -notin @('Start', 'Stop')) {
    Write-JsonResponse -StatusCode ([HttpStatusCode]::BadRequest) -Body @{ error = "action must be 'Start' or 'Stop'" }
    return
}

# 1. Managed Identity is already signed in for PowerShell functions when
#    "identity" is configured in host.json / the Function App has System-Assigned identity enabled.
Write-Host "Using System-Assigned Managed Identity ($((Get-AzContext).Account.Id))"

# 2. Find tagged VMs
$vms = Get-AzVM -Status | Where-Object { $_.Tags[$tagName] -eq $tagValue }

if (-not $vms) {
    Write-JsonResponse -StatusCode ([HttpStatusCode]::OK) -Body @{ message = "No VMs found with tag $tagName=$tagValue" }
    return
}

Write-Host "Found $($vms.Count) VM(s) tagged $tagName=$tagValue."

# 3. Act
$results = foreach ($vm in $vms) {

    $powerState = ($vm.PowerState -replace 'VM ', '')
    $needsWork  = ($action -eq 'Start' -and $powerState -ne 'running') -or
                  ($action -eq 'Stop'  -and $powerState -eq 'running')

    if (-not $needsWork) {
        [pscustomobject]@{ vm = $vm.Name; result = "skipped - already $powerState" }
        continue
    }

    if ($whatIf) {
        [pscustomobject]@{ vm = $vm.Name; result = "whatif - would $action" }
        continue
    }

    try {
        if ($action -eq 'Start') {
            Start-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name | Out-Null
        }
        else {
            Stop-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Force | Out-Null
        }
        [pscustomobject]@{ vm = $vm.Name; result = "$($action)ed" }
    }
    catch {
        Write-Error "[fail] $($vm.Name): $($_.Exception.Message)"
        [pscustomobject]@{ vm = $vm.Name; result = "failed - $($_.Exception.Message)" }
    }
}

Write-JsonResponse -StatusCode ([HttpStatusCode]::OK) -Body @{ action = $action; count = $results.Count; results = $results }
