<#
.SYNOPSIS
This script extracts Power BI dataset table metadata (partition names and DAX query definitions) for datasets using the INFO.PARTITIONS() DMV query.

.DESCRIPTION
Unlike existing methods that require enabling the Admin API settings or dataset lineage, this approach works **without either**. It utilizes the `executeQueries` API endpoint with user impersonation and temporary admin rights when required.

.OUTPUT
- `PowerBI_Report_DataSources_v2.csv` (input to the script)
- `workspace_to_dataset.json` (internal JSON structure for processing)
- `workspace_to_dataset_tables.csv` (final output with dataset table metadata)
- Logs: `ErrorLog_tables_v2.txt`, `ErrorLogDetail_tables_v2.txt`
#>

# Load Power BI module and authenticate
Import-Module MicrosoftPowerBIMgmt
Login-PowerBIServiceAccount

# Get access token for REST API calls
$accessToken = Get-PowerBIAccessToken -AsString

# Set paths and configuration
$inputcsvFilePath = "PowerBI_Report_DataSources_v2.csv"
$jsonFilePath_workspace_dataset = "workspace_to_dataset.json"
$json_dataset_tablesFilePath = "workspace_to_dataset_tables.csv"
$errorLogFile = "ErrorLog_tables_v2.txt"
$errorLogFileDetail = "ErrorLogDetail_tables_v2.txt"
$currentUserEmail = "a-hnathbin@ausnetservices.com.au"
$resumeexistingrun = $true
$startProcessing = $false
$ErrorActionPreference = "Stop"

# Step 1: Filter input CSV to include only relevant datasets (e.g., containing 'yourdatawarehouse' in connection)
$dataset_data = Import-Csv -Path $inputcsvFilePath | Where-Object { $_.ConnectionDetails -like '*yourdatawarehouse*' }

# Step 2: Build a hashtable of workspaceId -> datasetIds
$uniqueDataset = $dataset_data | Sort-Object -Property WorkspaceId, DatasetId -Unique
$workspaceDict = @{}
foreach ($row in $uniqueDataset) {
    $workspaceId = $row.WorkspaceId
    $datasetId = $row.DatasetId

    if (-not $workspaceDict.ContainsKey($workspaceId)) {
        $workspaceDict[$workspaceId] = @()
    }
    $workspaceDict[$workspaceId] += $datasetId
}

# Step 3: Serialize and save workspace-to-dataset map
if (-not $resumeexistingrun) {
    $jsonOutput = $workspaceDict | ConvertTo-Json -Depth 2
    Set-Content -Path $jsonFilePath_workspace_dataset -Value $jsonOutput
}

# Deserialize JSON for processing
$jsonObject = Get-Content -Raw -Path $jsonFilePath_workspace_dataset | ConvertFrom-Json

# Prepare API headers
$headers = @{
    "Authorization" = "$accessToken"
    "Content-Type"  = "application/json"
}

# Step 4: Iterate over workspaces and datasets
foreach ($workspaceId in $jsonObject.PSObject.Properties.Name) {
    if ($resumeexistingrun -and -not $startProcessing) {
        if ($workspaceId -eq "10f4c015-0bdd-496d-aa24-816f8f2d663b") {
            $startProcessing = $true
        } else {
            continue
        }
    }

    $datasetIds = $jsonObject.$workspaceId
    $adminAddedFlag = $false

    foreach ($datasetId in $datasetIds) {
        Write-Output "Processing DatasetId: $datasetId in Workspace: $workspaceId"

        $apiUrl = "https://api.powerbi.com/v1.0/myorg/groups/$workspaceId/datasets/$datasetId/executeQueries"
        $payload = @{
            queries = @(@{ query = "EVALUATE INFO.PARTITIONS()" })
            serializerSettings = @{ includeNulls = $true }
            impersonatedUserName = $currentUserEmail
        } | ConvertTo-Json -Depth 10

        try {
            $response = Invoke-RestMethod -Uri $apiUrl -Method 'POST' -Headers $headers -Body $payload
            "Successfully fetched table info for $workspaceId / $datasetId" | Out-File -FilePath $errorLogFileDetail -Append
        } catch {
            # Log failure and attempt temporary admin addition
            "[$(Get-Date)] Error on $workspaceId / $datasetId" | Out-File -FilePath $errorLogFile -Append
            $_.Exception.Message | Out-File -FilePath $errorLogFileDetail -Append

            # Attempt to add current user as admin
            $addUserApi = "https://api.powerbi.com/v1.0/myorg/admin/groups/$workspaceId/users"
            $addUserPayload = @{
                emailAddress = $currentUserEmail
                groupUserAccessRight = "Admin"
            } | ConvertTo-Json -Depth 10

            $null = Invoke-RestMethod -Uri $addUserApi -Method 'POST' -Headers $headers -Body $addUserPayload
            $adminAddedFlag = $true

            # Retry after admin added
            try {
                $response = Invoke-RestMethod -Uri $apiUrl -Method 'POST' -Headers $headers -Body $payload
            } catch {
                "Failed even after admin grant: $($_.Exception.Message)" | Out-File -FilePath $errorLogFileDetail -Append
                continue
            }
        }

        # Parse and export result
        foreach ($result in $response.results) {
            foreach ($table in $result.tables) {
                foreach ($row in $table.rows) {
                    $resultRow = [PSCustomObject]@{
                        WorkspaceId     = $workspaceId
                        DatasetId       = $datasetId
                        PartitionName   = $row.'[Name]'
                        QueryDefinition = $row.'[QueryDefinition]'
                    }
                    $resultRow | Export-Csv -Path $json_dataset_tablesFilePath -NoTypeInformation -Append
                }
            }
        }
    }

    # Step 5: Clean up by removing admin access if added
    if ($adminAddedFlag) {
        try {
            $removeUserApi = "https://api.powerbi.com/v1.0/myorg/admin/groups/$workspaceId/users/$currentUserEmail"
            $null = Invoke-RestMethod -Uri $removeUserApi -Method 'DELETE' -Headers $headers
            "Removed admin rights from $currentUserEmail in workspace $workspaceId" | Out-File -FilePath $errorLogFileDetail -Append
        } catch {
            "Failed to remove admin: $($_.Exception.Message)" | Out-File -FilePath $errorLogFileDetail -Append
        }
    }
}
