# Example usage of deploy-configure-vcenter.ps1
# This demonstrates the complete automated workflow from deployment to configuration

.\deploy-configure-vcenter.ps1 `
    -OVAPath "C:\path\to\VMware-vCenter-Server-Appliance-8.0.x.x-xxxxxxxx.ova" `
    -ESXiHost "192.168.1.10" `
    -ESXiUser "root" `
    -ESXiPassword "YourESXiPassword" `
    -VMName "vCenter01" `
    -Datastore "datastore1" `
    -NetworkName "VM Network" `
    -IPAddress "192.168.1.100" `
    -SubnetMask "255.255.255.0" `
    -Gateway "192.168.1.1" `
    -DNSServer "192.168.1.1" `
    -RootPassword "YourRootPassword" `
    -SSO_DomainName "vsphere.local" `
    -SSO_Password "YourSSOPassword" `
    -DatacenterName "Production-DC" `
    -ClusterName "Cluster01" `
    -EnableHA `
    -EnableDRS `
    -DRSAutomationLevel "FullyAutomated" `
    -NTPServers @("pool.ntp.org", "time.google.com") `
    -LicenseKey "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX" `
    -DeploymentSize "tiny" `
    -FQDN "vcenter01.domain.com"

# Minimal configuration example (defaults):
.\deploy-configure-vcenter.ps1 `
    -OVAPath "C:\VMware-vCenter-8.0.ova" `
    -ESXiHost "192.168.1.10" `
    -ESXiUser "root" `
    -ESXiPassword "password" `
    -VMName "vCenter01" `
    -Datastore "datastore1" `
    -NetworkName "VM Network" `
    -IPAddress "192.168.1.100" `
    -SubnetMask "255.255.255.0" `
    -Gateway "192.168.1.1" `
    -DNSServer "192.168.1.1" `
    -RootPassword "root123" `
    -SSO_DomainName "vsphere.local" `
    -SSO_Password "sso123"
