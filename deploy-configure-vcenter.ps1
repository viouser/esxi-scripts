param (
    # Deployment Parameters
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
    
    # Configuration Parameters
    [Parameter(Mandatory=$false)]
    [string]$DatacenterName = "Datacenter",
    
    [Parameter(Mandatory=$false)]
    [string]$ClusterName = "Cluster01",
    
    [Parameter(Mandatory=$false)]
    [string[]]$NTPServers,
    
    [Parameter(Mandatory=$false)]
    [string]$LicenseKey,
    
    [Parameter(Mandatory=$false)]
    [switch]$EnableHA,
    
    [Parameter(Mandatory=$false)]
    [switch]$EnableDRS,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('Manual', 'PartiallyAutomated', 'FullyAutomated')]
    [string]$DRSAutomationLevel = 'FullyAutomated',
    
    # Optional Deployment Parameters
    [Parameter(Mandatory=$false)]
    [string]$DeploymentSize = "tiny",
    
    [Parameter(Mandatory=$false)]
    [string]$DiskMode = "thin",
    
    [Parameter(Mandatory=$false)]
    [string]$FQDN,
    
    # Workflow Control
    [Parameter(Mandatory=$false)]
    [int]$VCSAReadyTimeout = 45
)

#region Helper Functions

function Write-WorkflowHeader {
    param([string]$Title)
    
    Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  $($Title.PadRight(57)) ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
}

function Write-WorkflowStep {
    param([string]$Step, [string]$Description)
    
    Write-Host "`n[STEP $Step] $Description" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Gray
}

function Test-Prerequisites {
    Write-WorkflowStep -Step "0" -Description "Validating Prerequisites"
    
    # Check PowerCLI
    $powerCLI = Get-Module -Name VMware.PowerCLI -ListAvailable
    if (-not $powerCLI) {
        throw "VMware PowerCLI module not found. Install with: Install-Module -Name VMware.PowerCLI"
    }
    Write-Host "✓ PowerCLI module found" -ForegroundColor Green
    
    # Check OVFTool
    $ovfTool = "C:\Program Files\VMware\VMware OVF Tool\ovftool.exe"
    if (-not (Test-Path $ovfTool)) {
        throw "OVFTool not found at: $ovfTool. Please install VMware OVF Tool."
    }
    Write-Host "✓ OVFTool found" -ForegroundColor Green
    
    # Check OVA file
    if (-not (Test-Path $OVAPath)) {
        throw "OVA file not found at: $OVAPath"
    }
    Write-Host "✓ OVA file exists: $OVAPath" -ForegroundColor Green
    
    # Test ESXi connectivity
    try {
        $null = Connect-VIServer -Server $ESXiHost -User $ESXiUser -Password $ESXiPassword -ErrorAction Stop
        Write-Host "✓ ESXi host accessible: $ESXiHost" -ForegroundColor Green
        Disconnect-VIServer -Server * -Confirm:$false
    }
    catch {
        throw "Cannot connect to ESXi host: $_"
    }
}

function Get-SubnetPrefix {
    param([string]$SubnetMask)
    
    $octets = $SubnetMask.Split('.')
    $binaryString = ""
    
    foreach ($octet in $octets) {
        $binaryString += [Convert]::ToString([int]$octet, 2).PadLeft(8, '0')
    }
    
    return ($binaryString.ToCharArray() | Where-Object { $_ -eq '1' }).Count
}

function Invoke-VCSADeployment {
    Write-WorkflowStep -Step "1" -Description "Deploying VCSA OVA"
    
    $ovfTool = "C:\Program Files\VMware\VMware OVF Tool\ovftool.exe"
    
    # Build OVF configuration
    $config = @{
        'deployment_option.value' = $DeploymentSize
        'guestinfo.cis.appliance.net.addr.family' = 'ipv4'
        'guestinfo.cis.appliance.net.mode' = 'static'
        'guestinfo.cis.appliance.net.addr' = $IPAddress
        'guestinfo.cis.appliance.net.pnid' = if ($FQDN) { $FQDN } else { $IPAddress }
        'guestinfo.cis.appliance.net.prefix' = (Get-SubnetPrefix -SubnetMask $SubnetMask)
        'guestinfo.cis.appliance.net.gateway' = $Gateway
        'guestinfo.cis.appliance.net.dns.servers' = $DNSServer
        'guestinfo.cis.appliance.root.passwd' = $RootPassword
        'guestinfo.cis.vmdir.domain-name' = $SSO_DomainName
        'guestinfo.cis.vmdir.password' = $SSO_Password
    }
    
    # Build property assignments
    $properties = @()
    foreach ($key in $config.Keys) {
        $properties += "--prop:$key=$($config[$key])"
    }
    
    # Construct OVFTool command
    $command = @(
        "`"$ovfTool`""
        "--acceptAllEulas"
        "--allowExtraConfig"
        "--diskMode=$DiskMode"
        "--datastore=`"$Datastore`""
        "--network=`"$NetworkName`""
        "--name=`"$VMName`""
        ($properties -join " ")
        "`"$OVAPath`""
        "vi://$($ESXiUser):$($ESXiPassword)@$ESXiHost/"
    ) -join " "
    
    Write-Host "Deployment Size: $DeploymentSize" -ForegroundColor Cyan
    Write-Host "IP Address: $IPAddress" -ForegroundColor Cyan
    Write-Host "`nThis may take 15-30 minutes...`n" -ForegroundColor Yellow
    
    try {
        $result = Invoke-Expression $command
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "`n✓ VCSA OVA deployment completed" -ForegroundColor Green
            return $true
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
    Write-WorkflowStep -Step "2" -Description "Waiting for VCSA to Initialize"
    
    Write-Host "Checking VCSA web interface availability..." -ForegroundColor Cyan
    Write-Host "This typically takes 10-15 minutes after OVA deployment`n" -ForegroundColor Yellow
    
    $timeout = (Get-Date).AddMinutes($VCSAReadyTimeout)
    $ready = $false
    $attempts = 0
    
    while ((Get-Date) -lt $timeout -and -not $ready) {
        $attempts++
        try {
            $response = Invoke-WebRequest -Uri "https://$IPAddress" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                $ready = $true
            }
        }
        catch {
            Write-Host "." -NoNewline
            if ($attempts % 60 -eq 0) {
                $elapsed = [math]::Round(((Get-Date) - $timeout.AddMinutes($VCSAReadyTimeout)).TotalMinutes * -1, 1)
                Write-Host " ($elapsed min elapsed)" -ForegroundColor Gray
            }
            Start-Sleep -Seconds 30
        }
    }
    
    if ($ready) {
        Write-Host "`n✓ VCSA web interface is responding" -ForegroundColor Green
        Write-Host "Waiting additional 2 minutes for services to fully initialize..." -ForegroundColor Yellow
        Start-Sleep -Seconds 120
        return $true
    }
    else {
        Write-Host "`n✗ VCSA not responding after $VCSAReadyTimeout minutes" -ForegroundColor Red
        throw "VCSA readiness timeout - check appliance status manually"
    }
}

function Invoke-VCenterConfiguration {
    Write-WorkflowStep -Step "3" -Description "Configuring vCenter Server"
    
    # Connect to vCenter
    Write-Host "Connecting to vCenter..." -ForegroundColor Cyan
    try {
        $vcUser = "administrator@$SSO_DomainName"
        $connection = Connect-VIServer -Server $IPAddress -User $vcUser -Password $SSO_Password -ErrorAction Stop
        Write-Host "✓ Connected to vCenter as $vcUser" -ForegroundColor Green
    }
    catch {
        throw "Failed to connect to vCenter: $_"
    }
    
    # Configure license (if provided)
    if ($LicenseKey) {
        Write-Host "`nConfiguring license..." -ForegroundColor Cyan
        try {
            $licenseManager = Get-View -Id 'LicenseManager-LicenseManager'
            $licenseAssignmentManager = Get-View -Id $licenseManager.LicenseAssignmentManager
            
            $license = $licenseManager.AddLicense($LicenseKey, $null)
            $vcenterInstanceId = $licenseAssignmentManager.QueryAssignedLicenses($global:DefaultVIServer.InstanceUuid)[0].EntityId
            $licenseAssignmentManager.UpdateAssignedLicense($vcenterInstanceId, $LicenseKey, $null)
            Write-Host "✓ License configured: $($license.Name)" -ForegroundColor Green
        }
        catch {
            Write-Host "⚠ License configuration failed: $_" -ForegroundColor Yellow
        }
    }
    
    # Create datacenter
    Write-Host "`nCreating datacenter '$DatacenterName'..." -ForegroundColor Cyan
    try {
        $datacenter = Get-Datacenter -Name $DatacenterName -ErrorAction SilentlyContinue
        if (-not $datacenter) {
            $datacenter = New-Datacenter -Location (Get-Folder -NoRecursion) -Name $DatacenterName
            Write-Host "✓ Datacenter created" -ForegroundColor Green
        }
        else {
            Write-Host "⚠ Datacenter already exists" -ForegroundColor Yellow
        }
    }
    catch {
        throw "Failed to create datacenter: $_"
    }
    
    # Create cluster
    Write-Host "`nCreating cluster '$ClusterName'..." -ForegroundColor Cyan
    try {
        $cluster = Get-Cluster -Name $ClusterName -Location $datacenter -ErrorAction SilentlyContinue
        if (-not $cluster) {
            $clusterParams = @{
                Name = $ClusterName
                Location = $datacenter
                HAEnabled = $EnableHA
                DrsEnabled = $EnableDRS
            }
            
            if ($EnableDRS) {
                $clusterParams.DrsAutomationLevel = $DRSAutomationLevel
            }
            
            $cluster = New-Cluster @clusterParams
            Write-Host "✓ Cluster created" -ForegroundColor Green
            if ($EnableHA) { Write-Host "  - HA: Enabled" -ForegroundColor Cyan }
            if ($EnableDRS) { Write-Host "  - DRS: Enabled ($DRSAutomationLevel)" -ForegroundColor Cyan }
        }
        else {
            Write-Host "⚠ Cluster already exists" -ForegroundColor Yellow
        }
    }
    catch {
        throw "Failed to create cluster: $_"
    }
    
    # Configure NTP (if provided)
    if ($NTPServers) {
        Write-Host "`nConfiguring NTP servers..." -ForegroundColor Cyan
        try {
            $vami = Get-CisService -Name 'com.vmware.appliance.techpreview.ntp'
            $vami.set($NTPServers)
            
            $ntpService = Get-CisService -Name 'com.vmware.appliance.techpreview.services.service'
            $ntpService.restart(@{service_name = 'ntpd'})
            Write-Host "✓ NTP servers configured: $($NTPServers -join ', ')" -ForegroundColor Green
        }
        catch {
            Write-Host "⚠ NTP configuration failed: $_" -ForegroundColor Yellow
        }
    }
    
    # Configure advanced settings
    Write-Host "`nConfiguring advanced settings..." -ForegroundColor Cyan
    try {
        $advSettings = @{
            'config.vpxd.event.maxAgeEnabled' = 'true'
            'config.vpxd.event.maxAge' = '30'
            'config.vpxd.task.maxAgeEnabled' = 'true'
            'config.vpxd.task.maxAge' = '30'
        }
        
        foreach ($setting in $advSettings.GetEnumerator()) {
            Get-AdvancedSetting -Entity $global:DefaultVIServer -Name $setting.Key | 
                Set-AdvancedSetting -Value $setting.Value -Confirm:$false | Out-Null
        }
        Write-Host "✓ Advanced settings configured" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠ Some advanced settings failed" -ForegroundColor Yellow
    }
    
    Write-Host "`n✓ vCenter configuration completed" -ForegroundColor Green
}

function Show-DeploymentSummary {
    Write-WorkflowHeader -Title "Deployment & Configuration Summary"
    
    Write-Host "VM Name:          $VMName" -ForegroundColor White
    Write-Host "IP Address:       $IPAddress" -ForegroundColor White
    Write-Host "FQDN:             $(if ($FQDN) { $FQDN } else { 'N/A' })" -ForegroundColor White
    Write-Host "Datastore:        $Datastore" -ForegroundColor White
    Write-Host "Network:          $NetworkName" -ForegroundColor White
    Write-Host "Deployment Size:  $DeploymentSize" -ForegroundColor White
    
    Write-Host "`n=== vCenter Configuration ===" -ForegroundColor Yellow
    Write-Host "Datacenter:       $DatacenterName" -ForegroundColor White
    Write-Host "Cluster:          $ClusterName" -ForegroundColor White
    Write-Host "HA Enabled:       $EnableHA" -ForegroundColor White
    Write-Host "DRS Enabled:      $EnableDRS" -ForegroundColor White
    if ($EnableDRS) {
        Write-Host "DRS Automation:   $DRSAutomationLevel" -ForegroundColor White
    }
    
    Write-Host "`n=== Access Information ===" -ForegroundColor Yellow
    Write-Host "Web UI:           https://$IPAddress/" -ForegroundColor Green
    Write-Host "VAMI:             https://$IPAddress`:5480/" -ForegroundColor Green
    Write-Host "SSO Domain:       $SSO_DomainName" -ForegroundColor Green
    Write-Host "Administrator:    administrator@$SSO_DomainName" -ForegroundColor Green
    
    Write-Host "`n=== Next Steps ===" -ForegroundColor Yellow
    Write-Host "1. Add ESXi hosts to cluster:" -ForegroundColor White
    Write-Host "   Add-VMHost -Name <esxi-host> -Location '$ClusterName' -User root -Password <password>" -ForegroundColor Gray
    Write-Host "2. Configure storage (datastores, datastore clusters)" -ForegroundColor White
    Write-Host "3. Set up networking (distributed switches, port groups)" -ForegroundColor White
    Write-Host "4. Create VM templates and content library" -ForegroundColor White
    Write-Host "5. Configure backup and monitoring solutions`n" -ForegroundColor White
}

#endregion

#region Main Workflow

Write-WorkflowHeader -Title "vCenter Server Automated Deployment & Configuration"

Write-Host "This workflow will:" -ForegroundColor Cyan
Write-Host "  1. Deploy VCSA OVA to ESXi host" -ForegroundColor White
Write-Host "  2. Wait for VCSA initialization" -ForegroundColor White
Write-Host "  3. Configure vCenter (datacenter, cluster, settings)" -ForegroundColor White
Write-Host "`nEstimated time: 20-40 minutes`n" -ForegroundColor Yellow

try {
    # Step 0: Prerequisites
    Test-Prerequisites
    
    # Step 1: Deploy VCSA
    Invoke-VCSADeployment
    
    # Step 2: Wait for readiness
    Wait-VCSAReady
    
    # Step 3: Configure vCenter
    Invoke-VCenterConfiguration
    
    # Summary
    Show-DeploymentSummary
    
    Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║         Workflow Completed Successfully                   ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Green
}
catch {
    Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║         Workflow Failed                                    ║" -ForegroundColor Red
    Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "`nCheck the error above and retry or complete manually." -ForegroundColor Yellow
    exit 1
}
finally {
    # Disconnect from any servers
    if ($global:DefaultVIServer) {
        Disconnect-VIServer -Server * -Confirm:$false
    }
}

#endregion
