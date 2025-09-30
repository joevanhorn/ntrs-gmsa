# variables.tf
# Variable definitions for Azure gMSA Automation

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-okta-automation"
}

variable "automation_account_name" {
  description = "Name of the Azure Automation Account"
  type        = string
  default     = "aa-okta-gmsa"
}

variable "key_vault_name" {
  description = "Base name of the Key Vault (random suffix will be added)"
  type        = string
  default     = "kv-okta-gmsa"
}

variable "runbook_name" {
  description = "Name of the runbook"
  type        = string
  default     = "Create-gMSA"
}

variable "hybrid_worker_group_name" {
  description = "Name of the Hybrid Runbook Worker Group"
  type        = string
  default     = "OnPremADWorkers"
}

variable "domain_controller" {
  description = "FQDN of the domain controller"
  type        = string
  default     = "dc01.contoso.com"
}

variable "domain_admin_username" {
  description = "Domain admin username (stored in Key Vault)"
  type        = string
  sensitive   = true
}

variable "domain_admin_password" {
  description = "Domain admin password (stored in Key Vault)"
  type        = string
  sensitive   = true
}

variable "webhook_auth_token" {
  description = "Optional authentication token for webhook validation"
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_monitoring" {
  description = "Enable Log Analytics monitoring"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "Okta-gMSA-Automation"
    ManagedBy   = "Terraform"
    Environment = "Production"
  }
}
