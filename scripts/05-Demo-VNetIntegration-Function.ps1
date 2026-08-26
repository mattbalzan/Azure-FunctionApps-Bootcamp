<#
.SYNOPSIS
    Demo 05 | VNet-Integrated Function
    Health and inventory function that reaches internal (on-prem/private)
    resources via Regional VNet Integration.

.DESCRIPTION
    Runs on a Premium or Dedicated (App Service) plan with Regional VNet
    Integration enabled, giving the function outbound line-of-sight into a
    VNet - and from there, via VPN/ExpressRoute, to on-premises networks. This
    is the Functions equivalent of a Hybrid Runbook Worker: reach.

    Reports the instance's OS build/uptime, tests TCP connectivity to an
    internal endpoint that is NOT reachable from a Consumption plan without
    VNet integration, and lists the outbound IP the traffic will appear from.

    Timer-triggered so it runs unattended as a recurring health check.
    `function.json`:

        {
          "bindings": [
            { "name": "Timer", "type": "timerTrigger", "direction": "in", "schedule": "0 */15 * * * *" }
          ]
        }

.PARAMETER InternalEndpoint
    Hostname to TCP-test from inside the VNet. Defaults to 'dc01.contoso.local'.

.PARAMETER Port
    Port to test on the internal endpoint. Defaults to 389 (LDAP).

.NOTES
    Author  : Matt Balzan | mattbalzan.github.io/My-Site
    Runs on : Premium (EP1+) or Dedicated plan with Regional VNet Integration
              (see 07-Setup-VNetIntegration.ps1). Not available on Consumption.
    Identity: The Function App's own context. With a System-Assigned Managed
              Identity, Connect-AzAccount -Identity works here too.
#>

param
(
    [Parameter(Mandatory = $false)]
    [string] $InternalEndpoint = 'dc01.contoso.local',

    [Parameter(Mandatory = $false)]
    [int] $Port = 389
)

$ErrorActionPreference = 'Stop'

Write-Host "=== VNet-integrated job starting ==="
Write-Host "Instance        : $env:WEBSITE_INSTANCE_ID"
Write-Host "Plan            : $env:WEBSITE_SKU"
Write-Host "VNet route all  : $env:WEBSITE_VNET_ROUTE_ALL"
Write-Host ""

# 1. OS + uptime (same host info as any Windows worker)
$os = Get-CimInstance Win32_OperatingSystem
Write-Host "OS              : $($os.Caption) $($os.Version)"
Write-Host "Last boot       : $($os.LastBootUpTime)"
Write-Host ""

# 2. Internal connectivity - the whole reason you use VNet Integration
Write-Host "--- Connectivity ---"
$test = Test-NetConnection -ComputerName $InternalEndpoint -Port $Port -WarningAction SilentlyContinue
if ($test.TcpTestSucceeded) {
    Write-Host "Reached $InternalEndpoint on port $Port"
}
else {
    Write-Warning "Could NOT reach $InternalEndpoint on port $Port - check VNet Integration, NSGs and DNS."
}
Write-Host ""

# 3. Outbound IP - useful when whitelisting this Function App on an internal firewall
Write-Host "--- Outbound identity ---"
try {
    $outboundIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 5)
    Write-Host "Public outbound IP: $outboundIp (only relevant if NOT routing all traffic through the VNet)"
}
catch {
    Write-Warning "Could not resolve outbound IP: $($_.Exception.Message)"
}

Write-Host "=== VNet-integrated job complete ==="
