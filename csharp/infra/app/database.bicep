metadata description = 'Create database accounts.'

param location string = resourceGroup().location
param tags object = {}

param accountName string
param databaseName string
param containerNames array
param partitionKeyName string
param vectorPropertyName string

var database = {
  name: databaseName // Database for application
}

// concatenate / with the partition key and vector property names
var partitionKeyPath = '/${partitionKeyName}'
var vectorPath = '/${vectorPropertyName}'
var vectorExcludedIndexPath = '${vectorPath}/?'

var containers = [for containerName in containerNames:{
    name: containerName // Container for products
    partitionKeyPaths: [
      partitionKeyPath // Partition for product data
    ]
    indexingPolicy: {
      automatic: true
      indexingMode: 'consistent'
      includedPaths: [
        {
          path: '/*'
        }
      ]
      excludedPaths: [
        {
          path: vectorExcludedIndexPath
        }
      ]
      vectorIndexes: [
        {
          path: vectorPath
          type: 'quantizedFlat'   //'diskANN'
        }
      ]
    }
    vectorEmbeddingPolicy: {
      vectorEmbeddings: [
        {
          path: vectorPath
          dataType: 'float32'
          dimensions: 1536
          distanceFunction: 'cosine'
        }
      ]
    }
  }
]

module cosmosDbAccount '../core/database/cosmos-db/nosql/account.bicep' = {
  name: 'cosmos-db-account'
  params: {
    name: accountName
    location: location
    tags: tags
    enableServerless: true
    enableVectorSearch: true
    enableNoSQLFullTextSearch: false
    disableKeyBasedAuth: true
  }
}

module cosmosDbDatabase '../core/database/cosmos-db/nosql/database.bicep' = {
  name: 'cosmos-db-database-${database.name}'
  params: {
    name: database.name
    parentAccountName: cosmosDbAccount.outputs.name
    tags: tags
    setThroughput: false
  }
}

module cosmosDbContainers '../core/database/cosmos-db/nosql/container.bicep' = [
  for (container, _) in containers: {
    name: 'cosmos-db-container-${container.name}'
    params: {
      name: container.name
      parentAccountName: cosmosDbAccount.outputs.name
      parentDatabaseName: cosmosDbDatabase.outputs.name
      tags: tags
      setThroughput: false
      partitionKeyPaths: container.partitionKeyPaths
      indexingPolicy: container.indexingPolicy
      vectorEmbeddingPolicy: container.vectorEmbeddingPolicy
    }
  }
]

module cosmosDbLeases '../core/database/cosmos-db/nosql/container.bicep' = {
  name: 'cosmos-db-container-leases'
  params: {
    name: 'leases'
    parentAccountName: cosmosDbAccount.outputs.name
    parentDatabaseName: cosmosDbDatabase.outputs.name
    tags: tags
    setThroughput: false
    partitionKeyPaths: ['/id']
  }
}

output endpoint string = cosmosDbAccount.outputs.endpoint
output accountName string = cosmosDbAccount.outputs.name
output connectionString string = cosmosDbAccount.outputs.connectionString

output database object = {
  name: cosmosDbDatabase.outputs.name
}
output containers array = [
  for (_, index) in containers: {
    name: cosmosDbContainers[index].outputs.name
  }
]
