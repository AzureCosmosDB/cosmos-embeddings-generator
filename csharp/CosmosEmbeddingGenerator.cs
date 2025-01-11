using Azure.AI.OpenAI;
using Azure.Identity;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;
using OpenAI.Embeddings;
using System.Security.Cryptography;
using System.Text;

namespace CosmosEmbeddingGenerator
{
    public class CosmosEmbeddingGeneratorFunction
    {
        private readonly ILogger _logger;
        private readonly AzureOpenAIClient _openAiClient;
        private readonly EmbeddingClient _embeddingClient;
        private readonly int _dimensions;
        private readonly string _vectorProperty;
        private readonly string _hashProperty;
        private readonly string _propertyToEmbed;

        public CosmosEmbeddingGeneratorFunction(ILoggerFactory loggerFactory, IConfiguration configuration)
        {
            _logger = loggerFactory.CreateLogger<CosmosEmbeddingGeneratorFunction>();

            string openAiEndpoint = configuration["OPENAI_ENDPOINT"] ?? throw new InvalidOperationException("'OpenAiEndpoint' must be defined.");
            string deploymentName = configuration["OPENAI_DEPLOYMENT_NAME"] ?? throw new InvalidOperationException("'OpenAiDeploymentName' must be defined.");
            string openAiDimensions = configuration["OPENAI_DIMENSIONS"] ?? throw new InvalidOperationException("'OpenAiDimensions' must be defined.");
            string vectorProperty = configuration["COSMOS_VECTOR_PROPERTY"] ?? throw new InvalidOperationException("'VectorProperty' must be defined.");
            string hashProperty = configuration["COSMOS_HASH_PROPERTY"] ?? throw new InvalidOperationException("'HashProperty' must be defined.");
            string propertyToEmbed = configuration["COSMOS_PROPERTY_TO_EMBED"] ?? throw new InvalidOperationException("'PropertyToEmbed' must be defined.");


            _openAiClient = new AzureOpenAIClient(new Uri(openAiEndpoint), new DefaultAzureCredential());
            _embeddingClient = _openAiClient.GetEmbeddingClient(deploymentName);
            _dimensions = int.Parse(openAiDimensions);
            _vectorProperty = vectorProperty;
            _hashProperty = hashProperty;
            _propertyToEmbed = propertyToEmbed;

        }

        /// <summary>
        /// This function listens for changes to new or existing CosmosDb documents/items,
        /// and updates them in place with vector embeddings.
        ///
        /// The expected document/item has at least these 3 properties, and note that 'text' 
        /// is the property that gets embedded.
        ///
        /// Example document:
        /// {
        ///     "id": "cosmosdb_overview_1",
        ///     "customerId": "1",
        ///     "text": "Azure Cosmos DB is a fully managed NoSQL, relational, and vector database. It offers single-digit millisecond response times, automatic and instant scalability, along with guaranteed speed at any scale. Business continuity is assured with SLA-backed availability and enterprise-grade security."
        /// }
        /// </summary>
        /// <param name="input">The list of documents that were modified in the CosmosDB container.</param>
        /// <param name="context">The execution context of the Azure Function.</param>
        /// <returns>A task that represents the asynchronous operation. The task result contains the updated documents with vector embeddings.</returns>
        [Function(nameof(CosmosEmbeddingGeneratorFunction))]
        [CosmosDBOutput(
            databaseName: "%COSMOS_DATABASE_NAME%",
            containerName: "%COSMOS_OUTPUT_CONTAINER_NAME%",
            Connection = "COSMOS_CONNECTION")]
        public async Task<object?> Run(
            [CosmosDBTrigger(
                databaseName: "%COSMOS_DATABASE_NAME%",
                containerName: "%COSMOS_CONTAINER_NAME%",
                Connection = "COSMOS_CONNECTION",
                LeaseContainerName = "leases",
                CreateLeaseContainerIfNotExists = true)] IReadOnlyList<dynamic> input,
            FunctionContext context)
        {
            // List of documents to be returned to output binding
            var toBeUpdated = new List<(JObject doc, string hash, string toEmbed)>();

            if (input?.Count > 0)
            {
                _logger.LogInformation("Documents modified: {count}", input.Count);
                for (int i = 0; i < input.Count; i++)
                {
                    var document = input[i];

                    // Parse document into a json object
                    JObject jsonDocument = JObject.Parse(document.ToString());

                    // Check hash value to see if document is new or modified
                    if (IsDocumentNewOrModified(jsonDocument, out var newHash))
                    {
                        toBeUpdated.Add((jsonDocument, newHash, jsonDocument.Property(_propertyToEmbed)?.ToString() ?? string.Empty));
                    }
                }
            }

            // Process documents that have been modified
            if (toBeUpdated.Count > 0)
            {
                _logger.LogInformation("Updating embeddings for: {count}", toBeUpdated.Count);

                // Generate embeddings on the specified document property or document
                var embeddings = await GetEmbeddingsAsync(toBeUpdated.Select(tbu => tbu.toEmbed));
                //var embeddings = await GetEmbeddingsAsync(toBeUpdated.Select(tbu => tbu.doc.ToString()));

                StringBuilder output = new StringBuilder().AppendLine("[");
                for (int i = 0; i < toBeUpdated.Count; i++)
                {
                    var (jsonDocument, hash, toEmbed) = toBeUpdated[i];

                    // Add the hash to the document
                    jsonDocument[_hashProperty] = hash;

                    // Add the embeddings to the document
                    jsonDocument[_vectorProperty] = JArray.FromObject(embeddings[i]);

                    // Serialize the result and return it to the output binding
                    output.Append(jsonDocument.ToString());
                    output.AppendLine(",");
                }
                output.Length -= 1 + Environment.NewLine.Length;
                output.AppendLine().AppendLine("]");

                return output.ToString();
            }

            return null;
        }

        private bool IsDocumentNewOrModified(JObject jsonDocument, out string newHash)
        {
            var existingProperty = jsonDocument.Property(_hashProperty);
            // No hash property, document is new
            if (existingProperty is null)
            {
                // Generate a hash of the document.
                newHash = ComputeJsonHash(jsonDocument);
                return true;
            }

            // Generate a hash of the document/property
            newHash = ComputeJsonHash(jsonDocument);

            // Document has changed, process it
            if (newHash != existingProperty.Value.ToString())
                return true;

            // Document has not changed, skip processing
            return false;
        }

        private async Task<List<float[]>> GetEmbeddingsAsync(IEnumerable<string> inputs)
        {
            var options = new EmbeddingGenerationOptions
            {
                Dimensions = _dimensions
            };

            var response = await _embeddingClient.GenerateEmbeddingsAsync(inputs, options);
            var results = new List<float[]>(response.Value.Count);
            foreach (var e in response.Value)
            {
                results.Add(e.ToFloats().ToArray());
            }
            return results;
        }

        private string ComputeJsonHash(JObject jsonDocument)
        {

            // Cleanse the document of system, vector and hash properties
            jsonDocument = CleanseDocumentProperties(jsonDocument);

            // Compute a hash on entire document generating embeddings on entire document
            // Re-serialize the JSON to canonical form (sorted keys, no extra whitespace)
            //var canonicalJson = JsonConvert.SerializeObject(jsonDocument, Formatting.None);

            // Generate a hash on the property to be embedded
            var property = jsonDocument.Property(_propertyToEmbed)?.ToString() ?? string.Empty;

            // Compute SHA256 hash
            //byte[] hashBytes = SHA256.HashData(Encoding.UTF8.GetBytes(canonicalJson));
            byte[] hashBytes = SHA256.HashData(Encoding.UTF8.GetBytes(property));
            return BitConverter.ToString(hashBytes).Replace("-", "").ToLowerInvariant();
        }

        private JObject CleanseDocumentProperties(JObject jsonDocument)
        {
            jsonDocument.Remove(_vectorProperty);
            jsonDocument.Remove(_hashProperty);
            jsonDocument.Remove("_rid");
            jsonDocument.Remove("_self");
            jsonDocument.Remove("_etag");
            jsonDocument.Remove("_attachments");
            jsonDocument.Remove("_lsn");
            jsonDocument.Remove("_ts");
            return jsonDocument;
        }
    }
}
