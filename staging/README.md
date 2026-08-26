# 📦 Staged for another repository

The contents of this folder are **not part of Azure-FunctionApps-Bootcamp**.

[Azure-Automation-Bootcamp](https://github.com/mattbalzan/Azure-Automation-Bootcamp)
wasn't open in the workspace when these files were written, so the Bicep
deployment for it was staged here instead.

## To move it across

```powershell
# From the root of a local clone of Azure-Automation-Bootcamp
Copy-Item -Path '<path-to>/Azure-FunctionApps-Bootcamp/staging/Azure-Automation-Bootcamp/infra' `
          -Destination . -Recurse
```

Then delete this `staging/` folder from the Functions repo.

## What was assumed

The templates were written against the public Readme of the Automation repo, so
double-check these before deploying:

| Assumption | Where |
| ---------- | ----- |
| Runbook filenames match `scripts/0*-Demo-*.ps1` | [infra/modules/automationAccount.bicep](Azure-Automation-Bootcamp/infra/modules/automationAccount.bicep) |
| Runbooks are PowerShell 7.2 (`PowerShell72`) | Same file — change to `PowerShell` for 5.1 |
| Default names `aa-bootcamp` / `law-bootcamp` | [infra/main.bicepparam](Azure-Automation-Bootcamp/infra/main.bicepparam) |
| Region `uksouth` | Same file |
