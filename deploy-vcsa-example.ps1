# Example usage of deploy-vcsa.ps1
# This demonstrates how to call the script with all required parameters

.\deploy-vcsa.ps1 `
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
    -DeploymentSize "tiny" `
    -DiskMode "thin" `
    -FQDN "vcenter01.domain.com"

# Optional parameters (with defaults):
# -DeploymentSize: "tiny" (options: "tiny", "small", "medium", "large", "xlarge")
# -DiskMode: "thin" (options: "thin", "thick", "eagerZeroedThick")
# -FQDN: If omitted, uses IPAddress as PNID
