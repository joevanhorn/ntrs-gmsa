# Azure gMSA Automation for Okta

Automated infrastructure for creating Group Managed Service Accounts (gMSA) in Active Directory, triggered from Okta Workflows via Azure Automation webhooks.

## 🚀 Features

- **Automated gMSA Creation**: Create gMSAs via webhook from Okta Workflows
- **Secure Credential Management**: Credentials stored in Azure Key Vault
- **Infrastructure as Code**: Complete Terraform configuration
- **CI/CD Pipeline**: GitHub Actions for automated deployment
- **Comprehensive Logging**: Azure Monitor integration for audit trails
- **Idempotent Operations**: Safe to run multiple times

## 📋 Prerequisites

- Azure subscription with appropriate permissions
- GitHub repository with Actions enabled
- Active Directory domain controller
- Domain-joined Windows Server for Hybrid Runbook Worker
- Okta Workflows license

## 🏗️ Architecture

```
┌─────────────────┐
│  Okta Workflow  │
└────────┬────────┘
         │ HTTPS POST
         ▼
┌─────────────────────────────────────────┐
│         Azure Automation                │
│  ┌───────────────────────────────────┐  │
│  │  Webhook → Runbook (PowerShell)   │  │
│  └──────────────┬────────────────────┘  │
│                 │                        │
│  ┌──────────────▼──────────────┐        │
│  │    Azure Key Vault          │        │
│  │  - Domain Admin Credentials │        │
│  └─────────────────────────────┘        │
└─────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│     Hybrid Runbook Worker               │
│  (On Domain-Joined Server)              │
│  ┌───────────────────────────────────┐  │
│  │  Active Directory PowerShell      │  │
│  │  New-ADServiceAccount             │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│     Active Directory                    │
│  - Group Managed Service Account        │
└─────────────────────────────────────────┘
```

## 📁 Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── terraform-deploy.yml    # GitHub Actions workflow
├── terraform/
│   ├── main.tf                     # Main Terraform configuration
│   ├── variables.tf                # Variable definitions
│   ├── outputs.tf                  # Output definitions
│   ├── terraform.tfvars.example    # Example variables file
│   └── runbooks/
│       └── Create-gMSA.ps1         # PowerShell runbook script
├── .gitignore
└── README.md
```

## 🚦 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/azure-gmsa-automation.git
cd azure-gmsa-automation
```

### 2. Set Up Azure Prerequisites

See [SETUP.md](SETUP.md) for detailed instructions.

Quick version:
```bash
# Create Terraform state storage
az group create --name rg-terraform-state --location eastus
az storage account create --name sttfstate$(openssl rand -hex 4) --resource-group rg-terraform-state --location eastus
az storage container create --name tfstate --account-name YOUR_STORAGE_ACCOUNT
```

### 3. Configure GitHub Secrets

Add these secrets to your GitHub repository:
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `TF_STATE_RESOURCE_GROUP`
- `TF_STATE_STORAGE_ACCOUNT`
- `TF_STATE_CONTAINER`
- `DOMAIN_ADMIN_USERNAME`
- `DOMAIN_ADMIN_PASSWORD`
- `DOMAIN_CONTROLLER`

### 4. Deploy Infrastructure

```bash
# Push to main branch to trigger deployment
git add .
git commit -m "Deploy infrastructure"
git push origin main
```

### 5. Register Hybrid Worker

On your domain-joined server:
```powershell
# Follow instructions in Azure Portal:
# Automation Account > Hybrid worker groups > Add hybrid worker
```

### 6. Configure Okta Workflow

Use the webhook URI from GitHub Secret `AZURE_WEBHOOK_URI` in your Okta Workflow HTTP request.

## 📝 Usage

### Creating a gMSA from Okta

Send a POST request to the webhook with this payload:

```json
{
  "AccountName": "gmsa-app-service",
  "DNSHostName": "appserver.contoso.com",
  "PrincipalsAllowedToRetrieve": ["APPSERVER01$", "APPSERVER02$"],
  "Description": "Service account for application",
  "ServicePrincipalNames": ["HTTP/appserver.contoso.com"],
  "OrganizationalUnit": "OU=ServiceAccounts,DC=contoso,DC=com"
}
```

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `AccountName` | Yes | Name of the gMSA (without $) |
| `DNSHostName` | Yes | DNS host name for the account |
| `PrincipalsAllowedToRetrieve` | No | List of computers/users allowed to retrieve password |
| `Description` | No | Description of the account |
| `ServicePrincipalNames` | No | List of SPNs for the account |
| `OrganizationalUnit` | No | OU path where account should be created |
| `KdsRootKeyId` | No | Specific KDS Root Key to use |

### Response Format

**Success:**
```json
{
  "Status": "Success",
  "AccountName": "gmsa-app-service",
  "DNSHostName": "appserver.contoso.com",
  "DistinguishedName": "CN=gmsa-app-service,OU=ServiceAccounts,DC=contoso,DC=com",
  "SamAccountName": "gmsa-app-service$",
  "ObjectGUID": "12345678-1234-1234-1234-123456789012",
  "Created": "2025-09-30T10:30:00Z",
  "Message": "gMSA created successfully",
  "Timestamp": "2025-09-30 10:30:00"
}
```

**Error:**
```json
{
  "Status": "Failed",
  "AccountName": "gmsa-app-service",
  "Error": "Access denied",
  "ErrorDetails": "...",
  "Timestamp": "2025-09-30 10:30:00"
}
```

## 🔧 Local Development

### Prerequisites
- Terraform >= 1.5.0
- Azure CLI
- Azure PowerShell module

### Local Testing

```bash
cd terraform

# Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Initialize Terraform
terraform init \
  -backend-config="resource_group_name=YOUR_RG" \
  -backend-config="storage_account_name=YOUR_STORAGE" \
  -backend-config="container_name=tfstate"

# Plan changes
terraform plan

# Apply changes (be careful!)
terraform apply
```

## 🔒 Security Considerations

- ✅ **Credentials**: Never stored in code, always in Key Vault
- ✅ **Webhook URI**: Sensitive value, stored in GitHub Secrets
- ✅ **OIDC Authentication**: Use federated credentials instead of client secrets
- ✅ **Branch Protection**: Require PR reviews for main branch
- ✅ **Environment Protection**: Require approvals for production deployments
- ✅ **Audit Logging**: All job executions logged to Azure Monitor
- ✅ **Least Privilege**: Service accounts have minimum required permissions

## 📊 Monitoring

### View Job History

```bash
# Via Azure CLI
az automation job list \
  --resource-group rg-okta-automation \
  --automation-account-name aa-okta-gmsa

# Via Azure Portal
# Navigate to: Automation Account > Jobs
```

### Log Analytics Queries

```kusto
// Failed jobs in last 24 hours
AutomationJobLogs
| where TimeGenerated > ago(24h)
| where ResultType == "Failed"
| project TimeGenerated, RunbookName, ErrorMessage

// Success rate by runbook
AutomationJobLogs
| where TimeGenerated > ago(7d)
| summarize 
    Total = count(),
    Success = countif(ResultType == "Success"),
    Failed = countif(ResultType == "Failed")
  by RunbookName
| extend SuccessRate = round(100.0 * Success / Total, 2)
```

## 🔄 Maintenance

### Rotate Webhook

Webhooks should be rotated every 6-12 months:

1. Update `main.tf` to create new webhook
2. Commit and push changes
3. Update Okta Workflow with new URI
4. Remove old webhook configuration

### Update Runbook

1. Modify `terraform/runbooks/Create-gMSA.ps1`
2. Commit changes
3. Push to main branch
4. GitHub Actions will automatically deploy updates

### Rotate Credentials

```bash
# Update domain admin password in Key Vault
az keyvault secret set \
  --vault-name YOUR_VAULT_NAME \
  --name DomainAdminPassword \
  --value "NEW_PASSWORD"
```

## 🐛 Troubleshooting

### Common Issues

**Issue: Job stays in "Queued" status**
- Solution: Check Hybrid Worker is online and registered

**Issue: "Access Denied" errors**
- Solution: Verify domain credentials and permissions in Active Directory

**Issue: "Cannot find AD module"**
- Solution: Install RSAT-AD-PowerShell on Hybrid Worker

**Issue: Webhook returns 404**
- Solution: Verify webhook hasn't expired, check runbook is published

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for more details.

## 📚 Documentation

- [Setup Guide](docs/SETUP.md) - Complete setup instructions
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [API Reference](docs/API.md) - Webhook API documentation
- [Architecture](docs/ARCHITECTURE.md) - Detailed architecture overview

## 🤝 Contributing

1. Create a feature branch
2. Make your changes
3. Test thoroughly in non-production environment
4. Submit a pull request
5. Wait for review and approval

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

For issues or questions:
1. Check the [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
2. Review [GitHub Issues](https://github.com/your-org/azure-gmsa-automation/issues)
3. Contact the platform team

## 🔗 Related Projects

- [Azure Automation Documentation](https://learn.microsoft.com/azure/automation/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Okta Workflows](https://help.okta.com/en-us/content/topics/workflows/workflows-main.htm)

## 📈 Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and changes.
*trigger initial push)

---

**Maintainers**: Your Platform Team  
**Last Updated**: 2025-09-30
