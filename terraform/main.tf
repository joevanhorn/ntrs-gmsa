# main.tf
# Terraform configuration for Azure gMSA Automation infrastructure

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  
  # Configure backend for state management
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "sttfstate${var.environment}"
    container_name       = "tfstate"
    key                  = "okta-gmsa-automation.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Data source for current client
data "azurerm_client_config" "current" {}

# Random suffix for globally unique names
resource "random_integer" "suffix" {
  min = 1000
  max = 9999
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Purpose   = "Okta-gMSA-Automation"
    }
  )
}

# Automation Account
resource "azurerm_automation_account" "main" {
  name                = var.automation_account_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Key Vault
resource "azurerm_key_vault" "main" {
  name                       = "${var.key_vault_name}-${random_integer.suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  # Enable for deployment scenarios
  enabled_for_deployment          = true
  enabled_for_template_deployment = true

  tags = var.tags
}

# Key Vault Access Policy for Automation Account
resource "azurerm_key_vault_access_policy" "automation" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_automation_account.main.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List"
  ]
}

# Key Vault Access Policy for Terraform (to set secrets)
resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Purge",
    "Recover"
  ]
}

# Store domain admin username in Key Vault
resource "azurerm_key_vault_secret" "domain_admin_username" {
  name         = "DomainAdminUsername"
  value        = var.domain_admin_username
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [
    azurerm_key_vault_access_policy.terraform
  ]

  tags = var.tags
}

# Store domain admin password in Key Vault
resource "azurerm_key_vault_secret" "domain_admin_password" {
  name         = "DomainAdminPassword"
  value        = var.domain_admin_password
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [
    azurerm_key_vault_access_policy.terraform
  ]

  tags = var.tags
}

# Optional: Store webhook validation token
resource "azurerm_key_vault_secret" "webhook_token" {
  name         = "WebhookToken"
  value        = var.webhook_auth_token
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [
    azurerm_key_vault_access_policy.terraform
  ]

  tags = var.tags
}

# Import PowerShell modules
resource "azurerm_automation_module" "az_accounts" {
  name                    = "Az.Accounts"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main.name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/Az.Accounts"
  }
}

resource "azurerm_automation_module" "az_keyvault" {
  name                    = "Az.KeyVault"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main.name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/Az.KeyVault"
  }

  depends_on = [
    azurerm_automation_module.az_accounts
  ]
}

# Create the Runbook
resource "azurerm_automation_runbook" "create_gmsa" {
  name                    = var.runbook_name
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main.name
  log_verbose             = true
  log_progress            = true
  description             = "Creates Group Managed Service Accounts in Active Directory"
  runbook_type            = "PowerShell"

  content = templatefile("${path.module}/runbooks/Create-gMSA.ps1", {
    key_vault_name    = azurerm_key_vault.main.name
    domain_controller = var.domain_controller
  })

  tags = var.tags
}

# Publish the Runbook
resource "azurerm_automation_job_schedule" "publish" {
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main.name
  runbook_name            = azurerm_automation_runbook.create_gmsa.name
  
  # This is a workaround to ensure the runbook is published
  # The actual publishing happens through the runbook content update
  
  depends_on = [
    azurerm_automation_runbook.create_gmsa
  ]
}

# Hybrid Worker Group
resource "azurerm_automation_hybrid_runbook_worker_group" "onprem" {
  name                    = var.hybrid_worker_group_name
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main.name
}

# Webhook for the Runbook
resource "azurerm_automation_webhook" "okta" {
  name                    = "Okta-gMSA-Webhook"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main.name
  expiry_time             = timeadd(timestamp(), "8760h") # 1 year from now
  enabled                 = true
  runbook_name            = azurerm_automation_runbook.create_gmsa.name
  run_on_worker_group     = azurerm_automation_hybrid_runbook_worker_group.onprem.name

  parameters = {}

  lifecycle {
    ignore_changes = [
      expiry_time
    ]
  }
}

# Log Analytics Workspace (Optional - for monitoring)
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "${var.automation_account_name}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

# Diagnostic Settings for Automation Account
resource "azurerm_monitor_diagnostic_setting" "automation" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "automation-diagnostics"
  target_resource_id         = azurerm_automation_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "JobLogs"
  }

  enabled_log {
    category = "JobStreams"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
