using Azure.AI.OpenAI;
using Azure.Identity;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using OpenAI.Embeddings;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

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
        /// The expected document/item has at least these 3 properties, and note that 'customerNotes' 
        /// is the property that gets embedded.
        ///
        /// Example document:
        /// {
        ///    "id": "00001",
        ///    "customerId": "10001",
        ///    "customerNotes": "lorum ipsum."
        /// }
        /// </summary>
        /// <param name="input">The list of documents that were modified in the CosmosDB container.</param>
        /// <param name="context">The execution context of the Azure Function.</param>
        /// <returns>A task that represents the asynchronous operation. The task result contains the updated documents with vector embeddings.</returns>
        [Function(nameof(CosmosEmbeddingGeneratorFunction))]
        [CosmosDBOutput(
            databaseName: "%COSMOS_DATABASE_NAME%",
            containerName: "%COSMOS_CONTAINER_NAME%",
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
            var toBeUpdated = new List<(JsonDocument doc, string hash, string toEmbed)>();

            if (input?.Count > 0)
            {
                _logger.LogInformation("Documents modified: {count}", input.Count);
                for (int i = 0; i < input.Count; i++)
                {
                    var document = input[i];

                    // Parse document into a json object
                    JsonDocument jsonDocument = JsonDocument.Parse(document.ToString());

                    // Check hash value to see if document is new or modified
                    if (IsDocumentNewOrModified(jsonDocument, out var newHash))
                    {
                        jsonDocument.RootElement.TryGetProperty(_propertyToEmbed, out JsonElement propertyElement);
                        toBeUpdated.Add((jsonDocument, newHash, propertyElement.GetString() ?? string.Empty));
                    }
                }
            }

            // Process documents that have been modified
            if (toBeUpdated.Count > 0)
            {
                _logger.LogInformation("Updating embeddings for: {count}", toBeUpdated.Count);

                // Generate embeddings on the specified document property or document
                var embeddings = await GetEmbeddingsAsync(toBeUpdated.Select(tbu => tbu.toEmbed));

                StringBuilder output = new StringBuilder().AppendLine("[");
                for (int i = 0; i < toBeUpdated.Count; i++)
                {
                    var (jsonDocument, hash, toEmbed) = toBeUpdated[i];

                    // Create a new JSON object with the updated properties
                    using (var stream = new MemoryStream())
                    {
                        using (var writer = new Utf8JsonWriter(stream))
                        {
                            writer.WriteStartObject();

                            foreach (JsonProperty property in jsonDocument.RootElement.EnumerateObject())
                            {
                                if (property.Name != _hashProperty && property.Name != _vectorProperty)
                                {
                                    property.WriteTo(writer);
                                }
                            }

                            writer.WriteString(_hashProperty, hash);
                            writer.WriteStartArray(_vectorProperty);
                            foreach (var value in embeddings[i])
                            {
                                writer.WriteNumberValue(value);
                            }
                            writer.WriteEndArray();

                            writer.WriteEndObject();
                        }

                        stream.Position = 0;
                        var updatedJsonDocument = JsonDocument.Parse(stream);
                        output.Append(updatedJsonDocument.RootElement.GetRawText());
                        output.AppendLine(",");
                    }
                }
                output.Length -= 1 + Environment.NewLine.Length;
                output.AppendLine().AppendLine("]");

                return output.ToString();
            }

            return null;
        }

        private bool IsDocumentNewOrModified(JsonDocument jsonDocument, out string newHash)
        {
            if (jsonDocument.RootElement.TryGetProperty(_hashProperty, out JsonElement existingProperty))
            {
                // Generate a hash of the document/property
                newHash = ComputeJsonHash(jsonDocument);

                // Document has changed, process it
                if (newHash != existingProperty.GetString())
                    return true;

                // Document has not changed, skip processing
                return false;
            }
            else
            {
                // No hash property, document is new
                newHash = ComputeJsonHash(jsonDocument);
                return true;
            }
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

        private string ComputeJsonHash(JsonDocument jsonDocument)
        {

            // Cleanse the document of system, vector and hash properties
            jsonDocument = RemoveProperties(jsonDocument);

            // Compute a hash on entire document generating embeddings on entire document
            // Re-serialize the JSON to canonical form (sorted keys, no extra whitespace)

            // Generate a hash on the property to be embedded
            jsonDocument.RootElement.TryGetProperty(_propertyToEmbed, out JsonElement propertyElement);
            var property = propertyElement.GetString() ?? string.Empty;

            // Compute SHA256 hash
            byte[] hashBytes = SHA256.HashData(Encoding.UTF8.GetBytes(property));
            return BitConverter.ToString(hashBytes).Replace("-", "").ToLowerInvariant();
        }

        private JsonDocument RemoveProperties(JsonDocument jsonDocument)
        {
            using (var stream = new MemoryStream())
            {
                using (var writer = new Utf8JsonWriter(stream))
                {
                    writer.WriteStartObject();

                    foreach (JsonProperty property in jsonDocument.RootElement.EnumerateObject())
                    {
                        if (property.Name != _vectorProperty &&
                            property.Name != _hashProperty &&
                            property.Name != "_rid" &&
                            property.Name != "_self" &&
                            property.Name != "_etag" &&
                            property.Name != "_attachments" &&
                            property.Name != "_lsn" &&
                            property.Name != "_ts")
                        {
                            property.WriteTo(writer);
                        }
                    }

                    writer.WriteEndObject();
                }

                stream.Position = 0;
                return JsonDocument.Parse(stream);
            }
        }
    }
}
