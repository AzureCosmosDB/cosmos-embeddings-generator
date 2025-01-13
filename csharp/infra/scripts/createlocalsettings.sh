#!/bin/bash

set -e

if [ ! -f "./local.settings.json" ]; then

    output=$(azd env get-values)

    # Initialize variables
    COSMOS_CONNECTION__accountEndpoint=""
    COSMOS_DATABASE_NAME=""
    COSMOS_CONTAINER_NAME=""
    COSMOS_VECTOR_PROPERTY=""
    COSMOS_HASH_PROPERTY=""
    COSMOS_PROPERTY_TO_EMBED=""
    OPENAI_ENDPOINT=""
    OPENAI_DEPLOYMENT_NAME=""
    OPENAI_DIMENSIONS=""

    # Parse the output to get the endpoint URLs
    while IFS= read -r line; do
        if [[ $line == *"COSMOS_CONNECTION__accountEndpoint"* ]]; then
            COSMOS_CONNECTION__accountEndpoint=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
        fi
        if [[ $line == *"COSMOS_DATABASE_NAME"* ]]; then
            COSMOS_DATABASE_NAME=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
        fi
        if [[ $line == *"COSMOS_CONTAINER_NAME"* ]]; then
            COSMOS_CONTAINER_NAME=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
        fi
        if [[ $line == *"COSMOS_VECTOR_PROPERTY"* ]]; then
            COSMOS_VECTOR_PROPERTY=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
        fi
        if [[ $line == *"COSMOS_HASH_PROPERTY"* ]]; then
            COSMOS_HASH_PROPERTY=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
        fi
        if [[ $line == *"COSMOS_PROPERTY_TO_EMBED"* ]]; then
            COSMOS_PROPERTY_TO_EMBED=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
        fi
        if [[ $line == *"OPENAI_ENDPOINT"* ]]; then
            OPENAI_ENDPOINT=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
        fi
        if [[ $line == *"OPENAI_DEPLOYMENT_NAME"* ]]; then
            OPENAI_DEPLOYMENT_NAME=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
        fi
        if [[ $line == *"OPENAI_DIMENSIONS"* ]]; then
            OPENAI_DIMENSIONS=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
        fi
    done <<< "$output"

    cat <<EOF > ./local.settings.json
{
    "IsEncrypted": "false",
    "Values": {
        "AzureWebJobsStorage": "UseDevelopmentStorage=true",
        "FUNCTIONS_WORKER_RUNTIME": "python",
        
        "COSMOS_CONNECTION__accountEndpoint": "$COSMOS_CONNECTION__accountEndpoint",
        "COSMOS_DATABASE_NAME": "$COSMOS_DATABASE_NAME",
        "COSMOS_CONTAINER_NAME": "$COSMOS_CONTAINER_NAME",
        "COSMOS_VECTOR_PROPERTY": "$COSMOS_VECTOR_PROPERTY",
        "COSMOS_HASH_PROPERTY": "$COSMOS_HASH_PROPERTY",
        "COSMOS_PROPERTY_TO_EMBED": "$COSMOS_PROPERTY_TO_EMBED",
        "OPENAI_ENDPOINT": "$OPENAI_ENDPOINT",
        "OPENAI_DEPLOYMENT_NAME": "$OPENAI_DEPLOYMENT_NAME",
        "OPENAI_DIMENSIONS": "$OPENAI_DIMENSIONS"
    }
}
EOF

fi