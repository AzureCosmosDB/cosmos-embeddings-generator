$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\local.settings.json")) {

    $output = azd env get-values

    # Parse the output to get the endpoint values
    $expectedKeys = @(
        "COSMOS_CONNECTION__accountEndpoint",
        "COSMOS_CONTAINER_NAME",
        "COSMOS_DATABASE_NAME",
        "COSMOS_HASH_PROPERTY",
        "COSMOS_PROPERTY_TO_EMBED",
        "COSMOS_VECTOR_PROPERTY",
        "OPENAI_DEPLOYMENT_NAME",
        "OPENAI_DIMENSIONS",
        "OPENAI_ENDPOINT"
    )

    foreach ($line in $output) {
        foreach ($key in $expectedKeys) {
            if ($line -match $key) {
                Set-Variable -Name $key -Value (($line -split "=")[1] -replace '"','')
            }
        }
    }

    @{
        "IsEncrypted" = "false";
        "Values" = @{
            "AzureWebJobsStorage" = "UseDevelopmentStorage=true";
            "FUNCTIONS_WORKER_RUNTIME" = "dotnet-isolated";
            "COSMOS_CONNECTION__accountEndpoint" = "$COSMOS_CONNECTION__accountEndpoint";
            "COSMOS_CONTAINER_NAME" = "$COSMOS_CONTAINER_NAME";
            "COSMOS_DATABASE_NAME" = "$COSMOS_DATABASE_NAME";
            "COSMOS_HASH_PROPERTY" = "$COSMOS_HASH_PROPERTY";
            "COSMOS_PROPERTY_TO_EMBED" = "$COSMOS_PROPERTY_TO_EMBED";
            "COSMOS_VECTOR_PROPERTY" = "$COSMOS_VECTOR_PROPERTY";
            "OPENAI_DEPLOYMENT_NAME" = "$OPENAI_DEPLOYMENT_NAME";
            "OPENAI_DIMENSIONS" = "$OPENAI_DIMENSIONS";
            "OPENAI_ENDPOINT" = "$OPENAI_ENDPOINT";
        }
    } | ConvertTo-Json | Out-File -FilePath ".\local.settings.json" -Encoding ascii
}