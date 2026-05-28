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
# Last modified: 2026-03-17
#
# PSScriptAnalyzer: DefaultViServers is the standard PowerCLI variable for connected vCenter sessions; VCF PowerCLI 9 has no Get-VIServer -State.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'DefaultViServers is the standard PowerCLI variable for connected vCenter sessions.')]

<#
.SYNOPSIS
    Reports whether all ESXi hosts in a cluster have the same set of installed VIBs (homogeneous) or not (heterogeneous).

.DESCRIPTION
    Usage: .\Get-VcfClusterVibConsistency.ps1 -ClusterName <string> [-Server <string>]

    This script assumes you are already connected to vCenter using Connect-VIServer. It does not perform any
    connection or credential handling. Given a cluster name, it collects the list of installed VIBs on each
    ESXi host in that cluster via esxcli software vib list (VCF PowerCLI 9 / Get-EsxCli -V2), then compares
    them. If every host has the identical set of VIBs (by name and version), the script reports
    "homogeneous cluster". If any host has VIBs missing or extra compared to the reference (first host),
    or the same VIB name with a different version (disjoint versions), the script reports
    "heterogeneous cluster" and lists which hosts differ and their missing/extra VIBs.
    Comparison is case-insensitive for VIB names and versions (PowerShell default).

.PARAMETER ClusterName
    Name of the cluster to analyze. Must match the cluster name as it appears in vCenter. Required.

.PARAMETER LogLevel
    Minimum severity for console output: DEBUG, INFO, WARNING, or ERROR. Default is INFO. The log file always receives all levels.

.PARAMETER Server
    Optional. vCenter server name (FQDN or IP) to use when multiple VI servers are connected. If omitted,
    the default connection from Connect-VIServer is used (typically the only or most recently connected server).

.INPUTS
    None. ClusterName, LogLevel, and Server are supplied as parameters.

.OUTPUTS
    Writes "homogeneous cluster" or "heterogeneous cluster" to the pipeline and console, plus host-level
    delta details when heterogeneous. Also returns a PSCustomObject with ClusterName, Homogeneous,
    HostCount, ReferenceHost, and Deltas.

.EXAMPLE
    Get-Help .\Get-VcfClusterVibConsistency.ps1 -Full
    Get full usage, parameter descriptions, and examples.

.EXAMPLE
    Connect-VIServer -Server "vcenter.example.com" -User "administrator@vsphere.local" -Password $securePass
    .\Get-VcfClusterVibConsistency.ps1 -ClusterName "Production-Cluster-01"

.EXAMPLE
    .\Get-VcfClusterVibConsistency.ps1 -ClusterName "m01-cl01" -Server "m01-vc01.example.com"

.LINK
    Get-Help .\Get-VcfClusterVibConsistency.ps1 -Full

.NOTES
    Requires VCF PowerCLI 9 (Get-EsxCli, Get-Cluster, Get-VMHost). You must connect to vCenter with
    Connect-VIServer before running this script. The script does not disconnect the session when finished.
    VIB identity is based on Name and Version (fallback to Id if Name is missing). Disjoint names or
    disjoint versions (same VIB name, different version across hosts) indicate heterogeneity. The first
    host in the cluster is used as the reference for comparison. Comparison is case-insensitive.
    Logging is written to console and to a log file in the script directory:
    logs\VcfClusterVibConsistency-{yyyy-MM-dd}.log
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [string]$ClusterName,
    [Parameter(Mandatory = $false)] [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR")] [string]$LogLevel = "INFO",
    [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [string]$Server
)

$ErrorActionPreference = "Stop"

# Log level hierarchy for filtering console output (lower = more verbose). File always gets all levels.
$Script:LogLevelHierarchy = @{ "DEBUG" = 0; "INFO" = 1; "WARNING" = 2; "ERROR" = 3 }
$Script:ConfiguredLogLevel = $LogLevel

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

Function Test-LogLevel {
    <#
        .SYNOPSIS
        Returns whether a message of the given type should be shown on console per configured log level.
        .NOTES
        Message is shown when its level is at or above the configured level (e.g. INFO shows INFO, WARNING, ERROR).
    #>
    param(
        [Parameter(Mandatory = $true)] [string]$MessageType
    )
    $messageLevel = $Script:LogLevelHierarchy[$MessageType]
    $configuredLevelValue = $Script:LogLevelHierarchy[$Script:ConfiguredLogLevel]
    return ($messageLevel -ge $configuredLevelValue)
}

Function Write-LogMessage {

    <#
        .SYNOPSIS
        Writes a log line to the console (when at or above -LogLevel) and appends a timestamped line to the script log file.

        .DESCRIPTION
        Console shows [Type] Message only (no timestamp). Log file always receives [timestamp] [Type] Message. Aligned with SimpleSupervisorDeploymentAtScale.psm1.

        .PARAMETER Message
        The message text to log.

        .PARAMETER Type
        Severity: DEBUG, INFO, WARNING, or ERROR.

        .EXAMPLE
        Write-LogMessage -Type INFO -Message "Starting VIB collection."

        .NOTES
        Depends on $Script:LogFilePath and $Script:ConfiguredLogLevel. Log file is created by the script before first use.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR")] [string]$Type,
        [Parameter(Mandatory = $true)] [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Type] $Message"
    $msgTypeToColor = @{ "DEBUG" = "Gray"; "ERROR" = "Red"; "INFO" = "Green"; "WARNING" = "Yellow" }
    $messageColor = $msgTypeToColor[$Type]
    if (Test-LogLevel -MessageType $Type) {
        Write-Host -ForegroundColor $messageColor "[$Type] $Message"
        [Console]::Out.Flush()
    }
    if ($Script:LogFilePath -and (Test-Path -LiteralPath $Script:LogFilePath -PathType Leaf)) {
        try {
            Add-Content -LiteralPath $Script:LogFilePath -Value $logLine -ErrorAction Stop
        }
        catch {
            if (Test-LogLevel -MessageType "WARNING") {
                Write-Host -ForegroundColor Yellow "[WARNING] Could not write to log file: $($_.Exception.Message)"
                [Console]::Out.Flush()
            }
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
        PowerShell property access is case-insensitive, so Name/Version/Id are read without casing checks.
        This function normalizes to a "Name--Version" key so sets can be compared; disjoint names or
        disjoint versions (same name, different version) both produce different keys and indicate heterogeneity.

        .PARAMETER VibItem
        One VIB object from the esxcli software vib list output.

        .OUTPUTS
        System.String. A string in the form "Name--Version", or "Unknown--" if name cannot be determined.

        .EXAMPLE
        $key = Get-NormalizedVibKey -VibItem $vibItem

        .NOTES
        Uses Id as fallback when Name is not present.
    #>

    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory = $true)] [PSCustomObject]$VibItem
    )

    # PowerShell property access is case-insensitive; use Name, fallback to Id.
    $vibName = $VibItem.Name
    if (-not $vibName) {
        $vibName = $VibItem.Id
    }
    if (-not $vibName) {
        $vibName = "Unknown"
    }

    $vibVersion = $VibItem.Version
    if (-not $vibVersion) {
        $vibVersion = ""
    }

    [String]"$vibName--$vibVersion"
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
        $errorMessage = $_.Exception.Message
        Write-LogMessage -Type ERROR -Message "Host $($VMHost.Name): Failed to get VIB list. $errorMessage"
        # User-friendly throw when failure is likely due to missing or lost vCenter connection.
        if ($errorMessage -match "default server|DefaultViServer|not connected|connection|No connection") {
            throw "Cannot get VIB list from host. Ensure vCenter connection is active (Connect-VIServer). Run Get-Help .\Get-VcfClusterVibConsistency.ps1 -Full for prerequisites."
        }
        throw
    }
    return $vibKeySet
}


try {
    # Resolve which vCenter connection to use. VCF PowerCLI 9 does not support Get-VIServer -State; use $Global:DefaultViServers.
    if (-not $Global:DefaultViServers) {
        Write-LogMessage -Type ERROR -Message "No vCenter connection found. Connect to vCenter first with Connect-VIServer, then run this script. Example: Connect-VIServer -Server \"vcenter.example.com\" -User \"administrator@vsphere.local\" -Password (Read-Host -Prompt \"Password\" -AsSecureString); .\Get-VcfClusterVibConsistency.ps1 -ClusterName \"your-cluster-name\". If you use -Server, that vCenter must be one of the connected servers."
        throw "No vCenter connection. Connect with Connect-VIServer first. Run Get-Help .\Get-VcfClusterVibConsistency.ps1 -Full for usage and examples."
    }
    $connectedServers = @($Global:DefaultViServers | Where-Object { $_.IsConnected -eq $true })
    if (-not $connectedServers -or $connectedServers.Count -eq 0) {
        Write-LogMessage -Type ERROR -Message "No active vCenter session found. Connect to vCenter first with Connect-VIServer, then run this script. Example: Connect-VIServer -Server \"vcenter.example.com\" -User \"administrator@vsphere.local\" -Password (Read-Host -Prompt \"Password\" -AsSecureString); .\Get-VcfClusterVibConsistency.ps1 -ClusterName \"your-cluster-name\". If you use -Server, that vCenter must be one of the connected servers."
        throw "No active vCenter session. Connect with Connect-VIServer first. Run Get-Help .\Get-VcfClusterVibConsistency.ps1 -Full for usage and examples."
    }

    if ($Server) {
        $targetConnection = $connectedServers | Where-Object { $_.Name -eq $Server } | Select-Object -First 1
        if (-not $targetConnection) {
            $connectedNames = ($connectedServers | ForEach-Object { $_.Name }) -join ", "
            Write-LogMessage -Type ERROR -Message "vCenter server \"$Server\" is not in the list of connected servers. Connected: $connectedNames."
            throw "vCenter '$Server' is not connected. Use one of: $connectedNames. Or omit -Server to use the default."
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
        $availableClusters = @(Get-Cluster -Server $vcenterServerName -ErrorAction SilentlyContinue | Sort-Object -Property Name)
        $msg = "Cluster with name '$ClusterName' not found."
        if ($availableClusters.Count -gt 0) {
            $clusterNames = ($availableClusters | ForEach-Object { $_.Name }) -join ", "
            $msg += " Available clusters: $clusterNames."
        }
        Write-LogMessage -Type ERROR -Message $msg
        exit 1
    }
    if (-not $clusterObject) {
        Write-LogMessage -Type ERROR -Message "Cluster with name '$ClusterName' not found."
        exit 1
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
    $vibCollectActivity = "Collecting VIBs from $($clusterHosts.Count) host(s) in cluster `"$ClusterName`""
    $vibCollectStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $hostIndex = 0
    foreach ($vmHost in $clusterHosts) {
        $hostIndex++
        $elapsedSeconds = [math]::Floor($vibCollectStopwatch.Elapsed.TotalSeconds)
        $statusMessage = "Elapsed: $elapsedSeconds seconds"
        $currentOperation = "Host $hostIndex of $($clusterHosts.Count)"
        Write-Progress -Activity $vibCollectActivity -Status $statusMessage -CurrentOperation $currentOperation
        [Console]::Out.Flush()
        $currentHostName = $vmHost.Name
        $hostVibSets[$currentHostName] = Get-VibSetFromHost -VMHost $vmHost -VcenterServerName $vcenterServerName
    }
    Write-Progress -Activity $vibCollectActivity -Status "Complete" -Completed
    [Console]::Out.Flush()

    # Compare each host to the first host (reference).
    $referenceHostName = ($clusterHosts | Select-Object -First 1).Name
    $referenceVibSet = $hostVibSets[$referenceHostName]
    Write-LogMessage -Type DEBUG -Message "Reference host for cluster `"$ClusterName`": $referenceHostName"
    $hostsTestedList = ($hostVibSets.Keys | Sort-Object) -join ", "
    Write-LogMessage -Type DEBUG -Message "Hosts tested in cluster `"$ClusterName`": $hostsTestedList"
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
        Write-LogMessage -Type DEBUG -Message "Result: homogeneous cluster. All $($clusterHosts.Count) host(s) have the same VIB set."
    }
    else {
        Write-LogMessage -Type DEBUG -Message "Result: heterogeneous cluster. The following host(s) differ from reference host `"$referenceHostName`":"
        foreach ($deltaEntry in $deltaList) {
            Write-LogMessage -Type DEBUG -Message "  Host: $($deltaEntry.HostName)"
            if ($deltaEntry.Missing.Count -gt 0) {
                Write-LogMessage -Type DEBUG -Message "    Missing VIBs (vs reference): $($deltaEntry.Missing.Count)"
                foreach ($missingVib in $deltaEntry.Missing) {
                    Write-LogMessage -Type DEBUG -Message "      - $missingVib"
                }
            }
            if ($deltaEntry.Extra.Count -gt 0) {
                Write-LogMessage -Type DEBUG -Message "    Extra VIBs (not on reference): $($deltaEntry.Extra.Count)"
                foreach ($extraVib in $deltaEntry.Extra) {
                    Write-LogMessage -Type DEBUG -Message "      + $extraVib"
                }
            }
        }
    }
    # Return the result object.
    $result
}
catch {
    Write-LogMessage -Type ERROR -Message "Script failed: $($_.Exception.Message)"
    throw
}