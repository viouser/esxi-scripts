# AGENTS.md

This file provides guidance to agents (i.e., ADAL) when working with code in this repository.

## Overview

This is a PowerShell utility repository for managing ESXi TPM (Trusted Platform Module) encryption settings and recovery keys across VMware vCenter clusters.

**Single Script**: `testtpm.ps1` - Manages TPM encryption configuration and key extraction for ESXi hosts.

## Essential Commands

### Running the Script

**Prerequisites**:
- VMware PowerCLI module installed (`Install-Module -Name VMware.PowerCLI`)
- Active connection to vCenter (`Connect-VIServer`)
- Appropriate vCenter permissions for encryption management

**Collect TPM Keys** (default mode):
```powershell
.\testtpm.ps1
```
- Iterates through all ESXi hosts in all clusters
- Collects TPM encryption keys, recovery IDs, and status
- Outputs CSV: `tpm-keys-<vcenter>-<timestamp>.csv`

**Set TPM Mode & Enable Key Persistence**:
```powershell
.\testtpm.ps1 -set
```
- Configures encryption mode to TPM for all ESXi hosts
- Enables key persistence
- **WARNING**: Modifies ESXi security settings cluster-wide

### Testing During Development

To test on a single host first (recommended before production runs):
```powershell
# Uncomment line 6 in testtpm.ps1:
# Foreach ($h1 in Get-cluster |Sort-Object | Get-VMHost |Sort-Object |Select-Object -first 1 )
```

## Architecture

### Script Flow

**Collection Mode** (no `-set` flag):
1. Connects to each ESXi host via `Get-EsxCli` v2
2. Queries encryption settings via `esxcli.system.settings.encryption.*`
3. Extracts: FQDN, Recovery ID, Key, Mode, Key Persistence status
4. Exports to CSV with timestamp

**Set Mode** (`-set` flag):
1. Iterates all hosts in all clusters
2. Sets encryption mode to TPM
3. Enables key persistence
4. No output file generated

### Key Data Points

**Output CSV Fields**:
- `FQDN`: Host fully qualified domain name
- `Recovery ID`: TPM recovery identifier
- `Key`: TPM encryption key
- `Mode`: Current encryption mode
- `Key Persistence`: Whether key persistence is enabled

### ESXi CLI Integration

Script uses `Get-EsxCli -V2` for all operations:
- **Encryption mode**: `system.settings.encryption.set/get`
- **Recovery keys**: `system.settings.encryption.recovery.list`
- **Key persistence**: `system.security.keypersistence.enable/get`

## Critical Gotchas

1. **Must be connected to vCenter**: Script fails silently if no active vCenter connection exists. Always run `Connect-VIServer` first.

2. **vCenter from UID in filename**: Log filename extracts vCenter name from host UID (`$h1.uid.Split('@')[1].Split(':')[0]`). This assumes standard UID format.

3. **No rollback for `-set`**: Setting TPM mode and enabling key persistence has no undo mechanism in script. Manual ESXi configuration required to revert.

4. **V2 CLI requirement**: Script explicitly uses `Get-EsxCli -V2`. V1 CLI will not work.

5. **Cluster-wide operations**: Both modes iterate ALL hosts in ALL clusters. No filtering by cluster/host name.

6. **CSV overwrites**: Each run generates new CSV file with timestamp. Previous exports are not overwritten.

## Entry Points

**Main script**: `testtpm.ps1`
- Single parameter: `[switch]$set`
- Default behavior: Collection mode
- With `-set`: Configuration mode

**Output**: CSV files named `tpm-keys-<vcenter>-<timestamp>.csv` in script directory

## Environment

- **Platform**: Windows PowerShell
- **Dependencies**: VMware PowerCLI module
- **vCenter Connection**: Required before execution
- **Permissions**: ESXi encryption management rights
