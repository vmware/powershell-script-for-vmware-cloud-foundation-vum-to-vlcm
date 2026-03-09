# Copyright (c) 2025 Broadcom. All Rights Reserved.
# Broadcom Confidential. The term "Broadcom" refers to Broadcom Inc.
# and/or its subsidiaries.
#
# =============================================================================
#
# SOFTWARE LICENSE AGREEMENT
#
# Copyright (c) CA, Inc. All rights reserved.
#
# You are hereby granted a non-exclusive, worldwide, royalty-free license
# under CA, Inc.'s copyrights to use, copy, modify, and distribute this
# software in source code or binary form for use in connection with CA, Inc.
# products.
#
# This copyright notice shall be included in all copies or substantial
# portions of the software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# =============================================================================
#
# Last modified: 2026-03-09
#
# PSScriptAnalyzer: DefaultViServers is the standard PowerCLI variable for connected vCenter sessions; VCF PowerCLI 9 has no Get-VIServer -State.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'DefaultViServers is the standard PowerCLI variable for connected vCenter sessions.')]

<#
.SYNOPSIS
    Reports whether all ESXi hosts in a cluster have the same set of installed VIBs (homogeneous) or not (heterogeneous).

.DESCRIPTION
    This script assumes you are already connected to vCenter using Connect-VIServer. It does not perform any
    connection or credential handling. Given a cluster name, it collects the list of installed VIBs on each
    ESXi host in that cluster via esxcli software vib list (VCF PowerCLI 9 / Get-EsxCli -V2), then compares
    them. If every host has the identical set of VIBs (by name and version), the script reports
    "homogeneous cluster". If any host has VIBs missing or extra compared to the reference (first host),
    the script reports "heterogeneous cluster" and lists which hosts differ and their missing/extra VIBs.

.PARAMETER ClusterName
    Name of the cluster to analyze. Must match the cluster name as it appears in vCenter.

.PARAMETER Server
    Optional. vCenter server name (FQDN or IP) to use when multiple VI servers are connected. If omitted,
    the default connection from Connect-VIServer is used (typically the only or most recently connected server).

.OUTPUTS
    Writes "homogeneous cluster" or "heterogeneous cluster" to the pipeline and console, plus host-level
    delta details when heterogeneous. Also returns a PSCustomObject with ClusterName, Homogeneous,
    HostCount, ReferenceHost, and Deltas.

.EXAMPLE
    Connect-VIServer -Server "vcenter.example.com" -User "administrator@vsphere.local" -Password $securePass
    .\Get-VcfClusterVibConsistency.ps1 -ClusterName "Production-Cluster-01"

.EXAMPLE
    .\Get-VcfClusterVibConsistency.ps1 -ClusterName "m01-cl01" -Server "m01-vc01.example.com"

.NOTES
    Requires VCF PowerCLI 9 (Get-EsxCli, Get-Cluster, Get-VMHost). You must connect to vCenter with
    Connect-VIServer before running this script. The script does not disconnect the session when finished.
    VIB identity is based on Name and Version (fallback to Id if Name is missing). The first host in the
    cluster is used as the reference for comparison.
    Logging is written to console and to a log file in the script directory:
    logs\VcfClusterVibConsistency-{yyyy-MM-dd}.log
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [string]$ClusterName,
    [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [string]$Server
)

$ErrorActionPreference = "Stop"

#region Logging

$logDirectory = Join-Path -Path $PSScriptRoot -ChildPath "logs"
if (-not (Test-Path -Path $logDirectory -PathType Container)) {
    try {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }
    catch {
        throw "Failed to create log directory: $logDirectory. $($_.Exception.Message)"
    }
}

$logFileDateStamp = Get-Date -Format "yyyy-MM-dd"
$Script:LogFilePath = Join-Path -Path $logDirectory -ChildPath "VcfClusterVibConsistency-$logFileDateStamp.log"

Function Write-LogMessage {

    <#
        .SYNOPSIS
        Writes a timestamped log line to the console and appends it to the script log file.

        .DESCRIPTION
        Used for consistent logging. Output is written to the pipeline (console) and, when the log file
        exists, appended to the script-scoped log file path.

        .PARAMETER Message
        The message text to log.

        .PARAMETER Type
        Severity: DEBUG, INFO, WARNING, or ERROR.

        .EXAMPLE
        Write-LogMessage -Type INFO -Message "Starting VIB collection."

        .NOTES
        Depends on $Script:LogFilePath being set. Log file is created by the script before first use.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR")] [string]$Type,
        [Parameter(Mandatory = $true)] [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Type] $Message"
    Write-Output $logLine
    if ($Script:LogFilePath -and (Test-Path -LiteralPath $Script:LogFilePath -PathType Leaf)) {
        try {
            Add-Content -LiteralPath $Script:LogFilePath -Value $logLine -ErrorAction Stop
        }
        catch {
            Write-Output "[$timestamp] [WARNING] Could not write to log file: $($_.Exception.Message)"
        }
    }
}

if (-not (Test-Path -LiteralPath $Script:LogFilePath -PathType Leaf)) {
    try {
        New-Item -ItemType File -Path $Script:LogFilePath -Force | Out-Null
    }
    catch {
        throw "Failed to create log file: $Script:LogFilePath. $($_.Exception.Message)"
    }
}
Function Get-NormalizedVibKey {

    <#
        .SYNOPSIS
        Returns a single string key for a VIB (name and version) for comparison across hosts.

        .DESCRIPTION
        esxcli software vib list returns objects whose property names may be PascalCase or lowercase.
        This function normalizes to a "Name--Version" key so sets can be compared.

        .PARAMETER VibItem
        One VIB object from the esxcli software vib list output.

        .OUTPUTS
        A string in the form "Name--Version", or "Unknown--" if name cannot be determined.

        .EXAMPLE
        $key = Get-NormalizedVibKey -VibItem $vibItem

        .NOTES
        Uses Id as fallback when Name is not present.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [PSCustomObject]$VibItem
    )
    $vibName = $null
    $vibVersion = $null
    if ($VibItem.PSObject.Properties['Name']) { $vibName = $VibItem.Name }
    elseif ($VibItem.PSObject.Properties['name']) { $vibName = $VibItem.name }
    if ($VibItem.PSObject.Properties['Version']) { $vibVersion = $VibItem.Version }
    elseif ($VibItem.PSObject.Properties['version']) { $vibVersion = $VibItem.version }
    if (-not $vibName -and $VibItem.PSObject.Properties['Id']) { $vibName = $VibItem.Id }
    elseif (-not $vibName -and $VibItem.PSObject.Properties['id']) { $vibName = $VibItem.id }
    if (-not $vibVersion) { $vibVersion = "" }
    if (-not $vibName) { $vibName = "Unknown" }
    return "$vibName--$vibVersion"
}
Function Get-VibSetFromHost {

    <#
        .SYNOPSIS
        Collects the set of installed VIB keys (name--version) for one ESXi host.

        .DESCRIPTION
        Uses Get-EsxCli -V2 and software.vib.list to retrieve installed VIBs on the given host,
        then normalizes each to a comparable string key. Returns a case-insensitive set of keys.

        .PARAMETER VMHost
        The VMHost object (from Get-VMHost) to query.

        .PARAMETER VcenterServerName
        vCenter server name (FQDN or IP) used for the Get-EsxCli -Server parameter.

        .OUTPUTS
        A HashSet of strings (VIB keys). Empty set if the host has no VIBs or if software.vib.list is unavailable.

        .EXAMPLE
        $vibKeySet = Get-VibSetFromHost -VMHost $vmHost -VcenterServerName $vcenterServerName

        .NOTES
        Throws if Get-EsxCli or Invoke fails. Logs a warning and returns an empty set if software.vib.list is missing.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $VMHost,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [string]$VcenterServerName
    )
    $vibKeySet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    try {
        $esxCli = Get-EsxCli -VMHost $VMHost -V2 -Server $VcenterServerName -ErrorAction Stop
        $vibListCommand = $esxCli.software.vib.list
        if (-not $vibListCommand) {
            Write-LogMessage -Type WARNING -Message "Host $($VMHost.Name): software.vib.list not available."
            return $vibKeySet
        }
        $rawVibList = $vibListCommand.Invoke()
        $vibItems = @($rawVibList)
        foreach ($vibItem in $vibItems) {
            $vibKey = Get-NormalizedVibKey -VibItem $vibItem
            if ($vibKey) { [void]$vibKeySet.Add($vibKey) }
        }
    }
    catch {
        Write-LogMessage -Type ERROR -Message "Host $($VMHost.Name): Failed to get VIB list. $($_.Exception.Message)"
        throw
    }
    return $vibKeySet
}



try {
    # Resolve which vCenter connection to use. VCF PowerCLI 9 does not support Get-VIServer -State; use $Global:DefaultViServers.
    if (-not $Global:DefaultViServers) {
        $connectionHelp = @"
This script needs an active vCenter connection. Connect to vCenter first, then run the script.

Example:
  Connect-VIServer -Server "your-vcenter.example.com" -User "administrator@vsphere.local" -Password (Read-Host -Prompt "Password" -AsSecureString)
  .\Get-VcfClusterVibConsistency.ps1 -ClusterName "your-cluster-name"

If you use -Server, that vCenter must be one of the connected servers.
"@
        Write-LogMessage -Type ERROR -Message "No vCenter connection found. User must run Connect-VIServer before this script."
        throw $connectionHelp
    }
    $connectedServers = @($Global:DefaultViServers | Where-Object { $_.IsConnected -eq $true })
    if (-not $connectedServers -or $connectedServers.Count -eq 0) {
        $connectionHelp = @"
No active vCenter session was found. Connect to vCenter first, then run the script.

Example:
  Connect-VIServer -Server "your-vcenter.example.com" -User "administrator@vsphere.local" -Password (Read-Host -Prompt "Password" -AsSecureString)
  .\Get-VcfClusterVibConsistency.ps1 -ClusterName "your-cluster-name"

If you use -Server, that vCenter must be one of the connected servers.
"@
        Write-LogMessage -Type ERROR -Message "No connected vCenter session found. User must run Connect-VIServer before this script."
        throw $connectionHelp
    }

    if ($Server) {
        $targetConnection = $connectedServers | Where-Object { $_.Name -eq $Server } | Select-Object -First 1
        if (-not $targetConnection) {
            $connectedNames = ($connectedServers | ForEach-Object { $_.Name }) -join ", "
            throw "vCenter server '$Server' is not in the list of connected servers. Connected: $connectedNames."
        }
        $vcenterServerName = $targetConnection.Name
    }
    else {
        if ($connectedServers.Count -gt 1) {
            Write-LogMessage -Type INFO -Message "Multiple vCenter connections found. Using default: $($connectedServers[0].Name). Use -Server to specify another."
        }
        $vcenterServerName = $connectedServers[0].Name
    }

    Write-LogMessage -Type INFO -Message "Using vCenter: $vcenterServerName. Cluster: $ClusterName."

    # Resolve cluster and hosts.
    $clusterObject = $null
    try {
        $clusterObject = Get-Cluster -Server $vcenterServerName -Name $ClusterName -ErrorAction Stop
    }
    catch {
        Write-LogMessage -Type ERROR -Message "Get-Cluster failed for '$ClusterName' on '$vcenterServerName': $($_.Exception.Message)"
        throw "Cluster not found: '$ClusterName' on vCenter '$vcenterServerName'. Ensure the name matches exactly."
    }
    if (-not $clusterObject) {
        throw "Cluster not found: '$ClusterName' on vCenter '$vcenterServerName'."
    }

    $clusterHosts = $null
    try {
        $clusterHosts = Get-VMHost -Server $vcenterServerName -Location $clusterObject -ErrorAction Stop
    }
    catch {
        Write-LogMessage -Type ERROR -Message "Get-VMHost failed for cluster '$ClusterName': $($_.Exception.Message)"
        throw
    }
    if (-not $clusterHosts -or $clusterHosts.Count -eq 0) {
        throw "No ESXi hosts found in cluster '$ClusterName'."
    }

    # Gather VIB set per host.
    Write-LogMessage -Type INFO -Message "Collecting VIBs from $($clusterHosts.Count) host(s) in cluster `"$ClusterName`"."
    $hostVibSets = @{}
    foreach ($vmHost in $clusterHosts) {
        $currentHostName = $vmHost.Name
        $hostVibSets[$currentHostName] = Get-VibSetFromHost -VMHost $vmHost -VcenterServerName $vcenterServerName
    }

    # Compare each host to the first host (reference).
    $referenceHostName = ($clusterHosts | Select-Object -First 1).Name
    $referenceVibSet = $hostVibSets[$referenceHostName]
    $isHomogeneous = $true
    $deltaList = @()

    foreach ($currentHostName in $hostVibSets.Keys) {
        $currentHostVibSet = $hostVibSets[$currentHostName]
        $missingVibs = [System.Collections.Generic.List[string]]::new()
        $extraVibs = [System.Collections.Generic.List[string]]::new()
        foreach ($vibKey in $referenceVibSet) {
            if (-not $currentHostVibSet.Contains($vibKey)) { $missingVibs.Add($vibKey) }
        }
        foreach ($vibKey in $currentHostVibSet) {
            if (-not $referenceVibSet.Contains($vibKey)) { $extraVibs.Add($vibKey) }
        }
        if ($missingVibs.Count -gt 0 -or $extraVibs.Count -gt 0) {
            $isHomogeneous = $false
            $deltaList += [PSCustomObject]@{
                HostName = $currentHostName
                Missing  = $missingVibs | Sort-Object
                Extra    = $extraVibs | Sort-Object
            }
        }
    }

    # Build result and report.
    $result = [PSCustomObject]@{
        ClusterName   = $ClusterName
        Homogeneous   = $isHomogeneous
        HostCount     = $clusterHosts.Count
        ReferenceHost = $referenceHostName
        Deltas        = $deltaList
    }

    if ($isHomogeneous) {
        Write-LogMessage -Type INFO -Message "Result: homogeneous cluster. All $($clusterHosts.Count) host(s) have the same VIB set."
        Write-Output "homogeneous cluster"
    }
    else {
        Write-LogMessage -Type INFO -Message "Result: heterogeneous cluster. The following host(s) differ from reference host `"$referenceHostName`":"
        Write-Output "heterogeneous cluster"
        foreach ($deltaEntry in $deltaList) {
            Write-LogMessage -Type INFO -Message "  Host: $($deltaEntry.HostName)"
            if ($deltaEntry.Missing.Count -gt 0) {
                Write-LogMessage -Type INFO -Message "    Missing VIBs (vs reference): $($deltaEntry.Missing.Count)"
                foreach ($missingVib in $deltaEntry.Missing) {
                    Write-LogMessage -Type INFO -Message "      - $missingVib"
                }
            }
            if ($deltaEntry.Extra.Count -gt 0) {
                Write-LogMessage -Type INFO -Message "    Extra VIBs (not on reference): $($deltaEntry.Extra.Count)"
                foreach ($extraVib in $deltaEntry.Extra) {
                    Write-LogMessage -Type INFO -Message "      + $extraVib"
                }
            }
        }
    }

    $result
}
catch {
    Write-LogMessage -Type ERROR -Message "Script failed: $($_.Exception.Message)"
    throw
}