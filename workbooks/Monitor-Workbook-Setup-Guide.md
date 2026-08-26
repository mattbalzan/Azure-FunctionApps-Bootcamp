# Azure Monitor Workbook — Function Invocation Monitoring Setup Guide

A step-by-step guide to deploying [Function-Monitoring.workbook.json](Function-Monitoring.workbook.json), a workbook that reports Function App invocation outcomes, failure rates, exceptions and runtime cost drivers.

---

## 🎁 What you get

| Tile | Answers |
| ---- | ------- |
| **Invocations by outcome** | How many invocations succeeded or failed? |
| **Invocations over time** | Is the failure rate trending up? |
| **Failure rate by function** | Which function is the problem child? |
| **Recent exceptions** | What was the actual error message? |
| **Longest running invocations** | What is driving my execution-time billing? |
| **Invocations by instance** | How wide is the Function App scaling out? |

---

## ✅ Prerequisites

- A **Function App** with at least one invocation.
- **Application Insights** linked to the Function App — set at creation time, or via the `APPLICATIONINSIGHTS_CONNECTION_STRING` app setting.
- **Permissions**:
  - `Monitoring Contributor` — to create the workbook.
  - `Monitoring Reader` — for anyone who only needs to view it.
- Roughly **5 minutes** of data before the tiles populate.

---

## 1️⃣ Step 1 — Link Application Insights

The workbook reads the `requests` and `exceptions` tables, which only exist once Application Insights is collecting telemetry from the Function App.

**Portal:** Function App → *Settings* → **Application Insights** → *Turn on Application Insights* → pick or create a resource.

**PowerShell:**

```powershell
$appInsights = New-AzApplicationInsights -ResourceGroupName 'rg-functionapps-bootcamp' `
    -Name 'appi-func-bootcamp' -Location 'uksouth' -Kind 'web'

Update-AzFunctionAppSetting -ResourceGroupName 'rg-functionapps-bootcamp' -Name 'func-bootcamp' `
    -AppSetting @{ 'APPLICATIONINSIGHTS_CONNECTION_STRING' = $appInsights.ConnectionString } -Force
```

**Azure CLI:**

```bash
az monitor app-insights component create \
  --app appi-func-bootcamp --resource-group rg-functionapps-bootcamp --location uksouth

az functionapp config appsettings set \
  --name func-bootcamp --resource-group rg-functionapps-bootcamp \
  --settings "APPLICATIONINSIGHTS_CONNECTION_STRING=$CONN_STRING"
```

> **Cost warning:** Application Insights bills on ingested data volume (~£2.76/GB in UK South). Chatty `Write-Host`/`Write-Verbose` output lands in `traces` and can dominate the bill. Configure **sampling** in `host.json` if ingestion cost becomes an issue — you keep statistically representative data for the dashboard while paying for far less of it.

### 🔍 Verify data is flowing

Run this in the Application Insights **Logs** blade. If it returns nothing after ~5 minutes, Application Insights isn't linked, or no invocations have happened yet.

```kusto
requests
| summarize Invocations = count() by bin(timestamp, 5m)
```

---

## 2️⃣ Step 2 — Import the workbook

**Option A — Portal (quickest)**

1. Azure Portal → **Monitor** → **Workbooks** → **+ New**.
2. Click the **</> Advanced Editor** button in the toolbar.
3. Make sure the *Gallery Template* tab is selected.
4. Delete the placeholder JSON and paste the contents of `Function-Monitoring.workbook.json`.
5. Click **Apply**, then **Done Editing**.
6. **Save** — give it a name, pick the subscription, resource group and location.

**Option B — Deploy as code**

Workbooks are ARM resources of type `Microsoft.Insights/workbooks`. The template JSON goes into the `serializedData` property as a **string**, so it must be escaped:

```powershell
$serialized = (Get-Content .\Function-Monitoring.workbook.json -Raw)

New-AzResourceGroupDeployment `
    -ResourceGroupName    'rg-monitoring' `
    -TemplateFile         '.\workbook.bicep' `
    -serializedData       $serialized `
    -workbookDisplayName  'Azure Functions - Invocation Monitoring'
```

Minimal `workbook.bicep`:

```bicep
param location string = resourceGroup().location
param workbookDisplayName string
param serializedData string

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name:     guid(resourceGroup().id, workbookDisplayName)
  location: location
  kind:     'shared'
  properties: {
    displayName:    workbookDisplayName
    serializedData: serializedData
    category:       'workbook'
    version:        '1.0'
  }
}
```

---

## 3️⃣ Step 3 — Set the parameters

At the top of the workbook you'll see three pills:

| Parameter | Notes |
| --------- | ----- |
| **Time range** | Defaults to 24 hours. Also controls the `bin()` grain on the trend chart. |
| **Application Insights resource** | Multi-select — point it at every Function App you want to compare. |
| **Function** | Multi-select with an *All* option, populated from the data itself. |

Once set, use **Save** again so the selections persist as the workbook defaults.

---

## 4️⃣ Step 4 — Alert on what matters

The workbook is for looking; alerts are for being told. Create a log search alert from the same query:

```kusto
requests
| where success == "False"
| summarize Failures = count() by name
```

Portal → **Monitor** → **Alerts** → *New alert rule* → scope the Application Insights resource → paste the query → threshold `Failures > 0` → evaluate every 5 minutes over a 15-minute window → action group of your choice (email, Teams, webhook, or another function).

---

## 📖 Reference — the queries behind each tile

| Tile | Table | Key filter |
| ---- | ----- | ---------- |
| Invocations by outcome | `requests` | `iff(success == "True", "Succeeded", "Failed")` |
| Invocations over time | `requests` | as above, binned by `{TimeRange:grain}` |
| Failure rate by function | `requests` | `countif(success == "False")` |
| Recent exceptions | `exceptions` | `project timestamp, operation_Name, type, outermost_message` |
| Longest running invocations | `requests` | `order by duration desc` |
| Invocations by instance | `requests` | `summarize count() by cloud_RoleInstance` |

Useful columns in `requests` for Functions:

| Column | Meaning |
| ------ | ------- |
| `name` | Name of the function that was invoked |
| `success` | `"True"` or `"False"` |
| `resultCode` | HTTP status code for HTTP triggers, or a runtime result code |
| `duration` | Execution time in milliseconds |
| `cloud_RoleName` | The Function App name |
| `cloud_RoleInstance` | The specific worker instance that handled the invocation |
| `operation_Id` | Correlates every telemetry item for a single invocation |

---

## 🔧 Troubleshooting

| Symptom | Cause / fix |
| ------- | ----------- |
| All tiles empty | Application Insights not linked, or no invocations in the selected time range. Run the verify query in Step 1. |
| Function pill shows no options | No `requests` data yet, or the Application Insights resource parameter is unset. |
| Exceptions tile empty but failures exist | Some failures (e.g. bad HTTP input) surface as `resultCode` on `requests` rather than an `exceptions` row — check the failure rate tile instead. |
| Duration looks wrong for Consumption plan | Cold starts add latency to the first invocation after idle; filter or annotate separately if comparing warm vs cold performance. |
| Workbook saves but is empty for colleagues | They need `Monitoring Reader` on the Application Insights resource, not just access to the workbook. |
| High ingestion cost | Enable **sampling** in `host.json`, or reduce `Write-Host`/`Write-Verbose` volume — both land in `traces` and add up quickly on chatty functions. |

---

## 🖼️ Demo Report

_Add a screenshot of your deployed workbook here (e.g. `images/workbook-demo.png`) once you have real data flowing._
