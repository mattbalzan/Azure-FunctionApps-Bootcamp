<#
.SYNOPSIS
    Demo 06 | Build the whole lab with Az PowerShell
    Builds the complete Azure Functions bootcamp lab in one pass.

.DESCRIPTION
    End-to-end lab build. Creates the resource group, a storage account
    (required by every Function App for triggers/state), an Application
    Insights resource, and a Function App with a System-Assigned Managed
    Identity. Grants that identity least-privilege RBAC scoped to the resource
    group, packages and zip-deploys the demo functions, and prints the
    function key needed to call the HTTP-triggered demos.

    Run it from your own machine after Connect-AzAccount. Tear the lab down
    with Remove-AzResourceGroup.

.PARAMETER ResourceGroup
    Resource group to create or reuse. Defaults to 'rg-functionapps-bootcamp'.

.PARAMETER Location
    Azure region for all resources. Defaults to 'uksouth'.

.PARAMETER FunctionAppName
    Function App name. Defaults to a randomised 'func-bootcamp-NNNN'.

.PARAMETER Plan
    'Consumption' or 'Premium'. Premium is required for VNet Integration
    (see 07-Setup-VNetIntegration.ps1). Defaults to 'Consumption'.

.PARAMETER ScriptPath
    Folder containing the demo function .ps1 files. Defaults to this script's folder.

.EXAMPLE
    .\06-Setup-FunctionApp.ps1

    Builds the lab with all defaults in UK South on the Consumption plan.

.EXAMPLE
    .\06-Setup-FunctionApp.ps1 -ResourceGroup rg-func-demo -Location westeurope -Plan Premium

    Builds the lab with explicit names in West Europe on a Premium plan.

.NOTES
    Author  : Matt Balzan | mattbalzan.github.io/My-Site
    Runs on : Your machine (Connect-AzAccount first)
    Modules : Az.Accounts, Az.Functions, Az.Storage, Az.ApplicationInsights, Az.Resources
    Rights  : Owner or Contributor + User Access Administrator (for the role assignment)
#>

param
(
    [string] $ResourceGroup   = 'rg-functionapps-bootcamp',
    [string] $Location        = 'uksouth',
    [string] $FunctionAppName = "func-bootcamp-$((Get-Random -Maximum 9999))",
    [ValidateSet('Consumption', 'Premium')]
    [string] $Plan            = 'Consumption',
    [string] $ScriptPath      = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

# 1. Resource group
Write-Host "[1/7] Resource group..." -ForegroundColor Cyan
if (-not (Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $ResourceGroup -Location $Location | Out-Null
}

# 2. Storage account (mandatory backing store for every Function App)
Write-Host "[2/7] Storage account..." -ForegroundColor Cyan
$storageName = "stfuncbc$((Get-Random -Maximum 99999))"
$storage = New-AzStorageAccount `
    -ResourceGroupName $ResourceGroup `
    -Name              $storageName `
    -Location          $Location `
    -SkuName           'Standard_LRS' `
    -Kind              'StorageV2'

# 3. Application Insights
Write-Host "[3/7] Application Insights..." -ForegroundColor Cyan
$appInsights = New-AzApplicationInsights `
    -ResourceGroupName $ResourceGroup `
    -Name              "appi-$FunctionAppName" `
    -Location          $Location `
    -Kind              'web'

# 4. Function App with System-Assigned Managed Identity
Write-Host "[4/7] Function App '$FunctionAppName' ($Plan plan)..." -ForegroundColor Cyan
$funcParams = @{
    ResourceGroupName        = $ResourceGroup
    Name                     = $FunctionAppName
    Location                 = $Location
    StorageAccountName       = $storage.StorageAccountName
    Runtime                  = 'PowerShell'
    RuntimeVersion           = '7.2'
    FunctionsVersion         = '4'
    OSType                   = 'Windows'
    ApplicationInsightsName  = $appInsights.Name
    IdentityType             = 'SystemAssigned'
}

if ($Plan -eq 'Premium') {
    $funcParams['PlanName'] = "asp-$FunctionAppName"
    $funcParams['SkuName']  = 'EP1'
}
else {
    $funcParams['PlanLocation'] = $Location  # Consumption plan
}

$functionApp = New-AzFunctionApp @funcParams

Write-Host "      Managed Identity principalId: $($functionApp.IdentityPrincipalId)"

# 5. Grant RBAC to the Managed Identity (least privilege - scope to the RG)
Write-Host "[5/7] RBAC assignment..." -ForegroundColor Cyan
$sub = (Get-AzContext).Subscription.Id
New-AzRoleAssignment `
    -ObjectId           $functionApp.IdentityPrincipalId `
    -RoleDefinitionName 'Virtual Machine Contributor' `
    -Scope              "/subscriptions/$sub/resourceGroups/$ResourceGroup" `
    -ErrorAction SilentlyContinue | Out-Null

# 6. Package and zip-deploy the demo functions
Write-Host "[6/7] Packaging and deploying functions..." -ForegroundColor Cyan
$functions = @(
    @{ Name = 'Demo-HelloWorld';    File = '01-Demo-HelloWorld-Function.ps1';           Trigger = 'httpTrigger'; Methods = @('get','post') }
    @{ Name = 'Demo-StartStopVMs';  File = '02-Demo-ManagedIdentity-StartStopVMs.ps1';  Trigger = 'httpTrigger'; Methods = @('post') }
    @{ Name = 'Demo-WebhookTarget'; File = '03-Demo-Webhook-Function.ps1';              Trigger = 'httpTrigger'; Methods = @('post') }
)

$buildDir = Join-Path ([System.IO.Path]::GetTempPath()) "func-bootcamp-build-$(Get-Random)"
New-Item -ItemType Directory -Path $buildDir | Out-Null

foreach ($fn in $functions) {
    $srcFile = Join-Path $ScriptPath $fn.File
    if (-not (Test-Path $srcFile)) { Write-Warning "Missing $srcFile - skipped"; continue }

    $fnDir = Join-Path $buildDir $fn.Name
    New-Item -ItemType Directory -Path $fnDir | Out-Null
    Copy-Item $srcFile (Join-Path $fnDir 'run.ps1')

    @{
        bindings = @(
            @{ authLevel = 'function'; type = $fn.Trigger; direction = 'in'; name = 'Request'; methods = $fn.Methods }
            @{ type = 'http'; direction = 'out'; name = 'Response' }
        )
    } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $fnDir 'function.json')

    Write-Host "      staged: $($fn.Name)"
}

@{ version = '2.0' } | ConvertTo-Json | Set-Content (Join-Path $buildDir 'host.json')

$zipPath = Join-Path ([System.IO.Path]::GetTempPath()) "func-bootcamp-$(Get-Random).zip"
Compress-Archive -Path "$buildDir\*" -DestinationPath $zipPath -Force

Publish-AzWebApp -ResourceGroupName $ResourceGroup -Name $FunctionAppName -ArchivePath $zipPath -Force | Out-Null
Remove-Item $buildDir, $zipPath -Recurse -Force -ErrorAction SilentlyContinue

# 7. Retrieve the function key for the HelloWorld demo (never one-time, unlike a webhook URL)
Write-Host "[7/7] Retrieving function key..." -ForegroundColor Cyan
$keysUri = "/subscriptions/$sub/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$FunctionAppName/functions/Demo-HelloWorld/listkeys?api-version=2022-03-01"
$keys    = (Invoke-AzRestMethod -Path $keysUri -Method POST).Content | ConvertFrom-Json
$funcUri = "https://$FunctionAppName.azurewebsites.net/api/Demo-HelloWorld?code=$($keys.default)"

Write-Host "`nDone. Test the HelloWorld function with:" -ForegroundColor Green
Write-Host "  Invoke-RestMethod '$funcUri&name=Matt'"
Write-Host "`nTear the lab down with:" -ForegroundColor DarkGray
Write-Host "  Remove-AzResourceGroup -Name $ResourceGroup -Force"
