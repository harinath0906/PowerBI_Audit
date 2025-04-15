# PowerShell Script: Audit Power BI Reports, Datasets, and Dataflows
# Author: Hari Nath Bingi (havinath@gmail.com)
# Description:
#   This script connects to the Power BI Service, retrieves all reports, datasets,
#   and dataflows across all workspaces, and logs the associated data sources to a CSV file.
#   Useful for audits, governance, and migrations.

# Load Power BI PowerShell module
Import-Module MicrosoftPowerBIMgmt

# Authenticate to Power BI Service
Connect-PowerBIServiceAccount

# Initialize results array to store audit data
$results = @()

# Define paths for error logs
$errorLogFile = "ErrorLog_v2.txt"
$errorLogFileDetail = "ErrorLogDetail_v2.txt"

# Get all workspaces in the organization (requires admin privileges)
$workspaces = Get-PowerBIWorkspace -Scope Organization -All

# Iterate through each workspace
foreach ($workspace in $workspaces) {
    $workspaceId = $workspace.Id
    $workspaceName = $workspace.Name

    Write-Host "`nProcessing Workspace: $workspaceName"

    # --- REPORT & DATASET PROCESSING ---
    try {
        # Get all reports in the workspace
        $reports = Get-PowerBIReport -WorkspaceId $workspaceId
    } catch {
        # Log error if report retrieval fails
        $errorMessage = "[$(Get-Date)] Error in workspace: $workspaceName"
        $errorMessage | Out-File -FilePath $errorLogFile -Append

        $detailedErrorMessage = @"
[$(Get-Date)] Error in workspace: $workspaceName
Message: $($_.Exception.Message)
Stack Trace: $($_.Exception.StackTrace)
"@
        $detailedErrorMessage | Out-File -FilePath $errorLogFileDetail -Append
        continue
    }

    foreach ($report in $reports) {
        $reportName = $report.Name
        $datasetId = $report.DatasetId
        Write-Host "`nReport: $reportName"

        # Get dataset linked to the report
        $dataset = Get-PowerBIDataset -WorkspaceId $workspaceId | Where-Object { $_.Id -eq $datasetId }

        if ($dataset) {
            Write-Host "Dataset: $($dataset.Name)"

            # Get data sources used in the dataset
            $dataSources = Get-PowerBIDatasource -WorkspaceId $workspaceId -DatasetId $dataset.Id

            if ($dataSources.Count -eq 0) {
                Write-Host "No Data Sources found, adding empty datasource."
                $dataSources = @([PSCustomObject]@{
                    Name = "No Data Source"
                    Type = "None"
                })
            }

            foreach ($dataSource in $dataSources) {
                Write-Host "  DataSource: $($dataSource.Name), Type: $($dataSource.Type)"

                # Store result for output
                $results += [PSCustomObject]@{
                    WorkspaceName = $workspaceName
                    WorkspaceId   = $workspaceId
                    ReportName    = $reportName
                    DatasetName   = $dataset.Name
                    DataSource    = $dataSource.Name
                    DataSourceType = $dataSource.Type
                }
            }
        } else {
            Write-Host "No Dataset found for this report."
        }
    }

    # --- DATAFLOW PROCESSING ---
    $dataflows = Get-PowerBIDataflow -WorkspaceId $workspaceId

    foreach ($dataflow in $dataflows) {
        $dataflowName = $dataflow.Name
        Write-Host "`nDataflow: $dataflowName"

        # Get data sources associated with the dataflow
        $dataflowDataSources = Get-PowerBIDataflowDatasource -WorkspaceId $workspaceId -DataflowId $dataflow.Id

        if ($dataflowDataSources.Count -eq 0) {
            Write-Host "No Data Sources found for Dataflow, adding empty datasource."
            $dataflowDataSources = @([PSCustomObject]@{
                Name = "No Data Source"
                Type = "None"
            })
        }

        foreach ($dataSource in $dataflowDataSources) {
            Write-Host "  DataSource: $($dataSource.Name), Type: $($dataSource.Type)"

            # Store result for output
            $results += [PSCustomObject]@{
                WorkspaceName  = $workspaceName
                WorkspaceId    = $workspaceId
                DataflowName   = $dataflowName
                DataSource     = $dataSource.Name
                DataSourceType = $dataSource.Type
            }
        }
    }
}

# --- EXPORT RESULTS TO CSV ---

$csvFilePath = "PowerBI_Report_DataSources_and_Dataflows.csv"
$results | Export-Csv -Path $csvFilePath -NoTypeInformation

Write-Host "`n✅ Completed processing all workspaces, reports, and dataflows."
Write-Host "📄 Results saved to: $csvFilePath"
