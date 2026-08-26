<#
.SYNOPSIS
    Demo 07 | Configure Regional VNet Integration
    Onboards a Premium or Dedicated Function App onto a VNet for private,
    outbound (and optionally inbound) connectivity.

.DESCRIPTION
    Creates a VNet with a subnet delegated to Microsoft.Web/serverFarms (the
    delegation Regional VNet Integration requires), enables the integration on
    the Function App, and optionally routes ALL outbound traffic through the
    VNet so on-prem firewalls only ever see the VNet's address space.

    Regional VNet Integration only works on Premium (EP1+) or Dedicated (App
    Service) plans - Consumption is not supported. Pair the result with
    05-Demo-VNetIntegration-Function.ps1 to prove internal connectivity.

.PARAMETER ResourceGroup
    Resource group containing the Function App and the VNet.

.PARAMETER FunctionAppName
    Name of the Function App to integrate (must be Premium or Dedicated).

.PARAMETER VNetName
    Name of the VNet to create or reuse. Defaults to 'vnet-functionapps-bootcamp'.

.PARAMETER SubnetName
    Name of the delegated subnet to create. Defaults to 'snet-func-integration'.

.PARAMETER VNetAddressPrefix
    Address space for the VNet. Defaults to '10.20.0.0/16'.

.PARAMETER SubnetAddressPrefix
    Address space for the delegated subnet. Defaults to '10.20.1.0/24'.

.PARAMETER RouteAllThroughVNet
    When set, routes all outbound traffic (not just RFC1918 ranges) through
    the VNet via WEBSITE_VNET_ROUTE_ALL.

.EXAMPLE
    .\07-Setup-VNetIntegration.ps1 -ResourceGroup rg-functionapps-bootcamp `
        -FunctionAppName func-bootcamp-1234

    Creates the VNet/subnet and integrates the Function App with default names.

.EXAMPLE
    .\07-Setup-VNetIntegration.ps1 -ResourceGroup rg-functionapps-bootcamp `
        -FunctionAppName func-bootcamp-1234 -RouteAllThroughVNet

    Same as above, but forces ALL outbound traffic through the VNet.

.NOTES
    Author  : Matt Balzan | mattbalzan.github.io/My-Site
    Runs on : Your machine (Connect-AzAccount first)
    Modules : Az.Accounts, Az.Network, Az.Websites
    Requires: Function App must be on a Premium (EP1+) or Dedicated plan.
#>

param
(
    [Parameter(Mandatory = $true)]  [string] $ResourceGroup,
    [Parameter(Mandatory = $true)]  [string] $FunctionAppName,
    [string] $VNetName             = 'vnet-functionapps-bootcamp',
    [string] $SubnetName           = 'snet-func-integration',
    [string] $VNetAddressPrefix    = '10.20.0.0/16',
    [string] $SubnetAddressPrefix  = '10.20.1.0/24',
    [switch] $RouteAllThroughVNet
)

$ErrorActionPreference = 'Stop'

# 1. Create the VNet + delegated subnet if they don't already exist
Write-Host "[1/3] VNet '$VNetName'..." -ForegroundColor Cyan
$vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroup -Name $VNetName -ErrorAction SilentlyContinue

if (-not $vnet) {
    $delegation = New-AzDelegation -Name 'delegation-serverfarms' -ServiceName 'Microsoft.Web/serverFarms'

    $subnetConfig = New-AzVirtualNetworkSubnetConfig `
        -Name          $SubnetName `
        -AddressPrefix $SubnetAddressPrefix `
        -Delegation    $delegation

    $vnet = New-AzVirtualNetwork `
        -ResourceGroupName $ResourceGroup `
        -Name              $VNetName `
        -Location          (Get-AzResourceGroup -Name $ResourceGroup).Location `
        -AddressPrefix     $VNetAddressPrefix `
        -Subnet            $subnetConfig
}

# 2. Enable Regional VNet Integration on the Function App
#    (Az.Websites does not expose this directly, so we call the well-documented
#    Azure CLI command from inside the PowerShell script.)
Write-Host "[2/3] Enabling VNet Integration on '$FunctionAppName'..." -ForegroundColor Cyan
az functionapp vnet-integration add `
    --resource-group $ResourceGroup `
    --name            $FunctionAppName `
    --vnet            $VNetName `
    --subnet          $SubnetName | Out-Null

# 3. Optionally route ALL outbound traffic through the VNet
if ($RouteAllThroughVNet) {
    Write-Host "[3/3] Routing all outbound traffic through the VNet..." -ForegroundColor Cyan
    Update-AzFunctionAppSetting -ResourceGroupName $ResourceGroup -Name $FunctionAppName `
        -AppSetting @{ 'WEBSITE_VNET_ROUTE_ALL' = '1' } -Force | Out-Null
}
else {
    Write-Host "[3/3] Skipped - only RFC1918 traffic routes through the VNet by default." -ForegroundColor DarkGray
}

Write-Host "`nDone. Verify with:" -ForegroundColor Green
Write-Host "  az functionapp vnet-integration list --resource-group $ResourceGroup --name $FunctionAppName"
Write-Host "`nThen run the connectivity check:" -ForegroundColor Cyan
Write-Host "  Invoke-RestMethod https://$FunctionAppName.azurewebsites.net/api/Demo-VNetCheck?code=<functionKey>"
