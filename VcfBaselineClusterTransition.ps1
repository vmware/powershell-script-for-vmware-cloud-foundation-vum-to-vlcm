<#
.SYNOPSIS
    Facilitates the transition of vLCM baseline (VUM) managed clusters to vLCM image management in VMware Cloud Foundation.

.DESCRIPTION
    VcfBaselineClusterTransition.ps1 automates the process of converting vSphere Lifecycle Manager (vLCM)
    baseline-managed clusters (formerly VUM/Update Manager) to vLCM image-based management. This script
    provides both interactive menu-driven and headless command-line interfaces for:

    - Connecting to SDDC Manager and vCenter instances
    - Importing vLCM images from vCenter to SDDC Manager
    - Running compliance checks for clusters against images
    - Transitioning baseline-managed clusters to image management
    - Monitoring transition progress and task status
    - Managing vLCM images and temporary clusters

    The script supports both serial and parallel processing for multiple cluster operations and provides
    comprehensive logging and error handling throughout the workflow.

    INTERACTIVE MODE:
    Running the script without parameters launches a menu-driven interface that guides you through
    the complete workflow with validation and prompts at each step.

    HEADLESS MODE:
    Running the script with parameters enables automated, non-interactive execution suitable for
    CI/CD pipelines and scheduled tasks. Use -Silence to suppress console output (logs to file only).

.PARAMETER CheckTaskStatus
    Checks the status of background tasks (image uploads or compliance checks).
    Requires -TaskType parameter to specify which type of task to check.

    Valid TaskType values:
    - SddcManagerImageUpload: Image import operations
    - ComplianceCheck: Cluster compliance checks

.PARAMETER CheckTransitions
    Displays the transition status of clusters being converted to image management.
    Can show all transitions or filter by specific cluster/workload domain.

    Optional parameters: -ClusterName, -WorkloadDomainName
    Without parameters: Shows status summary of all cluster transitions

.PARAMETER ClusterName
    Specifies the name of the vSphere cluster to operate on.
    Used with compliance checks, transitions, and status queries.

    Example: "m01-cl01", "production-cluster-01"

.PARAMETER ComplianceCheck
    Initiates a compliance check of a cluster against a specified vLCM image.
    Validates compatibility before actual transition and identifies required changes.

    Required parameters:
    - Single cluster: -ClusterName, -WorkloadDomainName, -SddcManagerImageName
    - Multiple clusters: -JsonInput (with optional -Parallel)

    The compliance check creates a detailed report in the logs directory showing:
    - Component version changes
    - Hardware support package changes
    - Compatibility status (COMPLIANT, NON_COMPLIANT, INCOMPATIBLE, UNKNOWN)

.PARAMETER Connect
    Establishes connections to SDDC Manager and Workload Domain vCenter(s).
    Uses credentials from SddcManagerCredentials.json or prompts for input.

    Optional parameter: -JsonInput to specify alternate credentials file
    Optional parameter: -Silence to suppress console output

    The script automatically:
    - Validates SDDC Manager version (requires 5.2.2.0+)
    - Retrieves vCenter credentials from SDDC Manager
    - Connects to selected vCenter(s) in workload domains

.PARAMETER TransitionCluster
    Converts a vLCM baseline-managed cluster to image-based management.
    Requires successful compliance check before execution.

    Required parameters:
    - Single cluster: -ClusterName, -WorkloadDomainName
    - Multiple clusters: -JsonInput (with optional -Parallel)

    The transition process:
    1. Validates compliance check has been run
    2. Applies NSX-vLCM trust relationship (ComputeManagerSettingsDrift)
    3. Transitions cluster to image management
    4. Remediates all hosts in the cluster
    5. Provides real-time progress updates

.PARAMETER DeleteImageFromSddcManager
    Removes a vLCM image from SDDC Manager.
    Use with caution - typically for correcting import errors or removing obsolete images.

    Required parameter: -SddcManagerImageName
    Cannot remove images currently assigned to clusters.

.PARAMETER DeleteTemporaryCluster
    Removes temporary clusters created during image import process (pre-vCenter 9.0).
    Only removes clusters with no ESX hosts for safety.

    Required parameters: -ClusterName (temporary cluster name), -VcenterName

    Safety feature: Script will not delete clusters containing ESX hosts.

.PARAMETER Disconnect
    Disconnects from all vCenter servers and SDDC Manager.
    Cleans up credential variables from memory.

    Optional parameter: -Silence to suppress console output

.PARAMETER Help
    Displays detailed help information about available parameters and usage examples.
    Provides quick reference for headless operations.

.PARAMETER ImportImagesFromVcenter
    Imports vLCM images from connected vCenter(s) into SDDC Manager.
    Supports both vCenter 9.0+ image catalog and legacy cluster-based images.

    Parameters:
    - Single image: -VcenterImageName, -VcenterName
    - Multiple images: -JsonInput (with optional -Parallel)
    - Optional: -Silence to suppress console output

    For vCenter versions prior to 9.0, the image is sourced from a cluster's vLCM
    configuration. After successful import, temporary clusters can be removed.

.PARAMETER JsonInput
    Path to JSON input file for batch operations.
    Format varies by operation type.

    Compliance Check JSON format:
    [
      {
        "ClusterName": "cluster-name",
        "WorkloadDomainName": "domain-name",
        "SddcManagerImageName": "image-name"
      }
    ]

    Cluster Transition JSON format:
    [
      {
        "ClusterName": "cluster-name",
        "WorkloadDomainName": "domain-name"
      }
    ]

    Image Import JSON format:
    [
      {
        "VcenterImageName": "image-or-cluster-name",
        "VcenterName": "vcenter.example.com"
      }
    ]

.PARAMETER JsonOutput
    Path to JSON output file for saving operation results.
    Used with -ShowBaselineClusters and -ShowImagesInVcenter.

    Output includes cluster/image details for integration with other tools.

.PARAMETER Parallel
    Enables parallel processing for multiple cluster operations.
    Significantly reduces time for batch operations.

    Used with: -ComplianceCheck, -TransitionCluster, -ImportImagesFromVcenter
    Requires: -JsonInput parameter

    Note: Parallel operations run to completion without user interaction.
    Use -CheckTaskStatus or -CheckTransitions to monitor progress.

.PARAMETER RetryTransition
    Retries a failed cluster transition operation from the point of failure.

    Required parameter: -TaskId (from failed transition)

    Use -CheckTransitions to find failed task IDs, or check logs for task ID.
    The script will resume from the failed step without repeating successful steps.

.PARAMETER ReviewComplianceResults
    Displays stored compliance check results for analysis.

    Options:
    - Specific cluster: -ClusterName, -WorkloadDomainName
    - All clusters: -ShowAllClusters
    - Full details: Add -ShowExtendedResults

    Results include component changes, compatibility status, and remediation requirements.

.PARAMETER Silence
    Suppresses console output (logs only to file).
    All operations are logged to logs/VcfBaselineClusterTransition-MM-dd-yyyy.log

    Cannot be used with serial processing operations that show progress indicators.
    Compatible with -Parallel operations.

.PARAMETER TaskId
    Specifies the task ID for task-related operations.

    Used with:
    - -RetryTransition: To retry a failed transition
    - -CheckTaskStatus: To check specific task status

    Task IDs are GUIDs in format: "550e8400-e29b-41d4-a716-446655440000"
    Find task IDs in logs or use -CheckTransitions/-CheckTaskStatus to list them.

.PARAMETER TaskType
    Specifies the type of task to check status for.

    Valid values:
    - "SddcManagerImageUpload": Image import operations from vCenter
    - "ComplianceCheck": Cluster compliance check operations

    Required when using -CheckTaskStatus parameter.

.PARAMETER TemporaryClusterName
    Name of temporary cluster to delete.
    Used with -DeleteTemporaryCluster.

    Temporary clusters are created when importing images from vCenter versions prior to 9.0.
    After successful image import, these clusters can be safely removed.

.PARAMETER SddcManagerImageName
    Name of the vLCM image stored in SDDC Manager.

    Used with:
    - -ComplianceCheck: To specify which image to check against
    - -DeleteImageFromSddcManager: To specify which image to remove

    Image names must match exactly as stored in SDDC Manager.
    Use -ShowImagesInSddcManager to list available images.

.PARAMETER ShowAllClusters
    Displays information for all clusters (used with -ReviewComplianceResults).
    Shows compliance status summary for all baseline-managed clusters.

.PARAMETER ShowBaselineClusters
    Lists all vLCM baseline-managed clusters in connected vCenter(s).
    Includes cluster name, vCenter, workload domain, and compliance status.

    Optional parameter: -JsonOutput to save results to file

.PARAMETER ShowImagesInSddcManager
    Displays all vLCM images stored in SDDC Manager.
    Includes base image version, components, add-ons, and hardware support packages.

    Image details are also saved to individual JSON files in logs directory.

.PARAMETER ShowImagesInVcenter
    Shows all vLCM images available in connected vCenter(s).
    For vCenter 9.0+: Lists images from image catalog
    For vCenter <9.0: Lists clusters with vLCM image management enabled

    Optional parameter: -JsonOutput to save results to file

.PARAMETER ShowExtendedResults
    Displays full compliance check details (not just summary).
    Used with -ReviewComplianceResults to show complete JSON output.

    Includes detailed component-level changes, messages, and impacts.

.PARAMETER SkipPowercliVersionCheck
    Bypasses PowerCLI version validation.
    Use with caution - may cause compatibility issues with older PowerCLI versions.

    This script requires VCF.PowerCLI 9.0 or later.
    VMware.PowerCLI is not supported.

.PARAMETER WorkloadDomainName
    Name of the VCF Workload Domain containing the target cluster.

    Used with:
    - -ComplianceCheck
    - -TransitionCluster
    - -ReviewComplianceResults
    - -CheckTransitions

    Example: "m01", "production-domain", "edge-domain"

.PARAMETER VcenterImageName
    Name of the vLCM image in vCenter.

    For vCenter 9.0+: Image name from image catalog
    For vCenter <9.0: Cluster name containing the vLCM image configuration

    Used with -ImportImagesFromVcenter to specify source image.

.PARAMETER VcenterName
    Fully Qualified Domain Name (FQDN) of the vCenter server.

    Used with:
    - -ImportImagesFromVcenter: To specify source vCenter
    - -DeleteTemporaryCluster: To specify vCenter containing cluster

    Example: "m01-vc01.example.com", "vcenter.domain.local"

.PARAMETER Version
    Displays the script version and exits.
    Useful for checking installed version or including in automation logs.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1

    Launches interactive menu-driven interface for guided cluster transitions.
    The menu provides step-by-step workflow with validation and prompts.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -Version

    Displays script version information:
    Version: 1.0.0.0.60

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -Connect -Silence

    Connects to SDDC Manager and vCenter(s) without console output.
    Uses credentials from SddcManagerCredentials.json.
    All operations logged to logs/VcfBaselineClusterTransition-MM-dd-yyyy.log

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -Connect -JsonInput "C:\configs\sddc-credentials.json"

    Connects using credentials from custom location.
    Useful for managing multiple SDDC Manager environments.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ShowBaselineClusters

    Lists all baseline-managed clusters in connected vCenter(s):
    - Cluster name
    - vCenter name
    - Workload domain
    - Compliance status
    - Associated SDDC Manager image (if compliance check run)

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ShowBaselineClusters -JsonOutput "clusters.json"

    Exports baseline cluster list to JSON file for use with batch operations.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ShowImagesInSddcManager

    Displays all vLCM images in SDDC Manager with details:
    - Image name
    - Base ESXi version
    - Component versions
    - Add-ons
    - Hardware support packages

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ShowImagesInVcenter -JsonOutput "vcenter-images.json"

    Lists vLCM images from connected vCenter(s) and saves to JSON file.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ImportImagesFromVcenter -VcenterImageName "m01-cl01" -VcenterName "m01-vc01.example.com"

    Imports a single vLCM image from vCenter cluster into SDDC Manager.
    For vCenter <9.0, the cluster name is the image source.
    Shows progress indicator and completion status.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ImportImagesFromVcenter -JsonInput "images.json" -Parallel

    Imports multiple vLCM images in parallel from JSON file:
    [
      {"VcenterImageName": "m01-cl01", "VcenterName": "m01-vc01.example.com"},
      {"VcenterImageName": "m01-cl02", "VcenterName": "m01-vc01.example.com"}
    ]

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ComplianceCheck -ClusterName "m01-cl01" -WorkloadDomainName "m01" -SddcManagerImageName "esx-803"

    Checks if cluster m01-cl01 is compatible with image esx-803.
    Shows progress indicator during check.
    Displays compliance summary and saves detailed results to:
    logs/cluster-compatibility-for-m01-cl01-on-m01-with-esx-803.json

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ComplianceCheck -JsonInput "clusters.json"

    Runs serial compliance checks for multiple clusters from JSON file:
    [
      {
        "ClusterName": "m01-cl01",
        "WorkloadDomainName": "m01",
        "SddcManagerImageName": "esx-803"
      },
      {
        "ClusterName": "m01-cl02",
        "WorkloadDomainName": "m01",
        "SddcManagerImageName": "esx-803"
      }
    ]
    Shows progress for each cluster sequentially.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ComplianceCheck -JsonInput "clusters.json" -Parallel

    Runs parallel compliance checks for multiple clusters.
    All checks start simultaneously without waiting for completion.
    Use -CheckTaskStatus to monitor progress.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ReviewComplianceResults -ClusterName "m01-cl01" -WorkloadDomainName "m01"

    Displays stored compliance check results for cluster m01-cl01:
    - Compliance status (COMPLIANT, NON_COMPLIANT, INCOMPATIBLE, UNKNOWN)
    - Summary of component changes by severity (ERROR, WARNING, INFO)
    - Impact assessment
    - Location of full JSON results

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ReviewComplianceResults -ClusterName "m01-cl01" -WorkloadDomainName "m01" -ShowExtendedResults

    Shows full compliance details including complete JSON output with:
    - Component-level changes
    - Current and target versions
    - Detailed compatibility messages
    - Impact analysis

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ReviewComplianceResults -ShowAllClusters

    Displays compliance status summary for all baseline-managed clusters
    that have had compliance checks run.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -TransitionCluster -ClusterName "m01-cl01" -WorkloadDomainName "m01"

    Transitions cluster m01-cl01 to vLCM image management.
    Requires successful compliance check before execution.
    Shows real-time progress with step completion indicators.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -TransitionCluster -JsonInput "transitions.json"

    Transitions multiple clusters serially from JSON file:
    [
      {"ClusterName": "m01-cl01", "WorkloadDomainName": "m01"},
      {"ClusterName": "m01-cl02", "WorkloadDomainName": "m01"}
    ]

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -TransitionCluster -JsonInput "transitions.json" -Parallel

    Transitions multiple clusters in parallel.
    All transitions start simultaneously.
    Use -CheckTransitions to monitor progress.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -CheckTransitions

    Shows status summary of all cluster transitions:
    - Cluster name
    - Workload domain
    - Task status (In Progress, Successful, Failed)
    - Task ID
    - Start and completion times

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -CheckTransitions -ClusterName "m01-cl01" -WorkloadDomainName "m01"

    Shows detailed transition status for specific cluster:
    - Overall task status
    - Current step being processed
    - Steps completed / total steps
    - Task ID for retry if needed

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -RetryTransition -TaskId "550e8400-e29b-41d4-a716-446655440000"

    Retries a failed transition task using the task ID.
    Resumes from the point of failure without repeating successful steps.
    Find task IDs using -CheckTransitions or in log files.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -CheckTaskStatus -TaskType "ComplianceCheck"

    Displays status of all compliance check tasks:
    - Cluster name
    - Status (In Progress, Successful, Failed, NOT_CHECKED_YET)
    - Start time
    - Completion time
    - Error messages (if any)

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -CheckTaskStatus -TaskType "SddcManagerImageUpload"

    Shows status of all image import operations.
    Useful for monitoring parallel image imports.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -DeleteImageFromSddcManager -SddcManagerImageName "test-image-01"

    Removes image "test-image-01" from SDDC Manager.
    Interactive mode prompts for confirmation.
    Cannot remove images currently assigned to clusters.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -DeleteTemporaryCluster -ClusterName "temp-image-cluster" -VcenterName "m01-vc01.example.com"

    Removes temporary cluster created during image import (pre-vCenter 9.0).
    Safety check: Only removes clusters with no ESX hosts.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -Disconnect

    Disconnects from all vCenter servers and SDDC Manager.
    Cleans up credentials from memory.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    None. This script writes output to console and log file but does not output objects to the pipeline.

    Log files are created in the "logs" subdirectory with the naming pattern:
    logs/VcfBaselineClusterTransition-MM-dd-yyyy.log

    Compliance results are saved to:
    logs/cluster-compatibility-for-{ClusterName}-on-{WorkloadDomain}-with-{ImageName}.json

.NOTES
    File Name      : VcfBaselineClusterTransition.ps1
    Version        : 1.0.0.0.60
    Author         : Broadcom
    Prerequisite   : PowerShell 7.2 or later
                     VCF.PowerCLI 9.0 or later (VMware.PowerCLI not supported)
                     PowerCLI DefaultVIServerMode set to Multiple
                     SDDC Manager 5.2.2.0 or later
                     Network connectivity to SDDC Manager and vCenter(s)
                     SDDC Manager user with ADMIN role (for credential retrieval)

    Configuration  : Set PowerCLI for multiple vCenter connections:
                     Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Scope User

    Error Handling : The script uses inline error handling with try/catch blocks and error checking.
                     Most functions write errors to log and return/exit based on severity.
                     Critical operations exit the script; recoverable errors continue with warnings.

    Workflow       : 1. Connect to SDDC Manager (credentials from JSON or prompts)
                     2. Connect to vCenter(s) in workload domains
                     3. Import vLCM images from vCenter to SDDC Manager
                     4. Run compliance checks on clusters
                     5. Review compliance results and remediate issues
                     6. Transition clusters to image management
                     7. Monitor transition progress

    JSON Formats   :
                     SddcManagerCredentials.json:
                     {
                       "SddcManagerFqdn": "sddc-manager.example.com",
                       "SddcManagerUserName": "administrator@vsphere.local",
                       "SddcManagerPassword": "VMware123!"
                     }

                     Cluster compliance check JSON (array format):
                     [
                       {
                         "ClusterName": "m01-cl01",
                         "WorkloadDomainName": "m01",
                         "SddcManagerImageName": "esx-803"
                       },
                       {
                         "ClusterName": "m01-cl02",
                         "WorkloadDomainName": "m01",
                         "SddcManagerImageName": "esx-803"
                       }
                     ]

                     Cluster transition JSON (array format):
                     [
                       {
                         "ClusterName": "m01-cl01",
                         "WorkloadDomainName": "m01"
                       },
                       {
                         "ClusterName": "m01-cl02",
                         "WorkloadDomainName": "m01"
                       }
                     ]

                     Image import JSON (array format):
                     [
                       {
                         "VcenterImageName": "m01-cl01",
                         "VcenterName": "m01-vc01.example.com"
                       },
                       {
                         "VcenterImageName": "image-catalog-name",
                         "VcenterName": "m01-vc01.example.com"
                       }
                     ]

    Copyright      : Copyright (c) 2025 Broadcom. All Rights Reserved.
                     Broadcom Confidential. The term "Broadcom" refers to Broadcom Inc.
                     and/or its subsidiaries.

    License        : You are hereby granted a non-exclusive, worldwide, royalty-free license under
                     CA, Inc.'s copyrights to use, copy, modify, and distribute this software in
                     source code or binary form for use in connection with CA, Inc. products.

                     This copyright notice shall be included in all copies or substantial portions
                     of the software.

                     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
                     IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
                     FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
                     AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
                     LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
                     OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
                     THE SOFTWARE.

    Last Modified  : 2025-01-20

.LINK
    Knowledge Base Article:
    https://knowledge.broadcom.com/external/article?articleNumber=385617

.LINK
    vSphere Lifecycle Manager Documentation:
    https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/managing-host-and-cluster-lifecycle-8-0.html

.LINK
    VMware Cloud Foundation Documentation:
    https://docs.vmware.com/en/VMware-Cloud-Foundation/index.html
#>

# Copyright (c) 2025 Broadcom. All Rights Reserved.
# Broadcom Confidential. The term "Broadcom" refers to Broadcom Inc.
# and/or its subsidiaries.
#
###
#
# SOFTWARE LICENSE AGREEMENT
#
#
#
# Copyright (c) CA, Inc. All rights reserved.
#
#
#
# You are hereby granted a non-exclusive, worldwide, royalty-free license under CA, Inc.'s
# copyrights to use, copy, modify, and distribute this software in source code or binary form
# for use in connection with CA, Inc. products.
#
#
# This copyright notice shall be included in all copies or substantial portions of the software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
# NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
# DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
####

 Param (
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$CheckTaskStatus,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$CheckTransitions,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$ClusterName,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$ComplianceCheck,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$Connect,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$TransitionCluster,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$CreateVcenterImage,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$DeleteImageFromSddcManager,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$DeleteTemporaryCluster,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$Disconnect,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$Help,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$ImportImagesFromVcenter,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$JsonInput,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$JsonOutput,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$Parallel,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$RetryTransition,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$ReviewComplianceResults,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$Silence,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$TaskId,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$TaskType,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$TemporaryClusterName,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$SddcManagerImageName,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$ShowAllClusters,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$ShowBaselineClusters,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$ShowImagesInSddcManager,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$ShowImagesInVcenter,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$ShowExtendedResults,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$SkipPowercliVersionCheck,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$WorkloadDomainName,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$VcenterImageName,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$VcenterName,
    [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$Version
 )

$ScriptVersion = '1.0.0.0.60'

Function Show-AnyKey {

    <#
        .SYNOPSIS
        The function Show-AnyKey requires the user press a key before continuing.

        .DESCRIPTION
        When this script is run in interactive mode (rather than headless), this function is called
        to invite the user to press a key and return to the original function or menu, after
        reading an informational message.
    #>

    # function Show-AnyKey is not required in headless mode
    if ($Headless -eq "disabled") {
        Write-Host "`nPress any key to continue...`n" -ForegroundColor Yellow;
        $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') | Out-Null
    }
}

Function Get-SddcManagerVersion {

    <#
        .SYNOPSIS
        The function Get-SddcManagerVersion returns a portion of SDDC Manager release.

        .DESCRIPTION
        The major version version and first three minor revisions are returned.

        .EXAMPLE
        Returns 9.0.0.0
    #>

    # Powershell [version] is only a 16-bit int, so the SDDC Manager version must truncated.
    $PatternVersion = '^(\d+\.\d+\.\d+\.\d+)'
    $SddcManagerVersion= ($DefaultSddcManagerConnections.ProductVersion)
    $SanitizedSddcManagerVersion = $SddcManagerVersion -replace "(?<=$PatternVersion).*", ''

    return $SanitizedSddcManagerVersion

}
Function New-ChoiceMenu {

    <#
        .SYNOPSIS
        The function New-ChoiceMenu presents a yes/no decision prompt to the user.

        .DESCRIPTION
        The function takes in two mandatory values, a question (which prefaces the choice) and a
        default in the form of "yes" or "no."  The user's answer (in the form of 0 or 1) is
        returned to the source function and then processed.

        .EXAMPLE
        $Decision = New-ChoiceMenu -Question "Would you like to create $LogFolder" -DefaultAnswer yes

        .PARAMETER Question
        Specifies what question to answer the end user.

        .PARAMETER DefaultAnswer
        Specifies what answer (yes or no) is chosen if a user hits enter rather than entering Y/N.
    #>

    Param (
        [Parameter (Mandatory = $True)] [ValidateNotNullOrEmpty()] [String]$Question,
        [Parameter (Mandatory = $True)] [ValidateNotNullOrEmpty()] [String]$DefaultAnswer
    )

    $Choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $Choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes', "Yes"))
    $Choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No', "No"))

    if ($DefaultAnswer -eq "Yes") {
        $Decision = $Host.UI.PromptForChoice($Title, $Question, $Choices, 0)
    }
    else {
        $Decision = $Host.UI.PromptForChoice($Title, $Question, $Choices, 1)
    }

    return $Decision
}

Function New-LogFile {

    <#
        .SYNOPSIS
        At script launch, the function New-LogFile creates a log file if not already present.

        .DESCRIPTION
        The function New-LogFile creates a log file in logs sub-directory off of the PSScriptRoot directory
        with a timestamp in the format of Year-Month-Day. Should a logs sub-directory already exist, logs
        for this script may be identified by the prefix "VcfBaselineClusterTransition-"

        .EXAMPLE
        New-LogFile
    #>

    # create one log file for each day the script is run.
    $FileTimeStamp = Get-Date -Format "MM-dd-yyyy"
    $Global:LogFolder = Join-Path -Path $PSScriptRoot -ChildPath 'logs'
    $Global:LogFile = Join-Path -Path $LogFolder -ChildPath "VcfBaselineClusterTransition-$FileTimeStamp.log"
    $LogFolderExists = Test-Path $LogFolder

    if (!$LogFolderExists) {
        Write-Host "LogFolder not found, creating $LogFolder" -ForegroundColor Yellow;
        New-Item -ItemType Directory -Path $LogFolder | Out-Null
        if (!$?) {
            Write-Host "Failed to create log directory. Exiting."
            exit
        }
    }

    # Create the log file if not already present.
    # Every time the log file is created query the environmental settings and log them.
    if (! (Test-Path $LogFile)) {
        New-Item -type File -Path $LogFile | Out-Null
        Get-EnvironmentSetup
    }
}

Function Write-LogMessage {

    <#
        .SYNOPSIS
        The function Write-LogMessage writes a message to a log file and optionally displays it.

        .DESCRIPTION
        The function Write-LogMessage facilitates severity-level color-coded Messages to be sent to the
        screen, with a plain-text Message logged to a file.

        .EXAMPLE
        Write-LogMessage -Type ERROR -Message "No JSON input file $SddcManagerCredentialsJson detected."

        .EXAMPLE
        Write-LogMessage -Type ERROR -SuppressOutputToScreen -Message "No JSON input file $SddcManagerCredentialsJson detected."

        .EXAMPLE
        Write-LogMessage -Type ERROR -PrependNewLine -Message "No JSON input file $SddcManagerCredentialsJson detected."

        .EXAMPLE
        Write-LogMessage -Type ERROR -AppendNewLine -Message "No JSON input file $SddcManagerCredentialsJson detected."

        .PARAMETER AppendNewLine
        Specifies if a blank line should be written to the screen after the message is displayed.

        .PARAMETER PrependNewLine
        Specifies if a blank line should be written to the screen before the message is displayed.

        .PARAMETER Message
        Specifies the message logged and optionally displayed to the user.

        .PARAMETER SuppressOutputToScreen
        Specifies if the message should only be logged (and not displayed to the user).

        .PARAMETER Type
        Specifies a list of severity of the logged and optionally displayed to the user. In the case of
        a displayed Message, the severity will be color coded accordingly.
    #>

    Param (
        [Parameter (Mandatory = $False)] [Switch]$AppendNewLine,
        [Parameter (Mandatory = $True)] [AllowEmptyString()] [String]$Message,
        [Parameter (Mandatory = $False)] [Switch]$PrependNewLine,
        [Parameter (Mandatory = $False)] [Switch]$SuppressOutputToScreen,
        [Parameter (Mandatory = $False)] [ValidateSet("INFO", "ERROR", "WARNING", "EXCEPTION","ADVISORY")] [String]$Type = "INFO"
    )

    $MsgTypeToColor=@{
        "INFO" = "Green";
        "ERROR" = "Red" ;
        "WARNING" = "Yellow" ;
        "ADVISORY" = "Yellow" ;
        "EXCEPTION" = "Cyan"
    }
    $MessageColor=$MsgTypeToColor.$Type

    $TimeStamp = Get-Date -Format "MM-dd-yyyy_HH:mm:ss"

    if ($PrependNewLine -and $($Global:LogOnly -eq "disabled")) {
        Write-Output ""
    }

    if (!$SuppressOutputToScreen -and ($Global:LogOnly -eq "disabled")) {
        Write-Host -ForegroundColor $MessageColor "[$Type] $Message"
    }

    if ($AppendNewLine -and ($Global:LogOnly -eq "disabled")) {
        Write-Output ""
    }

    $LogContent = '[' + $TimeStamp + '] ' + '('+ $Type + ')' + ' ' + $Message
    Add-Content -path $LogFile $LogContent
}

Function Connect-SddcManager {

    <#
        .SYNOPSIS
        The function Connect-SddcManager authenticates against a user-defined SDDC Manager.

        .DESCRIPTION
        This function uses either a JSON input file (which it can create as part of the workflow)
        or an SDDC manager FQDN, SSO/federated username, and SSO/federated password, provided via
        prompts to login to an SDDC manager. The user must have administrative rights.

        .EXAMPLE
        Connect-SddcManager
    #>

    # Remove prior error state for better parsing.
    $Error.Clear()
    # For safety, this script only supports a connection to one SDDC Manager at a time.
    if ($DefaultSddcManagerConnections) {

        # Check if there is a valid refresh token by invoking an arbitrary VCF cmdlet.
        $Response = (Invoke-VcfGetDomains -ErrorAction SilentlyContinue).Elements

        if (($Error[0] -match "TOKEN_NOT_FOUND") -or ($Error[0] -match "JWT expired")) {
            $TokenExpired = 'true'
        } elseif ($Error[0] -match "is recognized as a name of a cmdlet") {
            Write-LogMessage -Type ERROR -AppendNewLine -Message "Could not find PowerCLI cmdlet Invoke-VcfGetDomains. Your PowerCLI installation may be incomplete."
            exit
        }

        if ($Response) {
            if ($TokenExpired) {
                Write-LogMessage -Type ADVISORY -SuppressOutputToScreen -Message "$($Error[0])"
                Write-LogMessage -Type ADVISORY -Message "SDDC Manager token for `"$Global:SddcManagerFqdn`" has expired.  Attempting to re-authenticate..."
                Disconnect-SddcManager -NoPrompt -Silence
                try {
                    $ConnectedToSddcManager = Connect-VcfSddcManagerServer -Server $Global:SddcManagerFqdn -User $Global:SddcManagerUserName -Password $Global:SddcManagerPassword -ErrorAction SilentlyContinue
                } catch [Exception] {
                    Write-LogMessage -Type ERROR -Message "SDDC Manager connection to `"$Global:SddcManagerFqdn`" produced error message: $($Error[0])"
                }

            } else {
                Write-LogMessage -Type ADVISORY -Message "Already connected to SDDC Manager `"$($DefaultSddcManagerConnections.Name)`"."
                return
            }
        }
    }

    $Error.Clear()
    # valid if the credentials file exists
    $SddcManagerCredentialsJsonFileExists = Test-Path $SddcManagerCredentialsJson

    try {
        if ($SddcManagerCredentialsJsonFileExists) {
            Write-LogMessage -Type INFO -PrependNewLine -AppendNewLine -Message "Detected JSON input file `"$SddcManagerCredentialsJson`"."
            $Global:SddcManagerFqdn = (Get-Content $SddcManagerCredentialsJson | ConvertFrom-Json).SddcManagerFqdn
            $Global:SddcManagerUserName = (Get-Content $SddcManagerCredentialsJson | ConvertFrom-Json).SddcManagerUserName
            $Global:SddcManagerPassword = (Get-Content $SddcManagerCredentialsJson | ConvertFrom-Json).SddcManagerPassword

            # Check inputs,  If the values cannot be set, assume improper formatting of some sort.
            if ( ([String]::IsNullOrEmpty($Global:SddcManagerFqdn)) -or ([String]::IsNullOrEmpty($Global:SddcManagerUserName)) -or ([String]::IsNullOrEmpty($Global:SddcManagerPassword)) ) {
                Write-LogMessage -Type ERROR -Message "Please confirm the formatting of $SddcManagerCredentialsJson and return to the script."
                exit
            }

        } else {
            if ($Global:LogOnly -eq "enabled") {
                # Use Write-Output as well as Write-LogMessage output to screen suppressed in Silence mode.
                Write-Host "Option -Silence cannot be used when JSON credential file not present." -ForegroundColor Red
                Write-LogMessage -Type ERROR -Message "Option -Silence cannot be used when JSON credential file not present."
                exit
            }
            Write-LogMessage -Type WARNING -AppendNewLine -Message "JSON SDDC Credentials input file `"$SddcManagerCredentialsJson`" not detected"
            Write-LogMessage -Type WARNING -SuppressOutputToScreen -Message "Could not locate JSON credentials file `"$SddcManagerCredentialsJson`" ."
            Write-LogMessage -Type INFO -AppendNewLine -Message "Please enter your connection details at the prompt."
            $Global:SddcManagerFqdn = Read-Host "Enter your SDDC Manager FQDN"
            $Global:SddcManagerUserName = Read-Host "Enter your SDDC Manager SSO username"
            $Global:SddcManagerPassword = Read-Host "Enter your SDDC Manager SSO password" -AsSecureString
        }

        $ConnectedToSddcManager = Connect-VcfSddcManagerServer -Server $Global:SddcManagerFqdn -User $Global:SddcManagerUserName -Password $Global:SddcManagerPassword -ErrorAction SilentlyContinue

    } catch {
    }

    # Display friendly Messages to the end user for common errors
    if ($Error[0] -match "IDENTITY_UNAUTHORIZED_ENTITY") {
        Write-LogMessage -Type ERROR -Message "Failed to connect to SDDC Manager `"$Global:SddcManagerFqdn`" using username `"$Global:SddcManagerUserName`". Please check your credentials."
    } elseif ($Error[0] -match "nodename nor servname provided") {
        Write-LogMessage -Type ERROR -Message "Cannot resolve SDDC Manager `"$Global:SddcManagerFqdn`". If this is a valid SDDC Manager FQDN, please check your DNS settings."
    } elseif ($Error[0] -match "The requested URL <code>/v1/tokens</code> was not found on this Server") {
        Write-LogMessage -Type ERROR -Message "SDDC Manager `"$Global:SddcManagerFqdn`" did not return a valid response. Please check that `"$Global:SddcManagerFqdn`" is a valid SDDC Manager FQDN and if its services are healthy."
    } elseif ($Error[0] -match "The SSL connection could not be established.") {
        Write-LogMessage -Type ERROR -Message "SSL Connection error to SDDC Manager `"$Global:SddcManagerFqdn`". Please check that SDDC Manager has a CA signed certificate or Powershell trusts insecure certificates."
    } elseif ($Error[0] -match "Permission not found") {
        Write-LogMessage -Type ERROR -Message "Username `"$Global:SddcManagerUserName`" does not have access to SDDC Manager."
    } elseif ($Error[0] -match "not recognized as a name of a cmdlet") {
        Write-LogMessage -Type ERROR -Message "Could not find PowerCLI cmdlet Connect-VcfSddcManagerServer. Your PowerCLI installation may be incomplete."
    } elseif ($Error[0] -match "but the module could not be loaded") {
        Write-LogMessage -Type ERROR -Message "VMware.Sdk.Vcf.SddcManager, the module containing the required Connect-VcfSddcManagerServer PowerCLI cmdlet could not be loaded.  Your PowerCLI environment may not be configured correctly.  Please investigate before re-running this script."
    } elseif ($Error[0]) {
        # See if there's a deeper Message first, then throw the whole error Message.
        if ( $($Error[0].Exception.InnerException.Message)) {
            Write-LogMessage -Type ERROR -Message "Error Message: $($Error[0].Exception.InnerException.Message)"
        } else {
            Write-LogMessage -Type ERROR -Message "Error Message: $($Error[0])"
            }
    }

     # Catches the first attempt to enter a valid endpoint and credentials and if
     # invalid loops back to the start of the function if the user agrees.
    if (! $ConnectedToSddcManager) {
        if ($SddcManagerCredentialsJsonFileExists) {
            Write-LogMessage -Type ERROR -PrependNewLine -Message "Please confirm your SDDC Manager FQDN and user credentials in $SddcManagerCredentialsJson and return to the script."
            exit
        }
        $Decision = New-ChoiceMenu -Question "Would you like to re-enter your SDDC Manager FQDN and user credentials?" -DefaultAnswer yes

        # default to allowing the user to attempt to re-authenticate
        if ($Decision -eq 0) {
            # Loop back to function
            Connect-SddcManager
        } else {
            Show-AnyKey
            break
        }
    } else {
        Write-LogMessage -Type INFO -AppendNewLine -Message "Successfully connected to SDDC Manager `"$Global:SddcManagerFqdn`"."
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "SDDC Manager `"$Global:SddcManagerFqdn`" version is `"$($DefaultSddcManagerConnections.ProductVersion)`"."

        # After successfully connecting to SDDC Manager, check that it's at the minimum required release.

        $SddcManagerVersion = Get-SddcManagerVersion

        if ([Version]($SddcManagerVersion) -lt [Version]($MinimumVcfRelease)) {
            Write-LogMessage -Type ERROR -Message "SDDC Manager version $SddcManagerVersion detected on `"$($DefaultSddcManagerConnections.Name)`". Version $MinimumVcfRelease or later is required."
            Disconnect-SddcManager -NoPrompt -Silence
            exit
        }

        # To avoid password reentry, the script will automatically create a SDDC Manager Credential JSON file
        # based off of user inputted data. This action is called late in the script to ensure the credentials
         # entered are correct.
        if (! $SddcManagerCredentialsJsonFileExists) {
            Write-LogMessage -Type ADVISORY -AppendNewLine -Message "Your SDDC Manager login credentials may be saved to a file to allow non-interactive login in the future. This is not required, and the file may be safely removed at any time."
            $Decision = New-ChoiceMenu -Question "Would you like to save your SDDC login credentials in a JSON file?" -DefaultAnswer no
            # selection zero equals yes
            if ($Decision -eq 0) {
                Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "User chose to save SDDC Manager credentials to JSON file."
                Write-LogMessage -Type INFO -AppendNewLine -Message "Writing credentials to `"$SddcManagerCredentialsJson`" ..."
                $DecodedPasswordInterimStep = [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($Global:SddcManagerPassword)
                $DecodedSddcManagerPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($DecodedPasswordInterimStep)
                [System.Runtime.InteropServices.Marshal]::ZeroFreeCoTaskMemUnicode($DecodedPasswordInterimStep)

                $JsonHashTable = @{
                    'SddcManagerFqdn' = $Global:SddcManagerFqdn
                    'SddcManagerUserName' = $Global:SddcManagerUserName
                    'SddcManagerPassword' = $DecodedSddcManagerPassword
                }
                $JsonOutput = $JsonHashTable | ConvertTo-Json
                Set-Content -path $SddcManagerCredentialsJson $JsonOutput
            } else {
                Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "User chose not to save SDDC Manager credentials to JSON file."
            }
        }
    }
}

Function Test-SddcManagerConnection {

    <#
        .SYNOPSIS
        The function Test-SddcManagerConnection verifies that the script is connected to SDDC Manager.

        .DESCRIPTION
        This function checks tries two different means of determining if there's SDDC Manager connection.

        .EXAMPLE
        Test-SddcManagerConnection
    #>

    try {
        $Response = (Invoke-VcfGetDomains -ErrorAction SilentlyContinue).Elements
    } catch {

    }
    if ($Error[0] -match "JWT signature|JWT expired|HttpClient.Timeout|TOKEN_NOT_FOUND|You are not currently connected") {
        Connect-SddcManager
    }

}


Function Connect-Vcenter {

        <#
        .SYNOPSIS
        The function Connect-Vcenter establishes a connection to one or more Workload Domain vCenter(s).

        .DESCRIPTION
        This function connects to each vCenter using credentials sourced from SDDC ManagerDifferent credentials
        are used depending if the Workload Domain vCenter is using isolated or MGMT SSO credentials. These
        credentials are never exposed to the end user.

        .EXAMPLE
        Connect-Vcenter

    #>

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    # Intercept disconnected vCenter calls
    $DisconnectedVcenters = ($Global:DefaultViServers | Where-Object IsConnected -eq $False).Name

    $ReconnectedVcenters = @()

    if ($DisconnectedVcenters) {

        $MgmtDomain = (Invoke-VcfGetDomains -type MANAGEMENT).Elements
        $MgmtSsoDomainElements = (Invoke-VcfGetCredentials -AccountType SYSTEM -ResourceType PSC).Elements | Where-Object { $_.Resource.DomainNames -eq $($MgmtDomain.Name) -and $_.Username -match "@$($MgmtDomain.SsoName)" }

        foreach ($VcenterName in $DisconnectedVcenters) {
            $VcenterUserName = ((Invoke-VcfGetCredentials -AccountType SYSTEM -ResourceType PSC).Elements | Where-Object { $_.Resource.ResourceName -eq $VcenterName }).Username
            if (!$VcenterUserName) {
                # check if the domain uses a shared SSO
                if (((Invoke-VcfGetDomains).Elements | Where-Object {$_.Vcenters.fqdn -eq $VcenterName }).IsManagementSsoDomain -eq $True ) {
                    $VcenterUserName = $($MgmtSsoDomainElements).Username
                    $SecureVcenterPassword = ConvertTo-SecureString -String $($MgmtSsoDomainElements).Password -AsPlainText -Force
                }
            } else {
                $VcenterPassword = ((Invoke-VcfGetCredentials -AccountType SYSTEM -ResourceType PSC).Elements | Where-Object { $_.Resource.ResourceName -eq $VcenterName }).Password
                $SecureVcenterPassword = ConvertTo-SecureString -String $VcenterPassword -AsPlainText -Force
            }
            Remove-Variable -ErrorAction SilentlyContinue -Name VcenterPassword
            $VcenterCredential = New-Object System.Management.Automation.PSCredential($VcenterUserName, $SecureVcenterPassword)

            try {
                $ConnectedToVcenterServer = Connect-VIServer -Server $VcenterName -Credential $VcenterCredential -ErrorAction Stop
            } catch [Exception] {
                Write-LogMessage -Type ERROR -Message "Failed to re-connect to vCenter `"$VcenterName`"."
                Write-LogMessage -Type ERROR -Message "$($Error[0].Exception.InnerException.Message)"
            }

            if ($ConnectedToVcenterServer) {
                $ReconnectedVcenters += $VcenterName
                Write-LogMessage -Type INFO -AppendNewLine -Message "Successfully reconnected to vCenter `"$VcenterName`"."
            }

        }

    }

    # List all connected vCenter(s).
    $ConnectedVcenters = ($Global:DefaultViServers | Where-Object IsConnected -eq $True).Name
    if ($ConnectedVcenters) {
        foreach ($VcenterName in $ConnectedVcenters) {
            # Don't perform a vC disconnect if we just reconnected that vCenter a moment before.
            if (! $ReconnectedVcenters.Contains($VcenterName)) {
                Write-LogMessage -Type ADVISORY -AppendNewLine -Message "Already connected to vCenter `"$VcenterName`"."
                Disconnect-Vcenter -VcenterName $VcenterName
            }
        }
    }

    if  ($Headless -eq "disabled") {
        Write-Host "The following vCenter(s) were detected in SDDC Manager `"$($DefaultSddcManagerConnections.Name)`": `n"  -ForegroundColor Green
    }

    # Collect details of VCF domains to get vCenter FQDN and WLD name.
    $Response = (Invoke-VcfGetDomains).Elements | Sort-Object

    # This is very unlikely, but the remaining calls in this function depend on properly-formed
    # VCF WLD output.
    if ([String]::IsNullOrEmpty($Response)) {
        Write-LogMessage -Type ERROR -Message "Unable to list VCF Workload Domains."
        Write-LogMessage -Type ERROR -Message "$($Error[0])"
        Show-AnyKey
        break
    }

    # Prepare a selection menu of options based on generated IDs.
    $VcenterDisplayObject = @()
    $VcenterIndex = 1

    $VcenterDisplayObject += [pscustomobject]@{
        'Id'                  = "Id"
        'VcenterName'         = "vCenter"
        'WorkloadDomainName'  = "Workload Domain"
    }

    $VcenterDisplayObject += [pscustomobject]@{
        'Id'                  = "--"
        'VcenterName'         = "-------"
        'WorkloadDomainName'  = "---------------"
    }

    # First option is to connect to all vCenters.
    $VcenterDisplayObject += [pscustomobject]@{
        'Id'                  = "$VcenterIndex"
        'VcenterName'         = "<ALL VCENTERS>"
        'WorkloadDomainName'  = "N/A"
    }

    foreach ($Line in $Response) {
        $VcenterIndex++
        $VcenterDisplayObject += [pscustomobject]@{
            'Id'                 = $VcenterIndex
            'VcenterName'        = $Line.Vcenters.fqdn
            'WorkloadDomainName' = $Line.Name
        }
    }

    # Only present a selection choice for interactive mode.
    if ($Headless -eq "disabled") {
        $VcenterDisplayObject | Format-Table -Property @{Expression = " " }, Id, VcenterName, WorkloadDomainName -Autosize -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }
        Write-Host "`nThis script can only transition vLCM baseline-managed clusters for connected vCenter(s).`n" -ForegroundColor Yellow
    }

    Do {

    if ($Headless -eq "disabled") {
        $VersionSelection = Read-Host "Enter an id, a comma-delimited list of ids of vCenters to connect to, or type 'c' to cancel"

        if ($VersionSelection -eq "c") {
            return
        }

        Write-Output ""
    }

    # Determine the management SSO domain.
    $MgmtDomain = (Invoke-VcfGetDomains -type MANAGEMENT).Elements

    # Verify the user has sufficient permissions to pull vCenter credentials from SDDC Manager.
    # Operator and Viewer do not have access to SSO credentials.
    try {
        $MgmtSsoDomainElements = (Invoke-VcfGetCredentials -AccountType SYSTEM -ResourceType PSC).Elements | Where-Object { $_.Resource.DomainNames -eq $($MgmtDomain.Name) -and $_.Username -match "@$($MgmtDomain.SsoName)" }
    }
    catch {
        if ($($Error[0]) -match "Forbidden") {
            $AccessDenied = 'true'
        }
    }
    if (! $MgmtSsoDomainElements) {
        if ($AccessDenied -eq 'true') {
            Write-LogMessage -Type ERROR -Message "Your SDDC Manager SSO user does not have sufficient access. Please reconnect to SDDC Manager as a user with the ADMIN role."
        } else {
            Write-LogMessage -Type ERROR -Message "Cannot retrieve vCenter credentials from SDDC Manager."
        }
        Write-LogMessage -Type ERROR -Message "$($Error[0])"
        Show-AnyKey
        Show-MainMenu
    }
    $MgmtSsoDomainUsername = $($MgmtSsoDomainElements).Username
    $MgmtSsoDomainPassword = ConvertTo-SecureString -String $($MgmtSsoDomainElements).Password -AsPlainText -Force

    # Destroy the variable that contains a non-secured password, now that it's no longer needed.
    Clear-Variable -Name MgmtSsoDomainElements

    # Headless operations automatically connects to all vCenter(s). Mock the <ALL VCENTERS> connection choice.
    # to reduce complexity.
    if ($Headless -eq "enabled") {
        $VersionSelection = ($VcenterDisplayObject | Where-Object {$_.VcenterName -eq "<ALL VCENTERS>"}).Id
    }

    # Check if the user selected to Connect to all vCenters.
    if ((($VcenterDisplayObject | Where-Object {$_.Id -eq $VersionSelection}).VcenterName) -eq "<ALL VCENTERS>") {
        $SelectedVcenterIds = @()
        # The first index value is "<ALL-VCENTERS>" followed by individual vCenters.
        for ($I = 2; $I -le $VcenterIndex; $I+=1) {
            $SelectedVcenterIds += $I
        }
    } else {
        $SelectedVcenterIds = $VersionSelection.Split(",")
    }
    # Create an array of vCenters based on the user's selection.
    Write-LogMessage -Type INFO  -AppendNewLine -Message "Preparing to connect to vCenter(s)..."
        foreach ($SelectedVcenterId in ($SelectedVcenterIds | Get-Unique)) {

        $SelectedVcenterName = (($VcenterDisplayObject | Where-Object {$_.Id -eq $SelectedVcenterId}).VcenterName)
        if ([String]::IsNullOrEmpty($SelectedVcenterName)) {
            Write-LogMessage -Type ERROR -Message "$SelectedVcenterId identifier or delimiter not valid. Please re-enter your selection."
            $BadId = "true"
            # If the Id is bad immediately break and ask the user to re-enter their selection.
            break
        } else {
            # Check for bad user input (individual and all vCenter options are mutually exclusive).
            if ($SelectedVcenterName -ne "<ALL VCENTERS>") {

                # Check if the selected Workload Domain uses the MGMT SSO domain.
                $VcenterName = ($VcenterDisplayObject | Where-Object {$_.Id -eq $SelectedVcenterId}).VcenterName
                $WorkloadDomainName = ($VcenterDisplayObject | Where-Object {$_.Id -eq $SelectedVcenterId}).WorkloadDomainName
                $SharedSsoDomain = ((Invoke-VcfGetDomains).Elements | Where-Object Name -eq $WorkloadDomainName).IsManagementSsoDomain

                if ($SharedSsoDomain -eq $True ) {
                    $VcenterCredential = New-Object System.Management.Automation.PSCredential($MgmtSsoDomainUsername, $MgmtSsoDomainPassword)
                } else {
                    $IsolatedWldDomain = (Invoke-VcfGetDomains).Elements | Where-Object Name -eq $WorkloadDomainName

                    $IsolatedWldSsoDomainElements = (Invoke-VcfGetCredentials -AccountType SYSTEM -ResourceType PSC).Elements | Where-Object { $_.Resource.DomainNames -eq $($IsolatedWldDomain.Name) -and $_.Username -match "@$($IsolatedWldDomain.SsoName)" }

                    $IsolatedWldSsoDomainUsername = $($IsolatedWldSsoDomainElements).Username

                    $IsolatedWldSsoDomainPassword = ConvertTo-SecureString -String $($IsolatedWldSsoDomainElements).Password -AsPlainText -Force
                    # Destroy the variable that contains the non-secured password, now that it's no longer needed.
                    Clear-Variable -Name IsolatedWldSsoDomainElements
                    $VcenterCredential = New-Object System.Management.Automation.PSCredential($IsolatedWldSsoDomainUsername, $IsolatedWldSsoDomainPassword)
                }

                try {
                    $ConnectedToVcenterServer = Connect-VIServer -Server $VcenterName -Credential $VcenterCredential -ErrorAction Stop
                } catch [Exception] {
                    Write-LogMessage -Type ERROR -Message "Failed to connect to vCenter `"$VcenterName`"."
                    Write-LogMessage -Type ERROR -Message "$($Error[0].Exception.InnerException.Message)"
                }

                if ($ConnectedToVcenterServer) {
                    Write-LogMessage -Type INFO -Message "Successfully connected to vCenter `"$VcenterName`"."
                }

                } else {
                    Write-LogMessage -Type ERROR -Message "Individual vCenter and <ALL VCENTERS> option selected. Ignoring '<ALL VCENTERS>.'"
                    Write-Output ""
                }
                $BadId = "false"
            }
        }
    } While ($BadId -eq "true")

}

Function Test-VcentersConnection {

    <#
        .SYNOPSIS
        The function Test-VcentersConnection checks for a vCenter connection.

        .DESCRIPTION
        This function displays an error Message if there are no vCenter connections
        defined in the global variable DefaultViServers or if one or more vCenter(s) has
        the property isConnected:false. Afterward, the Connect-Vcenter function
        is called to remedy the situation.

        .EXAMPLE
        Test-VcenterServersConnection
    #>

    # Check if any vCenter(s) are known
    if (! $Global:DefaultViServers ) {
        Connect-Vcenter
    }

    # Check if any vCenter are in a disconnected state
    $DisconnectedVcenters = ($Global:DefaultViServers | Where-Object IsConnected -eq $False).Name

    if ($DisconnectedVcenters) {
        foreach ($DisconnectedVcenter in $DisconnectedVcenters) {
            Write-LogMessage -Type ERROR -AppendNewLine -Message "vCenter `"$DisconnectedVcenter`" is disconnected."
        }
        Write-LogMessage -Type INFO -AppendNewLine -Message "Automatically reconnecting to vCenter(s)..."
        Connect-Vcenter
    }
}
Function Get-BaselineManagedClusters {

     <#
        .SYNOPSIS
        The function Get-BaselineManagedClusters displays vLCM baseline (VUM) managed clusters.

        .DESCRIPTION
        This function examines to the isImageBased property of a VCF cluster to determine if it is image or baseline managed.
        It can be used to power a user selection of which cluster(s) should be converted to vLCM image management.

        .EXAMPLE
        Get-BaselineManagedClusters -ClusterSelection Multiple

        .EXAMPLE
        Get-BaselineManagedClusters -IdSelection 3

        .EXAMPLE
        Get-BaselineManagedClusters -JsonOutputFile VlcmBaseManagedCluster.json

        .PARAMETER ClusterSelection
        Specifies if a single or multiple clusters are selected for transition. Each option has a slightly different validation routine.

        .PARAMETER IdSelection
        Specifies the Id of a cluster selected for transition to vLCM Image Management.

        .PARAMETER JsonOutputFile
        Specifies if the findings should be saved to a JSON file.
    #>

    Param (
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$ClusterSelection,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$IdSelection,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$JsonOutputFile
    )

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection
    # Check if connected to vCenter(s).
    Test-VcentersConnection

    $VlcmBaselineManagedClustersDisplayObject = @()
    $VlcmBaselineManagedClustersIndex = 1

    $VlcmBaselineManagedClustersDisplayObject += [pscustomobject]@{
        'Id'                   = "Id"
        'ClusterName'          = "Cluster Name"
        'ClusterId'            = "Cluster Id"
        'VcenterName'          = "vCenter Name"
        'WorkloadDomainName'   = "Workload Domain"
        'WorkloadDomainId'     = "Workload Domain Id"
        'ComplianceStatus'     = "Compliance Status"
        'SddcManagerImageName' = "SDDC Manager Image Name"
    }

    $VlcmBaselineManagedClustersDisplayObject += [pscustomobject]@{
        'Id'                   = "--"
        'ClusterName'          = "------------"
        'ClusterId'            = "-"
        'VcenterName'          = "------------"
        'WorkloadDomainName'   = "---------------"
        'WorkloadDomainId'     = "-"
        'ComplianceStatus'     = "-----------------"
        'SddcManagerImageName' = "-----------------------"
    }

    if ($Headless -eq "enabled") {
        Write-LogMessage -Type INFO -PrependNewLine -AppendNewLine -Message "Scanning for vLCM baseline (VUM) managed clusters..."
    }
    # Only display vLCM baseline managed clusters for connected vCenters.
    foreach ($Vcenter in @($Global:DefaultViServers.Name | Sort-Object)) {
        try {
            $Response = (Invoke-VcfGetClusters -IsImageBased $False).Elements | Sort-Object Name
        } catch [Exception] {
            if ($($Error[0].Exception.Message) -match "The request was canceled due to the configured HttpClient.Timeout" ) {
                Write-LogMessage -Type ERROR -Message "Network error.  Cannot connect to SDDC Manager `"$Global:SddcManagerFqdn`"."
            } else {
                Write-LogMessage -Type ERROR -Message $Error[0].Exception.Message
            }
            $ResponseError=$true
        }
        if (!$Response) {
            break
        }
        foreach ($Line in $Response) {
        if ($Line.vCenter.fqdn -eq $Vcenter) {

            $ComplianceStatus = (Invoke-VcfGetClusterImageCompliance -Id ($Line.Id) -ErrorAction SilentlyContinue).Status
            if (! $ComplianceStatus) {
                $ComplianceStatus = "NOT_CHECKED_YET"
            }

            $SddcManagerImageName = (Invoke-VcfGetClusterImageCompliance -Id ($Line.Id) -ErrorAction SilentlyContinue).ClusterImage.Name
            if (! $SddcManagerImageName) {
                $SddcManagerImageName = "N/A"
            }

            $VlcmBaselineManagedClustersDisplayObject += [pscustomobject]@{
                'Id'                   = $VlcmBaselineManagedClustersIndex
                'ClusterName'          = $Line.Name
                'ClusterId'            = $Line.Id
                'VcenterName'          = $Line.vCenter.fqdn
                'WorkloadDomainName'   = (Invoke-VcfGetDomain -Id $($Line.Domain.Id)).Name
                'WorkloadDomainId'     = (Invoke-VcfGetDomain -Id $($Line.Domain.Id)).Id
                'ComplianceStatus'     = $ComplianceStatus
                'SddcManagerImageName' = $SddcManagerImageName
            }
            $VlcmBaselineManagedClustersIndex++
            $VlcmBaselineManagedClustersFound = 'true'
            Write-LogMessage -SuppressOutputToScreen -type INFO -Message "Cluster `"$($Line.Name)`" in Workload Domain `"$((Invoke-VcfGetDomain -Id $($Line.Domain.Id)).Name)`" is vLCM baseline (VUM) managed."
            }
        }
    }

    if (! $VlcmBaselineManagedClustersFound) {
        if (!$ResponseError) {
            Write-LogMessage -Type ERROR -AppendNewLine -Message "No vLCM baseline (VUM) managed clusters detected in connected vCenter(s)."
        }
        Show-AnyKey
        break
    }

    if (! $IdSelection) {
        if ($Headless -eq "disabled") {
            Write-Host "Displaying vLCM baseline (VUM) managed clusters in connected vCenter(s):`n" -ForegroundColor Green;
                return $VlcmBaselineManagedClustersDisplayObject | Format-Table -Property @{Expression = " " }, Id, ClusterName, VcenterName, WorkloadDomainName, ComplianceStatus, SddcManagerImageName -Autosize -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }
        } else {
            if ($JsonOutputFile) {
                # The first two rows of the array contain header information.
                $Id = 0
                $JsonHashTable = foreach($Cluster in $VlcmBaselineManagedClustersDisplayObject) {
                    try {
                        $SddcManagerImageName = (Invoke-VcfGetClusterImageCompliance -Id ($Cluster.ClusterId).ClusterImage.Name -ErrorAction SilentlyContinue)
                    } catch {
                    }
                    if (! $SddcManagerImageName) {
                        $SddcManagerImageName = "N/A"
                    }
                    if ($Id -ge 2) {
                        [ordered]@{
                                ClusterName = $Cluster.ClusterName
                                WorkloadDomainName = $Cluster.WorkloadDomainName
                                SddcManagerImageName = $Cluster.SddcManagerImageName
                        }
                    }
                    $Id++
                }
                $JsonOutput = $JsonHashTable | ConvertTo-Json
                Set-Content -path $JsonOutputFile $JsonOutput
            }

            if ($Global:LogOnly -eq "disabled") {
                Write-LogMessage -Type INFO -AppendNewLine -Message "vLCM Baseline (VUM) Managed Clusters:"
                if ($Headless) {
                    return $VlcmBaselineManagedClustersDisplayObject | Format-Table -Property @{Expression = " " }, ClusterName, VcenterName, WorkloadDomainName, ComplianceStatus, SddcManagerImageName -Autosize -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }
                } else {
                    return $VlcmBaselineManagedClustersDisplayObject | Format-Table -Property @{Expression = " " }, ClusterName, VcenterName, WorkloadDomainName -Autosize -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }
                }
            }
        }
    }
    # multi-cluster selection must be aware of three Elements, Cluster Name, Cluster vCenter, and Cluster WLD.
    if ($ClusterSelection -eq "multiple") {

        $SelectedClusters=@()

        foreach ($SelectedClusterId in $IdSelection.Split(",")) {
            if ([String]::IsNullOrEmpty($SelectedClusterId)) {
                return
            } else {
                $SelectedClusters += [pscustomobject]@{
                    'ClusterId'           = ($VlcmBaselineManagedClustersDisplayObject | Where-Object {$_.Id -eq $SelectedClusterId}).ClusterId
                    'ClusterName'         = ($VlcmBaselineManagedClustersDisplayObject | Where-Object {$_.Id -eq $SelectedClusterId}).ClusterName
                    'WorkloadDomainId'    = ($VlcmBaselineManagedClustersDisplayObject | Where-Object {$_.Id -eq $SelectedClusterId}).WorkloadDomainId
                    'WorkloadDomainName'  = ($VlcmBaselineManagedClustersDisplayObject | Where-Object {$_.Id -eq $SelectedClusterId}).WorkloadDomainName
                }
            }
        }
        return $SelectedClusters
    }
}

Function Remove-ImageFromSddcManager {

    <#
        .SYNOPSIS
        The function Remove-ImageFromSddcManager removes a vLCM Image from SDDC Manager.

        .DESCRIPTION
        This function should only be used to remove accidentally uploaded or stale images.
        It requires the ImageName parameter.

        .EXAMPLE
        Remove-ImageFromSddcManager -SddcManagerImageName vsphere803

        .PARAMETER ImageName
        Specifies which vLCM image name to remove from SDDC Manager
    #>

    Param (
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$SddcManagerImageName
    )

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    if ($Headless -eq "disabled") {
        try {
            $SddcManagerImageNames = (Invoke-VcfGetPersonalities -ErrorAction SilentlyContinue).Elements.PersonalityName
        } catch [Exception] {
            Write-LogMessage -Type ERROR -Message "Error looking up SDDC Manager Images: $($Error[0])`"."
            Show-AnyKey
            break
        }

        if ($SddcManagerImageNames) {

            $SddcManagerImageDisplayObject = @()
            $SddcManagerImageIndex = 1

            $SddcManagerImageDisplayObject += [pscustomobject]@{
                'Id'                   = "Id"
                'SddcManagerImageName' = "SDDC Manager Image Name"
            }
            $SddcManagerImageDisplayObject += [pscustomobject]@{
               'Id'                   = "--"
               'SddcManagerImageName' = "-----------------------"
            }
            foreach ($SddcManagerImageName in $SddcManagerImageNames) {
                $SddcManagerImageDisplayObject += [pscustomobject]@{
                    'Id'                   = $SddcManagerImageIndex
                    'SddcManagerImageName' = $SddcManagerImageName
                }
                $SddcManagerImageIndex++
            }
            Write-LogMessage -Type INFO -AppendNewLine -Message "Please only delete SDDC Manager images imported in error."

            $SddcManagerImageDisplayObject | Format-Table -Property @{Expression = " " }, Id, SddcManagerImageName -Autosize -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }

            Do {
                Write-Host ""
                $VersionSelection = Read-Host "Enter the id of the image you wish to delete, or press 'c' to cancel"
                if ($VersionSelection -eq "c") {
                    Write-LogMessage -Type INFO -PrependNewLine -Message "Cancellation requested. Returning to main menu."
                    Show-AnyKey
                    Show-MainMenu
                }
                $IsValidId = ($VersionSelection -in @($SddcManagerImageDisplayObject.Id))
                if (! $IsValidId) {
                    Write-LogMessage -Type ERROR -Message "Invalid selection: $VersionSelection identifier not found."
                }
            } While (! $IsValidId)
            $SddcManagerImageName = (($SddcManagerImageDisplayObject | Where-Object {$_.Id -eq $VersionSelection}).SddcManagerImageName)
        } else {
            Write-LogMessage -Type ERROR -Message "No images found in SDDC Manager `"$($DefaultSddcManagerConnections.Name)`"."
            Show-AnyKey
            break
        }
    }

    try {
        $Response = Invoke-VcfDeletePersonality -PersonalityName $SddcManagerImageName -ErrorAction SilentlyContinue
        # catch and explain the most common error.
    } catch {
        if ($($Error[0]) -match "PERSONALITY_NOT_FOUND") {
            Write-LogMessage -Type ERROR -Message "vLCM image `"$SddcManagerImageName`" not found in SDDC Manager `"$($DefaultSddcManagerConnections.Name)`"."
            Show-AnyKey
            exit
        } elseif ($($Error[0]) -match "Error calling DeletePersonality") {
            Write-LogMessage -Type ERROR -Message "Deletion operation for vLCM image `"$SddcManagerImageName`" failed with error: $($Error[0])."
            Show-AnyKey
            exit
        }
    }
    # iterate through all Personality names in SDDC Manager to determine if the image we tried to delete is still present.
    $Personalities = (Invoke-VcfGetPersonalities).Elements.PersonalityName
    foreach ($Personality in $Personalities) {
        if ($Personality -eq $SddcManagerImageName) {
            Write-LogMessage -Type ERROR -Message "Error: `"$SddcManagerImageName`" not deleted from from SDDC Manager `"$($DefaultSddcManagerConnections.Name)`"."
            Show-AnyKey
            exit
        }
    }
    Write-LogMessage -Type INFO -Message "Successfully deleted vLCM image `"$SddcManagerImageName`" from SDDC Manager `"$($DefaultSddcManagerConnections.Name)`"."
}

Function Test-VcenterImageCatalogSupport {
    <#
        .SYNOPSIS
        The function Test-VcenterImageCatalogSupport returns true if vCenter supports image catalogs.

        .DESCRIPTION
        Checks the Domain Capabilities of vCenter for "REPOSITORY_IMAGES" support.

        .EXAMPLE
        Test-VcenterImageCatalogSupport -VcenterName m01-vc01.example.com

        .PARAMETER VcenterName
        Specifies which vCenter to check
    #>

    Param (
        [Parameter (Mandatory = $True)] [ValidateNotNullOrEmpty()] [String]$VcenterName
    )

    try {
        $VcenterDetails = ((Invoke-VcfGetVcenters).Elements | Where-Object Fqdn -eq $VcenterName)
    } catch [Exception] {
        if ($($Error[0].Exception.Message) -match "The request was canceled due to the configured HttpClient.Timeout" ) {
            Write-LogMessage -Type ERROR -Message "Network error.  Cannot connect to vCenter `"$VcenterName`"."
        } else {
            Write-LogMessage -Type ERROR -Message $($Error[0].Exception.Message)
        }
    }

    if (!$VcenterDetails) {
        break
    }

    # Collect the capabilities of this domain based on its Domain ID
    $DomainCapabilities = (Invoke-VcfGetDomainCapabilitiesByDomainId -id $VcenterDetails.Domain.ID).Capabilities

    # REPOSITORY_IMAGES capability indicates support for vCenter image catalog (vCenter 9+).
    if ($DomainCapabilities.Contains("REPOSITORY_IMAGES")) {
        return $true
    } else {
        return $false
    }
}

Function Get-VcenterImageCatalog {

     <#
        .SYNOPSIS
        The function Get-VcenterImageCatalog return an image catalog.

        .DESCRIPTION
        The return value is an array of image catalogs in the named vCenter.  If no catalog
        Elements are present, return false.

        .EXAMPLE
        Get-VcenterImageCatalog -VcenterName m01-vc01.example.com

        .PARAMETER VcenterName
        Specifies which vCenter to check
    #>

    Param (
        [Parameter (Mandatory = $True)] [ValidateNotNullOrEmpty()] [String]$VcenterName
    )

    $VcenterDetails = ((Invoke-VcfGetVcenters).Elements | Where-Object Fqdn -eq $VcenterName)
    if ([String]::IsNullOrEmpty($VcenterDetails)) {
        Write-LogMessage -Type ERROR -Message "Invalid vCenter name `"$VcenterName`"."
        Show-AnyKey
        break
    }

    $RepositoryImageQuerySpec = Initialize-VcfRepositoryImageQuerySpec -VcenterIds $($VcenterDetails.ID)

    $VcenterImageCatalog = (Invoke-VcfInitiateRepositoryImagesQuery -RepositoryImageQuerySpec $RepositoryImageQuerySpec).Result.Elements

    # Check if the image catalog contains any images, if so return said catalog object.
    if ([String]::IsNullOrEmpty($VcenterImageCatalog)) {
        return $false;
    } else {
        return $VcenterImageCatalog
    }

}


Function Get-VcenterImages {

     <#
        .SYNOPSIS
        The function Get-VcenterImages shows vLCM Images in connected vCenter(s).

        .DESCRIPTION
        This function displays what vCenter clusters contain vLCM images and can be imported
        into SDDC Manager.

        .EXAMPLE
        Get-VcenterImages -JsonOutputFile imageList.json

        .PARAMETER JsonOutputFile
        Specifies what file to save JSON output to.
    #>

    Param (
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$JsonOutputFile
    )

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    # Check if connected to vCenter(s).
    Test-VcentersConnection

    # Prepare list of vCenter clusters with vLCM Image Management
    $ImageManagedClusterDetails = @()
    $ImageManagedClusters = 0

    Write-LogMessage -Type INFO -PrependNewLine -AppendNewLine -Message "Scanning vCenter(s) for vLCM images..."

    # iterate through each connected vCenter
    foreach ($VcenterName in ($Global:DefaultViServers.Name | Sort-Object)) {

        # Verify if ImageCatalog support can be queried.  The very capability check is a SDDCm 9.0+ capability.
        $SddcManagerVersion = Get-SddcManagerVersion
        if ( ([Version]$SddcManagerVersion) -ge ([Version]$MinimumImageCatalogSupportRelease) ) {
            # Check if image catalog is supported
            $VcenterImageCatalogSupport = Test-VcenterImageCatalogSupport -VcenterName $VcenterName
        }

        if ($VcenterImageCatalogSupport) {
            $VcenterImageCatalog = Get-VcenterImageCatalog -VcenterName $VcenterName
            $VcenterImageCatalogNames = $VcenterImageCatalog.Name
            foreach ($VcenterImageName in $VcenterImageCatalogNames | Sort-Object) {
                $ImageManagedClusterDetails += [pscustomobject]@{
                    'VcenterImageName' = $VcenterImageName
                    'VcenterName' = $VcenterName
                }
            $ImageManagedClusters++
            }
        } else {
            # only add LifecycleManaged clusters for the selected vCenter(s), to the managed clusters object
            foreach ($VcenterImageName in (Get-Cluster -Server $VcenterName -ErrorAction SilentlyContinue | Where-Object {$_.ExtensionData.LifecycleManaged}).Name | Sort-Object) {
                    $ImageManagedClusterDetails += [pscustomobject]@{
                    'VcenterImageName' = $VcenterImageName
                    'VcenterName' = $VcenterName
                    }
                $ImageManagedClusters++
            }
        }
    }

    if ($ImageManagedClusters -eq 0) {
        if (!$VcenterDetailsError) {
            Write-LogMessage -Type ERROR -Message "No vLCM images detected in the connected vCenter(s)."
        }
        Write-LogMessage -Type INFO -Message "Connect to vCenter to create a new vLCM image."
        Write-LogMessage -Type INFO -Message "https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/managing-host-and-cluster-lifecycle-8-0.html"
        Show-AnyKey
        break
    }

    # Prepare a selection menu of options based on generated IDs.
    $ClusterDisplayObject = @()
    $ClusterIndex = 1

    $ClusterDisplayObject += [pscustomobject]@{
        'Id'               = "Id"
        'VcenterImageName' = "vCenter Image Name"
        'VcenterName'      = "vCenter Name"
    }
       $ClusterDisplayObject += [pscustomobject]@{
           'Id'               = "--"
           'VcenterImageName' = "------------------"
           'VcenterName'      = "------------"
    }
    foreach ($Line in $ImageManagedClusterDetails) {
        $ClusterDisplayObject += [pscustomobject]@{
            'Id'               = $ClusterIndex
            'VcenterImageName' = $Line.VcenterImageName
            'VcenterName'      = $Line.VcenterName
        }

        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "vLCM image `"$($Line.VcenterImageName)`" found in vCenter `"$($Line.VcenterName)`""
        $ClusterIndex++
    }

    if ($Headless -eq "disabled") {
        Write-Host ""
        return $ClusterDisplayObject
    }

    if ($Global:LogOnly -eq "disabled") {
        Write-LogMessage -Type INFO -AppendNewLine -Message "vLCM images in attached vCenter(s):"
        $ClusterDisplayObject | Format-Table -Property @{Expression = " " }, VcenterImageName, VcenterName -Autosize -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }
    }

    if ($JsonOutputFile) {
        # The first two rows of the array contain header information.
        $Id = 0
        $JsonHashTable = foreach($ClusterMember in $ClusterDisplayObject) {
        if ($Id -ge 2) {
                @{
                    VcenterImageName = $ClusterMember.VcenterImageName
                    VcenterName = $ClusterMember.VcenterName
                }
                }
            $Id++
        }
        $JsonOutput = $JsonHashTable | ConvertTo-Json
        Set-Content -path $JsonOutputFile $JsonOutput
    }
}

Function Import-ImageFromVcenter {

    Param (
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$JsonInputFile,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$Parallel,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$Silence,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$VcenterImageName,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$VcenterName
    )

    <#
        .SYNOPSIS
        The function Import-ImageFromVcenter pulls a vLCM image from vCenter into SDDC Manager

        .DESCRIPTION
        This function calls Get-VcenterImages to get a list of clusters, in the connected vCenters,
        with the property extensionData.LifecycleManaged. It then provides three ways of allowing the user
        to decide which cluster(s) should be imported into SDDC Manager: on-screen-display (interactive),
        parameter-based (headless), and json input (headless)

        .EXAMPLE
        Import-ImageFromVcenter -VcenterImageName m01-cl01 -VcenterName m01-vc01.example.com

        .EXAMPLE
        Import-ImageFromVcenter -JsonInputFile ImagesToImport.json

        .EXAMPLE
        Import-ImageFromVcenter -JsonInputFile ImagesToImport.json -Parallel

        .PARAMETER Parameter
        Specifies if the image import should be parallelized.  If not specified, defaults to serial.

        .PARAMETER JsonInputFile
        Specifies the json input file that contains at least one set of vCenter names and images.

        .PARAMETER Silence
        Specifies if output should be displayed.

        .PARAMETER VcenterImageName
        Specifies the source cluster for the vLCM Image.

        .PARAMETER VcenterInputName
        Specifies the source vCenter for the vLCM Image.

    #>

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection
    # Check if connected to vCenter(s).
    Test-VcentersConnection

    # In interactive mode, a user's ClusterName and vCenter are provided by selecting an Id from a menu
    if ($Headless -eq "disabled") {
        $ClusterDisplayObject  = Get-VcenterImages
        $ClusterDisplayObject | Format-Table -Property @{Expression = " " }, Id, VcenterImageName, VcenterName -Autosize -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }
        Write-Output ""
        Do {
            # set (or reset in the event of invalid ID hit) an array of images to import into SDDC manager.
            $ImagesToImportIntoSddcManager =@()
            $VersionSelection = Read-Host "Enter an id or comma-delimited list of ids of image(s) to import into SDDC Manager or press 'c' to cancel"
            if ($VersionSelection -eq "c") {
                return
            }
            foreach ($SelectedImageId in $VersionSelection.Split(",")) {

                $IsValidId = ($SelectedImageId -in @($ClusterDisplayObject.Id))
                # return from loop if invalid ID is entered.
                if (! $IsValidId) {
                    if ($SelectedImageId -eq "") {
                        $SelectedImageId = "<EMPTY>"
                    }
                    Write-LogMessage -Type ERROR -Message "Invalid selection: $SelectedImageId identifier not found."
                    return
                }
                $ImagesToImportIntoSddcManager += [pscustomobject]@{
                    VcenterName = (($ClusterDisplayObject | Where-Object {$_.Id -eq $SelectedImageId}).VcenterName)
                    VcenterImageName = (($ClusterDisplayObject | Where-Object {$_.Id -eq $SelectedImageId}).VcenterImageName)
                }

            }
        } While (! $IsValidId)
    }

    if ($Headless -eq "enabled") {
        if ($JsonInputFile) {
            try {
                $ImagesToImportIntoSddcManager = (Get-Content $JsonInputFile) | Select-String -Pattern "^\s*$" -NotMatch | ConvertFrom-Json
            }
            catch {
                if ($Error[0] -match "Conversion from JSON failed with error") {
                    Write-LogMessage -Type ERROR -Message "JSON Validation error in $JsonInputFile"
                    Write-LogMessage -Type ERROR -Message "$($Error[0])"
                    exit
                }
            }

        } else {
            # turn the commandline parameter data into an array so the user-inputted data, either
            # in parameter form or json, can be validated in the same way
            $ImagesToImportIntoSddcManager = [pscustomobject]@{
                VcenterName = $VcenterName
                VcenterImageName = $VcenterImageName
            }
        }

        foreach ($Line in $ImagesToImportIntoSddcManager) {
            # use the previously defined ClusterDisplayObject for vC to cluster mappings
            if (! $($Line.VcenterName) -or ! $($Line.VcenterImageName) ) {
                Write-LogMessage -Type ERROR -Message "$JsonInputFile missing VcenterImageName and/or VcenterName"
                Write-LogMessage -Type ERROR -Message  "Please review this line: $Line"
                exit
            }

            # check if vCenter is valid
            $IsConnectedVcenter =  ($Global:DefaultViServers | Where-Object IsConnected -eq $True) | Where-Object Name -eq $($Line.VcenterName)

            if ([String]::IsNullOrEmpty($IsConnectedVcenter)) {
                Write-LogMessage -Type ERROR -Message "vCenter `"$($Line.VcenterName)`" not found in list of connected vCenter(s)."
                exit
            }

            $SddcManagerVersion = Get-SddcManagerVersion

            # Verify if ImageCatalog support can be queried.  The very capability check is a SDDCm 9.0+ capability.
            if ( ([Version]$SddcManagerVersion) -ge ([Version]$MinimumImageCatalogSupportRelease) ) {
                $ImageCatalogSupport = Test-VcenterImageCatalogSupport -VcenterName $($Line.VcenterName)
            }
            # Validating that an image belongs to a specific vCenter is different for the image catalog vs legacy images.
            if ($ImageCatalogSupport) {
                $VcenterImageCatalog = Get-VcenterImageCatalog -VcenterName ($Line.VcenterName)
                $VcenterImageId = ($VcenterImageCatalog | Where-Object {$_.Name -eq $($Line.VcenterImageName)}).RepositoryImageId.VcenterImageId
                if ([String]::IsNullOrEmpty($VcenterImageId)) {
                    Write-LogMessage -Type ERROR -Message "No vLCM image named `"$($Line.VcenterImageName)`" found in vCenter `"$($Line.VcenterName)`" image catalog."
                    exit
                }
            } else {
                # check if this cluster is found in the vCenter we're expecting
                $VcenterClusterMatch = Get-Cluster -Server $($Line.VcenterName) -ErrorAction SilentlyContinue | Where-Object Name -eq $($Line.VcenterImageName)
                if ([String]::IsNullOrEmpty($VcenterClusterMatch)) {
                    Write-LogMessage -Type ERROR -Message "No cluster named `"$($Line.VcenterImageName)`" found in vCenter `"$($Line.VcenterName)`" with vLCM image management."
                    exit
                }
            }
            $Response = (Invoke-VcfGetPersonalities).Elements | Where-Object PersonalityName -eq $($Line.VcenterImageName)
            if ($Response) {
                Write-LogMessage -Type ERROR -Message "An image named `"$($Line.VcenterImageName)`" already exists in SDDC Manager `"$($DefaultSddcManagerConnections.Name)`"."
                Write-LogMessage -Type INFO -Message "Please rename the source image in vCenter or delete the conflicting image from SDDC manager before retrying."
                return
            }
        }
    }
    # line break on screen
    if ($Headless -eq "disabled") {
        Write-Host ""
    }
    foreach ($Line in $ImagesToImportIntoSddcManager) {

        # Lookup the VCF vCenter Id by iterating through all WLD vCenter IDs registered to SDDC Manager.
        $VcenterId = ((Invoke-VcfGetVcenters).Elements | Where-Object { $_.Fqdn -eq $($Line.VcenterName)}).Id

        if (!$VcenterId ) {
            Write-LogMessage -Type ERROR -Message "Could not locate vCenter `"$($Line.VcenterName)`" in SDDC Manager `"$($DefaultSddcManagerConnections.Name)`"."
            Show-AnyKey
            break
        }

        $SddcManagerVersion = Get-SddcManagerVersion

        # Verify if ImageCatalog support can be queried.  The very capability check is a SDDCm 9.0+ capability.
        if ( ([Version]$SddcManagerVersion) -ge ([Version]$MinimumImageCatalogSupportRelease) ) {
            # Check for vCenter Image catalog Support
            $ImageCatalogSupport = Test-VcenterImageCatalogSupport -VcenterName $($Line.VcenterName)
        }

        if ($ImageCatalogSupport) {
            $VcenterImageCatalog = Get-VcenterImageCatalog -VcenterName $($Line.VcenterName)
            $VcenterImageId = ($VcenterImageCatalog | Where-Object {$_.Name -eq $($Line.VcenterImageName)}).RepositoryImageId.VcenterImageId
            if ([String]::IsNullOrEmpty($VcenterImageId)) {
                Write-LogMessage -Type ERROR -Message "Could not identify vCenter image catalog name `"$($Line.VcenterImageName)`" in vCenter `"$($Line.VcenterName)`"."
                Show-AnyKey
                break
            } else {
                $PersonalityUploadSpecReferred = Initialize-VcfPersonalityUploadSpecReferred -VcenterId $VcenterId -VcenterImageId $VcenterImageId
            }
        } else {
            # The vCenter cluster exists outside of SDDC manager and thus must be referenced by MorId.
            $ClusterMorId = (Get-Cluster -Server $($Line.VcenterName) -ErrorAction SilentlyContinue | Where-Object -Property Name -eq $($Line.VcenterImageName)).ExtensionData.MoRef.Value
            if ([String]::IsNullOrEmpty($ClusterMorId)) {
                Write-LogMessage -Type ERROR -Message "Could not identify cluster `"$($Line.VcenterImageName)`" in vCenter `"$($Line.VcenterName)`"."
                Show-AnyKey
                break
            } else {
                $PersonalityUploadSpecReferred = Initialize-VcfPersonalityUploadSpecReferred -ClusterMorId $ClusterMorId -VcenterId $VcenterId
            }
        }

        # Image name in vCenter will match image name in SDDC Manager
        $PersonalityUploadSpec = Initialize-VcfPersonalityUploadSpec -Name $($Line.VcenterImageName) -UploadMode "REFERRED" -UploadSpecReferredMode $PersonalityUploadSpecReferred
""
        try {
            $Response = Invoke-VcfUploadPersonality -PersonalityUploadSpec $PersonalityUploadSpec
        }
        catch {
            # Display friendly Messages to the end user for common errors
            if ($Error[0] -match "PERSONALITY_ALREADY_EXISTS") {
                Write-LogMessage -Type ERROR -AppendNewLine -Message "An image named `"$($Line.VcenterImageName)`" already exists in the SDDC Manager `"$($DefaultSddcManagerConnections.Name)`"."
                Write-LogMessage -Type INFO -Message "Please rename the source image in vCenter or delete the conflicting image from SDDC manager before retrying."
            } elseif ($Error[0] -match "PERSONALITY_UPLOAD_SPEC_INVALID_DATA") {
                Write-LogMessage -Type ERROR -AppendNewLine -Message "An image named `"$($Line.VcenterImageName)`" has an invalid spec.  Please contact support and provide this error message: $($Error[0])"
            } else {
                Write-LogMessage -Type ERROR -Message "Image import of `"$($Line.VcenterImageName)`" failed with error message `"$($Error[0])`"."
            }
        }
        if (! $Response) {
            return
        }
        Write-LogMessage -Type INFO -Message "Beginning import of vCenter vLCM image `"$($Line.VcenterImageName)`" into SDDC Manager `"$($DefaultSddcManagerConnections.Name)`"..."

        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "(Debugging information) Task Id is `"$($Response.Id)`" for the import job of image name `"$($Line.VcenterImageName)`" from vCenter `"$($Line.VcenterName)`""

        # Parallel tasks do not wait for the image to complete before moving onto the next one.
        # When the silence flag is invoked, in progress indicator is shown either.
        if (! ($Parallel) -and ! ($Silence)) {
            $ProcessTimer = [System.Diagnostics.Stopwatch]::StartNew()
            Do {
                $TaskId = $Response.Id
                $TaskStatus = (Invoke-VcfGetTask -Id $TaskId).Status
                Write-Progress -Activity "Image import in progress" -Status "$([math]::Round(($ProcessTimer.Elapsed.TotalSeconds),0)) seconds elapsed (updates every 5 seconds)."
                Start-Sleep -Seconds 5
            } While ($TaskStatus -eq 'IN_PROGRESS')

            Write-Progress -Completed
            $ProcessTimer.Stop()
            Write-Output ""

            Write-LogMessage -type INFO -SuppressOutputToScreen -Message "Image import of `"$($Line.VcenterImageName)`" took $([math]::Round(($ProcessTimer.Elapsed.TotalMinutes),2)) minutes to complete."
            if ($TaskStatus -eq "SUCCESSFUL") {
                Write-LogMessage -Type INFO -Message "Successfully created SDDC Manager image `"$($Line.VcenterImageName)`" into SDDC Manager `"$($DefaultSddcManagerConnections.Name)`""
                if (! $ImageCatalogSupport) {
                    # With the image successfully imported, the temporary cluster can be deleted.
                    Remove-TemporaryCluster -TemporaryClusterName $($Line.VcenterImageName) -TemporaryClusterVcenter $($Line.VcenterName)
                }
            } elseif ($TaskStatus -eq "FAILED") {
                $ErrorCode = (Invoke-VcfGetTask -Id $TaskId).Errors.ErrorCode
                if ($ErrorCode -match "PERSONALITY_WITH_SAME_SPEC_EXISTS") {
                    Write-LogMessage -Type ERROR -AppendNewLine -Message "Image import of `"$($Line.VcenterImageName)`" failed.  Another another image with the same manifest exists in `"$($DefaultSddcManagerConnections.Name)`"."
                } else {
                    $TaskErrorsCode = (Invoke-VcfGetTask -Id $TaskId).Errors.ErrorCode
                    $TaskErrorsMessage = (Invoke-VcfGetTask -Id $TaskId).Errors.Message
                    Write-LogMessage -Type ERROR -Message "Failed to import image `"$($Line.VcenterImageName)`" through task Id `"$TaskId`". ErrorCode: $TaskErrorsCode. ErrorMessage: $TaskErrorsMessage"
                }

            } else {
                Write-LogMessage -Type ERROR -Message $Response
                Write-LogMessage -Type ERROR -Message "Failed to import image task Id `"$TaskId`"."
            }
        }
    }
}



Function Show-ImageComplianceCheckResults {

    Param (
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$ClusterName,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$ShowExtendedResults,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$ShowAllClusters,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$WorkloadDomainName
    )

    <#
        .SYNOPSIS
        The function Show-ImageComplianceCheckResults displays a cluster's compliance status against a vLCM image.

        .DESCRIPTION
        This function is called by Invoke-ImageComplianceCheck and headless parameters. After the results have been stored
        in the database, this function displays the summarized results (and the full results in JSON in a file on the user's
        system) of the full check results.

        .EXAMPLE
        Show-ImageComplianceCheckResults -ClusterName m01-cl01 -WorkloadDomainName m01

        .EXAMPLE
        Show-ImageComplianceCheckResults -ClusterName m01-cl01 -WorkloadDomainName m01 -ShowExtendedResults

        .EXAMPLE
        Show-ImageComplianceCheckResults -ShowAllClusters

        .EXAMPLE
        Show-ImageComplianceCheckResults -ShowAllClusters -ShowExtendedResults

        .PARAMETER ClusterName
        Specifies the cluster name for baseline managed cluster

        .PARAMETER ShowExtendedResults
        Specifies if the full (rather than summarized) cluster compatibility results should be displayed on screen.

        .PARAMETER WorkloadDomainName
        Specifies the workload domain name containing baseline managed cluster.
    #>

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    if (! $ShowAllClusters) {

        # Derive a workload domain Id from the workload domain name.
        $WorkloadDomainId = ((Invoke-VcfGetDomains).Elements | Where-Object Name -eq $WorkloadDomainName).Id

        if (! $WorkloadDomainId) {
            Write-LogMessage -Type ERROR -Message "Workload Domain name `"$WorkloadDomainName`" not found."
            exit
        }

        # Derive a cluster Id from the cluster name (in a given workload domain).
        $ClusterId = ((Invoke-VcfGetClusters).Elements | Where-Object { $_.Domain.Id -eq $WorkloadDomainId -and $_.Name -eq $ClusterName}).Id

        # If the cluster Id is null, either the cluster name is invalid (doesn't exist in this WLD)
        if (! $ClusterId) {
            Write-LogMessage -Type ERROR -Message "Cluster name `"$ClusterName`" is invalid or not a member of workload domain `"$WorkloadDomainName`"."
            exit
        }

        $BaselineManagerClusters = [pscustomobject]@{
            WorkloadDomainId = $WorkloadDomainId
            WorkloadDomainName = $WorkloadDomainName
            ClusterId = $ClusterId
            ClusterName = $ClusterName
        }
    } else {
        $Response = (Invoke-VcfGetClusters -IsImageBased $False).Elements
        $BaselineManagerClusters =  @()
        Foreach ($BaselineManagerCluster in $Response) {

            $WorkloadDomainId = $($BaselineManagerCluster.Domain.Id)
            $WorkloadDomainName = (Invoke-VcfGetDomain -id $WorkloadDomainId).Name
            $ClusterId = ((Invoke-VcfGetClusters).Elements | Where-Object { $_.Domain.Id -eq $WorkloadDomainId -and $_.Name -eq $($BaselineManagerCluster.Name)}).Id
            $ClusterName = ((Invoke-VcfGetClusters).Elements | Where-Object { $_.Domain.Id -eq $WorkloadDomainId -and $_.Id -eq $ClusterId}).Name

            $BaselineManagerClusters += [pscustomobject]@{
                WorkloadDomainId = $WorkloadDomainId
                WorkloadDomainName = $WorkloadDomainName
                ClusterId = $ClusterId
                ClusterName = $ClusterName
            }
        }
    }

    Foreach ($Cluster in $BaselineManagerClusters) {

        try {
            $Response = Invoke-VcfGetClusterImageCompliance -Id $($Cluster.ClusterId)
        } catch {
            $ErrorMsg = $($Error[0].Exception.Message)
        }

        if ([String]::IsNullOrEmpty($Response)) {
            Write-LogMessage -Type ERROR -Message "Could not locate image compliance check results for cluster `"$($Cluster.ClusterName)`" in workload domain `"$($Cluster.WorkloadDomainName)`""
            Write-LogMessage -Type ERROR -Message "Error: $ErrorMsg"
            Show-AnyKey
            return
        }

        $SddcManagerImageName = $Response.ClusterImage.Name

        $JsonResponse = $Response | ConvertTo-Json

        Write-LogMessage -Type INFO -AppendNewLine -PrependNewLine -Message "Cluster `"$($Cluster.ClusterName)`" in Workload Domain `"$($Cluster.WorkloadDomainName)`" has status `"$($Response.Status)`"."

        if ($($Response.status) -eq "COMPLIANT") {
            Write-LogMessage -Type INFO -Message "No remediation or further action is required."
        } elseif ($($Response.status) -eq "NON_COMPLIANT") {
            Write-LogMessage -Type WARNING -AppendNewLine -Message "Remediation is required."
        } elseif ($($Response.status) -eq "INCOMPATIBLE") {
            Write-LogMessage -Type ERROR -AppendNewLine -Message "Remediation cannot proceed, this image is incompatible with the current state of cluster `"$($Cluster.ClusterName)`"."
            Write-LogMessage -Type ERROR -AppendNewLine -Message "Please review INCOMPATIBLE findings, resolve the findings through a new or modified image, and re-try the compliance check."
        } elseif ($($Response.status) -eq "UNKNOWN") {
            Write-LogMessage -Type ERROR -AppendNewLine -Message "Compatibility could not be determined.  Please ensure all the hosts in cluster `"$($Cluster.ClusterName)`" are available then re-run the check."
        } else { # A fifth state is not expected.
            Write-LogMessage -Type ERROR -AppendNewLine -Message "$_"
        }

        if ($($Response.status) -ne "COMPLIANT") {

            Write-LogMessage -Type INFO -AppendNewLine -Message "Summary of compatibility check cluster `"$($Cluster.ClusterName)`" in Workload Domain `"$($Cluster.WorkloadDomainName)`" against image `"$SddcManagerImageName`""

            # Define rather than derive the severities so that they can be ordered appropriately.
            $ClusterFindingSeverities = "ERROR", "WARNING", "INFO"

            # Find the highest severity impact then exit
            foreach ($Impact in $OrderedImpacts) {
                $ClusterImpact = (($Response.ImageComplianceDetails) | Where-Object { $_.Severity -eq "Impact"}).Impact | Select-Object -Unique
                if ($ClusterImpact) {
                    return
                }
            }

            $ComplianceFindingsDisplayObject = @()

            $ComplianceFindingsDisplayObject += [pscustomobject]@{
                'ComponentName'   = "Component Name"
                'ComponentVendor' = "Component Vendor"
                'CvChange'        = "Version Change"
                'Message'         = "Message"
                'Impact'          = "Impact"
                'Severity'        = "Severity"
            }

            $ComplianceFindingsDisplayObject += [pscustomobject]@{
                'ComponentName'   = "--------------"
                'ComponentVendor' = "----------------"
                'CvChange'        = "--------------"
                'Message'         = "--------"
                'Impact'          = "------"
                'Severity'        = "--------"
            }

            # Create a horizontal line separator to make it easier to view each result.
            # It starts two character in to match the non-separator lines.
            $Separator =  $("-" * ($($Host.UI.RawUI.WindowSize.Width) -2))

            foreach ($Severity in $ClusterFindingSeverities) {
                # Determine all the unique findings for the severity in question
                $UniqueFindingsPerSeverity = $Response.ImageComplianceDetails | Where-Object { $_.Severity -eq $Severity } | `
                    Select-Object ComponentName,ComponentType,ComponentCurrentVersion,ComponentTargetVersion,ComponentVendor,Message,Impact |`
                    Sort-Object -Property Message | Get-Unique -AsString

                foreach ($UniqueFinding in $UniqueFindingsPerSeverity ) {

                    # If there current and target version are the same (even if null), treat as non-change
                    if ($($UniqueFinding.ComponentCurrentVersion) -eq $($UniqueFinding.ComponentTargetVersion)) {
                        $CvChange = "No"
                    } else {
                        $CvChange = "Yes"
                    }

                    if ([String]::IsNullOrEmpty($UniqueFinding.Message)) {
                        $Message = "None"
                    } else {
                        $Message = $UniqueFinding.Message
                    }

                    if ([String]::IsNullOrEmpty($UniqueFinding.Impact)) {
                        $Impact = "N/A"
                    } else {
                        $Impact = $UniqueFinding.Impact
                    }

                    if ([String]::IsNullOrEmpty($UniqueFinding.ComponentName)) {
                        $ComponentName = "N/A"
                    } else {
                        $ComponentName = $UniqueFinding.ComponentName
                    }

                    if ([String]::IsNullOrEmpty($UniqueFinding.ComponentVendor)) {
                        $ComponentVendor = "N/A"
                    } else {
                        $ComponentVendor = $UniqueFinding.ComponentVendor
                    }
                    $ComplianceFindingsDisplayObject += [pscustomobject]@{
                        'ComponentName'    = $ComponentName
                        'ComponentVendor'  = $ComponentVendor
                        'CvChange'         = $CvChange
                        'Message'          = $Message
                        'Impact'           = $Impact
                        'Severity'         = $Severity
                    }
                    $ComplianceFindingsDisplayObject += "  $Separator"
                }
            }

            $ComplianceFindingsDisplayObject | Format-Table -Wrap -Property @{Expression = " " }, ComponentName, ComponentVendor, CvChange, Impact, Severity, Message -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }

            # Display detailed for critical issues (defined as incompatible)
            $IncompatibleResults = $Response.ImageComplianceDetails  | Where-Object { $_.ComplianceStatus -eq "INCOMPATIBLE" }
            if  ($IncompatibleResults) {
                Write-LogMessage -Type INFO -PrependNewLine -Message "Please carefully review the following INCOMPATIBLE findings:"
                $UniqueIncompatibleMessages = $($IncompatibleResults | Select-Object -Unique Message).Message
                foreach ($UniqueIncompatibleMessage in $UniqueIncompatibleMessages) {
                    $Entities = ($IncompatibleResults | Where-Object { $_.Message -eq $UniqueIncompatibleMessage }).EntityName
                    $ComponentType = ($IncompatibleResults | Where-Object { $_.Message -eq $UniqueIncompatibleMessage }).ComponentType | Get-Unique
                    Write-LogMessage -Type ADVISORY -PrependNewLine -Message "ESX hosts: $([String]$Entities -replace(" ",", ")) report the following Message in component `"$ComponentType`" : `n`n`"$UniqueIncompatibleMessage`""
                }
            }

            $JsonLogFile = Join-Path -Path $LogFolder -ChildPath "cluster-compatibility-for-$($Cluster.ClusterName)-on-$($Cluster.WorkloadDomainName)-with-$SddcManagerImageName.json"

            # Write the json Response to a discrete file for ease of parsing.
            Add-Content -path $JsonLogFile $JsonResponse

            # Also write the content to log file for troubleshooting with support.
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "=== START Compliance results for $($Cluster.ClusterName) using $SddcManagerImageName ==="
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message $JsonResponse
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "=== END Compliance results for $($Cluster.ClusterName) using $SddcManagerImageName ==="

            # Inform the user where to find the full the compliance findings.
            Write-LogMessage -Type INFO -PrependNewLine -Message "Full compliance findings stored for cluster `"$($Cluster.ClusterName)`" in Workload Domain `"$($Cluster.WorkloadDomainName)`" have been saved to $JsonLogFile "

            if ($ShowExtendedResults) {
                Write-Host "`nDisplaying Full Results:" -ForegroundColor Cyan
                Write-Output $JsonResponse | more
            }
        }
    }
}

Function Get-SddcManagerImages {

        <#
            .SYNOPSIS
            The function Get-SddcManagerImages displays and enables selection of vLCM images in SDDC Manager.

            .DESCRIPTION
            In interactive mode, this function displays the vLCM images in SDDC Manager and allows a user to select one as a target for a cluster compatibility scan.
            In headless mode, the function just displays results, and thus no Id field is required. Optionally, the results in headless mode, scan be saved to a
            json file.

            .EXAMPLE
            Get-SddcManagerImages -ShowId

            .EXAMPLE
            Get-SddcManagerImages -IdSelection 1

            .PARAMETER IdSelection
            Specifies which image, from an on-screen display, the user has selected.

            .PARAMETER ShowId
            Specifies that the list of vLCM Images in SDDC Manager should be displayed with an Id selection field (applicable to interactive mode).
        #>

    Param (
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$IdSelection,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$ShowAll,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$ShowId
    )

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    # show images (personalities) already present in SDDC Manager
    $Response = (Invoke-VcfGetPersonalities).Elements

    if ([String]::IsNullOrEmpty($Response)) {
        Write-LogMessage -Type ERROR -Message "No vLCM images found in SDDC Manager `"$($DefaultSddcManagerConnections.Name)`"."
        Show-AnyKey
        if ($Headless -eq "disabled") {
            Show-MainMenu
        }
    } else {
        $ImageNameIndex = 1
        $ImageNameDisplayObject = @()

        $ImageNameDisplayObject += [pscustomobject]@{
            'Id'                   = 'Id'
            'SddcManagerImageName' = "SDDC Manager Image Name"
            'ImageId'              = "Image Id"
            'BaseImageVersion'     = "Base Image"
            'ImageComponents'      = "Components"
            'ImageAddOns'          = "Addons"
            'ImageHardwareSupport' = "Hardware Support"
        }

        $ImageNameDisplayObject += [pscustomobject]@{
            'Id'                   = "--"
            'SddcManagerImageName' = "-----------------------"
            'ImageId'              = "----------"
            'BaseImageVersion'     = "----------"
            'ImageComponents'      = "----------"
            'ImageAddOns'          = "-------"
            'ImageHardwareSupport' = "----------------"
        }

        foreach ($Line in $Response) {

            # The full spec for each image may be sourced from vCenter through SDDC Manager
            if ($Env:SkipCertificateCheck) {
                $vCenterJsonOutput = (Invoke-WebRequest -SkipCertificateCheck $($Line.VsphereExportedJsonPath)).Content
            } else {
                try {
                    $vCenterJsonOutput = (Invoke-WebRequest $($Line.VsphereExportedJsonPath)).Content
                } catch {
                    if (($error[0].Exception.Message) -eq "The SSL connection could not be established, see inner exception.") {
                        Write-LogMessage -Type ERROR "SSL Connect trust issue with SDDC Manager. If this is expected please run `$Env:SkipCertificateCheck=`"enabled`" and re-run the script."
                        exit
                    }
                }

            }
            $JsonLogFile = Join-Path -Path $LogFolder -ChildPath "$($Line.PersonalityName).json"
            Set-Content -Path $JsonLogFile $vCenterJsonOutput

            # Write the json Response to a discrete file for ease of parsing.
            Set-Content -Path $($($Line.PersonalityName)+".json") $vCenterJsonOutput
            $ImageAddOnData = $Line.SoftwareInfo.AddOn
            if ([String]::IsNullOrEmpty($ImageAddOnData)) {
                $ImageAddOns = "N/A"
            } else {
                $ImageAddOns = @()
                foreach ($ImageAddOnItem in $ImageAddOnData) {
                    $ImageAddOns += "$($ImageAddOnItem.DisplayName): $($ImageAddOnItem.DisplayVersion)"
                }
            }

            $ImageComponentData = $Line.SoftwareInfo.Components.Values
            if ([String]::IsNullOrEmpty($ImageComponentData)) {
                $ImageComponents = "N/A"
            } else {
                $ImageComponents = @()
                foreach ($ImageComponent in $ImageComponentData) {
                    $ImageComponents += "$($ImageComponent.Details.DisplayName): $($ImageComponent.Details.DisplayVersion)"
                }
            }

            $ImageHardwareSupportData = $Line.SoftwareInfo.HardwareSupport.Packages.Values
            if ([String]::IsNullOrEmpty($ImageHardwareSupportData)) {
                $ImageHardwareSupport = "N/A"
            }
            else {
                $ImageHardwareSupport = @()
                foreach ($ImageHardwareSupportItem in $ImageHardwareSupportData) {
                    $ImageHardwareSupport += "$($ImageHardwareSupportItem.Pkg): $($ImageHardwareSupportItem._Version)"
                }
            }

            $ImageNameDisplayObject += [pscustomobject]@{
                'Id'                   = $ImageNameIndex
                'SddcManagerImageName' = $Line.PersonalityName
                'ImageId'              = $Line.PersonalityId
                'BaseImageVersion'     = $Line.SoftwareInfo.BaseImage.Version
                'ImageComponents'      = $ImageComponents
                'ImageAddOns'          = $ImageAddOns
                'ImageHardwareSupport' = $ImageHardwareSupport
            }
        $ImageNameIndex++
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "SDDC Manager Image Name `"$($Line.PersonalityName)`" with Image Id `"$($Line.PersonalityId)`" containing base image `"$($Line.SoftwareInfo.BaseImage.Version)`", components `"$ImageComponents`", Addons `"$ImageAddOns`", HSM `"$ImageHardwareSupport`" found in `"$($DefaultSddcManagerConnections.Name)`"."
        }

        if ((($Global:LogOnly -eq "disabled") -and ($Headless -eq "enabled")) -or ($ShowAll)){
            Write-LogMessage -Type INFO -PrependNewLine -AppendNewLine -Message "vLCM images available in SDDC Manager `"$($DefaultSddcManagerConnections.Name)`":"
            $ImageNameDisplayObject | Format-Table -Property @{Expression = {$_.SddcManagerImageName}; n='Prop'; width = 25 }, BaseImageVersion, ImageComponents, ImageAddOns, ImageHardwareSupport -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }
            Write-Host ""
        }
        if ($Headless -eq "disabled") {
            if ($IdSelection) {
                $SelectedImageName = ($ImageNameDisplayObject | Where-Object {$_.Id -eq $IdSelection}).SddcManagerImageName
                if (! $SelectedImageName) {
                    return "ERROR_INVALID_SELECTION"
                } else {
                    return $SelectedImageName
                }
            } elseif ($ShowId) {
                Write-LogMessage -Type INFO -AppendNewLine -Message "vLCM images available in SDDC Manager `"$($DefaultSddcManagerConnections.Name)`":"
                $ImageNameDisplayObject | Format-Table -Property @{Expression = {$_.Id}; n='Prop'; width = 5 }, SddcManagerImageName, BaseImageVersion, ImageComponents, ImageAddOns, ImageHardwareSupport -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }
            }
        }
    }
}

Function Invoke-ImageComplianceCheck {

        <#
            .SYNOPSIS
            The function Invoke-ImageComplianceCheck starts a compliance check of a cluster against a specific vLCM image.

            .DESCRIPTION
            The function ensure that the compliance check runs to completion before calling Show-ImageComplianceCheckResults to display
            the results to the user.

            .EXAMPLE
            Invoke-ImageComplianceCheck -ClusterName cl01 -WorkloadDomainName m01 -SddcManagerImageName esx-803-vendor

            .EXAMPLE
            Invoke-ImageComplianceCheck -JsonInputFile Clusters.json

            .EXAMPLE
            Invoke-ImageComplianceCheck -JsonInputFile Clusters.json -Parallel

            .PARAMETER ClusterName
            Specifies cluster to run a compatibility check against.

            .PARAMETER JsonInputFile
            Specifies the json input file that contains at least one set of cluster names, workload domains, and an image.
            JsonInputFile and ClusterName/WorkloadDomainName/SddcManagerImageName are mutually exclusive.

            .PARAMETER Parameter
            Specifies if the compliance checks should be parallelized.  If not specified, defaults to serial.

            .PARAMETER SddcManagerImageName
            Specifies which image the cluster should be checked against.

            .PARAMETER WorkloadDomainName
            Specifies which workload domain the cluster belongs to.
        #>

    Param (
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$ClusterName,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$SddcManagerImageName,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$JsonInputFile,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$Parallel,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$WorkloadDomainName
    )

    # Check if connected to SDDC Manager
    Test-SddcManagerConnection

    # For interactive mode, provide a cluster and image selection mechanism via an on-screen display.
    if ($Headless -eq "disabled") {
        Write-LogMessage -Type INFO -AppendNewLine -Message "Preparing for cluster compliance check..."
        Get-BaselineManagedClusters -ClusterSelection Multiple

        Do {
            Write-Output ""
            $IdSelection = Read-Host "Enter an id, a comma-delimited list of ids, or 'c' to cancel"
            # fail fast in canceled
            if ($IdSelection -eq 'c') {
                Write-LogMessage -Type INFO -PrependNewLine -Message "Cancellation requested. Returning to main menu."
                Show-AnyKey
                Show-MainMenu
            }
            # Check if the Id selection is non-null.
            if ($IdSelection) {
                $SelectedClusterDetails = Get-BaselineManagedClusters -ClusterSelection Multiple -IdSelection $IdSelection
            }
            # If ClusterName is null then no Id / ClusterName mapping was found.
            if (! $($SelectedClusterDetails.ClusterId)) {
                if ($IdSelection -eq "") {
                    $IdSelection = "<EMPTY>"
                }
                Write-LogMessage -Type ERROR -Message "Invalid id $IdSelection chosen. Please try again."
            }
        } while (! $($SelectedClusterDetails.ClusterId))

        Write-Output ""
        Get-SddcManagerImages -ShowId

        Do {
            Write-Output ""
            $IdSelection = Read-Host "Please enter the id of an image or press 'c' to cancel"

            # fail fast in canceled
            if ($IdSelection -eq 'c') {
                Write-LogMessage -Type INFO -PrependNewLine -Message "Cancellation requested. Returning to main menu."
                Show-AnyKey
                Show-MainMenu
            }
            # Check if the Id selection is non-null.
            if ($IdSelection) {
                $SddcManagerImageName = Get-SddcManagerImages -IdSelection $IdSelection
            }
            # If ClusterName is null then no Id / ClusterName mapping was found.
            if ($SddcManagerImageName -eq "ERROR_INVALID_SELECTION") {
                if ($IdSelection -eq "") {
                    $IdSelection = "<EMPTY>"
                }
                Write-LogMessage -Type ERROR -Message "Invalid Id $IdSelection chosen. Please try again."
            }
        } while (($SddcManagerImageName -eq "ERROR_INVALID_SELECTION"))
    } else {
        # In headless mode (non-interactive), first check for JSON input mode, check if the file
        # is properly formatted.
        if ($JsonInputFile) {
            try {
                $ClusterNameInputs = (Get-Content $JsonInputFile) | Out-String | Select-String -Pattern "^\s*$" -NotMatch | ConvertFrom-Json
            }
            catch {
                if ($Error[0] -match "Conversion from JSON failed with error") {
                    Write-LogMessage -Type ERROR -Message "JSON Validation error in $JsonInputFile"
                    Write-LogMessage -Type ERROR -Message "$($Error[0])"
                    exit
                }
            }
        }  else {
            # Turn the commandline parameter data into an array so the user-inputted data, either
            # in parameter form or json, can be validated in the same way.
            $ClusterNameInputs = [pscustomobject]@{
                SddcManagerImageName = $SddcManagerImageName
                WorkloadDomainName = $WorkloadDomainName
                ClusterName = $ClusterName
            }
        }

        # Initiate an array for selected clusters before its populated via for loop.
        $SelectedClusterDetails = @()

        # Validate JSON parameters and commandline parameters.
        foreach ($Line in $ClusterNameInputs) {

            # Verify image name specified.
            if ([String]::IsNullOrEmpty($($Line.SddcManagerImageName))) {
                Write-LogMessage -Type ERROR -Message "No image name specified."
                exit
            }

            # Verify image name exists in SDDC Manager.
            $Response = (Invoke-VcfGetPersonalities).Elements | Where-Object PersonalityName -eq $($Line.SddcManagerImageName)
            if (! $Response) {
                Write-LogMessage -Type ERROR -Message "Image name `"$($Line.SddcManagerImageName)`" not found."
                exit
            }
            # Derive a workload domain Id from the workload domain name.
            $WorkloadDomainId = ((Invoke-VcfGetDomains).Elements | Where-Object Name -eq $($Line.WorkloadDomainName)).Id

            # If the workload Domain Id is null, then the WLD was not found.
            if (! $WorkloadDomainId) {
                Write-LogMessage -Type ERROR -Message "Workload Domain name `"$($Line.WorkloadDomainName)`" not found."
                exit
            }

            # Derive a cluster Id from the cluster name (in a given workload domain).
            $ClusterId = ((Invoke-VcfGetClusters).Elements | Where-Object { $_.Domain.Id -eq $WorkloadDomainId -and $_.Name -eq $($Line.ClusterName) }).Id

            # If the cluster Id is null, either the cluster name is invalid (doesn't exist in this WLD)
            if (! $ClusterId) {
                Write-LogMessage -Type ERROR -Message "Cluster name `"$($Line.ClusterName)`" is invalid or not a member of workload domain `"$($Line.WorkloadDomainName)`"."
                exit
            }

            # Check to see if the cluster is already image managed (and thus not eligible for this workflow).
            $IsImageManaged = (Invoke-VcfGetClusters -IsImageBased $True).Elements | Where-Object Id -eq $ClusterId

            if ($IsImageManaged) {
                Write-LogMessage -Type ERROR -Message "Cluster name `"$($Line.ClusterName)`"  in `"$($Line.WorkloadDomainName)`" is already vLCM Image managed."
                exit
            }

            $SelectedClusterDetails += [pscustomobject]@{
                    'ClusterId'            = $ClusterId
                    'ClusterName'          = $($Line.ClusterName)
                    'WorkloadDomainId'     = $WorkloadDomainId
                    'WorkloadDomainName'   = $($Line.WorkloadDomainName)
                    'SddcManagerImageName' = $($Line.SddcManagerImageName)
            }
        }
    }

    # Begin common processing mode for headless and interactive mode.
    foreach($SelectedCluster in $SelectedClusterDetails) {
        # Refresh the token before each check.
        Test-SddcManagerConnection

        $ClusterId = $SelectedCluster.ClusterId
        $ClusterName = $SelectedCluster.ClusterName
        $WorkloadDomainId = $SelectedCluster.WorkloadDomainId
        $WorkloadDomainName = $SelectedCluster.WorkloadDomainName
        # JSON Payloads may have different images for different clusters.
        if ($Headless -eq "enabled") {
            $SddcManagerImageName = $SelectedCluster.SddcManagerImageName
        }

        # Look for the presence of a particular drift.
        try {
            $ComputeManagerSettingsDrift = (Invoke-VcfGetConfigs -ResourceId $WorkloadDomainId -ErrorAction SilentlyContinue).Elements | Where-Object -Property Name -eq "ComputeManagerSettingsDrift"
        } catch {
            $ErrorMsg = $($Error[0].Exception.Message)
            if ($ErrorMsg -match "FAILED_TO_FETCH_DRIFTS") {
                Write-LogMessage -Type ERROR -Message "Failed to retrieve all applicable drifts. Please verify all SDDC Manager services are healthy."
                Write-LogMessage -SuppressOutputToScreen -Type ERROR -Message $ErrorMsg
            } elseif ($ErrorMsg -match "VLCM_COMPLIANCE_CHECK is not supported in the current system state") {
                $Pattern = 'Message.*\'
                $MessageValue = [regex]::Matches($ErrorMsg, $Pattern).Value
                Write-LogMessage -Type ERROR -Message "At least one cluster in workload domain `"$WorkloadDomainName`" is in a bad state. The workflow cannot proceed."
                Write-LogMessage -Type ERROR -Message "Error is: $MessageValue."
            } else {
                Write-LogMessage -Type ERROR -Message "Error is: $ErrorMsg."
            }
            return
        }

        # If the drift is not found, warn the user as this workflow will apply it.
        if ([String]::IsNullOrEmpty($ComputeManagerSettingsDrift)) {
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "The image compliance check automatically creates a trust relationship between NSX and vSphere Lifecycle Manager."
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Applying drift to Workload Domain `"$WorkloadDomainName`"..."
        } else {
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "ComputeManagerSettingsDrift found on Workload Domain Name `"$WorkloadDomainName`" (Id: $WorkloadDomainId) when scanning `"$ClusterName`" (Id: $ClusterId)."
        }

        $Response = Invoke-VcfGetPersonalities

        # validate cluster heath from SDDC Manager standpoint

        $ClusterStatus = (Invoke-VcfGetCluster -Id $ClusterId).Status

        if ($ClusterStatus -ne "ACTIVE") {
            Write-LogMessage -Type ERROR -Message "Cluster `"$ClusterName`" has status `"$ClusterStatus`" and the workflow cannot proceed."
            return
        } else {
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Cluster `"$ClusterName`" has status active. The workflow can proceed."
        }

        # Utilize the user-provided personality name to generate the PersonalityID required for
        # running a compliance check against a cluster Id
        $ImageId = ($Response.Elements | Where-Object -Property personalityName -eq $SddcManagerImageName).personalityId

        if (! $ImageId ) {
             Write-LogMessage -Type ERROR -Message "$SddcManagerImageName Image not found"
             return
        }

        $ClusterComplianceCheckSpec = Initialize-VcfClusterImageComplianceCheckSpec -ClusterImageId $ImageId
        $ClusterUpdateSpec = Initialize-VcfClusterUpdateSpec -ClusterImageComplianceCheckSpec $ClusterComplianceCheckSpec

        try {
            $Response = Invoke-VcfUpdateCluster -Id $ClusterId -ClusterUpdateSpec $ClusterUpdateSpec -ErrorAction SilentlyContinue
        } catch {
        }

        # Due to pagination, "VMware.Bindings.Vcf.SddcManager.Model.Personality" is issued when no results are found.
        if ( (! $Response) -or ($Response -match "VMware.Bindings.Vcf.SddcManager.Model.Personality") ) {
            Write-LogMessage -Type ERROR -PrependNewLine -AppendNewLine -Message "Check vLCM compliance for cluster `"$ClusterName`" failed."
            if ( $($Error[0]) -match "VLCM_COMPLIANCE_CHECK" ) {
                Write-LogMessage -Type ERROR -AppendNewLine -Message "Cluster `"$ClusterName`" in `"$WorkloadDomainName`" is already being checked for image compliance.  Skipping check."
            } elseif ( $($Error[0]) -match "CLUSTER_IMAGE_VERSION_MISMATCH" ) {
                Write-LogMessage -Type ERROR SuppressOutputToScreen -AppendNewLine -Message $($Error[0].Exception.Message)
                Write-LogMessage -Type INFO -AppendNewLine -Message "The ESX base image chosen does not match the version currently used by your cluster's hosts."
            } else {
                Write-LogMessage -Type ERROR -AppendNewLine -Message "Full error message is: $($Error[0])"
            }
            continue
        }
        if ($Parallel) {
            Write-LogMessage -Type INFO "Beginning compliance check for `"$ClusterName`" in workload domain `"$WorkloadDomainName`" against image `"$SddcManagerImageName`"..."
        } else {
            Write-LogMessage -Type INFO -PrependNewLine -Message "Please wait while cluster `"$ClusterName`" in workload domain `"$WorkloadDomainName`" is checked against image `"$SddcManagerImageName`"..."
        }

        # Provide a task Id in the logs for debugging purposes.
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Cluster `"$ClusterName`" in Workload Domain `"$WorkloadDomainName`" checked against image `"$SddcManagerImageName`" initiated using Task Id `"$($Response.Id)`"."

        $ComplianceChecks = ((Invoke-VcfGetTasks -TaskType VLCM_COMPLIANCE_CHECK).Elements | Where-Object {$_.Status -eq "In Progress" }).Count
        if ($ComplianceChecks) {
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Currently $ComplianceChecks compliance check(s) is/are being processed by SDDC Manager."
        }
        # Parallel flag will disable polling for task to complete
        if (! ($Parallel)) {

            # Time the process to enable the user to estimate the scan time of another similar cluster.
            $ProcessTimer = [System.Diagnostics.Stopwatch]::StartNew()
            Do {
                $PreCheckTime = $([math]::Round(($ProcessTimer.Elapsed.TotalSeconds),0))
                $TaskId = $Response.Id
                $TaskStatus = (Invoke-VcfGetTask -Id $TaskId).Status

                # While each cmdlet should renew the TTL of the bearer token, this long running
                # function needs a safeguard to ensure the overall validity of the bearer token.
                if (($Error[0].Exception.Message -match "TOKEN_NOT_FOUND") -or ($Error[0].Exception.Message -match "JWT expired")) {
                        Connect-SddcManager
                }

                Write-Progress -Activity "Cluster compatibility check in progress" -Status "$([math]::Round(($ProcessTimer.Elapsed.TotalSeconds),0)) seconds elapsed (updates every 5 seconds)."
                Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Cluster compatibility check in progress for cluster `"$ClusterName`" in Workload Domain `"$WorkloadDomainName`" $([math]::Round(($ProcessTimer.Elapsed.TotalSeconds),0)) seconds elapsed"
                Start-Sleep -Seconds 5

                $PostCheckTime = $([math]::Round(($ProcessTimer.Elapsed.TotalSeconds),0))

                if (([int]$PreCheckTime + 300) -lt ([int]$PostCheckTime)) {
                    Write-LogMessage -Type WARNING -SuppressOutputToScreen -Message "More than 300 seconds have elapsed between task progress checks. This is unusual."
                }

            } While ($TaskStatus -eq 'In Progress')

            Write-Progress -Completed
            $ProcessTimer.Stop()

            # Query status one more time to see if the task was successful.
            $Response = (Invoke-VcfGetTask -Id $TaskId)

            # Record the scan time to log.
            Write-LogMessage -type INFO -SuppressOutputToScreen -Message "Cluster `"$ClusterName`" compliance check took $([math]::Round(($ProcessTimer.Elapsed.TotalMinutes),2)) minutes to complete"

            if ($Response.Status -eq "Successful") {
                Write-LogMessage -Type INFO -PrependNewLine -Message "$($Response.Name) completed successfully."
            } elseif ($Response.Status -eq "Failed") {
                Write-LogMessage -Type ERROR -PrependNewLine -Message "$($Response.Name) encountered a failure."
                $FailedSubTasks = $Response.Subtasks | Where-Object Status -eq "FAILED"
                Write-LogMessage -Type ERROR -PrependNewLine -Message "Status $($FailedSubTasks.Status) : $($FailedSubTasks.Name)"
                Write-LogMessage -Type ERROR -PrependNewLine -Message "$($FailedSubTasks.Errors.Message)"
                Write-LogMessage -type ERROR -PrependNewLine -Message "SDDC Manager error code: `"$($FailedSubTasks.Errors.ErrorCode)`", reference code `"$($FailedSubTasks.Errors.ReferenceToken)`" in Task ID `"$($Response.ID)`"."
                break
            } else {
                Write-LogMessage -Type ERROR -PrependNewLine -Message "$($Response.Name) completed with status $($Response.Status)."
                break
            }

            # Display the stored results of the aforementioned compliance check.
            Show-ImageComplianceCheckResults -ClusterName $ClusterName -WorkloadDomainName $WorkloadDomainName
        }
    }
}

Function Invoke-TransitionBaselineManagedCluster {

        <#
            .SYNOPSIS
            The function Invoke-TransitionBaselineManagedCluster applies a vLCM image to all hosts in a vLCM baseline (VUM) managed cluster.

            .DESCRIPTION
            The interface use of this function provides user feedback (on sub-steps completed, time elapsed) as it's a long process. If the
            process fails the user may retry immediately, or later (discovering the task through another function)

            .EXAMPLE
            Invoke-TransitionBaselineManagedCluster -ClusterName m01-cl01 -WorkloadDomainName m01 -ImageName vsphere803

            .EXAMPLE
            Invoke-TransitionBaselineManagedCluster -JsonInput ClustersToTransition.json

            .EXAMPLE
            Invoke-TransitionBaselineManagedCluster -JsonInput ClustersToTransition.json -Parallel

            .PARAMETER ClusterName
            Specifies cluster to convert.

            .PARAMETER FailedTaskId
            Specifies the task Id of a failed transition task.

            .PARAMETER JsonInputFile
            Specifies the json input file that contains at least one set of cluster names and workload domains.

            .PARAMETER Parallel
            Specifies if clusters should be transitioned to vLCM image management in parallel (default is serial).

            .PARAMETER RetryTransition
            Specifies if the transition task should be retried.

            .PARAMETER WorkloadDomainName
            Specifies which workload domain the cluster belongs to.
        #>

    Param (
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$ClusterName,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$FailedTaskId,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$JsonInputFile,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$Parallel,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$RetryTransition,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$WorkloadDomainName
    )

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    # The retry transition workflow resumes an existing task rather than starts a new one.
    if ($RetryTransition) {
        try {
            $Response = Invoke-VcfRetryTask -Id $FailedTaskId
        } catch {
            if ( $($Error[0].Exception.Message) -match "TA_TASK_CAN_NOT_BE_RETRIED" ) {
                Write-LogMessage -Type ERROR -Message "Task cannot be retried."
                Show-AnyKey
                break
            } else {
                Write-LogMessage -Type ERROR -Message "Error is: $($Error[0].Exception.Message)"
            }
        }

        # Begin timing the operation.
        $ProcessTimer = [System.Diagnostics.Stopwatch]::StartNew()

    } else {
        if ($Headless -eq "disabled") {
        # Refresh and display a list of vLCM baseline managed clusters.
        Get-BaselineManagedClusters -ClusterSelection Multiple

        Do {
            Write-Output ""
            Write-LogMessage -Type INFO -AppendNewLine -Message "Select the vLCM baseline clusters to transition to vLCM image management."
            $IdSelection = Read-Host "Enter an id, a comma-delimited list of ids in order, or 'c' to cancel"

            # Fail fast if the user cancels the operation.
            if ($IdSelection -eq 'c') {
                Write-LogMessage -Type INFO -AppendNewLine -Message "Cancellation requested. Returning to main menu."
                Show-AnyKey
                Show-MainMenu
            }
            # Check if the Id selection is non-null.
            if ($IdSelection) {
                $SelectedClusterDetails = Get-BaselineManagedClusters -ClusterSelection Multiple -IdSelection $IdSelection

            }
            # If the SelectedClusterDetails is null then no Id / ClusterName mapping was found.
            if (! $SelectedClusterDetails.ClusterId) {
                if ($IdSelection -eq "") {
                    $IdSelection = "<EMPTY>"
                }
                Write-LogMessage -Type ERROR -Message "Invalid Id `"$IdSelection`" chosen. Please try again."
            }
        } while (! $SelectedClusterDetails.ClusterId)

        Write-Host "`nConfirm you have reviewed the image compliance findings stored in `"$LogFolder`" before proceeding.`n" -ForegroundColor Yellow

        $Decision = New-ChoiceMenu -Question "Would you like to continue?" -DefaultAnswer no

        Write-Output ""
        # Check first if the user answered yes (option 1, the default) they want to proceed.
        if ($Decision -eq 1) {
            Write-LogMessage -Type INFO -Message "Cluster transition to vLCM image management not accepted."
            Show-AnyKey
            break
        } else {
            Write-LogMessage -Type INFO -AppendNewLine -Message "Cluster transition to vLCM image management accepted."
        }
        # We leverage multiple decisions in this function
        Remove-Variable -ErrorAction SilentlyContinue -Name Decision
    } else {
        #headless
        Write-LogMessage -Type INFO -PrependNewLine "Preparing for cluster transition(s)...`n"
        if ($JsonInputFile) {
            try {
                $ClusterNameInputs = (Get-Content $JsonInputFile) | Select-String -Pattern "^\s*$" -NotMatch | ConvertFrom-Json
            }
            catch {
                if ($Error[0] -match "Conversion from JSON failed with error") {
                    Write-LogMessage -Type ERROR -Message "JSON Validation error in $JsonInputFile"
                    Write-LogMessage -Type ERROR -Message "$($Error[0])"
                    exit
                }
            }
        } else {
            $ClusterNameInputs = [pscustomobject]@{
                WorkloadDomainName = $WorkloadDomainName
                ClusterName = $ClusterName
            }
        }

        # Initiate an array for selected clusters before its populated via for loop.
        $SelectedClusterDetails = @()

        # Validate JSON parameters and commandline parameters before adding them to an array matching the structure
        # of interactive input
        foreach ($Line in $ClusterNameInputs) {

           $WorkloadDomainId = ((Invoke-VcfGetDomains -ErrorAction SilentlyContinue).Elements | Where-Object Name -eq $($Line.WorkloadDomainName)).Id

            if (! $WorkloadDomainId) {
                Write-LogMessage -Type ERROR -Message "Workload Domain `"$($Line.WorkloadDomainName)`" not found"
                exit
            }

            $ClusterId = ((Invoke-VcfGetClusters -ErrorAction SilentlyContinue).Elements | Where-Object { $_.Domain.Id -eq $WorkloadDomainId -and $_.Name -eq $($Line.ClusterName) }).Id

            if (! $ClusterId) {
                Write-LogMessage -Type ERROR -Message "Cluster name `"$($Line.ClusterName)`" is invalid or not a member of workload domain `"$($Line.WorkloadDomainName))`"."
                exit
            }
            $SelectedClusterDetails += [pscustomobject]@{
                'ClusterId'          = $ClusterId
                'ClusterName'        = $($Line.ClusterName)
                'WorkloadDomainName' = $($Line.WorkloadDomainName)
            }
        }
    }

    foreach($SelectedCluster in $SelectedClusterDetails) {
        # Refresh the access token before moving onto a new cluster
        Test-SddcManagerConnection

        $ClusterId = $SelectedCluster.ClusterId
        $ClusterName = $SelectedCluster.ClusterName
        $WorkloadDomainName = $SelectedCluster.WorkloadDomainName

        # check if the compliance check has run, if not, fail fast.

        $Response = Invoke-VcfGetClusterImageCompliance -Id $ClusterId -ErrorAction SilentlyContinue

        if (! $Response) {

            if ($($Error[0].Exception.Message) -match "CLUSTER_IMAGE_COMPLIANCE_NOT_FOUND") {
                Write-LogMessage -Type ERROR -Message "Cluster compliance check hasn't been run on cluster `"$ClusterName`" in workload domain `"$WorkloadDomainName`"."
                Write-LogMessage -Type INFO -PrependNewLine -Message "This check must be run on each cluster before it can be converted to vLCM image management."
                Write-LogMessage -Type INFO -Message "Skipping `"$ClusterName`" in workload domain `"$WorkloadDomainName`"..."
                Write-LogMessage -Type ERROR -SuppressOutputToScreen -Message $($Error[0].Exception.Message)
                continue
            }
        }

        # Verify Image still exists
        $ImageFound = Invoke-VcfGetPersonality -PersonalityId $($Response.ClusterImage.Id) -ErrorAction SilentlyContinue

        if (! $ImageFound) {
            Write-LogMessage -Type ERROR -Message "Cannot find the vLCM image in SDDC Manager associated with cluster `"$ClusterName`" during the last compliance check."
            Write-LogMessage -Type ERROR -Message "The image may have been removed in error.  Please re-run the compliance check on another image, or after re-uploading"
            Write-LogMessage -Type ERROR -Message "The missing image."
            continue
        }

        $ClusterTransitionSpec  = Initialize-VcfClusterTransitionSpec -ErrorAction SilentlyContinue
        $ClusterUpdateSpec = Initialize-VcfClusterUpdateSpec -ClusterTransitionSpec $ClusterTransitionSpec -ErrorAction SilentlyContinue

        try {
            $Response = Invoke-VcfUpdateCluster -Id $ClusterId -ClusterUpdateSpec $ClusterUpdateSpec -ErrorAction SilentlyContinue
        } catch {
            if (!$Response -or ($Response -match "VMware.Bindings.Vcf.SddcManager.Model.ClusterImageCompliance") ) {
                # Catch the most common workflow error and provide guidance.
                if ( $($Error[0].Exception.Message) -match "vSphere Lifecycle Manager Images operation is currently working on this resource" ) {
                    Write-LogMessage -Type ERROR -Message "The transition of cluster `"$ClusterName`" in Workload Domain `"$WorkloadDomainName`" to vLCM image management is already progress."
                } elseif ($($Error[0].Exception.Message) -match "is already managed using vSphere Lifecycle Manager Images") {
                    Write-LogMessage -Type ERROR -Message "Cluster `"$ClusterName`" in Workload Domain `"$WorkloadDomainName`" has already been converted to image management."
                }
                else {
                    Write-LogMessage -Type ERROR -Message "An unexpected error occurred."
                    Write-LogMessage -Type ERROR -Message $($Error[0].Exception.Message)
                }

                if ($Headless -eq "disabled") {
                    Show-AnyKey
                    Show-MainMenu
                } else {
                    if ($JsonInputFile) {
                        Write-LogMessage -Type INFO -Message "Moving onto next cluster..."
                    } else {
                        exit
                    }
                }
            }
        }

        $TransitionChecks = ((Invoke-VcfGetTasks -TaskType VLCM_TRANSITION).Elements | Where-Object {$_.Status -eq "In Progress" }).Count
        if ($TransitionChecks) {
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Currently $TransitionChecks transition check(s) is/are being processed by SDDC Manager."
        }

        if ([String]::IsNullOrEmpty($Response)) {
            # The most common error is a check is already running.
            Write-LogMessage -Type ERROR -AppendNewLine -Message "Failed: cluster transition for cluster `"$ClusterName`" in Workload Domain `"$WorkloadDomainName`"."
            Write-LogMessage -Type ERROR -AppendNewLine -Message $($Error[0].Exception.Message)
            Show-AnyKey
            return
        }

        Write-LogMessage -Type INFO -Message "Beginning vLCM image transition for cluster `"$ClusterName`" in Workload Domain `"$WorkloadDomainName`"."
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "vLCM image transition for cluster `"$ClusterName`" in Workload Domain `"$WorkloadDomainName`" initiated using Task ID `"$($Response.Id)`"."

        # in Silence mode, process all work serially by not waiting for them to complete before exiting.
        # Parallel flag will disable polling for task to complete
        if (! ($Parallel)) {
            # Check if connected to SDDC Manager.
            Test-SddcManagerConnection

            # Time the process to enable the user to roughly estimate the time another cluster scan may take.
            $ProcessTimer = [System.Diagnostics.Stopwatch]::StartNew()
            # Determine the total number of transition steps required.
            $TotalStepCount = ((Invoke-VcfGetTask -Id $Response.Id).SubTasks | Measure-Object).Count

            Do {
                    $PreCheckTime = $([math]::Round(($ProcessTimer.Elapsed.TotalSeconds),0))
                    $TaskId = $Response.Id
                    try {
                        $TaskStatus = (Invoke-VcfGetTask -Id $TaskId).Status
                    # if the task fails due to a invalid token, reconnect to SDDC manager.
                    } catch [Exception] {
                        if (($Error[0].Exception.Message -match "TOKEN_NOT_FOUND") -or ($Error[0].Exception.Message -match "JWT expired")) {
                            Connect-SddcManager
                        }
                    }
                    $CurrentStepCount = ((Invoke-VcfGetTask -Id $TaskId).SubTasks | Where-Object -Property Status -eq "SUCCESSFUL" | Measure-Object).Count
                    $InProgressStepName = ((Invoke-VcfGetTask -Id $TaskId).SubTasks | Where-Object -Property Status -eq "IN_PROGRESS").Name

                    Write-Progress -Id 1 -Activity "Completed step $CurrentStepCount of $TotalStepCount       " -Status "Processing: $InProgressStepName" -PercentComplete ($CurrentStepCount/$TotalStepCount*100)
                    Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Cluster transition step $CurrentStepCount of $TotalStepCount of `"$ClusterName`" in Workload Domain `"$WorkloadDomainName`" underway.  $([math]::Round(($ProcessTimer.Elapsed.TotalSeconds),0)) seconds elapsed."
                    Write-Progress -Id 2 -Activity "Cluster transition in progress" -Status "$([math]::Round(($ProcessTimer.Elapsed.TotalSeconds),0)) seconds elapsed (updates every 5 seconds)."
                    Start-Sleep -Seconds 5

                    $PostCheckTime = $([math]::Round(($ProcessTimer.Elapsed.TotalSeconds),0))

                    if (([int]$PreCheckTime + 300) -lt ([int]$PostCheckTime)) {
                        Write-LogMessage -Type WARNING -SuppressOutputToScreen -Message "More than 300 seconds have elapsed between task progress checks. This is unusual."
                    }

            } While ($TaskStatus -eq 'In Progress')

            Write-Progress -Id 1 -Completed
            Write-Progress -Id 2 -Completed

            $ProcessTimer.Stop()

            # Write the full details on the cluster transition to the log file.
            $JsonResponse = $Response | ConvertTo-Json
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message $JsonResponse

            if ($TaskStatus -eq 'Failed') {
                # There should only be one failed task, as the workflow will fail out when the first task fails.  However, just in case, we want to return
                # a single task, so return just one task for safety.
                $FailedTask = (Invoke-VcfGetTask -Id $TaskId | Select-Object -Expand SubTasks | Where-Object -Property Status -eq "FAILED") | Select-Object -First 1
                Write-LogMessage -Type ERROR -Message "Transition was unsuccessful for cluster `"$ClusterName`" in Workload Domain `"$WorkloadDomainName`"."
                Write-LogMessage -Type ERROR -Message "Failed Task Name: $($FailedTask.Name)"
                Write-LogMessage -Type ERROR -Message "Subtask $($FailedStep.Name) with Task Id $TaskId failed."
                if ($null -ne $($FailedStep.errors)) {
                    Write-LogMessage -Type ERROR -Message "Error: $($FailedStep.errors)."
                }
                if ($null -ne $($FailedStep.errors.errorCode)) {
                    Write-LogMessage -Type ERROR -Message "Error code: $($FailedStep.errors.errorCode)."
                }
                if ($null -ne $($FailedStep.errors.Message)) {
                    Write-LogMessage -Type ERROR -Message "Error Message: $($FailedStep.errors.Message)."
                }

                Write-LogMessage -Type INFO -PrependNewLine -Message "Full details of the transition have been written to $LogFile."
                Write-LogMessage -Type INFO -PrependNewLine -Message "When the findings have been remediated, the workflow can be retried."

                $Decision = New-ChoiceMenu -Question "Would you like to retry the transition for cluster `"$ClusterName`" in workload domain `"$WorkloadDomainName`" now?" -DefaultAnswer yes

                # If user chooses yes, retry the task.
                if ($Decision -eq 0) {
                    # Retry the transition task.
                    Invoke-TransitionBaselineManagedCluster -RetryTransition -FailedTaskId $TaskId
                } else {
                    Show-AnyKey
                    break
                }

                $ProcessTimer.Stop()

                } elseif ($TaskStatus -eq 'Successful') {
                    Write-LogMessage -Type INFO -Message "Cluster `"$ClusterName`" in Workload Domain `"$WorkloadDomainName`" has been successfully converted to vLCM image management."
                } else {
                    Write-LogMessage -Type ERROR -Message "Cluster `"$ClusterName`" in Workload Domain `"$WorkloadDomainName`" vLCM image application exited with status `"$TaskStatus`"."
                }
                Write-LogMessage -type INFO -SuppressOutputToScreen -Message "vLCM cluster transition for cluster `"$ClusterName`" in Workload Domain `"$WorkloadDomainName`" $([math]::Round(($ProcessTimer.Elapsed.TotalMinutes),2)) minutes to complete."
                Write-LogMessage -Type INFO -PrependNewLine -Message "Full details of the transition written to $LogFile."
            }
        }
    }
}

Function Remove-TemporaryCluster {

        <#
            .SYNOPSIS
            The function Remove-TemporaryCluster deletes the temporary cluster used to hold a constructed vCenter vLCM image.

            .DESCRIPTION
            The function will only remove the cluster if does not contain any hosts.

            .EXAMPLE
            Remove-TemporaryCluster -TemporaryClusterName m01-cl01 -temporaryClusterVcenter m01-vc01.example.com

            .PARAMETER TemporaryClusterName
            Specifies cluster to remove.

            .PARAMETER TemporaryClusterVcenter
            Specifies which vCenter the cluster is a member of.
        #>

    Param (
        [Parameter (Mandatory = $True)] [ValidateNotNullOrEmpty()] [String]$TemporaryClusterName,
        [Parameter (Mandatory = $True)] [ValidateNotNullOrEmpty()] [String]$TemporaryClusterVcenter
    )

    # Check if connected to vCenter.
    Test-VcentersConnection

    # headless operations require input validation, which is otherwise handled, in interactive operations,
    # by the issuing function.
    if ($Headless -eq "enabled") {

        $IsConnectedVcenter =  ($Global:DefaultViServers | Where-Object IsConnected -eq $True) | Where-Object Name -eq $TemporaryClusterVcenter
        if ([String]::IsNullOrEmpty($IsConnectedVcenter)) {
            Write-LogMessage -Type ERROR -Message "vCenter `"$TemporaryClusterVcenter`" not found in list of connected vCenters."
            exit
        }

        # check if the cluster exists in the chosen vCenter.
        $Response = Get-Cluster -Server $TemporaryClusterVcenter -ErrorAction SilentlyContinue |  Where-Object { $_.Name -eq $TemporaryClusterName}
        if ([String]::IsNullOrEmpty($Response)) {
            Write-LogMessage -Type ERROR -Message "Cluster `"$TemporaryClusterName`" does not exist in vCenter `"$TemporaryClusterVcenter`"."
            exit
        }
    }

    $ClusterHostMembersFound = (Get-Cluster -Server $TemporaryClusterVcenter -Name $TemporaryClusterName -ErrorAction SilentlyContinue | Get-VMHost).Name | Sort-Object

    # Do not delete a cluster that has ESX hosts.
    if ([String]::IsNullOrEmpty($ClusterHostMembersFound)) {
        Write-LogMessage -Type INFO -Message "Safety check passed - No ESX hosts detected in cluster `"$TemporaryClusterName`" in vCenter `"$TemporaryClusterVcenter`"."
        $Response = Remove-Cluster -Server $TemporaryClusterVcenter -Cluster $TemporaryClusterName -Confirm:$False -ErrorAction 'SilentlyContinue' | Out-Null

        $Response = Get-Cluster -Server $TemporaryClusterVcenter -Name $TemporaryClusterName -ErrorAction SilentlyContinue
        if ($Response) {
            Write-LogMessage -Type ERROR -Message "Cluster `"$TemporaryClusterName`" in vCenter `"$TemporaryClusterVcenter` could not be deleted."
            exit
        } else {
            Write-LogMessage -Type INFO -Message "Deleted cluster `"$TemporaryClusterName`" in vCenter `"$TemporaryClusterVcenter`"."
        }

    } else {
        Write-LogMessage -Type WARNING -Message "Will not delete cluster `"$TemporaryClusterName`" in vCenter `"$TemporaryClusterVcenter`" due to the presence of existing hosts."
        foreach ( $EsxHost in $ClusterHostMembersFound) {
            Write-LogMessage -Type INFO -Message "ESX host `"$EsxHost`" found in cluster `"$TemporaryClusterName`""
        }
    }
}

Function Show-TaskStatus {

    <#
        .SYNOPSIS
        The function Show-TaskStatus displays the status of a type of task.

        .DESCRIPTION
        The function assists headless, silent operations where a task need not complete before
        the issuing command returns. There are two options today: ComplianceCheck and SddcManagerImageUpload.

        .EXAMPLE
        Show-TaskStatus -TaskType SddcManagerImageUpload

        .EXAMPLE
        Show-TaskStatus -TaskType ComplianceCheck

        .EXAMPLE
        Show-TaskStatus -TaskType ComplianceCheck

        .PARAMETER ComplianceCheck
        Specifies the name of a cluster to check.

        .PARAMETER TaskType
        Specifies what type of task to display.
    #>

    Param (
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$TaskType
    )

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    Write-LogMessage -type INFO -AppendNewLine -PrependNewLine -Message "Scanning for $TaskType tasks..."

    if ($TaskType -eq "SddcManagerImageUpload") {

        $Response = (Invoke-VcfGetTasks).Elements | Where-Object {$_.Type -eq "PERSONALITY_UPLOAD"}

    } elseif ($TaskType -eq "ComplianceCheck") {

        # In order to just get the latest compliance check for a cluster we have to iterate through
        # Invoke-VcfGetTasks for each cluster with an additional filter.
        $BaselineClusters = (Invoke-VcfGetClusters -IsImageBased $False).Elements.Name | Sort-Object
        $Response = @()
        foreach ($BaselineClusterName in $BaselineClusters) {
            $Response += (Invoke-VcfGetTasks).Elements | Where-Object {$_.Type -eq "VLCM_COMPLIANCE_CHECK"} | Where-Object {$_.Name -match $BaselineClusterName } | Sort-Object CreationTimestamp | Select-Object -Last 1 | Select-Object Name,Status,CreationTimestamp,CompletionTimestamp,Errors
        }
    } else {
        Write-LogMessage -Type ERROR -Message "Unknown task type."
        exit
    }

    # Exit if no results for the task type
    if ([String]::IsNullOrEmpty($Response)) {
            Write-LogMessage -type ERROR -Message "No $TaskType tasks found in `"$($DefaultSddcManagerConnections.Name)`"."
            exit
    } else {
        $Tasks = @()

        $Tasks += [pscustomobject]@{
            'Name'                    = "Name"
            'TaskStatus'              = "Status"
            'TaskCreationTimestamp'   = "Task Start Time"
            'TaskCompletionTimestamp' = "Task End Time"
            'TaskErrorMessage'        = "Error Message"
        }

        $Tasks += [pscustomobject]@{
            'Name'                    = "-----"
            'TaskStatus'              = "------"
            'TaskCreationTimestamp'   = "---------------"
            'TaskCompletionTimestamp' = "-------------"
            'TaskErrorMessage'        = "-------------"
        }

        foreach ($Line in $Response) {

            Write-LogMessage -SuppressOutputToScreen -Type INFO -Message $($Line | ConvertTo-Json)

            # Replace null data with more useful information.
            if ([String]::IsNullOrEmpty($Line.CreationTimestamp)) {
                $TaskStatus = "<NOT_CHECKED_YET>"
                $TaskCreationTimestamp = "N/A"
            } else {
                $TaskStatus = $Line.Status
                $TaskCreationTimestamp = $Line.CreationTimestamp
            }

            if ([String]::IsNullOrEmpty($Line.Errors)) {
                $TaskError = "N/A"
            } else {
                $TaskError = $Line.Error
            }

            if ([String]::IsNullOrEmpty($Line.CompletionTimestamp)) {
                $TaskCompletionTimestamp = "N/A"
            } else {
                $TaskCompletionTimestamp = $Line.CompletionTimestamp
            }

            $StringPrefixes = "vSphere Lifecycle Manager Image Upload ","Check image compliance of cluster "
            foreach ($StringPrefix in $StringPrefixes) {
                $EntityName = $($Line.Name) -replace $StringPrefix
                if ($EntityName -ne $($Line.Name)) {
                    break
                }
            }

            $Tasks += [pscustomobject]@{
                'Name'                    = $EntityName
                'TaskStatus'              = $TaskStatus
                'TaskCreationTimestamp'   = $TaskCreationTimestamp
                'TaskCompletionTimestamp' = $TaskCompletionTimestamp
                'TaskErrorMessage'        = $TaskError
            }

        }

        # Only show the tabular view if the -silent option is not used.
        if ($Global:LogOnly -eq "disabled") {
           $Tasks | Format-Table -Property @{Expression = " " }, Name, TaskStatus, TaskCreationTimestamp, TaskCompletionTimestamp, TaskErrorMessage -Autosize -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }
        }
    }
}

Function Show-ClusterTransitionStatus {

    <#
        .SYNOPSIS
        The function Show-ClusterTransitionStatus displays the transition status of a cluster.

        .DESCRIPTION
        The function assists headless operations (especially in silent mode) where the call returns before
        the transition is complete.

        .EXAMPLE
        Show-ClusterTransitionStatus -ClusterName m01-cl01 -WorkloadDomainName m01

        .EXAMPLE
        Show-ClusterTransitionStatus -ReturnSummary

        .PARAMETER ClusterName
        Specifies which cluster's transition results to display.

        .PARAMETER ReturnSummary
        Specifies the option to display the status of all cluster transitions.

        .PARAMETER WorkloadDomainName
        Specifies which workload domain a cluster belongs to.
    #>

    Param (
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$ClusterName,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$ReturnSummary,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$WorkloadDomainName
    )

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    Write-LogMessage -Type INFO -PrependNewLine -Message "Scanning for cluster transition status messages...`n"

    if ($ReturnSummary) {

        # Begin by looking at the VLCM Transition tasks, as it takes some time before the cluster changes from isImage=false to isImage=true
        $ConvertedClusterIds = ((Invoke-VcfGetTasks -TaskType "VLCM_TRANSITION").Elements.Resources.ResourceId)

        if (! $ConvertedClusterIds) {
            Write-LogMessage -type INFO -Message "No cluster transition tasks found in SDDC Manager `"$($DefaultSddcManagerConnections.Name)`"."
            Show-AnyKey
            break
        }
        $ClusterStatus = @()

        $ClusterStatus += [pscustomobject]@{
            'ClusterName'             = "Cluster Name"
            'WorkloadDomainName'      = "Workload Domain"
            'TransitionStatus'        = "Task Status"
            'TaskId'                  = "Task Id"
            'TaskCreationTimeStamp'   = "Task Start Time"
            'TaskCompletionTimeStamp' = "Task End Time"
        }

        $ClusterStatus += [pscustomobject]@{
            'ClusterName'             = "-------------"
            'WorkloadDomainName'      = "---------------"
            'TransitionStatus'        = "-----------"
            'TaskId'                  = "--------"
            'TaskCreationTimeStamp'   = "---------------"
            'TaskCompletionTimeStamp' = "-------------"
        }

        foreach ($ClusterId in $ConvertedClusterIds) {
            $Cluster = (Invoke-VcfGetCluster -Id $ClusterId)
            $Response = (Invoke-VcfGetTasks -TaskType "VLCM_TRANSITION").Elements | Where-Object {$_.Resources.ResourceId -eq $($Cluster.Id)}
            if (! $Response ) {
                $TransitionStatus = "N/A"
            } else {
                $TransitionStatus = $Response.Status
            }
            # A "1/1/1" date means the task is not yet complete. Display "N/A" for better readability.
            if (($($Response.CompletionTimeStamp) -eq "1/1/0001 12:00:00 AM") -or  ([String]::IsNullOrEmpty($Response.CompletionTimestamp))) {
                $TaskCompletionTimeStamp = "N/A"
            } else {
                $TaskCompletionTimeStamp = $($Response.CompletionTimeStamp)
            }

            $ClusterStatus += [pscustomobject]@{
                'ClusterName'             = $($Cluster.Name)
                'WorkloadDomainName'      = (Invoke-VcfGetDomain -Id $($Cluster.Domain.Id)).Name
                'TransitionStatus'        = $TransitionStatus
                'TaskId'                  = $Response.Id
                'TaskCreationTimeStamp'   = $Response.CreationTimeStamp
                'TaskCompletionTimeStamp' = $TaskCompletionTimeStamp
            }
            Write-LogMessage -type INFO -SuppressOutputToScreen -Message "Cluster `"$($Cluster.Name)`" in Workload Domain `"$((Invoke-VcfGetDomain -Id $($Cluster.Domain.Id)).Name)`" image transition process status is `"$TransitionStatus`". Task started at `"$($Response.CreationTimeStamp)`" and completed at `"$TaskCompletionTimeStamp`""
        }
        $ClusterStatus | Format-Table -Property @{Expression = " " }, ClusterName, WorkloadDomainName, TransitionStatus, TaskCreationTimeStamp, TaskCompletionTimeStamp -Autosize -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }
    }

    if ($ClusterName -and $WorkloadDomainName) {
        $Response = ((Invoke-VcfGetDomains).Elements | Where-Object Name -eq $WorkloadDomainName).clusters.Id
        if (! $Response) {
            Write-LogMessage -Type ERROR -Message "Workload domain `"$WorkloadDomainName`" does not exist"
            exit
        }
        foreach ($MemberClusterId in $Response) {
            if ( ((Invoke-VcfGetCluster -Id $MemberClusterId).Name) -eq $ClusterName) {
                $SelectedClusterId = $MemberClusterId
            }
        }

        if (! $SelectedClusterId) {
            Write-LogMessage -Type ERROR -Message "Cluster name `"$ClusterName`" not found in `"$WorkloadDomainName`""
            exit
        }

        $Response = (Invoke-VcfGetTasks -TaskType "VLCM_TRANSITION").Elements | Where-Object {$_.Resources.ResourceId -eq $SelectedClusterId}
        if (! $Response) {
            Write-LogMessage -Type ERROR -Message "No cluster transition task found for `"$ClusterName`" in Workload Domain `"$WorkloadDomainName`"."
            exit
        }

        Write-LogMessage -Type INFO -Message "The vLCM image transition details for vLCM image transition task for cluster `"$ClusterName`" in Workload Domain `"$WorkloadDomainName`":"
        if ($Response.Errors) {
            Write-LogMessage -Type INFO -Message "The cluster transition failed with error: $($Response.Errors)"
        }
        if ( ($Response.SubTasks | Where-Object -Property Status -eq "IN_PROGRESS").Name) {
            Write-LogMessage -Type INFO -Message "The current sub-step is being processed: $($($Response.SubTasks | Where-Object -Property Status -eq "IN_PROGRESS").Name)"
        }
        $TotalStepCount = ($Response.SubTasks | Measure-Object).Count
        $CurrentStepCount = ( $Response.SubTasks | Where-Object -Property Status -eq "SUCCESSFUL" | Measure-Object).Count

        Write-LogMessage -Type INFO -Message "$CurrentStepCount steps out of $TotalStepCount steps completed."
        Write-LogMessage -Type INFO -Message "Status of the transition is: $($Response.Status)"
        if ($($Response.Status) -eq "Failed") {
            $FailedTaskID = $((Invoke-VcfGetTasks -TaskType "VLCM_TRANSITION" -TaskStatus "Failed").Elements | Where-Object {$_.Name -match $ClusterName }).Id
            Write-LogMessage -Type INFO -Message "Transition of failed with ID $FailedTaskID."
            Write-LogMessage -Type INFO -Message "Re-try transition by running the script with the arguments `"-RetryTransition -TaskId $FailedTaskID`"."
        }
    }
}

Function Disconnect-SddcManager {

    <#
        .SYNOPSIS
        The function Disconnect-SddcManager Disconnects from SDDC Manager.

        .DESCRIPTION
        The function assists Disconnecting from SDDC Manager. It's called in the following ways: automatically when exiting the interactive mode,
        and through a prompt when a user wishes to Switch SDDC managers through the interactive and headless mode.

        .EXAMPLE
        Disconnect-SddcManager -OverrideQuestion "Do you really want to Disconnect?"

        .EXAMPLE
        Disconnect-SddcManager -NoPrompt

        .EXAMPLE
        Disconnect-SddcManager -Silence

        .PARAMETER OverrideQuestion
        Specifies an override prompt for disconnecting from SDDC Manger

        .PARAMETER NoPrompt
        Specifies the option to disconnect without confirmation

        .PARAMETER Silence
        Specifies the option to not display the output to screen.
    #>

    Param (
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$OverrideQuestion,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$NoPrompt,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$Silence
    )

    if (! $DefaultSddcManagerConnections.IsConnected) {
        if (!$Silence) {
            Write-LogMessage -Type INFO -Message "No SDDC Manager connection detected."
        }
    } else {
        # Declare SDDC Manager variable so the name can be logged after disconnection.
        $Global:SddcManagerFqdn = $DefaultSddcManagerConnections.Name

        if ( !$NoPrompt) {
            if ($OverrideQuestion) {
                $Decision = New-ChoiceMenu -Question "$OverrideQuestion" -DefaultAnswer no
            } else {
                $Decision = New-ChoiceMenu -Question "Would you like to disconnect from `"$Global:SddcManagerFqdn`"" -DefaultAnswer no
            }
        }

        # Check if the user chose option 0, yes do disconnect from vCenter.
        if (($Decision -eq 0) -or ($NoPrompt)) {
            Disconnect-VcfSddcManagerServer -Server $DefaultSddcManagerConnections.Name
            if ($?) {
                if ($Silence) {
                    Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Successfully disconnected from SDDC Manager `"$Global:SddcManagerFqdn`"."
                } else {
                    Write-LogMessage -Type INFO -Message "Successfully disconnected from SDDC Manager `"$Global:SddcManagerFqdn`"."
                }
            } else {
                Write-LogMessage -Type ERROR -Message "Failed to disconnect from SDDC Manager `"$Global:SddcManagerFqdn`"."
            }
        } else {
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "User chose not to disconnect from `"$Global:SddcManagerFqdn`"."
        }
    }
}

Function Disconnect-Vcenter {

    <#
        .SYNOPSIS
        The function Disconnect-Vcenter disconnects from vCenter(s).

        .DESCRIPTION
        The function assists disconnecting from vCenter(s). It's called in the following ways: automatically
        when exiting the interactive mode, and through a prompt in interactive and headless mode.

        .EXAMPLE
        Disconnect-Vcenter -NoPrompt

        .EXAMPLE
        Disconnect-Vcenter -Silence

        .PARAMETER Silence
        Specifies the option to not display the output to screen.

        .PARAMETER vCenterName
        Specifies the vCenterName to disconnect
    #>

    Param (
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$Silence,
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [String]$VcenterName

    )

    if ($VcenterName) {
        Disconnect-VIServer -Server $VcenterName -Force -Confirm:$False -ErrorAction SilentlyContinue
        if ($Silence) {
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Successfully disconnected from vCenter `"$VcenterName`"."
        } else {
           Write-LogMessage -Type INFO -AppendNewLine -Message "Successfully disconnected from vCenter `"$VcenterName`"."
        }
        return
    }

    $ConnectedVcenters = ($Global:DefaultViServers | Where-Object IsConnected -eq $True).Name

    if ($ConnectedVcenters) {

        foreach ($VcenterName in $ConnectedVcenters) {
            if ($Silence) {
                 Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Successfully disconnected from vCenter `"$VcenterName`"."
            } else {
                Write-LogMessage -Type INFO -Message "Successfully disconnected from vCenter `"$VcenterName`"."
            }
            Disconnect-VIServer -Server $VcenterName -Force -Confirm:$False -ErrorAction SilentlyContinue
        }

        # Handle an edge case where non-tracked vCenters are connected.
        if ( $Global:DefaultViServers.IsConnected) {
             Disconnect-VIServer -Server * -Force -Confirm:$False -ErrorAction SilentlyContinue
        }
    }
}


Function Show-IncompleteTasks {

    <#
        .SYNOPSIS
        The function Show-IncompleteTasks enables lookup and resumption of failed tasks.

        .DESCRIPTION
        The function primarily assists re-trying cluster transition tasks.

        .EXAMPLE
        Show-IncompleteTasks
    #>


    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    # It is sufficient to just look for a failed task, as there's precisely one task Id per cluster
    # transition. The task Id can be resumed, but another one cannot be spawned. Therefore a cluster
    # cannot have a task with status failed and another with status successful.

    $Response = (Invoke-VcfGetTasks -TaskType "VLCM_TRANSITION" -TaskStatus "Failed").Elements

    if (!$Response) {
        Write-LogMessage -Type INFO -Message "No failed vLCM transition tasks found."
        Show-AnyKey
        break
    }

    $VlcmTransitionDisplayObject = @()
    $VlcmTransitionIndex = 1

    $VlcmTransitionDisplayObject += [pscustomobject]@{
        'Id'                  = 'Id'
        'ClusterName'         = "Cluster Name"
        'WorkloadDomainName'  = "Workload Domain"
        'TaskId'              = "Task Id"
        'taskCompletionTime'  = "Task Completion Time"
    }

    $VlcmTransitionDisplayObject += [pscustomobject]@{
        'Id'                  = "--"
        'ClusterName'         = "------------"
        'WorkloadDomainName'  = "---------------"
        'TaskId'              = "-------"
        'taskCompletionTime'  = "--------------------"
    }

    foreach ($Line in $Response) {
        $ClusterId = $Line.Resources.ResourceId
        $ClusterName = (Invoke-VcfGetCluster -Id $ClusterId).Name
        $WorkloadDomainName = (Invoke-VcfGetDomain -Id (Invoke-VcfGetCluster -Id $ClusterId).Domain.Id).Name
        $VlcmTransitionDisplayObject += [pscustomobject]@{
            'Id'                 = $VlcmTransitionIndex
            'ClusterName'        = $ClusterName
            'WorkloadDomainName' = $WorkloadDomainName
            'TaskId'             = $Line.Id
            'taskCompletionTime' = $Line.CompletionTimeStamp
        }
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "`"$ClusterName`" transition task found with Id $($Line.Id) from $($Line.CompletionTimeStamp)"
        $VlcmTransitionIndex++
    }
    # If VlcmTransitionIndex is not incremented from the default value no failures were found.
    if ($VlcmTransitionIndex -eq "1") {
        Write-LogMessage -Type INFO -Message "No failed vLCM cluster transition tasks located."
        Show-AnyKey
        break
    }

    # headless output is almost identical to non-headless (only the Id is elided)
    if ($Headless -eq "enabled") {
        Write-Host "Clusters that were not successfully transitioned to vLCM image management:`n" -ForegroundColor Green;
        $VlcmTransitionDisplayObject | Format-Table -Property @{Expression = " " }, ClusterName, WorkloadDomainName, TaskId, taskCompletionTime  -Autosize -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }
        exit
    }
    Write-LogMessage -Type INFO -AppendNewLine -Message "Cluster transition resumption workflow:"
    Write-Host "Clusters that were not successfully transitioned to vLCM image management:`n" -ForegroundColor Green;
    $VlcmTransitionDisplayObject | Format-Table -Property @{Expression = " " }, Id, ClusterName, WorkloadDomainName, TaskId, taskCompletionTime  -Autosize -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }

    Do {
        Write-Output ""
        $VersionSelection = Read-Host "Enter the id of an image or press 'c' to cancel"

        if ($VersionSelection -eq "c") {
            Show-AnyKey
             Show-MainMenu
        }
        $IsValidId = ($VersionSelection -in $($VlcmTransitionDisplayObject.Id))
        if (! $IsValidId) {
            Write-LogMessage -Type ERROR -Message "Invalid selection. $VersionSelection identifier not found."
        }
        } While (! $IsValidId)

    $FailedTaskId = ($VlcmTransitionDisplayObject | Where-Object {$_.Id -eq $VersionSelection}).TaskId
    $FailedClusterName = ($VlcmTransitionDisplayObject | Where-Object {$_.Id -eq $VersionSelection}).ClusterName

    Write-LogMessage -Type INFO -Message "Preparing to retry vLCM image transition for `"$FailedClusterName`" using task ID `"$FailedTaskId`"."
    Invoke-TransitionBaselineManagedCluster -RetryTransition -FailedTaskId $FailedTaskId
}

Function Get-EnvironmentSetup {

    <#
        .SYNOPSIS
        The function Get-EnvironmentSetup logs user environment details.

        .DESCRIPTION
        The function facilitates troubleshooting by populating each day's log files with useful runtime details.

        .EXAMPLE
        Get-EnvironmentSetup
    #>

    $PowerShellRelease = $($PSVersionTable.PSVersion).ToString()

    $VcfPowerCliRelease = (Get-Module -ListAvailable -Name VCF.PowerCLI -ErrorAction SilentlyContinue | Sort-Object Revision | Select-Object -First 1).Version
    $VmwarePowerCliRelease = (Get-Module -ListAvailable -Name VMware.PowerCLI -ErrorAction SilentlyContinue | Sort-Object Revision | Select-Object -First 1).Version

    $OperatingSystem = $($PSVersionTable.OS)

    # Work-around for MacOS which displays Darwin kernel release when from $($PSVersionTable.OS).  However, if this call fails, revert to what we know.
    if ($IsMacOS) {
        try {
            $MacOsVersion = (system_profiler SPSoftwareDataType -json | ConvertFrom-Json | ForEach-Object spsoftwaredatatype | Where-Object _name -eq os_overview).os_version
        } catch [Exception] {
        }
    }
    if ($MacOsVersion) {
        $OperatingSystem = $MacOsVersion
    }

    Show-Version -Silence

    Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Client PowerShell version is $PowerShellRelease"

    if ($VcfPowerCliRelease) {
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Client VCF.PowerCLI version is $VcfPowerCliRelease."
    }
    if ($VmwarePowerCliRelease) {
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Client VMware.PowerCLI version is $VmwarePowerCliRelease."
    }
    if (!$VcfPowerCliRelease -and !$VmwarePowerCliRelease) {
        Write-LogMessage -Type ERROR -SuppressOutputToScreen -Message "Client PowerCLI not installed."
    }

    Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Client Operating System is $OperatingSystem"

}

Function Get-Preconditions {

    <#
       .SYNOPSIS
       The function Get-Preconditions checks to if the script's preconditions are met.

       .DESCRIPTION
       The function provides will exit if any conditions it not met.

       .EXAMPLE
        Get-Preconditions
   #>

    # PowerCLI Module and Version Check
    $VcfModuleName = "VCF.PowerCLI"
    $VmwareModuleName = "VMware.PowerCLI"

    $VcfPowerCliModule = (Get-Module -ListAvailable -Name $VcfModuleName -ErrorAction SilentlyContinue) | Sort-Object Revision | Select-Object -First 1
    $VmwarePowerCliModule = (Get-Module -ListAvailable -Name $VmwareModuleName -ErrorAction SilentlyContinue) | Sort-Object Revision | Select-Object -First 1

    if (!$VcfPowerCliModule -and !$VmwarePowerCliModule ) {
        Write-LogMessage -Type EXCEPTION -AppendNewLine -Message "PowerCLI was not found. Please install VCF.PowerCLI 9.0 or later."
        exit
    } else {
         if ($VmwarePowerCliVersion) {
             Write-LogMessage -Type EXCEPTION -AppendNewLine -Message "VMware.PowerCLI version $VmwarePowerCliVersion discovered.  This script requires VCF.PowerCLI 9.0 or later.  Please upgrade."
             exit
         }
     }

    # PowerCLI Configuration Check
    try {
        $Response = Get-PowerCLIConfiguration | Where-Object -Property DefaultVIServerMode -eq "Multiple" | Where-Object -Property Scope -in ("User","Session")
    } catch [Exception] {
        if ($_.Exception.Message -match "is not recognized as a name of a cmdlet") {
            Write-LogMessage -Type ERROR -Message "Cannot find Get-PowerCLIConfiguration. You may need to reinstall PowerCLI."
        } else {
            Write-LogMessage -Type ERROR -Message "ERROR: $($_.Exception.Message)"
        }
        exit
    }

    if (! $Response) {
        Write-LogMessage -Type EXCEPTION -Message "PowerCLI must be configured to connect to multiple vCenters simultaneously."
        Write-Host "Run: Set-PowerCLIConfiguration -DefaultVIServerMode Multiple"
        exit
    }

    $CurrentPSVersion = ($PSVersionTable.PSVersion.Major),($PSVersionTable.PSVersion.Minor) -join "."

    If ( $CurrentPSVersion -lt $PSVersionMinVersion ) {
        Write-LogMessage -Type EXCEPTION -Message "Powershell $PSVersionMinVersion or higher is required."
        exit
    }

    # Windows 2012 and below do not support the default TLS cyphers required for recent
    # versions of Powershell and PowerCLI.
    if ($IsWindows) {
        if ([Environment]::OSVersion.Version.Major -lt 10) {
          Write-LogMessage -Type EXCEPTION -Message "Windows Server 2016+ or Windows 10+ required."
          exit
        }
    }
}

Function Show-Version {

    <#
        .SYNOPSIS
        The function Show-Version shows the version of the script.

        .DESCRIPTION
        The function provides version information.

        .EXAMPLE
        Show-Version

        .EXAMPLE
        Show-Version -Silence

        .PARAMETER Silence
        Specifies the option to not display the output to screen.
    #>

    Param (
        [Parameter (Mandatory = $False)] [ValidateNotNullOrEmpty()] [Switch]$Silence
    )
    if (! $Silence) {
        Write-LogMessage -Type INFO -Message "Version: $ScriptVersion"
    } else {
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Script Version: $ScriptVersion"
    }
}

Function Show-Help {

     <#
        .SYNOPSIS
        The function Show-Help shows available headless operations.

        .DESCRIPTION
        The function provides guidance for headless operations.

        .EXAMPLE
        Show-Help
    #>

    Write-Output "`nIf no parameters are specified, a menu-driven interface is presented.`n"
    Write-Output "Options:`n"
    Write-Output "-CheckTaskStatus                      # Check to see if a task has completed"
    Write-Output "   -Silence                           #   * Optional parameter: Silence."
    Write-Output "   -TaskType <type>                   #   * Mandatory Parameter: valid types include SddcManagerImageUpload and ComplianceCheck `n"
    Write-Output "-CheckTransitions                     # Check status of cluster transitions to image management."
    Write-Output "   -ClusterName <Cluster Name>        #   * Optional parameter: Cluster Name."
    Write-Output "   -Silence                           #   * Optional parameter: Silence."
    Write-Output "   -WorkloadDomainName <WLD>          #   * Optional parameter: Workload Domain Name.`n"
    Write-Output "-Connect                              # Connect to SDDC Manager and Workload Domain vCenter(s)."
    Write-Output "   -Silence                           #   * Optional parameter: Silence."
    Write-Output "   -JsonInput <credential file>       #   * Optional parameter: override for credential file (default: SddcManagerCredentials.json).`n"
    Write-Output "-ComplianceCheck                      # Check if a cluster is compatible with an image."
    Write-Output "   -ClusterName <Cluster Name>        #   * Optional parameter if JsonInput is not specified: Cluster Name."
    Write-Output "   -SddcManagerImageName <ImageName>  #   * Optional parameter if JsonInput is not specified: Image Name."
    Write-Output "   -JsonInput <JSON file>             #   * Optional parameter if Cluster/SddcManager is not specified: JsonInput."
    Write-Output "   -Parallel                          #   * Optional parameter: parallelize the cluster compliance checks (used in combination with -JsonInput)"
    Write-Output "   -Silence                           #   * Optional parameter: Silence. (Cannot be used with serial processing)"
    Write-Output "   -WorkloadDomainName <WLD>          #   * Mandatory parameter: Workload Domain Name.`n"
    Write-Output "-DeleteImageFromSddcManager           # Delete Image from SDDC Manager (use in case of misnamed image)"
    Write-Output "   -SddcManagerImageName <ImageName>  #   * Mandatory parameter: SDDC Manager image name."
    Write-Output "   -Silence                           #   * Optional parameter: Silence.`n"
    Write-Output "-DeleteTemporaryCluster               # Delete temporary cluster from image (use in case of accidental import)"
    Write-Output "   -ClusterName <Cluster Name>        #   * Mandatory parameter: Cluster Name."
    Write-Output "   -Silence                           #   * Optional parameter: Silence."
    Write-Output "   -VcenterName <vCenter FQDN>        #   * Mandatory parameter: vCenter Fully Qualified Domain Name.`n"
    Write-Output "-Disconnect                           # Disconnect from SDDC Manager and Workload Domain vCenters."
    Write-Output "   -Silence                           #   * Optional parameter: Silence.`n"
    Write-Output "-Help                                 # Get Help (show this Message).`n"
    Write-Output "-ImportImagesFromVcenter              # Import vLCM Images from connected vCenters into SDDC Manager."
    Write-Output "   -JsonInput <JSON file>             #   * Optional parameter: json input file for multiple imports."
    Write-Output "   -Parallel                          #   * Optional parameter: parallelize cluster transition (used in combination with -JsonInput)"
    Write-Output "   -Silence                           #   * Optional parameter: Silence."
    Write-Output "   -VcenterImageName <Image Name>     #   * Optional parameter: Source vCenter vLCM Image / Cluster Name."
    Write-Output "   -VcenterName <vCenter FQDN>        #   * Optional parameter: vCenter Fully Qualified Domain Name.`n"
    Write-Output "-ReviewComplianceResults              # Review the results of a cluster compliance check"
    Write-Output "   -ClusterName <Cluster Name>        #   * Optional parameter: Cluster Name."
    Write-Output "   -ShowAllClusters                   #   * Optional parameter: Show summary of all baseline-managed clusters."
    Write-Output "   -ShowExtendedResults               #   * Optional parameter: show full compliance findings."
    Write-Output "   -Silence                           #   * Optional parameter: Silence."
    Write-Output "   -WorkloadDomainName <WLD>          #   * Optional parameter: Workload Domain Name.`n"
    Write-Output "-RetryTransition                      # Retry a cluster transition to image management,"
    Write-Output "   -TaskId <Task Id>                  #    * Mandatory parameter: Task id of failed transition.`n"
    Write-Output "-ShowBaselineClusters                 # vLCM image management in vCenter and SDDC Manager."
    Write-Output "   -JsonOutput <Output file>          #   * Optional parameter: Save vLCM baseline cluster details to a json file."
    Write-Output "   -Silence                           #   * Optional parameter: Silence.`n"
    Write-Output "-ShowImagesInSddcManager              # Show all vLCM Images in SDDC Manager."
    Write-Output "   -Silence                           #   * Optional parameter: Silence.`n"
    Write-Output "-ShowImagesInVcenter                  # Show all vLCM Images in vCenter(s)."
    Write-Output "   -JsonOutput <Output file>          #   * Optional parameter: output vCenter vLCM image details to a json file."
    Write-Output "   -Silence                           #   * Optional parameter: Silence.`n"
    Write-Output "-TransitionCluster                    # Transition vLCM baseline (VUM) cluster to vLCM image management."
    Write-Output "   -ClusterName <Cluster Name>        #   * Mandatory parameter: Cluster Name."
    Write-Output "   -JsonInput <JSON file>             #   * Optional json input file for multiple cluster transitions."
    Write-Output "   -Parallel                          #   * Optional parameter: parallelize cluster transition (used in combination with -JsonInput)"
    Write-Output "   -Silence                           #   * Optional parameter: Silence."
    Write-Output "   -WorkloadDomainName <WLD>          #   * Mandatory parameter: Workload Domain Name.`n"
    Write-Output "-Version                              # Show script version.`n"
}

# The function Show-MainMenu enables the user to perform a guided vLCM baseline to vLCM image transitions.

Function Show-MainMenu {

    <#
     .SYNOPSIS
     The function Show-MainMenu shows the interactive menu.

     .DESCRIPTION
     The function facilitates a guided, interactive workflow.

     .EXAMPLE
     Show-MainMenu
    #>


if ($($DefaultSddcManagerConnections.IsConnected)) {
    $ConnectionBanner = " [Connected to: $($DefaultSddcManagerConnections.Name)]"
} else {
    $ConnectionBanner = ""
}

    Do {
        Clear-Host
        Write-Host -Object "`nvLCM Baseline (VUM) to vLCM Image Cluster Transition Menu.`n" -ForegroundColor Cyan
        Write-Host -NoNewline -Object " 1. Connect to SDDC Manager and select vCenter."  -ForegroundColor White
        Write-Host -Object "$ConnectionBanner" -ForegroundColor Green
        Write-Host -Object " 2. Import vLCM images from vCenter(s) into SDDC Manager." -ForegroundColor White
        Write-Host -Object " 3. Check existing cluster(s)' vLCM image compliance." -ForegroundColor White
        Write-Host -Object " 4. Transition vLCM baseline (VUM) cluster to vLCM image management." -ForegroundColor White
        Write-Host -Object " 5. (Optional) Disconnect from vCenter(s) and SDDC Manager." -ForegroundColor White
        Write-Host -Object " 6. (Optional) Retry incomplete transition tasks." -ForegroundColor White
        Write-Host -Object " 7. (Optional) Delete SDDC Manager Image." -ForegroundColor White
        Write-Host -Object " 8. (Optional) Show script version." -ForegroundColor White
        Write-Host -Object " 9. (Optional) Show cluster transition status." -ForegroundColor White
        Write-Host -Object " 10. (Optional) Show vLCM images in SDDC Manager." -ForegroundColor White
        Write-Host -Object " Q. Press Q to Quit" -ForegroundColor Cyan;
        Write-Host -Object $Errout
        $MenuInput = Read-Host -Prompt ' (1-10 or Q)'
        $MenuInput = $MenuInput -replace "`t|`n|`r",""
        Switch ($MenuInput)
        {
            1
            {
                Clear-Host
                Connect-SddcManager
                Connect-Vcenter
                Show-AnyKey
                Show-MainMenu
            }
            2
            {
                Clear-Host
                Import-ImageFromVcenter
                Show-AnyKey
                Show-MainMenu
            }
            3
            {
                Clear-Host
                Invoke-ImageComplianceCheck
                Show-AnyKey
                Show-MainMenu
            }
            4
            {
                Clear-Host
                Invoke-TransitionBaselineManagedCluster
                Show-AnyKey
                Show-MainMenu
            }
            5
            {
                Clear-Host
                Disconnect-SddcManager -OverrideQuestion "Would you like to disconnect from SDDC Manager and vCenter(s)?"
                Disconnect-Vcenter
                Show-AnyKey
                Show-MainMenu
            }
            6
            {
                Clear-Host
                Show-IncompleteTasks
                Show-AnyKey
                Show-MainMenu
            }
            7
            {
                Clear-Host
                Remove-ImageFromSddcManager
                Show-AnyKey
                Show-MainMenu
            }
            8
            {
                Clear-Host
                Show-Version
                Show-AnyKey
                Show-MainMenu
            }
            9
            {
                Clear-Host
                Show-ClusterTransitionStatus -ReturnSummary
                Show-AnyKey
                Show-MainMenu
            }
            10
            {
                Clear-Host
                Get-SddcManagerImages -ShowAll
                Show-AnyKey
                Show-MainMenu
            }
            Q
            {
                Disconnect-SddcManager -NoPrompt -Silence
                Disconnect-Vcenter -Silence
                Remove-Variable -ErrorAction SilentlyContinue -Name SddcManagerPassword -Scope Global
                Remove-Variable -ErrorAction SilentlyContinue -Name SddcManagerUserName -Scope Global
                Remove-Variable -ErrorAction SilentlyContinue -Name SddcManagerFqdn -Scope Global
                Exit
            }
            Default
            {
                $Errout = 'Invalid option please try again...'
            }
        }
    }
    Until ($MenuInput -eq 'q')
}

# Variables and Constants
$ConfirmPreference = "None"
$Global:ProgressPreference = 'Continue'
$PSStyle.Progress.Style = "`e[93;1m"
# Powershell 7.2 is the minimum required for the script to function, however, 7.2 is EOS.
$PSVersionMinVersion = '7.2'
$MinimumVcfRelease = '5.2.2.0'
$MinimumImageCatalogSupportRelease = '9.0.0.0'
$Global:LogOnly = "disabled"

New-LogFile
# Added temporarily for debugging
if (! $env:SkipChecks) {
    Get-Preconditions
}

if ($Help) {
    Show-Help
    exit
}

# assume headless mode until all conditions have been checked
$Global:Headless = 'enabled'

#default
$SddcManagerCredentialsJson= Join-Path -Path $PSScriptRoot -ChildPath "SddcManagerCredentials.json"

# If Silence is set, the Write-LogMessage function will not send output to the screen.
if ($Silence) {
    $Global:LogOnly = "enabled"
}

if ($Connect) {
    if ($JsonInput) {
        $SddcManagerCredentialsJson = $JsonInput
    }
    Connect-SddcManager
    Connect-Vcenter
} elseif ($Disconnect) {
    Disconnect-Vcenter
    Disconnect-SddcManager -NoPrompt
    Remove-Variable -ErrorAction SilentlyContinue -Name SddcManagerPassword -Scope Global
    Remove-Variable -ErrorAction SilentlyContinue -Name SddcManagerUserName -Scope Global
    Remove-Variable -ErrorAction SilentlyContinue -Name SddcManagerFqdn -Scope Global
    exit
} elseif ($CheckCompliance) {
    if ($ClusterName -and $WorkloadDomainName) {
        Show-ClusterComplianceStatus -ClusterName $ClusterName -WorkloadDomainName $WorkloadDomainName
    } else {
        Show-ClusterComplianceStatus -ReturnSummary
    }
}
elseif ($CheckTransitions) {
    if ($ClusterName -and $WorkloadDomainName) {
        Show-ClusterTransitionStatus -ClusterName $ClusterName -WorkloadDomainName $WorkloadDomainName
    } else {
        Show-ClusterTransitionStatus -ReturnSummary
    }
} elseif ($CheckTaskStatus) {
    if ($TaskType) {
        Show-TaskStatus -TaskType $TaskType
    } else {
        Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -CheckTaskStatus requires a -TaskType argument"
        exit
    }
} elseif ($ComplianceCheck) {
    # Check for JSON Input first
    if ($JsonInput) {
        $JsonInputExists = Test-Path $JsonInput
        # We can only proceed if the JsonInput file exists.
        if ($JsonInputExists) {
            if ($Parallel) {
                Invoke-ImageComplianceCheck -JsonInputFile $JsonInput -Parallel
            } else {
                if ($Silence) {
                    Write-LogMessage -Type ERROR -Message "Parameter `"-Silence`" cannot be used with serialized processing."
                    exit
                } else {
                    Invoke-ImageComplianceCheck -JsonInputFile $JsonInput
                }
            }
        } else {
            Write-LogMessage -Type ERROR -Message "JsonInput file `"$JsonInput`" not found."
            exit
        }
    # If JSON input is not specified, we need ClusterName/WorkloadDomainName/SddcManagerImageName specified.
    } elseif ((! $ClusterName) -or (! $WorkloadDomainName) -or (! $SddcManagerImageName)) {
        Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -ComplianceCheck requires the following arguments:"
        Write-LogMessage -Type ERROR -Message " -ClusterName <Cluster Name>"
        Write-LogMessage -Type ERROR -Message " -WorkloadDomainName <Workload Domain Name>"
        Write-LogMessage -Type ERROR -Message " -SddcManagerImageName <Image Name in SDDC Manager>"
        exit
    } else {
        Invoke-ImageComplianceCheck -ClusterName $ClusterName -WorkloadDomainName $WorkloadDomainName -SddcManagerImageName $SddcManagerImageName
    }
} elseif ($DeleteImageFromSddcManager) {
    if (! $SddcManagerImageName) {
        Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -DeleteImageFromSddcManager requires the following arguments:"
        Write-LogMessage -Type ERROR -Message " -SddcManagerImageName <Sddc Manager Image Name>"
        exit
    } else {
        Remove-ImageFromSddcManager -SddcManagerImageName $SddcManagerImageName
    }
} elseif ($DeleteTemporaryCluster) {
    if ($ClusterName -and $VcenterName) {
        Remove-TemporaryCluster -TemporaryClusterName $ClusterName -temporaryClusterVcenter $VcenterName
    } else {
        Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -DeleteTemporaryCluster requires the following arguments:"
        Write-LogMessage -Type ERROR -Message " -ClusterName <Cluster Name>"
        Write-LogMessage -Type ERROR -Message " -VcenterName <Cluster Name>"
        exit
    }
} elseif ($ImportImagesFromVcenter) {
    if ($JsonInput) {
        $JsonInputExists = Test-Path $JsonInput
        if ($JsonInputExists) {
            if ($Parallel) {
                Import-ImageFromVcenter -JsonInputFile $JsonInput -Parallel
            } else {
                if ($Silence) {
                    Write-LogMessage -Type ERROR -Message "Parameter `"-Silence`" cannot be used with serialized processing."
                    exit
                } else {
                    Import-ImageFromVcenter -JsonInputFile $JsonInput
                }
            }
        } else {
            Write-LogMessage -Type ERROR -Message "JsonInput $JsonInput not found"
            exit
        }
    } elseif ((! $VcenterImageName) -or (! $VcenterName)) {
        Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -ImportImagesFromVcenter requires the following arguments:"
        Write-LogMessage -Type ERROR -Message " -VcenterImageName <Source vCenter vLCM Image / Cluster Name>"
        Write-LogMessage -Type ERROR -Message " -VcenterName <vCenter Fully Qualified Domain Name>"
        exit
    } else {
        if ($Silence) {
            Import-ImageFromVcenter -VcenterImageName $VcenterImageName -VcenterName $VcenterName -Silence
        } else {
            Import-ImageFromVcenter -VcenterImageName $VcenterImageName -VcenterName $VcenterName
        }
    }
} elseif ($ReviewComplianceResults) {
    if ($ShowAllClusters) {
        if ($ShowExtendedResults) {
            Show-ImageComplianceCheckResults -ShowAllClusters -ShowExtendedResults
        } else {
            Show-ImageComplianceCheckResults -ShowAllClusters
        }

    } elseif ($ClusterName -and $WorkloadDomainName) {
        if ($ShowExtendedResults) {
            Show-ImageComplianceCheckResults $ClusterName -WorkloadDomainName $WorkloadDomainName -ShowExtendedResults
        } else {
            Show-ImageComplianceCheckResults $ClusterName -WorkloadDomainName $WorkloadDomainName
        }
    } else {
        Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -ReviewComplianceResults requires the following arguments:"
        Write-LogMessage -Type ERROR -Message " -ClusterName <Cluster Name>"
        Write-LogMessage -Type ERROR -Message " -WorkloadDomainName <Workload Domain Name>"
        exit
    }
}  elseif ($RetryTransition) {
    # check for required parameters
    if (! $TaskId) {
        Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -RetryTransition requires argument:"
        Write-LogMessage -Type ERROR -Message " -TaskId <Failed Task Id>"
        exit
    } else {
        $Response = (Invoke-VcfGetTasks -TaskType "VLCM_TRANSITION" -TaskStatus "Failed").Elements | Where-Object Id -eq $TaskId
        if ($Response) {
            Invoke-TransitionBaselineManagedCluster -RetryTransition -FailedTaskId $TaskId
        } else {
            Write-LogMessage -Type ERROR -Message "TaskId $TaskId does not correspond to a failed VLCM_TRANSITION task."
        }
    }
} elseif ($ShowBaselineClusters) {
    if ($JsonOutput) {
        Get-BaselineManagedClusters -JsonOutputFile $JsonOutput
    } else {
        Get-BaselineManagedClusters
    }
} elseif ($ShowImagesInSddcManager ) {
        Get-SddcManagerImages
} elseif ($ShowImagesInVcenter) {
    if ($JsonOutput) {
        Get-VcenterImages -JsonOutputFile $JsonOutput
    } else {
        Get-VcenterImages
    }
} elseif ($TransitionCluster) {
    if ($JsonInput) {
        $JsonInputExists = Test-Path $JsonInput
        if ($JsonInputExists) {
            if ($Parallel) {
                Invoke-TransitionBaselineManagedCluster -JsonInputFile $JsonInput -Parallel
            } else {
                if ($Silence) {
                    Write-LogMessage -Type ERROR -Message "Parameter `"-Silence`" cannot be used with serialized processing."
                    exit
                } else {
                    Invoke-TransitionBaselineManagedCluster -JsonInputFile $JsonInput
                }
            }
        } else {
            Write-LogMessage -Type ERROR -Message "JsonInput `"$JsonInput`" not found."
            exit
        }
    }
    # check for required parameters
    elseif ((! $ClusterName) -or (! $WorkloadDomainName)) {
        Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -TransitionCluster requires the following arguments:"
        Write-LogMessage -Type ERROR -Message " -ClusterName <Cluster Name>"
        Write-LogMessage -Type ERROR -Message " -WorkloadDomainName <Workload Domain Name>"
    } else {
        Invoke-TransitionBaselineManagedCluster -ClusterName $ClusterName -WorkloadDomainName $WorkloadDomainName
    }
} elseif ($Version) {
    Show-Version
} else {
    # if no options specified, enter interactive mode
    $Global:Headless = 'disabled'
    Show-MainMenu
}