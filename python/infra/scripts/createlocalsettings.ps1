$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\local.settings.json")) {

    $output = azd env get-values

    # Parse the output to get the endpoint values
    foreach ($line in $output) {
        if ($line -match "COSMOS_CONNECTION__accountEndpoint"){
            $COSMOS_CONNECTION__accountEndpoint = ($line -split "=")[1] -replace '"',''
        }
        if ($line -match "COSMOS_DATABASE_NAME"){
            $COSMOS_DATABASE_NAME = ($line -split "=")[1] -replace '"',''
        }
        if ($line -match "COSMOS_CONTAINER_NAME"){
            $COSMOS_CONTAINER_NAME = ($line -split "=")[1] -replace '"',''
        }
        if ($line -match "COSMOS_VECTOR_PROPERTY"){
            $COSMOS_VECTOR_PROPERTY = ($line -split "=")[1] -replace '"',''
        }
        if ($line -match "COSMOS_HASH_PROPERTY"){
            $COSMOS_HASH_PROPERTY = ($line -split "=")[1] -replace '"',''
        }
        if ($line -match "COSMOS_PROPERTY_TO_EMBED"){
            $COSMOS_PROPERTY_TO_EMBED = ($line -split "=")[1] -replace '"',''
        }
        if ($line -match "OPENAI_ENDPOINT"){
            $OPENAI_ENDPOINT = ($line -split "=")[1] -replace '"',''
        }
        if ($line -match "OPENAI_DEPLOYMENT_NAME"){
            $OPENAI_DEPLOYMENT_NAME = ($line -split "=")[1] -replace '"',''
        }
        if ($line -match "OPENAI_DIMENSIONS"){
            $OPENAI_DIMENSIONS = ($line -split "=")[1] -replace '"',''
        }
    }

    @{
        "IsEncrypted" = "false";
        "Values" = @{
            "AzureWebJobsStorage" = "UseDevelopmentStorage=true";
            "FUNCTIONS_WORKER_RUNTIME" = "python";
            "COSMOS_CONNECTION__accountEndpoint" = "$COSMOS_CONNECTION__accountEndpoint";
            "COSMOS_DATABASE_NAME" = "$COSMOS_DATABASE_NAME";
            "COSMOS_CONTAINER_NAME" = "$COSMOS_CONTAINER_NAME";
            "COSMOS_VECTOR_PROPERTY" = "$COSMOS_VECTOR_PROPERTY";
            "COSMOS_HASH_PROPERTY" = "$COSMOS_HASH_PROPERTY";
            "COSMOS_PROPERTY_TO_EMBED" = "$COSMOS_PROPERTY_TO_EMBED";
            "OPENAI_ENDPOINT" = "$OPENAI_ENDPOINT";
            "OPENAI_DEPLOYMENT_NAME" = "$OPENAI_DEPLOYMENT_NAME";
            "OPENAI_DIMENSIONS" = "$OPENAI_DIMENSIONS";
        }
    } | ConvertTo-Json | Out-File -FilePath ".\local.settings.json" -Encoding ascii
}