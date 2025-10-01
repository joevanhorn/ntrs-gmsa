<#
.SYNOPSIS
    Creates a Group Managed Service Account (gMSA) in Active Directory via Azure Runbook

.DESCRIPTION
    This runbook accepts a JSON payload from Okta Workflows via webhook and creates
    a gMSA in Active Directory using remote PowerShell execution on the domain controller.

.PARAMETER WebhookData
    Automatically passed by Azure Automation when triggered via webhook

.NOTES
    Author: Azure Automation
    Requirements: 
    - Hybrid Runbook Worker on domain-joined server
    - Domain admin credentials in Automation Account
    - PowerShell remoting enabled on domain controller
#>

param(
    [Parameter(Mandatory = $false)]
    [object]$WebhookData
)

#region Configuration
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Domain controller configuration - Terraform substitutes this value
$domainController = "${domain_controller}"

# Automation credential name
$credentialName = "DomainAdminCredential"

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
        default   { Write-Output $logMessage }
    }
}
#endregion

#region Main Execution
try {
    # Get domain credentials from Automation Account
    Write-Log "Retrieving credentials from Automation Account"
    $domainCredential = Get-AutomationPSCredential -Name $credentialName
    
    if ($null -eq $domainCredential) {
        Write-Log "Failed to retrieve credentials from Automation Account" -Level ERROR
        throw "Credential retrieval failed"
    }
    
    Write-Log "Credentials retrieved successfully" -Level SUCCESS
    
    # Validate webhook data
    if ($null -eq $WebhookData) {
        Write-Log "No webhook data received. This runbook must be triggered via webhook." -Level ERROR
        throw "No webhook data provided"
    }
    
    Write-Log "Webhook data received"
    
    # Parse the request body
    Write-Log "Parsing request body"
    $requestBody = $WebhookData.RequestBody | ConvertFrom-Json
    
    # Extract parameters
    $accountName = $requestBody.AccountName
    $dnsHostName = $requestBody.DNSHostName
    $principalsAllowedToRetrieve = $requestBody.PrincipalsAllowedToRetrieve
    $description = $requestBody.Description
    $servicePrincipalNames = $requestBody.ServicePrincipalNames
    $organizationalUnit = $requestBody.OrganizationalUnit
    
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
    
    # Define the script block to execute on the domain controller
    $scriptBlock = {
        param(
            [string]$AccountName,
            [string]$DNSHostName,
            [array]$PrincipalsAllowedToRetrieve,
            [string]$Description,
            [array]$ServicePrincipalNames,
            [string]$OrganizationalUnit
        )
        
        # Import Active Directory module
        Import-Module ActiveDirectory -ErrorAction Stop
        
        # Check if gMSA already exists
        $existingAccount = Get-ADServiceAccount -Filter "Name -eq '$AccountName'" -ErrorAction SilentlyContinue
        
        if ($existingAccount) {
            return @{
                Status = "AlreadyExists"
                AccountName = $AccountName
                Message = "gMSA already exists in Active Directory"
                DistinguishedName = $existingAccount.DistinguishedName
            }
        }
        
        # Verify KDS Root Key exists (required for gMSA)
        $kdsRootKey = Get-KdsRootKey | Select-Object -First 1
        
        if ($null -eq $kdsRootKey) {
            # Create KDS Root Key with immediate effect (test/demo only)
            # In production, remove -EffectiveImmediately for proper 10-hour replication
            Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10)) | Out-Null
        }
        
        # Build parameters for New-ADServiceAccount
        $gmsaParams = @{
            Name = $AccountName
            DNSHostName = $DNSHostName
            Enabled = $true
        }
        
        # Add optional parameters
        if (-not [string]::IsNullOrWhiteSpace($Description)) {
            $gmsaParams['Description'] = $Description
        }
        
        if ($null -ne $PrincipalsAllowedToRetrieve -and $PrincipalsAllowedToRetrieve.Count -gt 0) {
            $gmsaParams['PrincipalsAllowedToRetrieveManagedPassword'] = $PrincipalsAllowedToRetrieve
        }
        
        if ($null -ne $ServicePrincipalNames -and $ServicePrincipalNames.Count -gt 0) {
            $gmsaParams['ServicePrincipalNames'] = $ServicePrincipalNames
        }
        
        if (-not [string]::IsNullOrWhiteSpace($OrganizationalUnit)) {
            $gmsaParams['Path'] = $OrganizationalUnit
        }
        
        # Create the gMSA
        New-ADServiceAccount @gmsaParams -ErrorAction Stop
        
        # Verify creation
        Start-Sleep -Seconds 2
        $createdAccount = Get-ADServiceAccount -Identity $AccountName -Properties * -ErrorAction Stop
        
        # Return success result
        return @{
            Status = "Success"
            AccountName = $AccountName
            DNSHostName = $DNSHostName
            DistinguishedName = $createdAccount.DistinguishedName
            SamAccountName = $createdAccount.SamAccountName
            ObjectGUID = $createdAccount.ObjectGUID.ToString()
            Created = $createdAccount.Created.ToString('yyyy-MM-dd HH:mm:ss')
            Message = "gMSA created successfully"
        }
    }
    
    # Execute the script block on the domain controller
    Write-Log "Connecting to domain controller: $domainController"
    Write-Log "Executing gMSA creation commands"
    
    $result = Invoke-Command `
        -ComputerName $domainController `
        -Credential $domainCredential `
        -ScriptBlock $scriptBlock `
        -ArgumentList $accountName, $dnsHostName, $principalsAllowedToRetrieve, $description, $servicePrincipalNames, $organizationalUnit `
        -ErrorAction Stop
    
    Write-Log "gMSA operation completed successfully" -Level SUCCESS
    
    # Add timestamp to result
    $result['Timestamp'] = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    
    Write-Output "=========================================="
    Write-Output "gMSA Creation Result"
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
