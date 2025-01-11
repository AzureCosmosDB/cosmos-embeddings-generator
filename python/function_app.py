import os
import logging
import hashlib
import json
import azure.functions as func
from openai import AzureOpenAI
from azure.identity import DefaultAzureCredential, get_bearer_token_provider


# Retrieve application setings from local.settings.json
OPENAI_ENDPOINT = os.environ["OPENAI_ENDPOINT"]
OPENAI_DEPLOYMENT_NAME = os.environ["OPENAI_DEPLOYMENT_NAME"]
OPENAI_DIMENSIONS = int(os.environ["OPENAI_DIMENSIONS"])

COSMOS_DATABASE_NAME = os.environ["COSMOS_DATABASE_NAME"]
COSMOS_CONTAINER_NAME = os.environ["COSMOS_CONTAINER_NAME"]
COSMOS_VECTOR_PROPERTY = os.environ["COSMOS_VECTOR_PROPERTY"]
COSMOS_HASH_PROPERTY = os.environ["COSMOS_HASH_PROPERTY"]
COSMOS_PROPERTY_TO_EMBED = os.environ["COSMOS_PROPERTY_TO_EMBED"]

token_provider = get_bearer_token_provider(DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default")

# Initialize OpenAI client
OPENAI_CLIENT = AzureOpenAI(
    azure_endpoint = OPENAI_ENDPOINT, 
    azure_ad_token_provider=token_provider,
    api_version = "2024-02-01"
    )


# Initialize the function app
app = func.FunctionApp()


@app.function_name(name="cosmos-embedding-generator")
@app.cosmos_db_output(
    arg_name="output", 
    database_name="%COSMOS_DATABASE_NAME%", 
    container_name="%COSMOS_CONTAINER_NAME%", 
    connection="COSMOS_CONNECTION")
@app.cosmos_db_trigger(
    arg_name="input", 
    database_name="%COSMOS_DATABASE_NAME%", 
    container_name="%COSMOS_CONTAINER_NAME%",
    connection="COSMOS_CONNECTION", 
    lease_container_name="leases",
    create_lease_container_if_not_exists=True)
async def cosmos_embedding_generator(input: func.DocumentList, output: func.Out[func.Document]):
    """
    This function listens for changes to new or existing CosmosDb documents/items,
    and updates them in place with vector embeddings.

    The expected document/item has at least these 3 properties, and note that 'text' 
    is the property that gets embedded.

    Example document:
    {
        "id": "cosmosdb_overview_1",
        "customerId": "1",
        "text": "Azure Cosmos DB is a fully managed NoSQL, relational, and vector database. It offers single-digit millisecond response times, automatic and instant scalability, along with guaranteed speed at any scale. Business continuity is assured with SLA-backed availability and enterprise-grade security."
    }
    """

    if input:
        logging.info('Documents modified: %s', len(input))
        for document in input:
            json_document = document.to_dict()

            # Check hash value to see if document is new or modified
            is_new, hash_value = is_document_new_or_modified(json_document)
            
            if is_new:
                
                # Generate embeddings on the specified document property or document
                embeddings = get_embeddings(json_document[COSMOS_PROPERTY_TO_EMBED])
                #embeddings = get_embeddings(json.dumps(json_document))

                # Add the hash to the document
                json_document[COSMOS_HASH_PROPERTY] = hash_value

                # Add the embeddings to the document
                json_document[COSMOS_VECTOR_PROPERTY] = embeddings

                # Serialize the result and return it to the output binding
                output.set(func.Document.from_json(json.dumps(json_document)))
                

def is_document_new_or_modified(json_document: dict) -> tuple[bool, str]:

    # No hash property, document is new
    if COSMOS_HASH_PROPERTY not in json_document:
        new_hash = compute_json_hash(json_document)
        return True, new_hash

    # Save the existing hash
    existing_hash = json_document[COSMOS_HASH_PROPERTY]

    # Generate a hash of the document/property
    new_hash = compute_json_hash(json_document)

    # Document has changed, process it
    if new_hash != existing_hash:
        return True, new_hash

    # Document has not changed, skip processing
    return False, ""

def get_embeddings(input_text: str) -> list:
    
    response = OPENAI_CLIENT.embeddings.create(
        input = input_text, 
        dimensions = OPENAI_DIMENSIONS,
        model = OPENAI_DEPLOYMENT_NAME)
    
    embeddings = response.model_dump()
    return embeddings['data'][0]['embedding']

def compute_json_hash(json_document: dict) -> str:
    
    # Cleanse the document of system, vector and hash properties
    json_document = cleanse_document_properties(json_document)
        
    # Generate hash on the property to generate embedding on
    property = json_document[COSMOS_PROPERTY_TO_EMBED]

    # Compute a hash on entire document if generating embeddings on the document
    # Re-serialize the JSON to canonical form (sorted keys, no extra whitespace)
    #canonical_json = json.dumps(json_document, sort_keys=True)

    # Compute SHA256 hash
    #hash_object = hashlib.sha256(canonical_json.encode())
    hash_object = hashlib.sha256(property.encode())
    return hash_object.hexdigest()

def cleanse_document_properties(json_document: dict) -> dict:
    
    json_document.pop(COSMOS_VECTOR_PROPERTY, None)
    json_document.pop(COSMOS_HASH_PROPERTY, None)
    json_document.pop("_rid", None)
    json_document.pop("_self", None)
    json_document.pop("_etag", None)
    json_document.pop("_attachments", None)
    json_document.pop("_lsn", None)
    json_document.pop("_ts", None)
    
    return json_document
