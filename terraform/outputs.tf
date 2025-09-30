# outputs.tf
# Output values from the Terraform deployment

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "automation_account_name" {
  description = "Name of the Automation Account"
  value       = azurerm_automation_account.main.name
}

output "automation_account_id" {
  description = "Resource ID of the Automation Account"
  value       = azurerm_automation_account.main.id
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "runbook_name" {
  description = "Name of the created runbook"
  value       = azurerm_automation_runbook.create_gmsa.name
}

output "hybrid_worker_group_name" {
  description = "Name of the Hybrid Worker Group"
  value       = azurerm_automation_hybrid_runbook_worker_group.onprem.name
}

output "webhook_uri" {
  description = "Webhook URI for Okta integration (SENSITIVE - save immediately)"
  value       = azurerm_automation_webhook.okta.uri
  sensitive   = true
}

output "webhook_expiry" {
  description = "Webhook expiration date"
  value       = azurerm_automation_webhook.okta.expiry_time
}

output "automation_identity_principal_id" {
  description = "Principal ID of the Automation Account managed identity"
  value       = azurerm_automation_account.main.identity[0].principal_id
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace (if enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

# Instructions output
output "next_steps" {
  description = "Next steps after deployment"
  value = <<-EOT
  
  ========================================
  Deployment Successful!
  ========================================
  
  Next Steps:
  
  1. SAVE THE WEBHOOK URI:
     Run: terraform output -raw webhook_uri
     This URL cannot be retrieved again!
  
  2. Register Hybrid Worker:
     - RDP to your domain-joined server
     - Run the registration script:
       ${azurerm_automation_account.main.name} > Hybrid worker groups > Add
  
  3. Test the Runbook:
     - Navigate to Azure Portal
     - Go to Automation Account > Runbooks
     - Select '${azurerm_automation_runbook.create_gmsa.name}'
     - Click 'Start' and provide test parameters
  
  4. Configure Okta Workflow:
     - Use the webhook URI from step 1
     - Set HTTP method to POST
     - Configure JSON payload
  
  5. Monitor Jobs:
     - Automation Account > Jobs
     ${var.enable_monitoring ? "- Log Analytics Workspace: ${var.automation_account_name}-logs" : ""}
  
  Resources Created:
  - Resource Group: ${azurerm_resource_group.main.name}
  - Automation Account: ${azurerm_automation_account.main.name}
  - Key Vault: ${azurerm_key_vault.main.name}
  - Runbook: ${azurerm_automation_runbook.create_gmsa.name}
  - Hybrid Worker Group: ${azurerm_automation_hybrid_runbook_worker_group.onprem.name}
  
  ========================================
  EOT
}
