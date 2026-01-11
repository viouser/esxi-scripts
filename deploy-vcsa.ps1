param (
    [Parameter(Mandatory=$true)]
    [string]$OVAPath,
    
    [Parameter(Mandatory=$true)]
    [string]$ESXiHost,
    
    [Parameter(Mandatory=$true)]
    [string]$ESXiUser,
    
    [Parameter(Mandatory=$true)]
    [string]$ESXiPassword,
    
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    
    [Parameter(Mandatory=$true)]
    [string]$Datastore,
    
    [Parameter(Mandatory=$true)]
    [string]$NetworkName,
    
    [Parameter(Mandatory=$true)]
    [string]$IPAddress,
    
    [Parameter(Mandatory=$true)]
    [string]$SubnetMask,
    
    [Parameter(Mandatory=$true)]
    [string]$Gateway,
    
    [Parameter(Mandatory=$true)]
    [string]$DNSServer,
    
    [Parameter(Mandatory=$true)]
    [string]$RootPassword,
    
    [Parameter(Mandatory=$true)]
    [string]$SSO_DomainName,
    
    [Parameter(Mandatory=$true)]
    [string]$SSO_Password,
    
    [Parameter(Mandatory=$false)]
    [string]$DeploymentSize = "tiny",
    
    [Parameter(Mandatory=$false)]
    [string]$DiskMode = "thin",
    
    [Parameter(Mandatory=$false)]
    [string]$FQDN
)

#region Helper Functions

function Test-Prerequisites {
    <#
    .SYNOPSIS
    Validates prerequisites for VCSA deployment
    #>
    Write-Host "`n=== Validating Prerequisites ===" -ForegroundColor Yellow
    
    # Check if OVFTool is installed
    $ovfTool = "C:\Program Files\VMware\VMware OVF Tool\ovftool.exe"
    if (-not (Test-Path $ovfTool)) {
        throw "OVFTool not found at: $ovfTool. Please install VMware OVF Tool."
    }
    Write-Host "✓ OVFTool found" -ForegroundColor Green
    
    # Check if OVA file exists
    if (-not (Test-Path $OVAPath)) {
        throw "OVA file not found at: $OVAPath"
    }
    Write-Host "✓ OVA file exists: $OVAPath" -ForegroundColor Green
    
    # Test ESXi connectivity
    try {
        $null = Connect-VIServer -Server $ESXiHost -User $ESXiUser -Password $ESXiPassword -ErrorAction Stop
        Write-Host "✓ ESXi host accessible: $ESXiHost" -ForegroundColor Green
    }
    catch {
        throw "Cannot connect to ESXi host: $_"
    }
}

function New-OVFConfiguration {
    <#
    .SYNOPSIS
    Builds OVF configuration object for VCSA deployment
    #>
    param(
        [Parameter(Mandatory=$true)]$Parameters
    )
    
    Write-Host "`n=== Building OVF Configuration ===" -ForegroundColor Yellow
    
    $config = @{
        'deployment_option.value' = $Parameters.DeploymentSize
        'guestinfo.cis.appliance.net.addr.family' = 'ipv4'
        'guestinfo.cis.appliance.net.mode' = 'static'
        'guestinfo.cis.appliance.net.addr' = $Parameters.IPAddress
        'guestinfo.cis.appliance.net.pnid' = if ($Parameters.FQDN) { $Parameters.FQDN } else { $Parameters.IPAddress }
        'guestinfo.cis.appliance.net.prefix' = (Get-SubnetPrefix -SubnetMask $Parameters.SubnetMask)
        'guestinfo.cis.appliance.net.gateway' = $Parameters.Gateway
        'guestinfo.cis.appliance.net.dns.servers' = $Parameters.DNSServer
        'guestinfo.cis.appliance.root.passwd' = $Parameters.RootPassword
        'guestinfo.cis.vmdir.domain-name' = $Parameters.SSO_DomainName
        'guestinfo.cis.vmdir.password' = $Parameters.SSO_Password
    }
    
    Write-Host "✓ Configuration built" -ForegroundColor Green
    return $config
}

function Get-SubnetPrefix {
    <#
    .SYNOPSIS
    Converts subnet mask to prefix length (e.g., 255.255.255.0 -> 24)
    #>
    param([string]$SubnetMask)
    
    $octets = $SubnetMask.Split('.')
    $binaryString = ""
    
    foreach ($octet in $octets) {
        $binaryString += [Convert]::ToString([int]$octet, 2).PadLeft(8, '0')
    }
    
    return ($binaryString.ToCharArray() | Where-Object { $_ -eq '1' }).Count
}

function Build-OVFToolCommand {
    <#
    .SYNOPSIS
    Constructs the OVFTool command line for deployment
    #>
    param(
        [Parameter(Mandatory=$true)]$Parameters,
        [Parameter(Mandatory=$true)]$Config
    )
    
    $ovfTool = "C:\Program Files\VMware\VMware OVF Tool\ovftool.exe"
    
    # Build property assignments
    $properties = @()
    foreach ($key in $Config.Keys) {
        $properties += "--prop:$key=$($Config[$key])"
    }
    
    # Construct command
    $command = @(
        "`"$ovfTool`""
        "--acceptAllEulas"
        "--allowExtraConfig"
        "--diskMode=$($Parameters.DiskMode)"
        "--datastore=`"$($Parameters.Datastore)`""
        "--network=`"$($Parameters.NetworkName)`""
        "--name=`"$($Parameters.VMName)`""
        ($properties -join " ")
        "`"$($Parameters.OVAPath)`""
        "vi://$($Parameters.ESXiUser):$($Parameters.ESXiPassword)@$($Parameters.ESXiHost)/"
    )
    
    return $command -join " "
}

function Start-VCSADeployment {
    <#
    .SYNOPSIS
    Executes VCSA OVA deployment using OVFTool
    #>
    param(
        [Parameter(Mandatory=$true)]$Parameters,
        [Parameter(Mandatory=$true)]$Config
    )
    
    Write-Host "`n=== Starting VCSA Deployment ===" -ForegroundColor Yellow
    Write-Host "VM Name: $($Parameters.VMName)" -ForegroundColor Cyan
    Write-Host "IP Address: $($Parameters.IPAddress)" -ForegroundColor Cyan
    Write-Host "Deployment Size: $($Parameters.DeploymentSize)" -ForegroundColor Cyan
    Write-Host "`nThis may take 15-30 minutes...`n" -ForegroundColor Yellow
    
    $command = Build-OVFToolCommand -Parameters $Parameters -Config $Config
    
    try {
        $result = Invoke-Expression $command
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "`n✓ VCSA deployment completed successfully" -ForegroundColor Green
            return $result
        }
        else {
            throw "OVFTool deployment failed with exit code: $LASTEXITCODE"
        }
    }
    catch {
        Write-Host "`n✗ Deployment failed: $_" -ForegroundColor Red
        throw
    }
}

function Wait-VCSAReady {
    <#
    .SYNOPSIS
    Waits for VCSA to complete first boot and configuration
    #>
    param(
        [Parameter(Mandatory=$true)]$IPAddress,
        [Parameter(Mandatory=$false)]$TimeoutMinutes = 30
    )
    
    Write-Host "`n=== Waiting for VCSA to become ready ===" -ForegroundColor Yellow
    
    $timeout = (Get-Date).AddMinutes($TimeoutMinutes)
    $ready = $false
    
    while ((Get-Date) -lt $timeout -and -not $ready) {
        try {
            $response = Invoke-WebRequest -Uri "https://$IPAddress" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                $ready = $true
            }
        }
        catch {
            Write-Host "." -NoNewline
            Start-Sleep -Seconds 30
        }
    }
    
    if ($ready) {
        Write-Host "`n✓ VCSA web interface is responding" -ForegroundColor Green
    }
    else {
        Write-Host "`n⚠ VCSA not responding after $TimeoutMinutes minutes" -ForegroundColor Yellow
        Write-Host "You may need to check the appliance manually." -ForegroundColor Yellow
    }
}

function Show-DeploymentSummary {
    <#
    .SYNOPSIS
    Displays deployment summary information
    #>
    param([Parameter(Mandatory=$true)]$Parameters)
    
    Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║         VCSA Deployment Summary                           ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    Write-Host "VM Name:          $($Parameters.VMName)" -ForegroundColor White
    Write-Host "IP Address:       $($Parameters.IPAddress)" -ForegroundColor White
    Write-Host "Datastore:        $($Parameters.Datastore)" -ForegroundColor White
    Write-Host "Network:          $($Parameters.NetworkName)" -ForegroundColor White
    Write-Host "Deployment Size:  $($Parameters.DeploymentSize)" -ForegroundColor White
    
    Write-Host "`n=== Access Information ===" -ForegroundColor Yellow
    Write-Host "Web UI:           https://$($Parameters.IPAddress)/" -ForegroundColor Green
    Write-Host "SSO Domain:       $($Parameters.SSO_DomainName)" -ForegroundColor Green
    Write-Host "Administrator:    administrator@$($Parameters.SSO_DomainName)" -ForegroundColor Green
    
    Write-Host "`n=== Next Steps ===" -ForegroundColor Yellow
    Write-Host "1. Access the web UI (may take a few more minutes)" -ForegroundColor White
    Write-Host "2. Log in with administrator@$($Parameters.SSO_DomainName)" -ForegroundColor White
    Write-Host "3. Complete post-deployment configuration wizard" -ForegroundColor White
    Write-Host "4. Add ESXi hosts to the inventory`n" -ForegroundColor White
}

#endregion

#region Main Deployment Logic

try {
    # Validate prerequisites
    Test-Prerequisites
    
    # Build deployment parameters object
    $deployParams = @{
        OVAPath = $OVAPath
        ESXiHost = $ESXiHost
        ESXiUser = $ESXiUser
        ESXiPassword = $ESXiPassword
        VMName = $VMName
        Datastore = $Datastore
        NetworkName = $NetworkName
        IPAddress = $IPAddress
        SubnetMask = $SubnetMask
        Gateway = $Gateway
        DNSServer = $DNSServer
        RootPassword = $RootPassword
        SSO_DomainName = $SSO_DomainName
        SSO_Password = $SSO_Password
        DeploymentSize = $DeploymentSize
        DiskMode = $DiskMode
        FQDN = $FQDN
    }
    
    # Create OVF configuration
    $ovfConfig = New-OVFConfiguration -Parameters $deployParams
    
    # Deploy VCSA
    $deploymentResult = Start-VCSADeployment -Parameters $deployParams -Config $ovfConfig
    
    # Wait for VCSA to be ready
    Wait-VCSAReady -IPAddress $IPAddress -TimeoutMinutes 30
    
    # Show summary
    Show-DeploymentSummary -Parameters $deployParams
    
    Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║         Deployment Completed Successfully                 ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Green
}
catch {
    Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║         Deployment Failed                                  ║" -ForegroundColor Red
    Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "`nPlease check the logs and retry." -ForegroundColor Yellow
    exit 1
}
finally {
    # Disconnect from ESXi
    if ($global:DefaultVIServer) {
        Disconnect-VIServer -Server * -Confirm:$false
    }
}

#endregion
