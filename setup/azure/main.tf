terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.10.0"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
}
# Create resource group to hold all lab resources
resource "azurerm_resource_group" "deathcon_resource_group" {
  name     = var.resource_group_name
  location = var.location
}

# Register required providers
resource "azurerm_resource_provider_registration" "hybrid_connect" {
  name = "Microsoft.HybridConnectivity"
}
resource "azurerm_resource_provider_registration" "azure_arc_data" {
  name = "Microsoft.AzureArcData"
}



# Create a Log Analytics workspace
resource "azurerm_log_analytics_workspace" "sentinel_workspace" {
  name                = "sentinel-workspace"
  location            = azurerm_resource_group.deathcon_resource_group.location
  resource_group_name = azurerm_resource_group.deathcon_resource_group.name
  sku                 = "PerGB2018"
}

# Enable Azure Sentinel on the Log Analytics workspace
resource "azurerm_sentinel_log_analytics_workspace_onboarding" "example" {
  workspace_id                 = azurerm_log_analytics_workspace.sentinel_workspace.id
  customer_managed_key_enabled = false
}

# Create Data Collection Rule
resource "azurerm_monitor_data_collection_rule" "dcr" {
  name                = "example_dcr"
  resource_group_name = azurerm_resource_group.deathcon_resource_group.name
  location            = azurerm_resource_group.deathcon_resource_group.location
  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.sentinel_workspace.id
      name                  = "example_destination"
    }
  }
  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["example_destination"]
  }
  data_sources {
    syslog {
      facility_names = ["*"]
      log_levels     = ["*"]
      name           = "example-syslog-source"
      streams        = ["Microsoft-Syslog"]
    }
  }
}

# Create User Assigned Identity
resource "azurerm_user_assigned_identity" "associate-dcr-identity" {
  location = var.location
  name = "associate-dcr-identity"
  resource_group_name = var.resource_group_name
}
# Assign roles to identity
resource "azurerm_role_assignment" "associate-dcr-log-analytics" {
  scope = format("/subscriptions/%s",var.subscription_id)
  role_definition_name = "Log Analytics Contributor"
  principal_id = azurerm_user_assigned_identity.associate-dcr-identity.principal_id
}
resource "azurerm_role_assignment" "associate-dcr-monitoring" {
  scope = format("/subscriptions/%s",var.subscription_id)
  role_definition_name = "Monitoring Contributor"
  principal_id = azurerm_user_assigned_identity.associate-dcr-identity.principal_id
}
resource "azurerm_role_assignment" "associate-dcr-resource-admin" {
  scope = format("/subscriptions/%s",var.subscription_id)
  role_definition_name = "Azure Connected Machine Resource Administrator"
  principal_id = azurerm_user_assigned_identity.associate-dcr-identity.principal_id
}
resource "azurerm_role_assignment" "associate-dcr-vm-contributor" {
  scope = format("/subscriptions/%s",var.subscription_id)
  role_definition_name = "Virtual Machine Contributor"
  principal_id = azurerm_user_assigned_identity.associate-dcr-identity.principal_id
}
# Create policy
resource "azurerm_policy_definition" "example" {
  name         = "associate-linux-arc-with-dcr"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Associate Linux Arch Machines with DCR (Terraform)"
  policy_rule = jsonencode({
    "if" : {
      "allOf" : [
        {
          "field" : "type",
          "equals" : "Microsoft.HybridCompute/machines"
        },
        {
          "field" : "Microsoft.HybridCompute/machines/osName",
          "equals" : "linux"
        },
        {
          "field" : "location",
          "in" : [
            "australiacentral",
            "australiacentral2",
            "australiaeast",
            "australiasoutheast",
            "brazilsouth",
            "brazilsoutheast",
            "canadacentral",
            "canadaeast",
            "centralindia",
            "centralus",
            "centraluseuap",
            "eastasia",
            "eastus",
            "eastus2",
            "eastus2euap",
            "francecentral",
            "francesouth",
            "germanynorth",
            "germanywestcentral",
            "israelcentral",
            "italynorth",
            "japaneast",
            "japanwest",
            "jioindiacentral",
            "jioindiawest",
            "koreacentral",
            "koreasouth",
            "malaysiasouth",
            "mexicocentral",
            "northcentralus",
            "northeurope",
            "norwayeast",
            "norwaywest",
            "polandcentral",
            "qatarcentral",
            "southafricanorth",
            "southafricawest",
            "southcentralus",
            "southeastasia",
            "southindia",
            "spaincentral",
            "swedencentral",
            "swedensouth",
            "switzerlandnorth",
            "switzerlandwest",
            "taiwannorth",
            "taiwannorthwest",
            "uaecentral",
            "uaenorth",
            "uksouth",
            "ukwest",
            "westcentralus",
            "westeurope",
            "westindia",
            "westus",
            "westus2",
            "westus3"
          ]
        }
      ]
    },
    "then" : {
      "effect" : "[parameters('effect')]",
      "details" : {
        "type" : "Microsoft.Insights/dataCollectionRuleAssociations",
        "roleDefinitionIds" : [
          "/providers/microsoft.authorization/roleDefinitions/749f88d5-cbae-40b8-bcfc-e573ddc772fa",
          "/providers/microsoft.authorization/roleDefinitions/92aaf0da-9dab-42b6-94a3-d43ce8d16293"
        ],
        "evaluationDelay" : "AfterProvisioning",
        "existenceCondition" : {
          "anyOf" : [
            {
              "field" : "Microsoft.Insights/dataCollectionRuleAssociations/dataCollectionRuleId",
              "equals" : "[parameters('dcrResourceId')]"
            },
            {
              "field" : "Microsoft.Insights/dataCollectionRuleAssociations/dataCollectionEndpointId",
              "equals" : "[parameters('dcrResourceId')]"
            }
          ]
        },
        "deployment" : {
          "properties" : {
            "mode" : "incremental",
            "template" : {
              "$schema" : "https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
              "contentVersion" : "1.0.0.0",
              "parameters" : {
                "resourceName" : {
                  "type" : "string"
                },
                "location" : {
                  "type" : "string"
                },
                "dcrResourceId" : {
                  "type" : "string"
                },
                "resourceType" : {
                  "type" : "string"
                }
              },
              "variables" : {
                "dcrAssociationName" : "[concat('assoc-', uniqueString(concat(parameters('resourceName'), parameters('dcrResourceId'))))]",
                "dceAssociationName" : "configurationAccessEndpoint",
                "dcrResourceType" : "Microsoft.Insights/dataCollectionRules",
                "dceResourceType" : "Microsoft.Insights/dataCollectionEndpoints"
              },
              "resources" : [
                {
                  "condition" : "[equals(parameters('resourceType'), variables('dcrResourceType'))]",
                  "name" : "[variables('dcrAssociationName')]",
                  "type" : "Microsoft.Insights/dataCollectionRuleAssociations",
                  "apiVersion" : "2021-04-01",
                  "properties" : {
                    "dataCollectionRuleId" : "[parameters('dcrResourceId')]"
                  },
                  "scope" : "[concat('Microsoft.HybridCompute/machines/', parameters('resourceName'))]"
                },
                {
                  "condition" : "[equals(parameters('resourceType'), variables('dceResourceType'))]",
                  "name" : "[variables('dceAssociationName')]",
                  "type" : "Microsoft.Insights/dataCollectionRuleAssociations",
                  "apiVersion" : "2021-04-01",
                  "properties" : {
                    "dataCollectionEndpointId" : "[parameters('dcrResourceId')]"
                  },
                  "scope" : "[concat('Microsoft.HybridCompute/machines/', parameters('resourceName'))]"
                }
              ]
            },
            "parameters" : {
              "resourceName" : {
                "value" : "[field('name')]"
              },
              "location" : {
                "value" : "[field('location')]"
              },
              "dcrResourceId" : {
                "value" : "[parameters('dcrResourceId')]"
              },
              "resourceType" : {
                "value" : "[parameters('resourceType')]"
              }
            }
          }
        }
      }
    }
    }, )
  parameters = jsonencode({
    "effect": {
        "type": "String",
        "metadata": {
          "displayName": "Effect",
          "description": "Enable or disable the execution of the policy."
        },
        "allowedValues": [
          "DeployIfNotExists",
          "Disabled"
        ],
        "defaultValue": "DeployIfNotExists"
      },
      "dcrResourceId": {
        "type": "String",
        "metadata": {
          "displayName": "Data Collection Rule Resource Id or Data Collection Endpoint Resource Id",
          "description": "Resource Id of the Data Collection Rule or the Data Collection Endpoint to be applied on the Linux machines in scope.",
          "portalReview": "true",
          "assignPermissions": true
        }
      },
      "resourceType": {
        "type": "String",
        "metadata": {
          "displayName": "Resource Type",
          "description": "Either a Data Collection Rule (DCR) or a Data Collection Endpoint (DCE)",
          "portalReview": "true"
        },
        "allowedValues": [
          "Microsoft.Insights/dataCollectionRules",
          "Microsoft.Insights/dataCollectionEndpoints"
        ],
        "defaultValue": "Microsoft.Insights/dataCollectionRules"
      }
    })
}
resource "azurerm_subscription_policy_assignment" "example" {
 name = "example-association"
 policy_definition_id =  azurerm_policy_definition.example.id
 subscription_id = format("/subscriptions/%s",var.subscription_id)
 location = var.location
 identity {
   type = "UserAssigned"
   identity_ids = [azurerm_user_assigned_identity.associate-dcr-identity.id]
 }
 parameters = <<PARAMETERS
 {
  "dcrResourceId": {
      "value": "${azurerm_monitor_data_collection_rule.dcr.id}"
    }
 }
 PARAMETERS
}