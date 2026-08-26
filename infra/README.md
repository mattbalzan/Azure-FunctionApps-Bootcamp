# 🏗️ Infrastructure as Code

Bicep deployment for the Azure Functions bootcamp lab. The same template builds
either a simple public lab or the **locked-down reference architecture** from
[docs/Storage-Private-Endpoints.md](../docs/Storage-Private-Endpoints.md),
controlled by a single parameter.

| File | Purpose |
| ---- | ------- |
| [main.bicep](main.bicep) | Orchestrator — wires the modules together |
| [main.bicepparam](main.bicepparam) | Parameter file with commented defaults |
| [modules/network.bicep](modules/network.bicep) | VNet, delegated integration subnet, private endpoint subnet, NSG |
| [modules/storage.bicep](modules/storage.bicep) | Storage account, 4 private endpoints, 4 private DNS zones + links |
| [modules/monitoring.bicep](modules/monitoring.bicep) | Log Analytics workspace + workspace-based Application Insights |
| [modules/functionApp.bicep](modules/functionApp.bicep) | Hosting plan, Function App, Managed Identity, VNet integration |
| [modules/rbac.bicep](modules/rbac.bicep) | Least-privilege role assignments for the Managed Identity |

---

## 🚀 Deploy

```powershell
az group create --name rg-functionapps-bootcamp --location uksouth

az deployment group create `
    --resource-group rg-functionapps-bootcamp `
    --template-file  infra/main.bicep `
    --parameters     infra/main.bicepparam
```

Preview changes first with `--what-if` — worth doing, because the integration
subnet cannot be resized after the fact:

```powershell
az deployment group what-if `
    --resource-group rg-functionapps-bootcamp `
    --template-file  infra/main.bicep `
    --parameters     infra/main.bicepparam
```

---

## 🎛️ The parameter that changes everything

| `enablePrivateNetworking` | What you get |
| ------------------------- | ------------ |
| `true` (default) | VNet + delegated subnet, 4 private endpoints, 4 private DNS zones, `WEBSITE_VNET_ROUTE_ALL=1`, `WEBSITE_CONTENTOVERVNET=1`, and storage with **public network access disabled** |
| `false` | Storage, App Insights and Function App only — no networking. Cheapest way to run demos 01–04 |

> 🔹 Private networking is automatically skipped when `planType` is
> `Consumption`, because the Y1 plan cannot do Regional VNet Integration. That's
> a guard rail, not a bug — you'd otherwise pay for a topology the app can never use.

---

## 🔑 What the Managed Identity gets

Scoped to the storage account, not the subscription:

| Role | Why |
| ---- | --- |
| Storage Blob Data Owner | Blob read/write for demos and Durable state |
| Storage Queue Data Contributor | Queue triggers and Durable control queues |
| Storage Table Data Contributor | Durable history and the validation table tests |
| Storage File Data Privileged Contributor | Content share access when running over the VNet |
| Reader | Control-plane assertions in [08-Demo-StorageTest.ps1](../scripts/08-Demo-StorageTest.ps1) |
| Monitoring Metrics Publisher | Scoped to Application Insights only |

`Virtual Machine Contributor` is granted at resource group scope **only** when
`grantVmContributor = true`, since it's needed just for the start/stop VM demo.

---

## ✅ Validate after deploying

The deployment outputs a ready-made validation URL:

```powershell
$outputs = (az deployment group show `
    --resource-group rg-functionapps-bootcamp `
    --name main --query properties.outputs | ConvertFrom-Json)

$outputs.validationEndpoint.value
```

Deploy [08-Demo-StorageTest.ps1](../scripts/08-Demo-StorageTest.ps1), call that
endpoint, and you should get `"overall": "PASS"` across all 11 tests. See
[End-to-End Validation Results](../docs/Storage-Private-Endpoints.md#-end-to-end-validation-results).

---

## 🧹 Tear down

```powershell
az group delete --name rg-functionapps-bootcamp --yes --no-wait
```

> 🔹 Private DNS zones occasionally survive a resource group delete if another
> VNet link still references them. Check with
> `az network private-dns zone list -g rg-functionapps-bootcamp -o table`.

---

## 💰 Cost note

The locked-down topology is **not** the cheap option:

| Item | Rough cost |
| ---- | ---------- |
| EP1 Elastic Premium plan | ~£100+/month — always-warm, billed continuously |
| 4 × private endpoints | Per endpoint/hour + data processed |
| 4 × private DNS zones | Pennies |
| Log Analytics / App Insights | Ingestion-based, usually the surprise |

Set `enablePrivateNetworking = false` and `planType = 'Consumption'` when you're
just running the basic demos.
