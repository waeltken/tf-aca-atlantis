locals {
  suffix         = random_bytes.unique.hex
  fake_token     = "fake"
  repo_whitelist = "github.com/waeltken/*"
  fake_command   = ["atlantis", "server", "--gh-user", local.fake_token, "--gh-token", local.fake_token, "--repo-allowlist", local.repo_whitelist]
  command        = ["atlantis", "server", "--gh-app-id", var.gh_app_id, "--gh-app-key", var.gh_app_key, "--gh-webhook-secret", var.gh_webhook_secret, "--repo-allowlist", local.repo_whitelist]
}

resource "random_bytes" "unique" {
  length = 2
}

resource "azurerm_resource_group" "default" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
}

data "azurerm_resource_group" "default" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

locals {
  resource_group_name     = var.create_resource_group ? azurerm_resource_group.default[0].name : data.azurerm_resource_group.default[0].name
  resource_group_location = var.create_resource_group ? azurerm_resource_group.default[0].location : data.azurerm_resource_group.default[0].location
}

resource "azurerm_virtual_network" "default" {
  name                = "atlantis-vnet"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  address_space       = ["10.0.0.0/16"]
}
resource "azurerm_subnet" "atlantis" {
  name                 = "atlantis-subnet"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = ["10.0.0.0/23"]
}

resource "azurerm_network_security_group" "inbound_aks" {
  name                = "inbound-aks-nsg"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
}

resource "azurerm_log_analytics_workspace" "default" {
  name                = "atlantis-log-analytics"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
}

resource "azurerm_container_app_environment" "default" {
  name                     = "atlantis-aca-env"
  location                 = local.resource_group_location
  resource_group_name      = local.resource_group_name
  infrastructure_subnet_id = azurerm_subnet.atlantis.id

  log_analytics_workspace_id = azurerm_log_analytics_workspace.default.id
}

resource "azurerm_storage_account" "default" {
  name                            = "atlantisstorage${local.suffix}"
  location                        = local.resource_group_location
  resource_group_name             = local.resource_group_name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
}

resource "azurerm_storage_share" "data" {
  name                 = "atlantis-data"
  storage_account_name = azurerm_storage_account.default.name
  quota                = 1024
}

resource "azurerm_container_app_environment_storage" "data" {
  name                         = "atlantis-data"
  container_app_environment_id = azurerm_container_app_environment.default.id
  account_name                 = azurerm_storage_account.default.name
  share_name                   = azurerm_storage_share.data.name
  access_key                   = azurerm_storage_account.default.primary_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app" "default" {
  name                         = "atlantis-app"
  container_app_environment_id = azurerm_container_app_environment.default.id
  resource_group_name          = local.resource_group_name
  revision_mode                = "Single"

  template {
    container {
      name    = "atlantis"
      image   = "ghcr.io/runatlantis/atlantis:latest"
      cpu     = 2
      memory  = "4Gi"
      command = local.command

      readiness_probe {
        port      = 4141
        transport = "TCP"
        path      = "/healthz"
      }

      volume_mounts {
        name = "atlantis-data"
        path = "/atlantis"
      }
    }

    volume {
      name         = azurerm_container_app_environment_storage.data.name
      storage_name = azurerm_storage_share.data.name
      storage_type = "AzureFile"
    }
  }
  # Allow public ingress traffic
  ingress {
    external_enabled = true
    target_port      = 4141

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  lifecycle {
    ignore_changes = [ingress.0.custom_domain]
  }
}

output "default_domain_name" {
  value = azurerm_container_app.default.latest_revision_fqdn
}

