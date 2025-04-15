# 🔍 Power BI Audit Script

This PowerShell script connects to your Power BI Service, retrieves all reports, datasets, and dataflows across your tenant's workspaces, and logs their associated data sources into a CSV file.

## ✅ Features

- Authenticates using `Connect-PowerBIServiceAccount`
- Loops through all Power BI workspaces (Organization scope)
- Audits reports and datasets with their data sources
- Audits dataflows and their data sources
- Logs errors and detailed traces
- Exports results to `PowerBI_Report_DataSources_and_Dataflows.csv`

## 📦 Requirements

- Power BI PowerShell Module:
  ```powershell
  Install-Module -Name MicrosoftPowerBIMgmt
Admin privileges in Power BI Service

## Usage
Run PowerShell as Administrator
Execute the script
./Audit-PowerBI.ps1

## Output
PowerBI_Report_DataSources_and_Dataflows.csv – Main audit data
ErrorLog_v2.txt – Basic error log
ErrorLogDetail_v2.txt – Detailed exception trace

