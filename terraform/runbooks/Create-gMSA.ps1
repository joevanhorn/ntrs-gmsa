<#
.SYNOPSIS
    Creates a Group Managed Service Account (gMSA) in Active Directory via Azure Runbook

.DESCRIPTION
    This runbook accepts a JSON payload from Okta Workflows via webhook and creates
    a gMSA in Active Directory. It includes validation, error handling, and logging.

.PARAMETER WebhookData
    Automatically passed by Azure Automation when triggered via webhook

.NOTES
    Author: Azure Automation
    Requirements: 
    - Hybrid Runbook Worker on domain-joined server
    - Active Directory PowerShell module
    - Domain admin credentials stored in Azure Key Vault
#>

param(
    [Parameter(Mandatory = $false)]
    [object]$WebhookData
)

#region Configuration
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Azure Key Vault configuration
$keyVaultName = "${key_vault_name}"
$domainController = "${domain_controller}"

# Import Azure modules
Write-Output "Importing Azure PowerShell modules..."
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.KeyVault -ErrorAction Stop
Write-Output "Azure modules imported successfully"

# Log start
Write-Output "=========================================="
Write-Output "gMSA Creation Runbook Started"
Write-Output "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "=========================================="
#endregion

#region Functions
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        'ERROR'   { Write-Error $logMessage }
        'WARNING' { Write-Warning $logMessage }
        'SUCCESS' { Write-Output $logMessage }
        default   { Write-Output $logMessage }
    }
}

function Test-gMSAExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccountName,
        
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$Credential
    )
    
    try {
        $account = Get-ADServiceAccount -Filter "Name -eq '$AccountName'" -Server $domainController -Credential $Credential -ErrorAction SilentlyContinue
        return ($null -ne $account)
    }
    catch {
        return $false
    }
}

function Get-AzureKeyVaultCredential {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VaultName,
        
        [Parameter(Mandatory = $true)]
        [string]$UsernameSecretName,
        
        [Parameter(Mandatory = $true)]
        [string]$PasswordSecretName
    )
    
    try {
        Write-Log "Retrieving credentials from Key Vault: $VaultName"
        
        # Connect using Managed Identity
        Connect-AzAccount -Identity | Out-Null
        
        # Retrieve secrets
        $username = Get-AzKeyVaultSecret -VaultName $VaultName -Name $UsernameSecretName -AsPlainText
        $passwordSecret = Get-AzKeyVaultSecret -VaultName $VaultName -Name $PasswordSecretName
        $password = $passwordSecret.SecretValue
        
        # Create credential object
        $credential = New-Object System.Management.Automation.PSCredential($username, $password)
        
        Write-Log "Credentials retrieved successfully" -Level SUCCESS
        return $credential
    }
    catch {
        Write-Log "Failed to retrieve credentials from Key Vault: $($_.Exception.Message)" -Level ERROR
        throw
    }
}
#endregion

#region Main Execution
try {
    # Validate webhook data
    if ($null -eq $WebhookData) {
        Write-Log "No webhook data received. This runbook must be triggered via webhook." -Level ERROR
        throw "No webhook data provided"
    }
    
    Write-Log "Webhook data received"
    
    # Optional: Validate webhook token for additional security
    # Uncomment and configure if you want token-based authentication
    <#
    $expectedToken = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "WebhookToken" -AsPlainText
    if ($WebhookData.RequestHeader["X-Auth-Token"] -ne $expectedToken) {
        Write-Log "Invalid authentication token" -Level ERROR
        throw "Unauthorized request"
    }
    Write-Log "Authentication token validated"
    #>
    
    # Parse the request body
    Write-Log "Parsing request body"
    $requestBody = $WebhookData.RequestBody | ConvertFrom-Json
    
    # Extract parameters
    $accountName = $requestBody.AccountName
    $dnsHostName = $requestBody.DNSHostName
    $principalsAllowedToRetrieve = $requestBody.PrincipalsAllowedToRetrieve
    $description = $requestBody.Description
    $servicePrincipalNames = $requestBody.ServicePrincipalNames
    $kdsRootKeyId = $requestBody.KdsRootKeyId  # Optional
    $organizationalUnit = $requestBody.OrganizationalUnit  # Optional, e.g., "OU=ServiceAccounts,DC=contoso,DC=com"
    
    # Validate required parameters
    if ([string]::IsNullOrWhiteSpace($accountName)) {
        Write-Log "AccountName is required" -Level ERROR
        throw "Missing required parameter: AccountName"
    }
    
    if ([string]::IsNullOrWhiteSpace($dnsHostName)) {
        Write-Log "DNSHostName is required" -Level ERROR
        throw "Missing required parameter: DNSHostName"
    }
    
    Write-Log "Request parameters validated"
    Write-Log "Account Name: $accountName"
    Write-Log "DNS Host Name: $dnsHostName"
    Write-Log "Description: $description"
    
    # Import Active Directory module
    Write-Log "Importing Active Directory module"
    Import-Module ActiveDirectory -ErrorAction Stop
    
    # Get domain credentials from Key Vault
    $domainCredential = Get-AzureKeyVaultCredential `
        -VaultName $keyVaultName `
        -UsernameSecretName "DomainAdminUsername" `
        -PasswordSecretName "DomainAdminPassword"
    
    # Check if gMSA already exists
    Write-Log "Checking if gMSA already exists: $accountName"
    if (Test-gMSAExists -AccountName $accountName -Credential $domainCredential) {
        Write-Log "gMSA '$accountName' already exists" -Level WARNING
        
        # Return success but indicate it already exists
        $result = @{
            Status = "AlreadyExists"
            AccountName = $accountName
            Message = "gMSA already exists in Active Directory"
            Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        }
        
        Write-Output ($result | ConvertTo-Json)
        return
    }
    
    # Verify KDS Root Key exists (required for gMSA)
    Write-Log "Verifying KDS Root Key"
    $kdsRootKey = Get-KdsRootKey -Credential $domainCredential | Select-Object -First 1
    
    if ($null -eq $kdsRootKey) {
        Write-Log "No KDS Root Key found. Creating one..." -Level WARNING
        
        # Create KDS Root Key (use -EffectiveImmediately only in test environments)
        # In production, remove -EffectiveImmediately (10 hour wait required)
        Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10)) -Credential $domainCredential
        Write-Log "KDS Root Key created successfully" -Level SUCCESS
    }
    
    # Build parameters for New-ADServiceAccount
    $gmsaParams = @{
        Name = $accountName
        DNSHostName = $dnsHostName
        Credential = $domainCredential
        Server = $domainController
        Enabled = $true
    }
    
    # Add optional parameters
    if (-not [string]::IsNullOrWhiteSpace($description)) {
        $gmsaParams['Description'] = $description
    }
    
    if ($null -ne $principalsAllowedToRetrieve -and $principalsAllowedToRetrieve.Count -gt 0) {
        $gmsaParams['PrincipalsAllowedToRetrieveManagedPassword'] = $principalsAllowedToRetrieve
        Write-Log "Principals allowed to retrieve password: $($principalsAllowedToRetrieve -join ', ')"
    }
    
    if ($null -ne $servicePrincipalNames -and $servicePrincipalNames.Count -gt 0) {
        $gmsaParams['ServicePrincipalNames'] = $servicePrincipalNames
        Write-Log "Service Principal Names: $($servicePrincipalNames -join ', ')"
    }
    
    if (-not [string]::IsNullOrWhiteSpace($organizationalUnit)) {
        $gmsaParams['Path'] = $organizationalUnit
        Write-Log "Organizational Unit: $organizationalUnit"
    }
    
    if (-not [string]::IsNullOrWhiteSpace($kdsRootKeyId)) {
        $gmsaParams['KerberosEncryptionType'] = 'AES128,AES256'
        Write-Log "Using KDS Root Key: $kdsRootKeyId"
    }
    
    # Create the gMSA
    Write-Log "Creating gMSA: $accountName"
    New-ADServiceAccount @gmsaParams -ErrorAction Stop
    
    Write-Log "gMSA '$accountName' created successfully!" -Level SUCCESS
    
    # Verify creation
    Start-Sleep -Seconds 2
    $createdAccount = Get-ADServiceAccount -Identity $accountName -Server $domainController -Credential $domainCredential -Properties *
    
    if ($null -eq $createdAccount) {
        Write-Log "Failed to verify gMSA creation" -Level ERROR
        throw "gMSA creation verification failed"
    }
    
    Write-Log "gMSA creation verified" -Level SUCCESS
    
    # Prepare success response
    $result = @{
        Status = "Success"
        AccountName = $accountName
        DNSHostName = $dnsHostName
        DistinguishedName = $createdAccount.DistinguishedName
        SamAccountName = $createdAccount.SamAccountName
        ObjectGUID = $createdAccount.ObjectGUID.ToString()
        Created = $createdAccount.Created
        Message = "gMSA created successfully"
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }
    
    Write-Output "=========================================="
    Write-Output "gMSA Creation Successful"
    Write-Output "=========================================="
    Write-Output ($result | ConvertTo-Json -Depth 5)
    
}
catch {
    # Handle errors
    $errorMessage = $_.Exception.Message
    $errorDetails = $_.Exception | Format-List * -Force | Out-String
    
    Write-Log "ERROR: $errorMessage" -Level ERROR
    Write-Log "Error Details: $errorDetails" -Level ERROR
    
    # Prepare error response
    $result = @{
        Status = "Failed"
        AccountName = $accountName
        Error = $errorMessage
        ErrorDetails = $errorDetails
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }
    
    Write-Output "=========================================="
    Write-Output "gMSA Creation Failed"
    Write-Output "=========================================="
    Write-Output ($result | ConvertTo-Json -Depth 5)
    
    # Re-throw to mark the job as failed
    throw
}
finally {
    Write-Log "Runbook execution completed"
    Write-Output "=========================================="
}
#endregion
