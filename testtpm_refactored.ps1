param (
    [parameter(Mandatory=$false)]
    [switch]$set
)

#region Helper Functions

function Get-HostEsxCli {
    <#
    .SYNOPSIS
    Gets ESXi CLI v2 interface for a host
    #>
    param([Parameter(Mandatory=$true)]$VMHost)
    
    return Get-EsxCli -VMHost $VMHost -V2
}

function Set-HostTPMConfiguration {
    <#
    .SYNOPSIS
    Configures TPM mode and enables key persistence for an ESXi host
    #>
    param([Parameter(Mandatory=$true)]$VMHost)
    
    Write-Host "Setting TPM configuration for: $($VMHost.Parent):$($VMHost.Name)"
    
    $esxcli = Get-HostEsxCli -VMHost $VMHost
    
    # Set encryption mode to TPM
    $encryptionArgs = $esxcli.system.settings.encryption.set.CreateArgs()
    $encryptionArgs.mode = "TPM"
    $esxcli.system.settings.encryption.set.Invoke($encryptionArgs) | Out-Null
    
    # Enable key persistence
    $esxcli.system.security.keypersistence.enable.Invoke() | Out-Null
    
    Write-Host "  ✓ TPM mode enabled and key persistence activated" -ForegroundColor Green
}

function Get-HostTPMDetails {
    <#
    .SYNOPSIS
    Retrieves TPM encryption details from an ESXi host
    #>
    param([Parameter(Mandatory=$true)]$VMHost)
    
    Write-Host "Collecting TPM keys from: $($VMHost.Parent):$($VMHost.Name)"
    
    $esxcli = Get-HostEsxCli -VMHost $VMHost
    
    # Gather all encryption details
    $hostname = $esxcli.system.hostname.get.Invoke()
    $recoveryInfo = $esxcli.system.settings.encryption.recovery.list.Invoke()
    $encryptionMode = $esxcli.system.settings.encryption.get.Invoke()
    $keyPersistence = $esxcli.system.security.keypersistence.get.Invoke()
    
    return [PSCustomObject]@{
        FQDN              = $hostname.FullyQualifiedDomainName
        'Recovery ID'     = $recoveryInfo.key
        Key               = $recoveryInfo.recoveryid
        Mode              = $encryptionMode.mode
        'Key Persistence' = $keyPersistence.enabled
    }
}

function Export-TPMKeysToCSV {
    <#
    .SYNOPSIS
    Exports TPM keys collection to timestamped CSV file
    #>
    param(
        [Parameter(Mandatory=$true)]$TPMData,
        [Parameter(Mandatory=$true)]$LastHost
    )
    
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $vcenterName = $LastHost.uid.Split('@')[1].Split(':')[0]
    $logFile = "tpm-keys-$vcenterName-$timestamp.csv"
    
    $TPMData | Export-Csv -Path $logFile -NoTypeInformation
    
    Write-Host "`n$($TPMData.Count) host(s) exported to $logFile" -ForegroundColor Cyan
}

function Get-AllESXiHosts {
    <#
    .SYNOPSIS
    Gets all ESXi hosts across all clusters, sorted
    #>
    return Get-Cluster | Sort-Object | Get-VMHost | Sort-Object
}

#endregion

#region Main Script Logic

if ($set) {
    # Configuration Mode: Set TPM mode and enable key persistence
    Write-Host "`n=== TPM Configuration Mode ===" -ForegroundColor Yellow
    Write-Host "WARNING: This will modify TPM settings for ALL hosts in ALL clusters`n" -ForegroundColor Red
    
    $hosts = Get-AllESXiHosts
    $totalHosts = $hosts.Count
    $currentHost = 0
    
    foreach ($host in $hosts) {
        $currentHost++
        Write-Host "`n[$currentHost/$totalHosts] " -NoNewline -ForegroundColor Gray
        
        try {
            Set-HostTPMConfiguration -VMHost $host
        }
        catch {
            Write-Host "  ✗ Error: $_" -ForegroundColor Red
        }
    }
    
    Write-Host "`n=== Configuration Complete ===" -ForegroundColor Green
}
else {
    # Collection Mode: Gather TPM keys and export to CSV
    Write-Host "`n=== TPM Key Collection Mode ===" -ForegroundColor Yellow
    
    $tpmKeysCollection = @()
    $hosts = Get-AllESXiHosts
    $totalHosts = $hosts.Count
    $currentHost = 0
    $lastHost = $null
    
    foreach ($host in $hosts) {
        $currentHost++
        Write-Host "`n[$currentHost/$totalHosts] " -NoNewline -ForegroundColor Gray
        
        try {
            $tpmDetails = Get-HostTPMDetails -VMHost $host
            $tpmKeysCollection += $tpmDetails
            $lastHost = $host
        }
        catch {
            Write-Host "  ✗ Error collecting data: $_" -ForegroundColor Red
        }
    }
    
    if ($tpmKeysCollection.Count -gt 0 -and $lastHost) {
        Write-Host "`n=== Exporting Results ===" -ForegroundColor Yellow
        Export-TPMKeysToCSV -TPMData $tpmKeysCollection -LastHost $lastHost
    }
    else {
        Write-Host "`nNo TPM data collected. Ensure you are connected to vCenter." -ForegroundColor Red
    }
}

#endregion
