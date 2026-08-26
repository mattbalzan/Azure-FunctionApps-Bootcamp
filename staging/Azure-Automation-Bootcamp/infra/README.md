# 🏗️ Infrastructure as Code

Bicep deployment for the Azure Automation bootcamp lab — the declarative
equivalent of `scripts/06-Setup-AutomationAccount.ps1`.

| File | Purpose |
| ---- | ------- |
| [main.bicep](main.bicep) | Orchestrator — wires the modules together |
| [main.bicepparam](main.bicepparam) | Parameter file with commented defaults |
| [modules/automationAccount.bicep](modules/automationAccount.bicep) | Automation Account, Managed Identity, runbooks, schedule, hybrid worker group, diagnostic settings |
| [modules/monitoring.bicep](modules/monitoring.bicep) | Log Analytics workspace |
| [modules/rbac.bicep](modules/rbac.bicep) | Least-privilege role assignments for the Managed Identity |

---

## 🚀 Deploy

```powershell
az group create --name rg-automation-bootcamp --location uksouth

az deployment group create `
    --resource-group rg-automation-bootcamp `
    --template-file  infra/main.bicep `
    --parameters     infra/main.bicepparam
```

---

## 📊 Diagnostics are wired up for you

The most common reason the [Runbook-Monitoring workbook](../workbooks/Runbook-Monitoring.workbook.json)
shows nothing is that diagnostic settings were never enabled — `AzureDiagnostics`
stays empty until they are. This template creates them as part of the
deployment, streaming both categories to the workspace:

| Category | Contains | Cost impact |
| -------- | -------- | ----------- |
| `JobLogs` | Job start/stop/outcome records | Small — keep this |
| `JobStreams` | Every `Write-Output` line your runbooks emit | Usually the bulk of the bill |

If ingestion cost bites, set `enabled: false` on `JobStreams` in
[modules/automationAccount.bicep](modules/automationAccount.bicep). You keep every
workbook tile except the error-message stream.

---

## 📚 Runbooks

Runbooks are imported directly from the repo's raw GitHub URLs via
`publishContentLink`, so redeploying re-pulls the latest published version — no
manual import, no zip packaging:

| Runbook | Source |
| ------- | ------ |
| `01-Demo-HelloWorld-Runbook` | Smoke test |
| `02-Demo-ManagedIdentity-StartStopVMs` | Start/stop VMs by tag |
| `03-Demo-Webhook-Runbook` | Webhook payload receiver |
| `05-Demo-HybridWorker-Runbook` | Inventory + connectivity test |

> 🔹 `04-Demo-Webhook-Trigger.ps1` is deliberately **not** imported — it's a
> client-side script you run from your own machine, not a runbook.

---

## 🔑 What the Managed Identity gets

| Role | Scope | Why |
| ---- | ----- | --- |
| Virtual Machine Contributor | Resource group | Start/stop VM demo (toggle with `grantVmContributor`) |
| Log Analytics Reader | Workspace | Lets runbooks query their own job telemetry |
| Reader | Resource group | Resource enumeration in the hybrid worker demo |

Graph API permissions (Intune, Entra governance scenarios) are **not** covered
here — role assignments in Bicep can't grant app roles on Microsoft Graph. Use
the script linked from the main Readme after deploying.

---

## ⚠️ Known deployment quirks

| Issue | Fix |
| ----- | --- |
| `Schedule start time must be at least 5 minutes in the future` | The default is `utcNow() + 2h`. Redeploying much later can trip this — pass `scheduleStartTime` explicitly |
| Redeploy creates duplicate job schedules | Avoided here by deriving the job schedule name from `guid()` rather than `newGuid()` |
| Webhooks aren't deployed | ARM returns a webhook URI exactly once at creation and it can't be retrieved later, so it's a poor fit for IaC. Create it with `04-Demo-Webhook-Trigger.ps1` |
| Modules (Az, Graph) aren't deployed | Module import is slow and version-sensitive — do it post-deployment |

---

## 🧹 Tear down

```powershell
az group delete --name rg-automation-bootcamp --yes --no-wait
```
