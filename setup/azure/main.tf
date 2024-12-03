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
  workspace_id = azurerm_log_analytics_workspace.sentinel_workspace.id
  customer_managed_key_enabled = false
}

# Create Data Collection Rule
resource "azurerm_monitor_data_collection_rule" "dcr" {
  name = "example_dcr"
  resource_group_name = azurerm_resource_group.deathcon_resource_group.name
  location = azurerm_resource_group.deathcon_resource_group.location
  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.sentinel_workspace.id
      name = "example_destination"
    }
  }
  data_flow {
    streams = ["Microsoft-Syslog"]
    destinations = ["example_destination"]
  }
  data_sources {
    syslog {
      facility_names = ["*"]
      log_levels = ["*"]
      name="example-syslog-source"
      streams = ["Microsoft-Syslog"]
    }
  }
}
# Create DCR association
resource "azurerm_monitor_data_collection_rule_association" "example1" {
  name                    = "example1-dcra"
  target_resource_id      = format("/subscriptions/%s/resourcegroups/deathcon-demo-rg/providers/microsoft.hybridcompute/machines/%s", var.subscription_id, var.client_hostname)
  data_collection_rule_id = azurerm_monitor_data_collection_rule.dcr.id
  description             = "example_association"
}