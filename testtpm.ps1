param (
    [parameter(Mandatory=$false)]
    [switch]$set
)

if ($PSBoundParameters.ContainsKey('set')) {
    # Foreach ($h1 in Get-cluster |Sort-Object | Get-VMHost |Sort-Object |Select-Object -first 1 ) { # Check first host while testing
    Foreach ($h1 in Get-cluster |Sort-Object | Get-VMHost |Sort-Object ) {
        Write-host "Setting: Mode:TPM, keypersistence enable: $($h1.parent):$($h1.name)"
        $esxcli = Get-EsxCli -VMHost $h1 -V2 # Using v2
        $arguments = $esxcli.system.settings.encryption.set.CreateArgs()
        $arguments.mode = "TPM"
        $esxcli.system.settings.encryption.set.Invoke($arguments)
        $esxcli.system.security.keypersistence.enable.invoke()
    }
} else {

    $TPMkeysTable = @()
    Foreach ($h1 in Get-cluster |Sort-Object | Get-VMHost |Sort-Object ) {
        Write-host "Collecting TPM keys from: $($h1.parent):$($h1.name)"
        $esxcli = Get-EsxCli -VMHost $h1 -V2 # Using v2

        $myObject = [PSCustomObject]@{
            FQDN = $esxcli.system.hostname.get.invoke().FullyQualifiedDomainName
            'Recovery ID' = $esxcli.system.settings.encryption.recovery.list.invoke().key
            Key = $esxcli.system.settings.encryption.recovery.list.invoke().recoveryid
            Mode = $esxcli.system.settings.encryption.get.invoke().mode
            'Key Persistence' = $esxcli.system.security.keypersistence.get.invoke().enabled
        }
        $TPMkeystable += $myObject
    }
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $logFile = "tpm-keys-$($h1.uid.Split('@')[1].Split(':')[0])-$timestamp.csv" # Gets vCenter from UID
    $TPMkeysTable | ConvertTo-Csv | Out-File -FilePath $logFile
    Write-host "$($TPMkeysTable.count) lines written to $logFile"
}
