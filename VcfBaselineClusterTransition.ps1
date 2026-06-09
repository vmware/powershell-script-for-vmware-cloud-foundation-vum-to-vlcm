<#
.SYNOPSIS
    Facilitates the transition of vLCM baseline (VUM) managed clusters and standalone hosts to vLCM image management in VMware Cloud Foundation.

.DESCRIPTION
    VcfBaselineClusterTransition.ps1 automates the process of converting vSphere Lifecycle Manager (vLCM)
    baseline-managed clusters and standalone hosts (formerly VUM/Update Manager) to vLCM image-based management.

    This script provides three execution modes:

    1. INTERACTIVE MODE (Menu-Driven):
       Running the script without parameters launches a user-friendly menu interface that guides you through
       the complete workflow with prompts and validation at each step. Ideal for manual operations and
       learning the workflow.

    2. HEADLESS MODE (Command-Line with Parameters):
       Running with inline parameters enables single-resource operations suitable for one-off executions.

    3. HEADLESS MODE (JSON-Based Batch Processing):
       Using JSON input files with the -Parallel switch enables automated processing of multiple resources
       simultaneously, ideal for large-scale transitions and CI/CD pipelines.

    The script handles the following workflows:
    - Connecting to SDDC Manager and retrieving workload domain vCenter credentials
    - Importing vLCM images from vCenter to SDDC Manager
    - Running compliance checks for clusters/hosts against images
    - Supporting VxRail image seeding (auto-generated images for compatible clusters)
    - Transitioning baseline-managed resources to image management
    - Monitoring transition progress with detailed task status reporting
    - Retrying failed transitions with remediation options
    - Managing vLCM images (list, delete)
    - Managing temporary clusters created during image import

    The script provides comprehensive logging with configurable log levels (DEBUG through ERROR)
    and supports both console output and detailed log files for troubleshooting.

.PARAMETER CheckHostRemediationOptionsFile
    Validates a HostRemediationOptions override JSON file for use with the transition step.
    This file allows customization of host remediation behavior during cluster transitions.

    Requires: -JsonInput (path to HostRemediationOptions JSON file)

    Use this parameter to validate your remediation options before running the actual transition.

.PARAMETER CheckTaskStatus
    Checks the status of background tasks such as image uploads or compliance checks.

    Requires: -TaskType (specify "SddcManagerImageUpload" or "ComplianceCheck")
    Optional: -Silence (suppress console output, log only)

    Use this to monitor long-running operations that were started with -Parallel flag.

.PARAMETER CheckTransitions
    Checks the status of resource transitions to image management.

    Optional: -ResourceName (specific cluster/host name)
    Optional: -ResourceType ("Cluster" or "Standalone Host")
    Optional: -WorkloadDomainName (specific workload domain)
    Optional: -Silence (suppress console output)

    Without parameters, shows all transitions. With parameters, filters to specific resources.

.PARAMETER CollectLogs
    Creates a timestamped zip archive of all log files in the logs subdirectory.

    Output is saved to: <script directory>/VcfBaselineClusterTransition-logs-<yyyyMMdd-HHmmss>.zip

    Each file added to the archive is listed on the console. Use this to collect logs for
    support or troubleshooting. Does not require a connection to SDDC Manager or vCenter.

.PARAMETER ComplianceCheck
    Runs a compliance check to determine if a cluster or standalone host is compatible with a vLCM image.

    For single resource (parameter mode):
        Requires: -ResourceName, -WorkloadDomainName
        Optional: -SddcManagerImageName (omit for image seeding on compatible clusters)
        Optional: -ResourceType (defaults to "Cluster")
        Optional: -Silence

    For multiple resources (JSON mode):
        Requires: -JsonInput (path to JSON file with array of resources)
        Optional: -Parallel (run checks concurrently)
        Optional: -Silence (only with -Parallel)

    Image Seeding: For vCenter 8.0.3+ clusters with ESXi 8.0.3+ hosts, omit -SddcManagerImageName
    to auto-generate an image based on the cluster's current configuration.

.PARAMETER Connect
    Establishes connections to SDDC Manager and workload domain vCenter instances.

    Optional: -JsonInput (path to custom credentials file, default: SddcManagerCredentials.json)
    Optional: -Silence (suppress console output)

    The script will prompt for credentials if not provided via JSON file.
    Multiple vCenter connections are established automatically based on workload domains.

.PARAMETER CreateHostRemediationOptionsFile
    Creates a template HostRemediationOptions override JSON file for customizing transition behavior.

    Requires: -JsonOutput (path for the generated JSON template file)

    Use this to generate a template, then customize the remediation options before transition.

.PARAMETER DeleteImageFromSddcManager
    Deletes a vLCM image from SDDC Manager (useful for correcting misnamed images).

    Requires: -SddcManagerImageName (name of the image to delete)
    Optional: -Silence (suppress console output)

    WARNING: This operation cannot be undone. Ensure the image is not in use.

.PARAMETER DeleteTemporaryCluster
    Deletes a temporary cluster from a vLCM image (useful if imported accidentally).

    Requires: -TemporaryClusterName (name of the cluster to delete)
    Requires: -VcenterName (vCenter FQDN)
    Optional: -Silence (suppress console output)

.PARAMETER Disconnect
    Disconnects from SDDC Manager and all connected vCenter instances.

    Optional: -Silence (suppress console output)

.PARAMETER ExcludeSddcManagerImageName
    When used with -ShowBaselineResources and -JsonOutput, excludes the SDDC Manager image name
    from the JSON output. This is useful when generating JSON for compliance checks that will
    use image seeding from vCenter instead of specifying an SDDC Manager image.

    Recommended to run at the end of operations to properly close connections.

.PARAMETER Help
    Displays command-line help information showing all available parameters and usage examples.

    Equivalent to running with no parameters and selecting the help option from the menu.

.PARAMETER HostRemediationOptionsFile
    Specifies the path to a HostRemediationOptions override JSON file for customizing transition behavior.

    Use with: -TransitionResource

    This file allows fine-tuning of host remediation options such as evacuation modes,
    timeout settings, and failure handling during cluster transitions.

.PARAMETER ImportImagesFromVcenter
    Imports vLCM images from connected vCenter(s) into SDDC Manager.

    For single image (parameter mode):
        Optional: -VcenterImageName (source vLCM image or cluster name in vCenter)
        Optional: -VcenterName (vCenter FQDN)

    For multiple images (JSON mode):
        Optional: -JsonInput (path to JSON file with array of images)
        Optional: -Parallel (import images concurrently)
        Optional: -Silence

    Without parameters, presents an interactive selection menu.

.PARAMETER JsonInput
    Path to a JSON input file for batch operations.

    Used with: -ComplianceCheck, -TransitionResource, -ImportImagesFromVcenter, -Connect, -CheckHostRemediationOptionsFile

    JSON format varies by operation:
    - Compliance/Transition: Array of {ResourceName, WorkloadDomainName, [SddcManagerImageName]}
    - Import: Array of {VcenterImageName, VcenterName}
    - Connect: {SddcManagerFqdn, SddcManagerUserName, SddcManagerPassword}
    - HostRemediation: HostRemediationOptions configuration

.PARAMETER JsonOutput
    Path to a JSON output file for saving operation results.

    Used with: -CreateHostRemediationOptionsFile, -ShowBaselineResources, -ShowImagesInVcenter

    Saves structured data to file for further processing or record-keeping.

.PARAMETER LogLevel
    Sets the minimum log level for console output. All log levels are always written to the log file.

    Valid values: DEBUG, INFO, ADVISORY, WARNING, EXCEPTION, ERROR
    Default: INFO

    Log level hierarchy (lowest to highest):
    DEBUG < INFO < ADVISORY < WARNING < EXCEPTION < ERROR

    - DEBUG: Detailed diagnostic information for troubleshooting
    - INFO: General informational messages about progress (default)
    - ADVISORY: Important notices and guidance
    - WARNING: Warning messages about potential issues
    - EXCEPTION: Caught exceptions that were handled
    - ERROR: Error messages indicating failures

    Example: Set to DEBUG for verbose troubleshooting, ERROR for quiet automated runs.

.PARAMETER Parallel
    Enables parallel processing for batch operations.

    Used with: -ComplianceCheck (with -JsonInput), -TransitionResource (with -JsonInput), -ImportImagesFromVcenter (with -JsonInput)

    Significantly improves performance when processing multiple resources.
    Must be used with -JsonInput. When enabled, -Silence is recommended.

.PARAMETER RetryTransition
    Retries a failed cluster or standalone host transition to image management.

    Requires: -TaskId (task ID of the failed transition)

    Use this after remediating issues that caused the original transition to fail.
    The task ID can be obtained from transition failure messages or CheckTransitions.

.PARAMETER ResourceName
    Specifies the name of a cluster or standalone host.

    Used with: -ComplianceCheck, -TransitionResource, -CheckTransitions, -ReviewComplianceResults

    Must be the exact name as it appears in vCenter.

.PARAMETER ResourceType
    Specifies whether the resource is a cluster or standalone host.

    Valid values: "Cluster", "Standalone Host"
    Default: "Cluster" (when applicable)

    Used with: -ComplianceCheck, -TransitionResource, -CheckTransitions, -ReviewComplianceResults

.PARAMETER ReviewComplianceResults
    Reviews the results of a cluster or standalone host compliance check.

    Optional: -ResourceName (specific resource)
    Optional: -ResourceType ("Cluster" or "Standalone Host")
    Optional: -WorkloadDomainName (specific workload domain)
    Optional: -ShowAllResources (show all baseline-managed resources)
    Optional: -ShowExtendedResults (show detailed compliance findings)
    Optional: -Silence (suppress console output)

    Without parameters, shows all compliance results. Use filters to narrow results.

.PARAMETER Silence
    Suppresses console output while continuing to write to the log file.

    Used with: Most operations

    Recommended for automated/scheduled executions and when using -Parallel.
    The log file will still contain all details.

.PARAMETER TaskId
    Specifies the task ID for task-related operations.

    Used with: -RetryTransition, -CheckTaskStatus

    Task IDs are provided in failure messages and can be queried via CheckTransitions.

.PARAMETER TaskType
    Specifies the type of task to check status for.

    Used with: -CheckTaskStatus
    Valid values: "SddcManagerImageUpload", "ComplianceCheck"

    Different task types have different status reporting formats.

.PARAMETER TemporaryClusterName
    Specifies the name of a temporary cluster to delete from a vLCM image.

    Used with: -DeleteTemporaryCluster
    Requires: -VcenterName

.PARAMETER TransitionResource
    Transitions a vLCM baseline (VUM) managed cluster or standalone host to vLCM image management.

    For single resource (parameter mode):
        Requires: -ResourceName, -WorkloadDomainName, -ResourceType
        Optional: -HostRemediationOptionsFile (custom remediation options)
        Optional: -Silence

    For multiple resources (JSON mode):
        Requires: -JsonInput (path to JSON file with array of resources)
        Optional: -Parallel (transition resources concurrently)
        Optional: -HostRemediationOptionsFile (applies to all resources)
        Optional: -Silence

    This is the core operation that performs the actual vLCM mode transition.

.PARAMETER SddcManagerImageName
    Specifies the name of a vLCM image in SDDC Manager.

    Used with: -ComplianceCheck, -DeleteImageFromSddcManager

    For compliance checks, omit this parameter to use image seeding on compatible clusters.

.PARAMETER ShowAllResources
    Shows a summary of all baseline-managed clusters and standalone hosts.

    Used with: -ReviewComplianceResults

    Provides a comprehensive view of all resources across all workload domains.

.PARAMETER ShowBaselineResources
    Lists all vLCM baseline (VUM) managed clusters and standalone hosts.

    Optional: -JsonOutput (save results to JSON file)
    Optional: -ExcludeSddcManagerImageName (exclude SDDC Manager image name from JSON output)
    Optional: -Silence (suppress console output)

    Useful for discovering which resources are candidates for transition.

.PARAMETER ShowImagesInSddcManager
    Lists all vLCM images currently stored in SDDC Manager.

    Optional: -Silence (suppress console output)

    Shows images that have been imported from vCenter or auto-generated via image seeding.

.PARAMETER ShowImagesInVcenter
    Lists all vLCM images available in connected vCenter(s).

    Optional: -JsonOutput (save results to JSON file)
    Optional: -Silence (suppress console output)

    Shows images available for import to SDDC Manager.

.PARAMETER ShowExtendedResults
    Displays detailed compliance findings when reviewing results.

    Used with: -ReviewComplianceResults

    Provides verbose output including specific component version differences.

.PARAMETER SkipPowercliVersionCheck
    Skips the PowerCLI version compatibility check.

    WARNING: Use only if you're certain your PowerCLI version is compatible.
    The script requires VCF.PowerCLI 9.0.0.88628186 or later.

.PARAMETER WorkloadDomainName
    Specifies the name of a VMware Cloud Foundation workload domain.

    Used with: -ComplianceCheck, -TransitionResource, -CheckTransitions, -ReviewComplianceResults

    Must match the workload domain name as configured in SDDC Manager.

.PARAMETER VcenterImageName
    Specifies the name of a vLCM image or cluster name in vCenter.

    Used with: -ImportImagesFromVcenter

    Can be either an existing vLCM image name or a cluster name (to import that cluster's image).

.PARAMETER VcenterName
    Specifies the fully qualified domain name (FQDN) of a vCenter instance.

    Used with: -ImportImagesFromVcenter, -DeleteTemporaryCluster

.PARAMETER Version
    Displays the script version and exits.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    None. This script writes log messages to console and log file but does not output objects to the pipeline.

    Log files are created in the "logs" subdirectory with the naming pattern:
    logs/VcfBaselineClusterTransition-YYYY-MM-DD_HH-mm-ss.log

    Exit Codes:
    The script uses standardized exit codes to enable automation and improve debugging:

    0  - SUCCESS: Operation completed successfully
    1  - GENERAL_ERROR: Unspecified error (legacy exits not yet categorized)
    2  - PARAMETER_ERROR: Invalid parameters or validation failure (alias: INVALID_ARGUMENTS)
    3  - CONNECTION_ERROR: Failed to connect to SDDC Manager or vCenter (alias: VCENTER_CONNECTION_ERROR)
    4  - AUTHENTICATION_ERROR: Authentication or credential failure
    5  - RESOURCE_NOT_FOUND: Cluster, host, workload domain, or image not found
    6  - OPERATION_FAILED: Operation (transition, import, compliance) failed
    7  - TASK_FAILED: Background task failed or timed out
    8  - CONFIGURATION_ERROR: JSON or configuration file error (alias: FILE_NOT_FOUND)
    9  - PRECONDITION_ERROR: Prerequisites not met (modules, versions, permissions) (alias: VERSION_ERROR)
    10 - USER_CANCELLED: User cancelled the operation

    These exit codes allow CI/CD pipelines and monitoring systems to distinguish between failure
    types and implement appropriate retry logic or alerting strategies.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1

    Launches the interactive menu-driven interface. This is the recommended way to learn the workflow.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -Connect

    Connects to SDDC Manager and all workload domain vCenters using default credentials file.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -Connect -JsonInput "credentials.json"

    Connects to SDDC Manager using custom credentials file.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ShowBaselineResources

    Lists all vLCM baseline-managed clusters and standalone hosts across all workload domains.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ShowBaselineResources -JsonOutput "resources.json" -ExcludeSddcManagerImageName

    Exports baseline resources to JSON file without the SDDC Manager image name field.
    This is useful for generating input files for compliance checks that will use image seeding from vCenter.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ShowImagesInVcenter -JsonOutput "vcenter-images.json"

    Lists all vLCM images in vCenter and saves results to JSON file.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ImportImagesFromVcenter -VcenterImageName "m01-cl01" -VcenterName "m01-vc01.example.com"

    Imports a vLCM image from a specific cluster in vCenter to SDDC Manager.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ComplianceCheck -ResourceName "m01-cl01" -WorkloadDomainName "m01" -SddcManagerImageName "esx-803"

    Runs a compliance check for cluster "m01-cl01" against image "esx-803".

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ComplianceCheck -ResourceName "m01-cl01" -WorkloadDomainName "m01"

    Runs a compliance check with image seeding (auto-generates image for vCenter 8.0.3+ with ESX 8.0.3+ hosts).

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ComplianceCheck -JsonInput "clusters.json" -Parallel -Silence

    Runs parallel compliance checks for multiple clusters from JSON file with console output suppressed.

    JSON format:
    [
      {
        "ResourceName": "m01-cl01",
        "WorkloadDomainName": "m01",
        "SddcManagerImageName": "esx-803"
      },
      {
        "ResourceName": "w01-cl01",
        "WorkloadDomainName": "w01"
      }
    ]

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ReviewComplianceResults -ResourceName "m01-cl01" -WorkloadDomainName "m01" -ShowExtendedResults

    Reviews detailed compliance results for a specific cluster.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -CreateHostRemediationOptionsFile -JsonOutput "remediation-options.json"

    Creates a template HostRemediationOptions file for customizing transition behavior.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -TransitionResource -ResourceName "m01-cl01" -ResourceType "Cluster" -WorkloadDomainName "m01"

    Transitions a single cluster from baseline to image management using default remediation options.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -TransitionResource -ResourceName "m01-cl01" -ResourceType "Cluster" -WorkloadDomainName "m01" -HostRemediationOptionsFile "custom-remediation.json"

    Transitions a cluster with custom remediation options.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -TransitionResource -JsonInput "clusters.json" -Parallel -Silence

    Transitions multiple clusters in parallel from JSON file with console output suppressed.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -CheckTransitions -ResourceName "m01-cl01" -WorkloadDomainName "m01"

    Checks the status of a specific cluster's transition.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -RetryTransition -TaskId "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

    Retries a failed transition using the task ID from the original failure.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -DeleteImageFromSddcManager -SddcManagerImageName "esx-803-old"

    Deletes a vLCM image from SDDC Manager (use for correcting misnamed images).

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -Disconnect

    Disconnects from SDDC Manager and all vCenter instances.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -Version

    Displays the script version and exits.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -Help

    Displays command-line help information with all parameters and usage examples.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -ComplianceCheck -ResourceName "m01-cl01" -WorkloadDomainName "m01" -LogLevel DEBUG

    Runs a compliance check with DEBUG log level for detailed troubleshooting output.

.EXAMPLE
    .\VcfBaselineClusterTransition.ps1 -TransitionResource -JsonInput "production-clusters.json" -Parallel -LogLevel ERROR

    Transitions multiple clusters in parallel with minimal console output (errors only).

.NOTES
    File Name      : VcfBaselineClusterTransition.ps1
    Version        : 1.0.0.0.61
    Author         : Broadcom
    Prerequisite   : PowerShell 7.2 or later
                     VCF.PowerCLI 9.1.0 or later (VMware.PowerCLI not supported)
                     PowerCLI DefaultVIServerMode set to Multiple
                     SDDC Manager 5.2.2.x, VCF 9.0, or later
                     Windows Server 2016+ or Windows 10+ (for Windows environments)
                     Network connectivity to SDDC Manager and vCenter(s)
                     SDDC Manager user account with ADMIN role

    Configuration  : Set PowerCLI for multiple vCenter connections:
                     Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Scope User

                     Ignore certificate warnings (lab environments):
                     Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

    Error Handling : The script uses inline error handling with try/catch blocks and error checking.
                     Most operations log errors and continue or exit based on severity.
                     Critical operations may terminate the script with error messages.

                     For automation scenarios, check log files for detailed error information.
                     Log files are created in the ./logs directory with timestamps.

    Supported Features:
                     - VxRail image seeding (auto-generated images)
                     - VSRN image seeding (optional)
                     - vLCM Baseline to vLCM Image transition for non-Supervisor clusters
                     - Clusters with VMware Cloud Foundation 5.x sBOMs
                     - Parallel processing for batch operations
                     - Custom host remediation options
                     - Task retry for failed transitions

    Workflow       : Standard workflow for transitioning clusters:
                     1. Connect to SDDC Manager (credentials from JSON or prompts)
                     2. Connect to vCenter(s) in workload domains (automatic)
                     3. (Optional) Import vLCM images from vCenter to SDDC Manager
                     4. Run compliance checks on clusters/hosts
                     5. Review compliance results and remediate issues if needed
                     6. Transition clusters/hosts to image management
                     7. Monitor transition progress
                     8. (Optional) Retry failed transitions after remediation
                     9. Disconnect from all systems

    JSON Formats   :
                     SddcManagerCredentials.json:
                     {
                       "SddcManagerFqdn": "sfo-vcf01.example.com",
                       "SddcManagerUserName": "administrator@vsphere.local",
                       "SddcManagerPassword": "<your-password>"
                     }

                     SECURITY NOTE: SddcManagerCredentials.json stores the password as plaintext.
                     Restrict access to this file (chmod 600 on Linux/macOS; restrict ACL on Windows).
                     Never commit this file to source control. The file can be safely deleted at any time;
                     the script will prompt for credentials interactively if the file is absent.

                     Compliance/Transition clusters (array format):
                     [
                       {
                         "ResourceName": "m01-cl01",
                         "WorkloadDomainName": "m01",
                         "SddcManagerImageName": "esx-803"
                       },
                       {
                         "ResourceName": "w01-cl01",
                         "WorkloadDomainName": "w01"
                       }
                     ]
                     Note: Omit SddcManagerImageName for image seeding on compatible clusters.

                     Image import (array format):
                     [
                       {
                         "VcenterImageName": "m01-cl01",
                         "VcenterName": "m01-vc01.example.com"
                       },
                       {
                         "VcenterImageName": "custom-image-name",
                         "VcenterName": "w01-vc01.example.com"
                       }
                     ]

    Performance    : For large-scale operations:
                     - Use -Parallel with JSON input for multiple resources
                     - Use -Silence to reduce console overhead
                     - Set -LogLevel ERROR for minimal console output
                     - Monitor log files for detailed progress

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

    Last Modified  : 2026-06-02

.LINK
    Knowledge Base Article:
    https://knowledge.broadcom.com/external/article?articleNumber=385617

.LINK
    VCF 9.0 Admin Guide - vLCM Transition:
    https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-0/deployment/upgrading-cloud-foundation/upgrade-the-management-domain-to-vmware-cloud-foundation-5-2/vlcm-baseline-to-vlcm-image-cluster-transition-.html

.LINK
    VMware Cloud Foundation Documentation:
    https://docs.vmware.com/en/VMware-Cloud-Foundation/index.html

.LINK
    vSphere Lifecycle Manager Documentation:
    https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/managing-host-and-cluster-lifecycle-8-0.html
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
#
# Last Modified: 2026-04-25
#
####

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $false)] [Switch]$CheckHostRemediationOptionsFile,
    [Parameter(Mandatory = $false)] [Switch]$CheckTaskStatus,
    [Parameter(Mandatory = $false)] [Switch]$CheckTransitions,
    [Parameter(Mandatory = $false)] [Switch]$CollectLogs,
    [Parameter(Mandatory = $false)] [Switch]$ComplianceCheck,
    [Parameter(Mandatory = $false)] [Switch]$Connect,
    [Parameter(Mandatory = $false)] [Switch]$CreateHostRemediationOptionsFile,
    [Parameter(Mandatory = $false)] [Switch]$DeleteImageFromSddcManager,
    [Parameter(Mandatory = $false)] [Switch]$DeleteTemporaryCluster,
    [Parameter(Mandatory = $false)] [Switch]$Disconnect,
    [Parameter(Mandatory = $false)] [Switch]$ExcludeSddcManagerImageName,
    [Parameter(Mandatory = $false)] [Switch]$Help,
    [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$HostRemediationOptionsFile,
    [Parameter(Mandatory = $false)] [Switch]$ImportImagesFromVcenter,
    [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$JsonInput,
    [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$JsonOutput,
    [Parameter(Mandatory = $false)] [ValidateSet("DEBUG", "INFO", "ADVISORY", "WARNING", "EXCEPTION", "ERROR")] [String]$LogLevel = "INFO",
    [Parameter(Mandatory = $false)] [Switch]$Parallel,
    [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$ResourceName,
    [Parameter(Mandatory = $false)] [ValidateSet("Cluster", "Standalone Host")] [String]$ResourceType,
    [Parameter(Mandatory = $false)] [Switch]$RetryTransition,
    [Parameter(Mandatory = $false)] [Switch]$ReviewComplianceResults,
    [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$SddcManagerImageName,
    [Parameter(Mandatory = $false)] [Switch]$ShowAllResources,
    [Parameter(Mandatory = $false)] [Switch]$ShowBaselineResources,
    [Parameter(Mandatory = $false)] [Switch]$ShowExtendedResults,
    [Parameter(Mandatory = $false)] [Switch]$ShowImagesInSddcManager,
    [Parameter(Mandatory = $false)] [Switch]$ShowImagesInVcenter,
    [Parameter(Mandatory = $false)] [Switch]$Silence,
    [Parameter(Mandatory = $false)] [Switch]$SkipPowercliVersionCheck,
    [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$TaskId,
    [Parameter(Mandatory = $false)] [ValidateSet("ComplianceCheck", "SddcManagerImageUpload")] [String]$TaskType,
    [Parameter(Mandatory = $false)] [Switch]$TransitionResource,
    [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$VcenterImageName,
    [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$VcenterName,
    [Parameter(Mandatory = $false)] [Switch]$Version,
    [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$WorkloadDomainName
)

Set-StrictMode -Version 2

$scriptVersion = '1.0.0.62'

# Initialize log level configuration (imported from OneNodeDeployment.ps1)
$Script:configuredLogLevel = $LogLevel.ToUpper()

# Initialize SDDC Manager version cache (populated on first use).
$Script:CachedSddcManagerVersion = $null

# Define log level hierarchy for filtering console output (lowest to highest)
# All messages are always written to log file regardless of level
$Script:logLevelHierarchy = @{
    "DEBUG" = 0
    "INFO" = 1
    "ADVISORY" = 2
    "WARNING" = 3
    "EXCEPTION" = 4
    "ERROR" = 5
}

# Define standard exit codes for automation and debugging
# These codes allow CI/CD pipelines and monitoring systems to distinguish failure types
$Script:ExitCodes = @{
    SUCCESS                   = 0   # Successful execution
    GENERAL_ERROR             = 1   # General/unspecified error
    PARAMETER_ERROR           = 2   # Invalid parameters or validation failure
    CONNECTION_ERROR          = 3   # SDDC Manager or vCenter connection failure
    AUTHENTICATION_ERROR      = 4   # Authentication/credential failure
    RESOURCE_NOT_FOUND        = 5   # Cluster, host, domain, or image not found
    OPERATION_FAILED          = 6   # Operation (transition, import, compliance) failed
    TASK_FAILED               = 7   # Background task failed or timed out
    CONFIGURATION_ERROR       = 8   # JSON or configuration file error
    PRECONDITION_ERROR        = 9   # Prerequisites not met (modules, versions, etc.)
    USER_CANCELLED            = 10  # User cancelled operation
    # Aliases mapped to canonical codes for backward compatibility.
    INVALID_ARGUMENTS         = 2   # Maps to PARAMETER_ERROR
    FILE_NOT_FOUND            = 8   # Maps to CONFIGURATION_ERROR
    VCENTER_CONNECTION_ERROR  = 3   # Maps to CONNECTION_ERROR
    VERSION_ERROR             = 9   # Maps to PRECONDITION_ERROR
}

#region Parameter Validation
Function Test-ParameterValidation {

    <#
        .SYNOPSIS
        Validates script parameters and parameter combinations for common errors.

        .DESCRIPTION
        This function performs comprehensive parameter validation to catch common
        parameter errors early and provide helpful error messages to users.

        Validation includes:
        - File path existence checks
        - Format validation (cluster names, domain names, host names, IPs, UUIDs)
        - Enum validation (ResourceType must be exact values)
        - Mutually exclusive parameter detection
        - Required parameter combination enforcement

        Format Rules:
        - Cluster names: 1-80 chars, letters/numbers/spaces/_ + - ( )
        - Workload domain names: Same as cluster names
        - Host names (for Standalone Host): Valid FQDN or IPv4 address
        - ResourceType: Must be 'Cluster' or 'Standalone Host' (case-sensitive)

        .OUTPUTS
        None
        This function does not return any value. It exits the script with Exit-WithCode if validation fails.
        If all validations pass, the function completes silently and script execution continues.

        .NOTES
        This function exits the script with error code 2 (PARAMETER_ERROR) if validation fails.
        All validation happens before any API calls to fail fast.
    #>

    Write-LogMessage -Type DEBUG -Message "Entered Test-ParameterValidation function..."

    # Note: PowerShell's -match operator is case-insensitive by default, but we explicitly include
    # both [a-z] and [A-Z] in regex patterns for clarity and portability. Use -cmatch for case-sensitive matching.

    # Validate that file paths exist when specified.
    if ($JsonInput -and (-not (Test-Path $JsonInput))) {
        Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR -Message "JsonInput file '$JsonInput' does not exist."
    }

    # Validate that the JsonOutput directory exists.
    if ($JsonOutput) {
        $JsonOutputDir = Split-Path $JsonOutput -Parent
        if ($JsonOutputDir -and (-not (Test-Path $JsonOutputDir))) {
            Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR -Message "Output directory for JsonOutput '$JsonOutputDir' does not exist."
        }
    }

    # Validate workload domain name format (same rules as cluster names)
    if ($WorkloadDomainName) {
        if ($WorkloadDomainName -notmatch '^[a-zA-Z0-9\s_+\-()]{1,80}$') {
            Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR -Message "WorkloadDomainName '$WorkloadDomainName' is invalid. Must be 1-80 characters using only: letters, numbers, spaces, _ + - ( )"
        }
    }

    # Validate ResourceName format (context-dependent: hostname/FQDN/IP for hosts, cluster name for clusters)
    if ($ResourceName) {
        switch ($ResourceType) {
            "Standalone Host" {
                # For standalone hosts, ResourceName can be FQDN or IP address.
                $isFqdn = $ResourceName -match '^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$'
                $isIpv4 = $ResourceName -match '^((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)$'
                if (-not ($isFqdn -or $isIpv4)) {
                    Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR -Message "ResourceName `"$ResourceName`" for Standalone Host must be a valid FQDN or IPv4 address."
                }
            }
            "Cluster" {
                # For clusters, ResourceName follows cluster name rules.
                if ($ResourceName -notmatch '^[a-zA-Z0-9\s_+\-()]{1,80}$') {
                    Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR -Message "ResourceName '$ResourceName' for Cluster is invalid. Must be 1-80 characters using only: letters, numbers, spaces, _ + - ( )"
                }
            }
        }
    }

    # Validate vCenter name format (should be FQDN or IP).
    if ($VcenterName) {
        $isFqdn = $VcenterName -match '^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)+$'
        $isIpv4 = $VcenterName -match '^((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)$'

        if (-not ($isFqdn -or $isIpv4)) {
            Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR -Message "VcenterName `"$VcenterName`" is not a valid FQDN or IPv4 address."
        }
    }

    # Validate TaskId format (should be UUID-like)
    if ($TaskId -and ($TaskId -notmatch '^[0-9a-fA-F-]{36}$')) {
        Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR -Message "TaskId '$TaskId' is not a valid UUID format."
    }

    # Validate mutually exclusive parameter combinations.
    $exclusiveParams = @(
        'CollectLogs', 'Connect', 'Disconnect', 'TransitionResource', 'ComplianceCheck',
        'ReviewComplianceResults', 'CheckTaskStatus', 'CheckTransitions',
        'ShowBaselineResources', 'ShowImagesInSddcManager', 'ShowImagesInVcenter',
        'ImportImagesFromVcenter', 'DeleteImageFromSddcManager',
        'DeleteTemporaryCluster', 'RetryTransition', 'Help', 'Version'
    )

    # Use Where-Object for more efficient filtering. Wrap in @() to guarantee an array under Set-StrictMode.
    $selectedParams = @($exclusiveParams | Where-Object {
        $var = Get-Variable -Name $_ -ErrorAction SilentlyContinue
        $var -and $var.Value
    })

    if ($selectedParams.Count -gt 1) {
        Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR -Message "Multiple exclusive operations specified: $($selectedParams -join ', '). Please specify only one operation."
    }

    # Validate required parameter combinations.
    if ($ComplianceCheck -and (-not $ResourceName -and -not $JsonInput)) {
        Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR -Message "ComplianceCheck requires either -ResourceName or -JsonInput parameter."
    }

    if ($TransitionResource -and (-not $JsonInput -and -not $ResourceName)) {
        Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR -Message "TransitionResource requires either -JsonInput or -ResourceName parameter."
    }

    if ($CheckTaskStatus -and -not $TaskType) {
        Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR -Message "CheckTaskStatus requires -TaskType parameter."
    }

    if ($RetryTransition -and -not $TaskId) {
        Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR -Message "RetryTransition requires -TaskId parameter."
    }

    # If ResourceName is specified (without JsonInput), require WorkloadDomainName and ResourceType.
    if ($ResourceName -and -not $JsonInput) {
        if (-not $WorkloadDomainName) {
            Write-LogMessage -Type ERROR -Message "-ResourceName requires -WorkloadDomainName parameter."
            Write-LogMessage -Type ADVISORY -Message "Example: -ResourceName `"m01-cl01`" -WorkloadDomainName `"m01`" -ResourceType `"Cluster`""
            Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR
        }
        if (-not $ResourceType) {
            Write-LogMessage -Type ERROR -Message "-ResourceName requires -ResourceType parameter (`"Cluster`" or `"Standalone Host`")."
            Write-LogMessage -Type ADVISORY -Message "Example: -ResourceName 'm01-cl01' -WorkloadDomainName 'm01' -ResourceType 'Cluster'"
            Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR
        }
    }

    # If SddcManagerImageName is specified for compliance checks or transitions, require WorkloadDomainName.
    # Note: DeleteImageFromSddcManager and ImportImagesFromVcenter do not require (or use) WorkloadDomainName.
    if ($SddcManagerImageName -and -not $WorkloadDomainName -and -not $JsonInput -and -not $DeleteImageFromSddcManager -and -not $ImportImagesFromVcenter) {
        Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR -Message "-SddcManagerImageName requires -WorkloadDomainName parameter."
    }

    # If SddcManagerImageName is specified with ImportImagesFromVcenter, provide helpful error.
    if ($SddcManagerImageName -and $ImportImagesFromVcenter) {
        Write-LogMessage -Type ERROR -Message "-SddcManagerImageName cannot be used with -ImportImagesFromVcenter."
        Write-LogMessage -Type ADVISORY -Message "-ImportImagesFromVcenter uses -VcenterImageName (source cluster/image in vCenter) and -VcenterName (vCenter FQDN)."
        Write-LogMessage -Type ADVISORY -Message "The imported image will be named based on the source cluster name in vCenter."
        Write-LogMessage -Type ADVISORY -Message "Example: -ImportImagesFromVcenter -VcenterImageName `"m01-cl01`" -VcenterName `"vcenter-1.example.com`""
        Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR
    }

    Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Parameter validation completed successfully."
}
Function Show-AnyKey {

    <#
        .SYNOPSIS
        The function Show-AnyKey requires the user press a key before continuing.

        .DESCRIPTION
        When this script is run in interactive mode (rather than headless), this function is called
        to invite the user to press a key and return to the original function or menu, after
        reading an informational message.

        The function includes fallback mechanisms for environments where RawUI is not available.

        .OUTPUTS
        None
        This function does not return any value. It waits for user input in interactive mode,
        or completes immediately in headless mode.
    #>

    Write-LogMessage -Type DEBUG -Message "Entered Show-AnyKey function..."

    # Function Show-AnyKey is not required in headless mode.
    if (-not $Script:Headless) {
        Write-Host "Press any key to continue..." -ForegroundColor Yellow

        try {
            # Try to use RawUI.ReadKey (preferred method - doesn't echo character).
            if ($Host.UI -and $Host.UI.RawUI) {
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            } else {
                # Fallback to Read-Host if RawUI is not available.
                Write-LogMessage -Type DEBUG -Message "RawUI not available, using Read-Host fallback."
                $null = Read-Host "Press Enter to continue"
            }
        } catch {
            # If both fail, log and continue (don't crash the script).
            Write-LogMessage -Type WARNING -Message "Unable to read keyboard input: $_. Continuing..."
            Start-Sleep -Seconds 2
        }
    }
}
#endregion

#region Helpers and Logging
Function Get-SddcManagerVersion {

    <#
        .SYNOPSIS
        The function Get-SddcManagerVersion returns a portion of SDDC Manager release.

        .DESCRIPTION
        The first four version components (Major.Minor.Build.Revision) are extracted from
        the SDDC Manager ProductVersion and returned as a System.Version object.

        .EXAMPLE
        $Version = Get-SddcManagerVersion
        # Returns [version]"9.0.0.0"

        .EXAMPLE
        if ((Get-SddcManagerVersion) -ge [version]"9.0.0.0") {
            Write-Host "SDDC Manager 9.0 or later"
        }

        .OUTPUTS
        System.Version
        Returns the SDDC Manager version as a System.Version object, or exits the script on failure.
    #>

    Write-LogMessage -Type DEBUG -Message "Entered Get-SddcManagerVersion function..."

    # Verify connection exists using Get-Variable to avoid StrictMode errors before any connection is made.
    $sddcConnVar = Get-Variable -Name 'defaultSddcManagerConnections' -ErrorAction SilentlyContinue
    if (-not $sddcConnVar -or -not $sddcConnVar.Value) {
        Write-LogMessage -Type ERROR -Message "Not connected to SDDC Manager. Use -Connect parameter first."
        Exit-WithCode -ExitCode $Script:ExitCodes.CONNECTION_ERROR -Message "SDDC Manager connection required."
    }

    # Get version from connection object property (populated by Connect-VcfSddcManagerServer).
    $sddcManagerVersion = $sddcConnVar.Value.ProductVersion

    # Fall back to the appliance info API if the connection object property is not populated.
    if ([string]::IsNullOrEmpty($sddcManagerVersion)) {
        Write-LogMessage -Type DEBUG -Message "ProductVersion not available on connection object. Querying Invoke-VcfGetApplianceInfo..."
        $applianceInfo = Invoke-VcfGetApplianceInfo -ErrorAction SilentlyContinue
        $sddcManagerVersion = if ($applianceInfo -and $applianceInfo.PSObject.Properties['Version']) { $applianceInfo.Version } else { $null }
    }

    if ([string]::IsNullOrEmpty($sddcManagerVersion)) {
        Write-LogMessage -Type ERROR -Message "Unable to retrieve SDDC Manager version from connection or appliance info API."
        Exit-WithCode -ExitCode $Script:ExitCodes.CONNECTION_ERROR -Message "SDDC Manager version unavailable."
    }

    Write-LogMessage -Type DEBUG -Message "Full SDDC Manager version: $sddcManagerVersion"

    # PowerShell [version] type supports 4 components (Major.Minor.Build.Revision).
    # Extract first 4 version segments from SDDC Manager version string.
    if ($sddcManagerVersion -match '^(\d+\.\d+\.\d+\.\d+)') {
        $sanitizedSddcManagerVersion = $Matches[1]
    } else {
        Write-LogMessage -Type ERROR -Message "Unable to parse version from: $sddcManagerVersion"
        Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR -Message "Invalid SDDC Manager version format."
    }

    # Convert to [version] type and return.
    try {
        $VersionObject = [version]$sanitizedSddcManagerVersion
        return $VersionObject
    } catch {
        Write-LogMessage -Type ERROR -Message "Invalid version format: $sanitizedSddcManagerVersion - $_"
        Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR -Message "Cannot convert to System.Version."
    }
}
Function Get-VcenterImageSeedingSupport {

    <#
        .SYNOPSIS
        The function Get-VcenterImageSeedingSupport checks if a given vCenter supports image seeding.

        .DESCRIPTION
        Returns $true if the vCenter supports vLCM image seeding (version >= minimum required), $false otherwise.
        This function retrieves the vCenter version from SDDC Manager and compares it to the minimum required version.

        .PARAMETER MinimumVcenterVersion
        Specifies the minimum vCenter version required for vLCM image seeding support (e.g., "8.0.3").

        .PARAMETER VcenterId
        Specifies the vCenter ID (GUID) as registered in SDDC Manager.

        .EXAMPLE
        Get-VcenterImageSeedingSupport -VcenterId "b5763149-7a43-4a82-bd87-ef1dd32bdf74" -MinimumVcenterVersion "8.0.3"
        Returns $true if vCenter version >= 8.0.3, $false otherwise.

        .OUTPUTS
        Boolean
        Returns $true if vCenter supports vLCM image seeding (version >= minimum required), $false otherwise.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$MinimumVcenterVersion,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$VcenterId
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-VcenterImageSeedingSupport function for vCenter Id: $VcenterId"

    $processTimer = Start-ProcessTimer

    try {
        # Retrieve vCenter information (single API call for both version and name).
        $vcenterInfo = Invoke-VcfGetVcenter -Id $VcenterId -ErrorAction Stop
        $vcenterVersion = $vcenterInfo.Version
        $vcenterName = $vcenterInfo.Fqdn
    } catch {
        if ($_.Exception.Message -match "is not recognized as.*name of a cmdlet") {
            Write-LogMessage -Type ERROR -Message "VCF.PowerCLI cmdlet 'Invoke-VcfGetVcenter' not found. Please ensure VCF.PowerCLI $minimumVcfPowerCliVersion or later is installed."
            Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
        }
        Stop-ProcessTimer -Timer $processTimer -Operation "vCenter lookup (FAILED)" -Interval "Milliseconds"
        Write-LogMessage -Type ERROR -Message "Error looking up vCenter for vCenter Id $VcenterId : $_"
        return $false
    }

    # Validate version is not null or empty.
    if ([string]::IsNullOrEmpty($vcenterVersion)) {
        Stop-ProcessTimer -Timer $processTimer -Operation "vCenter lookup (NULL VERSION)" -Interval "Milliseconds"
        Write-LogMessage -Type ERROR -Message "vCenter version is null or empty for vCenter `"$vcenterName`" (Id: $VcenterId)"
        return $false
    }

    Stop-ProcessTimer -Timer $processTimer -Operation "Lookup operation for vCenter `"$vcenterName`" which runs version `"$vcenterVersion`"" -Interval "Milliseconds"

    Write-LogMessage -Type DEBUG -Message "vCenter `"$vcenterName`" version: $vcenterVersion (minimum required: $MinimumVcenterVersion)"

    # Extract first 3 version components (Major.Minor.Patch) using simple regex match.
    if ($vcenterVersion -match '^(\d+\.\d+\.\d+)') {
        $sanitizedVcenterVersion = $Matches[1]
    } else {
        Write-LogMessage -Type ERROR -Message "Invalid vCenter version format for `"$vcenterName`": $vcenterVersion"
        return $false
    }

    # Compare versions and return result.
    try {
        $result = ([version]$sanitizedVcenterVersion -ge [version]$MinimumVcenterVersion)
        Write-LogMessage -Type DEBUG -Message "Image seeding support for vCenter `"$vcenterName`": $result"
        return $result
    } catch {
        Write-LogMessage -Type ERROR -Message "Error comparing versions: $sanitizedVcenterVersion vs $MinimumVcenterVersion - $_"
        return $false
    }
}
Function Get-EsxImageSeedingSupport {

    <#
        .SYNOPSIS
        The function Get-EsxImageSeedingSupport checks if all the hosts in a cluster or standalone host support image seeding.

        .DESCRIPTION
        For clusters: Verifies that ESX versions are homogeneous and match a version that supports image seeding.
        For standalone hosts: Validates the provided ESX version meets the minimum requirement.

        Returns $true if the cluster/host supports vLCM image seeding, $false otherwise.

        .PARAMETER ClusterId
        Specifies the ESX Cluster ID (GUID). Use this parameter to check an entire cluster.

        .PARAMETER EsxVersion
        Specifies the ESX version string (e.g., "8.0.3-24280767"). Use this parameter for standalone hosts.

        .PARAMETER MinimumEsxVersion
        Specifies the minimum ESX version required for image seeding support (e.g., "8.0.3").

        .EXAMPLE
        Get-EsxImageSeedingSupport -ClusterId "6ebc34a8-055c-439e-947c-9c64a163081e" -MinimumEsxVersion "8.0.3"
        Returns $true if all hosts in cluster run ESX >= 8.0.3 with homogeneous versions.

        .EXAMPLE
        Get-EsxImageSeedingSupport -EsxVersion "8.0.3-24280767" -MinimumEsxVersion "8.0.3"
        Returns $true if ESX version >= 8.0.3.

        .OUTPUTS
        Boolean
        Returns $true if the ESX cluster/host supports vLCM image seeding (version >= minimum required), $false otherwise.
    #>

    Param (
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$ClusterId,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$EsxVersion,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$MinimumEsxVersion
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-EsxImageSeedingSupport function..."

    if ($ClusterId) {
        # Cluster mode: Check all hosts for version homogeneity.

        try {
            # Single API call for cluster information.
            $clusterInfo = Invoke-VcfGetCluster -id $ClusterId -ErrorAction Stop
            $clusterName = $clusterInfo.Name
            $vcenterName = $clusterInfo.Vcenter.Fqdn
        } catch {
            Write-LogMessage -Type ERROR -Message "Error looking up cluster for cluster Id $ClusterId : $_"
            return $false
        }

        Write-LogMessage -Type DEBUG -Message "Checking image seeding support for cluster `"$clusterName`" on vCenter `"$vcenterName`""

        $processTimer = Start-ProcessTimer

        try {
            $hostsInfo = Invoke-VcfGetHosts -ClusterId $ClusterId -ErrorAction Stop
            [array]$esxReleases = if ($hostsInfo -and $hostsInfo.PSObject.Properties['Elements'] -and $hostsInfo.Elements) { @($hostsInfo.Elements | Select-Object -ExpandProperty EsxiVersion) } else { @() }
        } catch {
            Stop-ProcessTimer -Timer $processTimer -Operation "Host lookup (FAILED)" -Interval "Milliseconds"
            Write-LogMessage -Type ERROR -Message "Error looking up hosts in cluster `"$clusterName`" : $_"
            return $false
        }

        # Validate we got host data.
        if (-not $esxReleases -or $esxReleases.Count -eq 0) {
            Stop-ProcessTimer -Timer $processTimer -Operation "Host lookup (NO HOSTS)" -Interval "Milliseconds"
            Write-LogMessage -Type ERROR -Message "No hosts found in cluster `"$clusterName`" (Id: $ClusterId)"
            return $false
        }

        $hostCount = $esxReleases.Count
        [array]$uniqueReleases = @($esxReleases | Get-Unique)

        # If there are different ESX versions in the cluster, image seeding is not supported.
        if ($uniqueReleases.Count -ne 1) {
            Stop-ProcessTimer -Timer $processTimer -Operation "ESX version lookup (HETEROGENEOUS)" -Interval "Milliseconds"
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Image seeding not supported on cluster `"$clusterName`" on vCenter `"$vcenterName`" due to $($uniqueReleases.Count) different ESX versions in the cluster."
            return $false
        }

        Stop-ProcessTimer -Timer $processTimer -Operation "Lookup time for gathering ESX versions" -Interval "Milliseconds"
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "$hostCount host(s) running ESX version `"$($uniqueReleases[0])`" on cluster `"$clusterName`" on vCenter `"$vcenterName`"."

        # Extract first 3 version components (Major.Minor.Patch) using simple regex match.
        # Use the scalar value from $uniqueReleases (guaranteed single element at this point).
        $esxVersionString = [string]$uniqueReleases[0]
        if ($esxVersionString -match '^(\d+\.\d+\.\d+)') {
            $sanitizedEsxVersion = $Matches[1]
        } else {
            Write-LogMessage -Type ERROR -Message "Invalid ESX version format in cluster `"$clusterName`": $esxVersionString"
            return $false
        }

    } elseif ($EsxVersion) {
        # Standalone host mode: Check provided version.

        Write-LogMessage -Type DEBUG -Message "Checking image seeding support for ESX version: $EsxVersion"

        # Extract first 3 version components (Major.Minor.Patch) using simple regex match.
        if ($EsxVersion -match '^(\d+\.\d+\.\d+)') {
            $sanitizedEsxVersion = $Matches[1]
        } else {
            Write-LogMessage -Type ERROR -Message "Invalid ESX version format: $EsxVersion"
            return $false
        }

    } else {
        # Neither parameter provided - invalid call.
        Write-LogMessage -Type ERROR -Message "Function Get-EsxImageSeedingSupport requires either -ClusterId or -EsxVersion parameter."
        return $false
    }

    # Compare versions and return result.
    try {
        $result = ([version]$sanitizedEsxVersion -ge [version]$MinimumEsxVersion)
        Write-LogMessage -Type DEBUG -Message "Image seeding support check result: $result (ESX version $sanitizedEsxVersion vs minimum ESX version $MinimumEsxVersion)"
        return $result
    } catch {
        Write-LogMessage -Type ERROR -Message "Error comparing ESX versions: $sanitizedEsxVersion vs $MinimumEsxVersion - $_"
        return $false
    }
}
Function New-ChoiceMenu {

    <#
        .SYNOPSIS
        The function New-ChoiceMenu presents a yes/no decision prompt to the user.

        .DESCRIPTION
        The function takes in two mandatory values, a question (which prefaces the choice) and a
        default answer in the form of "Yes" or "No" (case-insensitive). The user's answer is
        returned as an index (0 for Yes, 1 for No) to the calling function.

        If the function is called in a non-interactive environment, it automatically returns
        the default answer without prompting.

        .PARAMETER DefaultAnswer
        Specifies what answer (Yes or No) is chosen if a user hits Enter rather than selecting Y/N.
        Case-insensitive. Valid values: "Yes", "No".

        .PARAMETER Question
        Specifies the question to present to the user.

        .EXAMPLE
        $decision = New-ChoiceMenu -Question "Would you like to create $logFolder" -DefaultAnswer "Yes"
        Prompts user with default set to Yes. Returns 0 if Yes selected, 1 if No selected.

        .EXAMPLE
        if ((New-ChoiceMenu -Question "Continue?" -DefaultAnswer "No") -eq 0) {
            Write-Host "User chose Yes"
        }
        Example showing inline usage with comparison.

        .OUTPUTS
        Int32
        Returns the index of the selected choice:
          - 0 if user selects Yes
          - 1 if user selects No
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateSet("Yes", "No")] [String]$DefaultAnswer,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Question
    )

    Write-LogMessage -Type DEBUG -Message "Entered New-ChoiceMenu function with question: `"$Question`", defaultAnswer: $DefaultAnswer"

    # Determine default choice index.
    $defaultChoice = if ($DefaultAnswer -eq "Yes") { 0 } else { 1 }

    try {
        # Check if UI is available (may not be in non-interactive sessions).
        if (-not $Host.UI) {
            Write-LogMessage -Type WARNING -Message "No UI available for PromptForChoice. Defaulting to: $DefaultAnswer"
            Write-LogMessage -Type DEBUG -Message "Returning default choice: $defaultChoice"
            return $defaultChoice
        }

        # Create choice descriptions.
        $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes', "Yes"))
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No', "No"))

        # Present choice to user (empty title, question as message, choices array, default index).
        $decision = $Host.UI.PromptForChoice("", $Question, $choices, $defaultChoice)

        $selectedAnswer = if ($decision -eq 0) { "Yes" } else { "No" }
        Write-LogMessage -Type DEBUG -Message "User selected: $selectedAnswer (index: $decision)"

        return $decision

    } catch {
        # Fallback to default if any error occurs.
        Write-LogMessage -Type WARNING -Message "Error prompting for choice, defaulting to $DefaultAnswer : $_"
        Write-LogMessage -Type DEBUG -Message "Returning default choice: $defaultChoice"
        return $defaultChoice
    }
}
Function New-LogFile {

    <#
        .SYNOPSIS
        At script launch, the function New-LogFile creates a log file if not already present.

        .DESCRIPTION
        The function New-LogFile creates a log file in logs sub-directory off of the PSScriptRoot directory
        with a timestamp in the format of Month-Day-Year. Should a logs sub-directory already exist, logs
        for this script may be identified by the prefix "VcfBaselineClusterTransition-"

        This function sets the script-level variables $Script:LogFile and $Script:LogFolder.

        .EXAMPLE
        New-LogFile
        Creates the log directory and daily log file, setting script-level variables.

        .OUTPUTS
        None
        The function sets script-level variables $Script:LogFile and $Script:LogFolder.
    #>

    # Create one log file for each day the script is run.
    $fileTimeStamp = Get-Date -Format "MM-dd-yyyy"
    $Script:LogFolder = Join-Path -Path $PSScriptRoot -ChildPath 'logs'
    $Script:LogFile = Join-Path -Path $Script:LogFolder -ChildPath "VcfBaselineClusterTransition-$fileTimeStamp.log"

    # Create log directory if it doesn't exist.
    if (-not (Test-Path $Script:LogFolder)) {
        Write-Host "Log directory not found, creating $Script:LogFolder" -ForegroundColor Yellow

        try {
            New-Item -ItemType Directory -Path $Script:LogFolder -ErrorAction Stop | Out-Null
            Write-Host "Log directory created successfully: $Script:LogFolder" -ForegroundColor Green
        } catch {
            Write-Host "Failed to create log directory: $Script:LogFolder - $_" -ForegroundColor Red
            Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
        }
    }

    # Create the log file if not already present.
    # Every time the log file is created, query the environmental settings and log them.
    if (-not (Test-Path $Script:LogFile)) {
        try {
            New-Item -Type File -Path $Script:LogFile -ErrorAction Stop | Out-Null
            Write-Host "Log file created: $Script:LogFile" -ForegroundColor Green
            Get-EnvironmentSetup
            Write-LogMessage -Type DEBUG -Message "Log file initialized: $Script:LogFile"
        } catch {
            Write-Host "Failed to create log file: $Script:LogFile - $_" -ForegroundColor Red
            Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
        }
    } else {
        Write-LogMessage -Type DEBUG -Message "Using existing log file: $Script:LogFile"
    }
}

Function ConvertFrom-JsonSafely {

    <#
        .SYNOPSIS
        Safely loads and validates JSON content from a file with structured error handling.

        .DESCRIPTION
        This helper function provides standardized JSON file loading and validation with
        comprehensive error handling. It returns a structured result object that allows
        callers to decide how to handle errors.

        The function performs three validations:
        1. File existence check
        2. JSON format/syntax validation
        3. Content parsing

        USAGE GUIDELINES:
        - Always check the Success property of the returned result
        - Caller decides whether to exit script, retry, or propagate error
        - Use for all JSON configuration file loading

        .PARAMETER JsonFilePath
        Path to the JSON file to load and parse.

        .PARAMETER VariableName
        Name of the variable being loaded (used in error messages for context).

        .EXAMPLE
        # Standard usage pattern.
        $result = ConvertFrom-JsonSafely -JsonFilePath $JsonInputFile -VariableName "ResourceInputs"
        if (-not $result.Success) {
            Write-LogMessage -Type ERROR -Message "Failed to load JSON: $($result.ErrorMessage)"
            Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR
        }
        $data = $result.JsonData

        .EXAMPLE
        # Loading configuration with error handling.
        $result = ConvertFrom-JsonSafely -JsonFilePath "config.json" -VariableName "Configuration"
        if (-not $result.Success) {
            if ($result.ErrorCode -eq "ERR_FILE_NOT_FOUND") {
                Write-LogMessage -Type ERROR -Message "Config file not found. Please create config.json"
            } else {
                Write-LogMessage -Type ERROR -Message "Invalid JSON format: $($result.ErrorMessage)"
            }
            Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR
        }

        .OUTPUTS
        PSCustomObject
        Returns a hashtable with the following structure:
        - On Success: @{ Success = $true; JsonData = <parsed JSON object> }
        - On Failure: @{ Success = $false; ErrorMessage = <string>; ErrorCode = <string> }

        .NOTES
        Error Handling: This function returns structured error objects instead of throwing
        exceptions or calling exit. This allows the caller to decide how to handle errors.

        Error Codes:
        - ERR_FILE_NOT_FOUND: JSON file does not exist at specified path
        - ERR_JSON_FORMAT: Invalid JSON syntax (malformed JSON)
        - ERR_JSON_PARSE: Other parsing errors (permissions, encoding, etc.)
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$JsonFilePath,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$VariableName
    )

    Write-LogMessage -Type DEBUG -Message "Entered ConvertFrom-JsonSafely function..."

    # Helper function to format friendly JSON error messages.
    function Get-FriendlyJsonError {
        Param (
            [Parameter(Mandatory = $true)] [String]$ErrorMessage,
            [Parameter(Mandatory = $true)] [String]$JsonFilePath,
            [Parameter(Mandatory = $true)] [String]$VariableName
        )
        $friendlyMessage = "JSON parsing failed for file $JsonFilePath (Variable: $VariableName)."

        # Extract line number and position if available.
        if ($ErrorMessage -match "line (\d+), position (\d+)") {
            $lineNum = [int]$matches[1]
            $position = [int]$matches[2]

            # Common patterns to provide specific guidance.
            if ($ErrorMessage -match "After parsing a value an unexpected character was encountered") {
                $friendlyMessage += "`n`nCommon causes:`n"
                $friendlyMessage += "  - Missing comma at the end of line $($lineNum - 1) (check the line BEFORE line $lineNum)`n"
                $friendlyMessage += "  - Extra comma after the last property in an object`n"
                $friendlyMessage += "  - Unexpected character at line $lineNum, position $position"
            } else {
                $friendlyMessage += " Error near line $lineNum, position $position."
            }
        }

        $friendlyMessage += "`n`nTroubleshooting tips:`n"
        $friendlyMessage += "  1. Verify all property lines (except the last) end with a comma`n"
        $friendlyMessage += "  2. Check for matching opening/closing braces { }`n"
        $friendlyMessage += "  3. Ensure all strings are properly quoted with double quotes`n"
        $friendlyMessage += "  4. Validate JSON syntax using an online utility like https://jsonlint.com/`n"
        $friendlyMessage += "`nRaw error: $ErrorMessage"

        return $friendlyMessage
    }

    # Validate file exists before attempting to read.
    if (-not (Test-Path -Path $JsonFilePath)) {
        return Write-ErrorAndReturn `
            -ErrorMessage "JSON file not found: $JsonFilePath (Variable: $VariableName)" `
            -ErrorCode "ERR_FILE_NOT_FOUND"
    }

    try {
        # Load file content, remove empty lines, and parse JSON.
        $jsonData = (Get-Content -Path $JsonFilePath -ErrorAction Stop) |
            Select-String -Pattern "^\s*$" -NotMatch |
            ConvertFrom-Json -ErrorAction Stop

        # Count items if it's an array, or note it's a single object.
        $itemCount = if ($jsonData -is [array]) { $jsonData.Count } else { 1 }
        Write-LogMessage -Type DEBUG -Message "Successfully parsed JSON file `"$JsonFilePath`": $itemCount item(s) loaded for variable `"$VariableName`""

        return @{
            Success = $true
            JsonData = $jsonData
        }
    }
    catch [System.ArgumentException] {
        # Specific handling for JSON format errors.
        $friendlyMessage = Get-FriendlyJsonError -ErrorMessage $_.Exception.Message -JsonFilePath $JsonFilePath -VariableName $VariableName
        return Write-ErrorAndReturn `
            -ErrorMessage $friendlyMessage `
            -ErrorCode "ERR_JSON_FORMAT"
    }
    catch [System.Management.Automation.RuntimeException] {
        # Handles ConvertFrom-Json failures.
        if ($_.Exception.Message -match "Conversion from JSON failed") {
            $friendlyMessage = Get-FriendlyJsonError -ErrorMessage $_.Exception.Message -JsonFilePath $JsonFilePath -VariableName $VariableName
            return Write-ErrorAndReturn `
                -ErrorMessage $friendlyMessage `
                -ErrorCode "ERR_JSON_FORMAT"
        }
        # Other runtime exceptions.
        return Write-ErrorAndReturn `
            -ErrorMessage "Failed to parse JSON file $JsonFilePath (Variable: $VariableName): $($_.Exception.Message)" `
            -ErrorCode "ERR_JSON_PARSE"
    }
    catch {
        # Catch-all for unexpected errors (file permissions, encoding issues, etc.)
        return Write-ErrorAndReturn `
            -ErrorMessage "Unexpected error loading JSON file $JsonFilePath (Variable: $VariableName): $($_.Exception.Message)" `
            -ErrorCode "ERR_JSON_PARSE"
    }
}
Function Start-ProcessTimer {

    <#
        .SYNOPSIS
        Starts a process timer and returns the stopwatch object.

        .DESCRIPTION
        This helper function reduces code duplication by providing a standard way to
        start timing operations. Returns a started Stopwatch object ready for timing.

        .EXAMPLE
        $timer = Start-ProcessTimer
        # ... perform operation ...
        Stop-ProcessTimer -Timer $timer -Operation "My operation" -Interval "Seconds"

        .OUTPUTS
        System.Diagnostics.Stopwatch
        Returns a started Stopwatch object for timing operations.
    #>

    return [System.Diagnostics.Stopwatch]::StartNew()
}
Function Stop-ProcessTimer {

    <#
        .SYNOPSIS
        Stops a process timer and logs the elapsed time.

        .DESCRIPTION
        This helper function reduces code duplication by providing a standard way to
        stop timing operations and log results. Logs the elapsed time at INFO level
        (suppressed from console output).

        .PARAMETER Interval
        Time unit for display: "Milliseconds", "Seconds", or "Minutes".

        .PARAMETER Operation
        Description of the operation being timed (used in log message).

        .PARAMETER Timer
        The stopwatch object to stop.

        .EXAMPLE
        $timer = Start-ProcessTimer
        # ... perform operation ...
        Stop-ProcessTimer -Timer $timer -Operation "vCenter connection" -Interval "Seconds"
        Logs: "vCenter connection took 1.23 Seconds to complete."

        .OUTPUTS
        None
        This function does not return a value. It stops the timer and logs the elapsed time.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)] [ValidateSet("Milliseconds", "Seconds", "Minutes")] [String]$Interval,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Operation,
        [Parameter(Mandatory = $true)] [System.Diagnostics.Stopwatch]$Timer
    )

    if (-not $PSCmdlet.ShouldProcess("Process timer for operation: $Operation", "Stop")) {
        return
    }

    $Timer.Stop()

    $elapsedInterval = 0
    switch ($Interval) {
        "Milliseconds" {
            $elapsedInterval = [math]::Round($Timer.Elapsed.TotalMilliseconds, 2)
        }
        "Seconds" {
            $elapsedInterval = [math]::Round($Timer.Elapsed.TotalSeconds, 2)
        }
        "Minutes" {
            $elapsedInterval = [math]::Round($Timer.Elapsed.TotalMinutes, 2)
        }
    }

    Write-LogMessage -Type DEBUG -Message "$Operation took $elapsedInterval $Interval to complete."
}
Function Find-ExistingTask {

    <#
        .SYNOPSIS
        Checks if a Task exists for an existing ResourceId. Returns True if a duplicate task is found, false if not found.

        .DESCRIPTION
        Used for compliance and transition tasks where standalone host operations otherwise do not fast-fail.
        This function prevents duplicate task submissions by checking for existing in-progress tasks.

        .PARAMETER ClusterTaskType
        The TaskType associated with a Cluster transition or compliance task.

        .PARAMETER Operation
        A human readable description of the operation being performed.

        .PARAMETER ResourceId
        The Id associated with a cluster or standalone host.

        .PARAMETER ResourceName
        The name of the cluster or standalone host.

        .PARAMETER ResourceType
        "Cluster" or "Standalone Host"

        .PARAMETER StandAloneHostTaskType
        The TaskType associated with a Standalone host transition or compliance task.

        .PARAMETER SuppressVerboseWarning
        Suppresses the verbose WARNING message about existing tasks. When enabled, only a DEBUG message is logged.
        Useful when checking multiple resources in batch where individual warnings would be too verbose.

        .PARAMETER WorkloadDomainName
        The workload domain name for the resource.

        .EXAMPLE
        $exists = Find-ExistingTask -ClusterTaskType "VLCM_TRANSITION" -Operation "Compliance Check" -ResourceId "279d82ee-..." -ResourceName "esx-01.example.com" -ResourceType "Standalone Host" -WorkloadDomainName "w01" -StandAloneHostTaskType "DOMAIN_VLCM_TRANSITION"
        if ($exists) {
            Write-Host "Task already in progress, skipping."
        }

        .OUTPUTS
        Boolean
        Returns $true if an existing in-progress task is found (resource should be skipped), $false otherwise.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ClusterTaskType,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Operation,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ResourceId,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ResourceName,
        [Parameter(Mandatory = $true)] [ValidateSet("Cluster", "Standalone Host")] [String]$ResourceType,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$StandAloneHostTaskType,
        [Parameter(Mandatory = $false)] [Switch]$SuppressVerboseWarning,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$WorkloadDomainName
    )

    Write-LogMessage -Type DEBUG -Message "Entered Find-ExistingTask function..."

    # Query for existing in-progress tasks.
    $existingCheckId = $null
    $inProgressTasksResult = Invoke-VcfGetTasks -TaskStatus "In Progress" -ErrorAction SilentlyContinue
    # Wrap in @() to guarantee an array regardless of whether the API returns one or many elements.
    # VCF PowerCLI 9 returns strongly-typed objects (not PSCustomObject), so omit the -is [PSCustomObject] guard.
    # Use a try/catch inside Where-Object to tolerate any element whose property access throws.
    [array]$inProgressElements = if ($inProgressTasksResult -and $inProgressTasksResult.PSObject.Properties['Elements'] -and $inProgressTasksResult.Elements) {
        @($inProgressTasksResult.Elements) | Where-Object {
            $item = $_
            try { $null -ne $item.Type -and $null -ne $item.Resources } catch { $false }
        }
    } else { @() }
    switch ($ResourceType) {
        "Cluster" {
            $matchedTask = $inProgressElements | Where-Object {
                try { $_.Type -eq $ClusterTaskType -and $_.Resources.ResourceId -eq $ResourceId } catch { $false }
            } | Select-Object -First 1
            $existingCheckId = if ($matchedTask) { $matchedTask.Id } else { $null }
        }
        "Standalone Host" {
            # Use -contains to handle both single host tasks and batched tasks (where Resources.ResourceId is an array).
            $matchedTask = $inProgressElements | Where-Object {
                try { $_.Type -eq $StandAloneHostTaskType -and $_.Resources.ResourceId -contains $ResourceId } catch { $false }
            } | Select-Object -First 1
            $existingCheckId = if ($matchedTask) { $matchedTask.Id } else { $null }
        }
    }

    if ($existingCheckId) {
        # Get task details (single API call, reuse for both subtasks and status).
        try {
            $taskInfo = Invoke-VcfGetTask -Id $existingCheckId -ErrorAction Stop
        } catch {
            # Task not found - may have completed and been removed.
            if ($_.Exception.Message -match "NOT_FOUND|404|does not exist") {
                Write-LogMessage -Type DEBUG -Message "Task $existingCheckId not found (completed and removed). Proceeding with new $operation."
                return $false  # Allow new operation
            } else {
                $errorMsg = $_.Exception.Message
                Write-LogMessage -Type ERROR -Message "Failed to query existing task ${existingCheckId}: $errorMsg"
                throw  # Re-throw - API being down is critical
            }
        }

        $existingCheckDetails = $taskInfo.Subtasks | Where-Object {$_.Status -eq "IN_PROGRESS"}

        # Check for the edge case that the task has already completed or failed.
        if (-not $existingCheckDetails) {
            $taskStatus = $taskInfo.Status

            switch ($taskStatus) {
              "Failed" {
                Write-LogMessage -Type ERROR -SuppressOutputToScreen -Message "Please note a recent check of $ResourceType `"$ResourceName`" in workload domain `"$WorkloadDomainName`" via Task ID $existingCheckId failed quickly."
                return $false  # Allow retry of failed task
              }
              "In Progress" {
                if ($SuppressVerboseWarning) {
                    Write-LogMessage -Type DEBUG -Message "A $Operation is already in progress for $ResourceType `"$ResourceName`" in workload domain `"$WorkloadDomainName`" (Task Id: $existingCheckId). Skipping."
                } else {
                    Write-LogMessage -Type WARNING -Message "A $Operation is already in progress for $ResourceType `"$ResourceName`" in workload domain `"$WorkloadDomainName`" (Task Id: $existingCheckId). Skipping."
                }
                return $true
              }
              default {
                Write-LogMessage -Type WARNING -SuppressOutputToScreen -Message "Unexpected Task status `"$taskStatus`" for existing $ResourceType `"$ResourceName`" in workload domain `"$WorkloadDomainName`" (Task ID $existingCheckId). Re-running."
                return $false
              }
            }
        } else {
            if ($SuppressVerboseWarning) {
                Write-LogMessage -Type DEBUG -Message "A $Operation is already in progress for $ResourceType `"$ResourceName`" in workload domain `"$WorkloadDomainName`" which started at `"$($existingCheckDetails.CreationTimeStamp)`" and is now in subtask `"$($existingCheckDetails.Name)`" (Task ID $existingCheckId). Skipping."
            } else {
                Write-LogMessage -Type WARNING -Message "A $Operation is already in progress for $ResourceType `"$ResourceName`" in workload domain `"$WorkloadDomainName`" which started at `"$($existingCheckDetails.CreationTimeStamp)`" and is now in subtask `"$($existingCheckDetails.Name)`" (Task ID $existingCheckId). Skipping."
            }
            return $true
        }
    } else {
        # No existing in-progress task found for that resource Id.
        return $false
    }
}
Function Test-TaskStatus {

    <#
        .SYNOPSIS
        Provides standardized task status checking and error handling.

        .DESCRIPTION
        This helper function reduces code duplication by providing a standard way to
        check task status and handle different completion states.

        .PARAMETER Response
        The response object from a VCF task.

        .PARAMETER ResourceName
        Optional. Name of the resource (cluster or host) for context in logs.

        .PARAMETER ResourceType
        Optional. Type of resource: "Cluster", "Standalone Host", or "Standalone Host Batch".

        .PARAMETER WorkloadDomainName
        Optional. Workload domain name for context in logs.

        .EXAMPLE
        Test-TaskStatus -Response $response -ResourceType "Cluster" -ResourceName "cluster01" -WorkloadDomainName "w01"

        .OUTPUTS
        String
        Returns the task status: "Successful", "Failed", "In Progress", or "Unknown".
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] $Response,
        [Parameter(Mandatory = $false)] [String]$ResourceName,
        [Parameter(Mandatory = $false)] [ValidateSet("Cluster", "Standalone Host", "Standalone Host Batch")] [String]$ResourceType,
        [Parameter(Mandatory = $false)] [String]$WorkloadDomainName
    )

    Write-LogMessage -Type DEBUG -Message "Entered Test-TaskStatus function..."
    if ($ResourceName -or $ResourceType -or $WorkloadDomainName) {
        Write-LogMessage -Type DEBUG -SuppressOutputToScreen -Message "Task context: ResourceType=$ResourceType, ResourceName=$ResourceName, WorkloadDomainName=$WorkloadDomainName."
    }

    switch ($Response.Status) {
        "Successful" {
            Write-LogMessage -Type INFO -PrependNewLine -Message "$($Response.Name) completed successfully."
            return "Successful"
        }

        "Failed" {
            Write-LogMessage -Type ERROR -PrependNewLine -Message "$($Response.Name) encountered a failure."
            # Select the first failed subtask to avoid member-enumeration issues on arrays.
            $failedSubTask = $Response.SubTasks | Where-Object Status -eq "FAILED" | Select-Object -First 1
            if ($failedSubTask) {
                Write-LogMessage -Type ERROR -PrependNewLine -Message "Status $($failedSubTask.Status) : $($failedSubTask.Name)"
                Write-LogMessage -Type ERROR -PrependNewLine -Message "$($failedSubTask.Errors.Message)"
                Write-LogMessage -Type ERROR -PrependNewLine -Message "SDDC Manager error code: `"$($failedSubTask.Errors.ErrorCode)`", reference code `"$($failedSubTask.Errors.ReferenceToken)`" in Task ID `"$($Response.Id)`"."
            }
            $errorCodes = @($Response.SubTasks | Where-Object Status -eq "FAILED") | ForEach-Object { @($_.Errors) | ForEach-Object { $_.ErrorCode } }
            if ($errorCodes -contains "MORE_THAN_ONE_IMAGE_RECOMMENDED") {
                Write-LogMessage -Type INFO -Message "This cluster contains heterogeneous VIBs. If this is due to heterogeneous hardware please visit https://knowledge.broadcom.com/external/article/424294/temporarily-allow-vcenter-vmware-update.html for more details."
            }
            return "Failed"
        }

        { $_ -match "Unknown|Timed Out|Timed_Out|Cancelled" } {
            Write-LogMessage -Type INFO -PrependNewLine -Message "$($Response.Name) completed with status $($Response.Status). Unable to determine if the task completed or not."
            return $Response.Status
        }

        default {
            return "Unknown"
        }
    }
}
Function Get-WorkloadDomainId {

    <#
        .SYNOPSIS
        Retrieves the workload domain ID from the domain name with validation.

        .DESCRIPTION
        This helper function provides a standard way to lookup and validate workload domain IDs.
        It queries SDDC Manager for domains and returns the ID of the matching domain name.

        Returns a structured error object if the domain is not found or if there's an API error.
        Calls Test-SddcManagerConnection before listing domains, and retries once after Connect-SddcManager -Reconnect when the domains API returns 401 or JWT expiration.

        .PARAMETER WorkloadDomainName
        The name of the workload domain to look up.

        .OUTPUTS
        Hashtable with Success and either WorkloadDomainId or ErrorMessage/ErrorCode properties.
        On success: @{ Success = $true; WorkloadDomainId = "<guid>" }
        On failure: @{ Success = $false; ErrorMessage = "..."; ErrorCode = "ERR_..." }

        .EXAMPLE
        $result = Get-WorkloadDomainId -WorkloadDomainName "w01"
        if ($result.Success) {
            $domainId = $result.WorkloadDomainId
        } else {
            Write-LogMessage -Type ERROR -Message $result.ErrorMessage
            Exit-WithCode -ExitCode $Script:ExitCodes.RESOURCE_NOT_FOUND
        }

        .NOTES
        Error Handling: This is a helper function that returns structured error objects.
        Callers must check the Success property and handle errors appropriately.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$WorkloadDomainName
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-WorkloadDomainId function..."

    # Ensure SDDC Manager JWT is usable before listing domains (long JSON validation steps can outlive the initial connection test).
    Test-SddcManagerConnection

    Write-LogMessage -Type DEBUG -Message "Looking up workload domain: $WorkloadDomainName"
    Write-LogMessage -Type DEBUG -Message "Calling Invoke-VcfGetDomains API"

    $domainsResult = $null
    foreach ($attempt in @(1, 2)) {
        try {
            $domainsResult = Invoke-VcfGetDomains -ErrorAction Stop
            break
        } catch {
            if ($_.Exception.Message -match "is not recognized as.*name of a cmdlet") {
                Write-LogMessage -Type ERROR -Message "VCF.PowerCLI cmdlet 'Invoke-VcfGetDomains' not found. Please ensure VCF.PowerCLI $minimumVcfPowerCliVersion or later is installed."
                Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
            }
            if ($attempt -eq 1 -and $_.Exception.Message -match "401|Unauthorized|JWT expired|Token expired|ExpiredJwt") {
                Write-LogMessage -Type WARNING -Message "SDDC Manager domains query failed with an authorization error; reconnecting and retrying once..."
                Connect-SddcManager -Reconnect
                Test-SddcManagerConnection -MinimumTtlMinutes 1
                continue
            }
            Write-LogMessage -Type DEBUG -Message "Exception retrieving workload domain: $($_.Exception.Message)"
            return Write-ErrorAndReturn `
                -ErrorMessage "Failed to retrieve workload domain `"$WorkloadDomainName`": $($_.Exception.Message)" `
                -ErrorCode "ERR_OPERATION_FAILED"
        }
    }

    $domainElements = if ($domainsResult -and $domainsResult.PSObject.Properties['Elements'] -and $domainsResult.Elements) { @($domainsResult.Elements) } else { @() }
    $matchedDomain = $domainElements | Where-Object Name -eq $WorkloadDomainName | Select-Object -First 1
    $workloadDomainId = if ($matchedDomain) { $matchedDomain.Id } else { $null }

    if (-not $workloadDomainId) {
        Write-LogMessage -Type DEBUG -Message "Workload domain `"$WorkloadDomainName`" not found"
        return Write-ErrorAndReturn `
            -ErrorMessage "Workload domain `"$WorkloadDomainName`" not found in SDDC Manager." `
            -ErrorCode "ERR_DOMAIN_NOT_FOUND"
    }

    Write-LogMessage -Type DEBUG -Message "Found workload domain `"$WorkloadDomainName`" with ID: $workloadDomainId"
    return @{
        Success = $true
        WorkloadDomainId = $workloadDomainId
    }
}
Function Test-LogLevel {

    <#
        .SYNOPSIS
        Determines if a message should be displayed based on the configured log level.

        .DESCRIPTION
        Compares the message type against the configured log level threshold to determine
        if the message should be displayed on screen. All messages are always written to
        the log file regardless of level.

        The log level hierarchy from lowest to highest is:
        DEBUG < INFO < ADVISORY < WARNING < EXCEPTION < ERROR

        .PARAMETER MessageType
        The type/severity of the log message to check.

        .PARAMETER ConfiguredLevel
        The minimum log level configured for screen output.

        .EXAMPLE
        Test-LogLevel -MessageType "DEBUG" -ConfiguredLevel "INFO"
        Returns $false because DEBUG is below INFO threshold.

        .EXAMPLE
        Test-LogLevel -MessageType "ERROR" -ConfiguredLevel "INFO"
        Returns $true because ERROR is at or above INFO threshold.

        .OUTPUTS
        Boolean
        Returns $true if the message should be displayed, $false otherwise.

        .NOTES
        This function was imported from OneNodeDeployment.ps1 for standardized log level filtering.
    #>
    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ConfiguredLevel,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$MessageType
    )

    $messageLevel = $Script:logLevelHierarchy[$MessageType]
    $configuredLevelValue = $Script:logLevelHierarchy[$ConfiguredLevel]

    return ($messageLevel -ge $configuredLevelValue)
}
Function Write-ErrorAndReturn {

    <#
        .SYNOPSIS
        Writes an error message and returns a standardized error result.

        .DESCRIPTION
        This function provides a standardized way to handle errors by returning a consistent
        error result object without logging. This allows the caller to decide how to handle
        the error (log, propagate, retry, or exit). This design prevents duplicate error
        messages and gives callers full control over error handling.

        USAGE GUIDELINES:
        - Use in Helper/Validation/Utility functions (not main workflow functions)
        - Does NOT log the error - caller is responsible for logging if needed
        - Allows caller to decide how to handle the error (propagate, retry, or exit)
        - Always check the returned Success property in the caller

        Error Handling Pattern:
        1. Helper function calls Write-ErrorAndReturn to return structured error (no logging)
        2. Caller checks $result.Success
        3. Caller decides: log + exit, propagate error up the chain, or retry operation

        .PARAMETER ErrorMessage
        The error message to log and include in the result.

        .PARAMETER ErrorCode
        Optional error code for categorization. Defaults to "ERR_UNKNOWN".

        Error Code Categories (VcfBaselineClusterTransition):
        - Connection Errors (1xxx):
          ERR_NOT_CONNECTED_SDDC, ERR_NOT_CONNECTED_VCENTER, ERR_CONNECTION_TIMEOUT,
          ERR_CONNECTION_FAILED, ERR_AUTH_FAILED, ERR_TOKEN_EXPIRED

        - Validation Errors (2xxx):
          ERR_INVALID_PARAMETER, ERR_INVALID_JSON, ERR_MISSING_PARAMETER,
          ERR_FILE_NOT_FOUND, ERR_INVALID_CREDENTIALS, ERR_VALIDATION_FAILED

        - Resource Errors (3xxx):
          ERR_CLUSTER_NOT_FOUND, ERR_IMAGE_NOT_FOUND, ERR_DOMAIN_NOT_FOUND,
          ERR_RESOURCE_NOT_FOUND, ERR_VCENTER_NOT_FOUND, ERR_HOST_NOT_FOUND

        - Operation Errors (4xxx):
          ERR_COMPLIANCE_CHECK_FAILED, ERR_TRANSITION_FAILED, ERR_IMPORT_FAILED,
          ERR_DELETE_FAILED, ERR_TASK_FAILED, ERR_OPERATION_FAILED

        - Task Errors (5xxx):
          ERR_TASK_IN_PROGRESS, ERR_TASK_CANCELLED, ERR_TASK_TIMEOUT,
          ERR_TASK_UNKNOWN_STATE, ERR_RETRY_FAILED

        - JSON/Configuration Errors (6xxx):
          ERR_JSON_PARSE, ERR_JSON_FORMAT, ERR_CONFIG_INVALID,
          ERR_REMEDIATION_OPTIONS_INVALID

        .EXAMPLE
        # Helper function returns error object.
        Function Get-ClusterInfo {
            if (-not $cluster) {
                return Write-ErrorAndReturn `
                    -ErrorMessage "Cluster '$clusterName' not found in workload domain '$WorkloadDomainName'" `
                    -ErrorCode "ERR_CLUSTER_NOT_FOUND"
            }
            return @{ Success = $true; Cluster = $cluster }
        }

        .EXAMPLE
        # Caller checks result and decides how to handle.
        $result = Get-ClusterInfo -ClusterName $clusterName -WorkloadDomainName $WorkloadDomainName
        if (-not $result.Success) {
            Write-LogMessage -Type ERROR -Message "Failed to get cluster info: $($result.ErrorMessage)"
            exit 1  # Main workflow decides to exit
        }
        $cluster = $result.Cluster

        .OUTPUTS
        PSCustomObject
        Returns a hashtable with Success=$false, ErrorMessage, and ErrorCode properties.

        .NOTES
        Error Handling: This is a utility function used by helper/validation functions to return
        standardized error objects. Do NOT use 'exit 1' in helper functions; use this
        function instead to allow the caller to control error handling.

        This function was imported from OneNodeDeployment.ps1 for standardized error handling.
    #>
    Param(
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ErrorMessage,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$ErrorCode = "ERR_UNKNOWN"
    )

    # Return error object without logging - caller is responsible for logging if needed.
    # This prevents duplicate error messages when callers log the error themselves.
    return @{
        Success = $false
        ErrorMessage = $ErrorMessage
        ErrorCode = $ErrorCode
    }
}
Function Exit-WithCode {

    <#
        .SYNOPSIS
        Exits the script with a standardized exit code and optional final message.

        .DESCRIPTION
        This function provides a centralized exit point that ensures consistent exit code usage,
        optional cleanup operations, and clear logging before script termination. Using this
        function instead of direct 'exit' calls improves automation integration and debugging.

        Benefits of standardized exit codes:
        - CI/CD pipelines can distinguish between failure types and implement appropriate retry logic
        - Monitoring systems can categorize failures for better alerting and reporting
        - Debugging is faster with clear failure category indication
        - Follows PowerShell and Unix conventions for exit codes

        Exit Code Categories (see $Script:ExitCodes):
        0  - SUCCESS: Operation completed successfully
        1  - GENERAL_ERROR: Unspecified error
        2  - PARAMETER_ERROR: Invalid parameters or validation failure
        3  - CONNECTION_ERROR: Failed to connect to SDDC Manager or vCenter
        4  - AUTHENTICATION_ERROR: Authentication or credential failure
        5  - RESOURCE_NOT_FOUND: Cluster, host, workload domain, or image not found
        6  - OPERATION_FAILED: Operation (transition, import, compliance) failed
        7  - TASK_FAILED: Background task failed or timed out
        8  - CONFIGURATION_ERROR: JSON or configuration file error
        9  - PRECONDITION_ERROR: Prerequisites not met (modules, versions)
        10 - USER_CANCELLED: User cancelled the operation

        .PARAMETER ExitCode
        The exit code to return to the shell. Use values from $Script:ExitCodes hashtable
        for consistency and self-documentation.

        .PARAMETER Message
        Optional final message to log before exiting. If ExitCode is 0, logs as INFO.
        Otherwise logs as ERROR.

        .PARAMETER NoCleanup
        Skip optional cleanup operations before exit. Use this when cleanup has already
        been performed or is not desired.

        .EXAMPLE
        Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR -Message "Invalid cluster name format"

        Exits with code 2 and logs an error message about invalid parameters.

        .EXAMPLE
        Exit-WithCode -ExitCode $Script:ExitCodes.SUCCESS -Message "Transition completed successfully"

        Exits with code 0 and logs a success message.

        .EXAMPLE
        Exit-WithCode -ExitCode $Script:ExitCodes.CONNECTION_ERROR -Message "Failed to connect to SDDC Manager" -NoCleanup

        Exits with code 3, logs error, and skips cleanup operations.

        .OUTPUTS
        None. This function terminates the script with the specified exit code.

        .NOTES
        This function should be used for all script exits except in the main menu's exit option,
        which may have its own cleanup logic. Using this consistently throughout the script
        ensures predictable exit behavior for automation and debugging.
    #>
    Param(
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [Int]$ExitCode,
        [Parameter(Mandatory = $false)] [String]$Message,
        [Parameter(Mandatory = $false)] [Switch]$NoCleanup
    )

    Write-LogMessage -Type DEBUG -Message "Entered Exit-WithCode function..."

    # Log final message if provided.
    if ($Message) {
        if ($ExitCode -eq 0) {
            Write-LogMessage -Type INFO -Message $Message
        } else {
            Write-LogMessage -Type ERROR -Message $Message
        }
    }

    # Optional cleanup logic for error exits.
    if (-not $NoCleanup -and $ExitCode -ne 0) {
        Write-LogMessage -Type DEBUG -Message "Exit code $ExitCode indicates failure."
    }

    # Log the exit code for debugging.
    Write-LogMessage -Type DEBUG -Message "Script exiting with code $ExitCode"

    # Exit with the specified code.
    exit $ExitCode
}
Function Write-LogMessage {

    <#
        .SYNOPSIS
        Writes a severity-based color-coded message to the console and/or log file.

        .DESCRIPTION
        The Write-LogMessage function provides centralized logging functionality with support for
        different message types (INFO, ERROR, WARNING, EXCEPTION, ADVISORY, DEBUG). Messages are displayed
        on the console with color coding based on severity and written to a log file with timestamps.
        This function supports flexible output control allowing messages to be suppressed from either
        the console or log file as needed.

        Screen output is filtered based on the configured log level threshold (set via the -LogLevel
        script parameter). Only messages at or above the configured level are displayed on screen.
        All messages are always written to the log file regardless of their severity level.

        Log level hierarchy (lowest to highest):
        DEBUG < INFO < ADVISORY < WARNING < EXCEPTION < ERROR

        .PARAMETER Message
        The message content to be logged and/or displayed. Can be an empty string if needed.

        .PARAMETER Type
        The severity level of the message. Valid values are:
        - DEBUG (Gray): Debug information for troubleshooting and development
        - INFO (Green): General information messages
        - ADVISORY (Yellow): Advisory information for user guidance
        - WARNING (Yellow): Warning conditions that may need attention
        - EXCEPTION (Cyan): Exception details and stack traces
        - ERROR (Red): Error conditions that require attention
        Default value is "INFO".

        .PARAMETER SuppressOutputToScreen
        When specified, prevents the message from being displayed on the console regardless of log level.

        .PARAMETER PrependNewLine
        When specified, adds a blank line before displaying the message on the console.
        This parameter has no effect when SuppressOutputToScreen is used or when the message
        is filtered by log level threshold.

        .PARAMETER AppendNewLine
        When specified, adds a blank line after displaying the message on the console.
        This parameter has no effect when SuppressOutputToScreen is used or when the message
        is filtered by log level threshold.

        .EXAMPLE
        Write-LogMessage -Type INFO -Message "Process started successfully"
        Displays an informational message in green on the console and writes the message to the log file.

        .EXAMPLE
        Write-LogMessage -Type ERROR -Message "Failed to connect to server" -PrependNewLine
        Displays an error message in red with a blank line before it, and logs it to the file.

        .EXAMPLE
        Write-LogMessage -Type WARNING -Message "Configuration file not found, using defaults" -SuppressOutputToScreen
        Writes a warning message to the log file only, without displaying it on the console.

        .EXAMPLE
        Write-LogMessage -Type DEBUG -Message "Variable value: $myVar = $($myVar)"
        Displays a debug message in gray on the console (only if log level is DEBUG) and writes it to the log file.

        .NOTES
        This function was imported from OneNodeDeployment.ps1 for standardized log level filtering.
        The function relies on the $Script:LogFile, $Script:logOnly, and $Script:configuredLogLevel variables being set.
        The log file path should be established using the New-LogFile function before calling this function.
        The $Script:configuredLogLevel should be set during script initialization.

        .OUTPUTS
        None
        This function does not return a value. It writes messages to console and/or log file.
    #>

    Param (
        [Parameter(Mandatory = $false)] [Switch]$AppendNewLine,
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [String]$Message,
        [Parameter(Mandatory = $false)] [Switch]$PrependNewLine,
        [Parameter(Mandatory = $false)] [Switch]$SuppressOutputToScreen,
        [Parameter(Mandatory = $false)] [ValidateSet("INFO", "ERROR", "WARNING", "EXCEPTION", "ADVISORY", "DEBUG")] [String]$Type = "INFO"
    )

    # Define color mapping for different message types.
    $msgTypeToColor = @{
        "INFO" = "Green";
        "ERROR" = "Red" ;
        "WARNING" = "Yellow" ;
        "ADVISORY" = "Yellow" ;
        "EXCEPTION" = "Cyan";
        "DEBUG" = "Gray"
    }

    # Get the appropriate color for the message type.
    $messageColor = $msgTypeToColor.$Type

    # Create timestamp for log file entries (MM-dd-yyyy_HH:mm:ss format)
    $timeStamp = Get-Date -Format "MM-dd-yyyy_HH:mm:ss"

    # Determine if message should be displayed based on log level threshold.
    $shouldDisplay = Test-LogLevel -MessageType $Type -ConfiguredLevel $Script:configuredLogLevel

    # Add blank line before message if requested and not in log-only mode and meets log level threshold.
    if ($PrependNewLine -and (-not $Script:logOnly) -and $shouldDisplay) {
        Write-Host ""
    }

    # Display message to console with color coding (unless suppressed, in log-only mode, or below log level threshold).
    if (-not $SuppressOutputToScreen -and -not $Script:logOnly -and $shouldDisplay) {
        Write-Host -ForegroundColor $messageColor "[$Type] $Message"
    }

    # Add blank line after message if requested and not in log-only mode and meets log level threshold.
    if ($AppendNewLine -and (-not $Script:logOnly) -and $shouldDisplay) {
        Write-Host ""
    }

    # Write message to log file (always, regardless of log level).
    $logContent = '[' + $timeStamp + '] ' + '(' + $Type + ')' + ' ' + $Message
    try {
        Add-Content -ErrorVariable ErrorMessage -Path $Script:LogFile $logContent
    }
    catch {
        # Handle log file write failures gracefully.
        Write-Host "Failed to add content to log file $Script:LogFile."
        Write-Host $ErrorMessage
    }
}
#endregion

#region Connection
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

        .EXAMPLE
        Connect-SddcManager -Reconnect

        .PARAMETER Reconnect
        Specifies if one should reconnect to SDDC Manager using the global parameters of FQDN/UN/PW. Any existing SDDC Manager session is disconnected first so a new JWT is issued.

        .OUTPUTS
        None
        This function does not return a value. It establishes a connection or exits the script on failure.
    #>

    Param (
        [Parameter(Mandatory = $false)] [Switch]$Reconnect
    )

    Write-LogMessage -Type DEBUG -Message "Starting Connect-SddcManager function (Reconnect: $Reconnect)"

    # if $Global:SddcManagerFqdn is defined, we're re-entering the connection workflow having likely lost our token.
    if ($Reconnect) {
        Write-LogMessage -Type DEBUG -Message "Attempting to reconnect to SDDC Manager using stored credentials"
        Write-LogMessage -Type DEBUG -Message "SDDC Manager FQDN: $Global:SddcManagerFqdn, User: $Global:SddcManagerUserName"

        # Remove the old session first; otherwise Connect-VcfSddcManagerServer may leave a dead JWT in place and API calls keep returning 401.
        try {
            $sddcConnVarForReconnect = Get-Variable -Name "defaultSddcManagerConnections" -Scope Global -ErrorAction SilentlyContinue
            if ($sddcConnVarForReconnect -and $sddcConnVarForReconnect.Value) {
                $activeSddcForReconnect = @($sddcConnVarForReconnect.Value) | Where-Object { $_.IsConnected } | Select-Object -First 1
                if ($activeSddcForReconnect -and $activeSddcForReconnect.PSObject.Properties["Name"] -and $activeSddcForReconnect.Name) {
                    Write-LogMessage -Type DEBUG -Message "Pre-reconnect: disconnecting SDDC Manager session `"$($activeSddcForReconnect.Name)`"."
                    Disconnect-VcfSddcManagerServer -Server $activeSddcForReconnect.Name -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-LogMessage -Type DEBUG -Message "Pre-reconnect disconnect (non-fatal): $($_.Exception.Message)"
        }

        $ConnectedToSddcManager = $null
        if ($Global:SddcManagerFqdn -and $Global:SddcManagerUserName -and $Global:SddcManagerPassword) {
            try {
                $ConnectedToSddcManager = Connect-VcfSddcManagerServer -Server $Global:SddcManagerFqdn -User $Global:SddcManagerUserName -Password $Global:SddcManagerPassword -ErrorAction Stop
            } catch {
                Write-LogMessage -Type DEBUG -Message "Reconnection exception caught: $($_.Exception.GetType().Name)"
                $errorMessage = $_.Exception.Message

                # Check if this is a timeout/network error
                if ($errorMessage -match "timed out|timeout|network|unreachable|connection refused") {
                    Write-LogMessage -Type ERROR -PrependNewLine -Message "Connection to SDDC Manager `"$Global:SddcManagerFqdn`" timed out. Please check network connectivity and that SDDC Manager is running."
                    Write-LogMessage -Type ERROR -AppendNewLine -Message "Please confirm your SDDC Manager FQDN and user credentials in $sddcManagerCredentialsJson and return to the script."
                    Exit-WithCode -ExitCode $Script:ExitCodes.CONNECTION_ERROR
                } else {
                    Write-LogMessage -Type WARNING -Message "Failed to reconnect to SDDC Manager: $errorMessage"
                }
                $ConnectedToSddcManager = $null
            }
        }
        if ($ConnectedToSddcManager) {
            Write-LogMessage -Type DEBUG -Message "Successfully reconnected to SDDC Manager $Global:SddcManagerFqdn"
            Write-LogMessage -Type DEBUG -Message "Created new access token for $Global:SddcManagerFqdn"
            return
        } else {
            Write-LogMessage -Type DEBUG -Message "Reconnection attempt failed."
        }
    }

    # valid if the credentials file exists.
    Write-LogMessage -Type DEBUG -Message "Checking for credentials file: $sddcManagerCredentialsJson"
    $sddcManagerCredentialsJsonFileExists = Test-Path $sddcManagerCredentialsJson
    Write-LogMessage -Type DEBUG -Message "Credentials file exists: $sddcManagerCredentialsJsonFileExists"

    if ($sddcManagerCredentialsJsonFileExists) {
            Write-LogMessage -Type DEBUG -Message "Loading credentials from JSON file"
            Write-LogMessage -Type INFO -PrependNewLine -AppendNewLine -Message "Detected JSON input file `"$sddcManagerCredentialsJson`"."

            # Use the script's robust JSON parser.
            $credentialsResult = ConvertFrom-JsonSafely -JsonFilePath $sddcManagerCredentialsJson -VariableName "SddcManagerCredentials"
            if (-not $credentialsResult.Success) {
                Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR -Message $credentialsResult.ErrorMessage
            }
            $credentialsObject = $credentialsResult.JsonData

            # Validate that required properties exist.
            if (-not $credentialsObject.PSObject.Properties['SddcManagerFqdn']) {
                Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR -Message "Required property 'SddcManagerFqdn' not found in credentials file"
            }
            if (-not $credentialsObject.PSObject.Properties['SddcManagerUserName']) {
                Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR -Message "Required property 'SddcManagerUserName' not found in credentials file"
            }
            if (-not $credentialsObject.PSObject.Properties['SddcManagerPassword']) {
                Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR -Message "Required property 'SddcManagerPassword' not found in credentials file"
            }

            $Global:SddcManagerFqdn = $credentialsObject.SddcManagerFqdn
            $Global:SddcManagerUserName = $credentialsObject.SddcManagerUserName
            # Convert the plaintext password from the JSON file to a SecureString immediately.
            # This ensures the password is not held as plaintext in memory for the script lifetime.
            $Global:SddcManagerPassword = ConvertTo-SecureString -String $credentialsObject.SddcManagerPassword -AsPlainText -Force

            # Validate that credentials values are not empty before converting.
            if ( ([String]::IsNullOrEmpty($Global:SddcManagerFqdn)) -or ([String]::IsNullOrEmpty($Global:SddcManagerUserName)) -or ([String]::IsNullOrEmpty($credentialsObject.SddcManagerPassword)) ) {
                Write-LogMessage -Type ERROR -Message "One or more required credentials are empty in $sddcManagerCredentialsJson"
                Exit-WithCode -ExitCode $Script:ExitCodes.AUTHENTICATION_ERROR -Message "Please verify SddcManagerFqdn, SddcManagerUserName, and SddcManagerPassword are properly set."
            }
        } else {
            if ($Script:logOnly) {
                # Use Write-Output to bypass logging suppression in Silence mode.
                Write-Output "ERROR: Option -Silence cannot be used when JSON credential file not present."
                Exit-WithCode -ExitCode $Script:ExitCodes.AUTHENTICATION_ERROR -Message "Option -Silence cannot be used when JSON credential file not present."
            }
            Write-LogMessage -Type WARNING -AppendNewLine -Message "JSON SDDC Credentials input file `"$sddcManagerCredentialsJson`" not detected"
            Write-LogMessage -Type WARNING -SuppressOutputToScreen -Message "Could not locate JSON credentials file `"$sddcManagerCredentialsJson`" ."

            # Prompt for credentials, re-prompting until all fields are filled.
            do {
                Write-LogMessage -Type INFO -AppendNewLine -Message "Please enter your connection details at the prompt."
                $Global:SddcManagerFqdn = Read-Host "Enter your SDDC Manager FQDN"
                $Global:SddcManagerUserName = Read-Host "Enter your SDDC Manager SSO username"
                $Global:SddcManagerPassword = Read-Host "Enter your SDDC Manager SSO password" -AsSecureString

                $passwordLength = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Global:SddcManagerPassword)
                ).Length
                if ([string]::IsNullOrWhiteSpace($Global:SddcManagerFqdn) -or
                    [string]::IsNullOrWhiteSpace($Global:SddcManagerUserName) -or
                    $passwordLength -eq 0) {
                    Write-LogMessage -Type ERROR -Message "SDDC Manager FQDN, username, and password are all required. Please try again."
                }
            } while ([string]::IsNullOrWhiteSpace($Global:SddcManagerFqdn) -or
                     [string]::IsNullOrWhiteSpace($Global:SddcManagerUserName) -or
                     $passwordLength -eq 0)
        }

        # Attempt connection; loop if the user opts to retry after a failure.
        $connectionAttempted = $false
        do {
            if ($connectionAttempted) {
                Write-LogMessage -Type INFO -AppendNewLine -Message "Please enter your connection details at the prompt."
                $Global:SddcManagerFqdn = Read-Host "Enter your SDDC Manager FQDN"
                $Global:SddcManagerUserName = Read-Host "Enter your SDDC Manager SSO username"
                $Global:SddcManagerPassword = Read-Host "Enter your SDDC Manager SSO password" -AsSecureString
            }
            $connectionAttempted = $true
            Write-LogMessage -Type DEBUG -Message "Attempting to connect to SDDC Manager: `"$Global:SddcManagerFqdn`" with user `"$Global:SddcManagerUserName`"..."
            $ConnectedToSddcManager = $null
            try {
                $ConnectedToSddcManager = Connect-VcfSddcManagerServer -Server $Global:SddcManagerFqdn -User $Global:SddcManagerUserName -Password $Global:SddcManagerPassword -ErrorAction Stop
                Write-LogMessage -Type DEBUG -Message "Connection attempt completed (Success: $($null -ne $ConnectedToSddcManager))"
            } catch {
                Write-LogMessage -Type DEBUG -Message "Connection exception caught: $($_.Exception.GetType().Name)"

                # Display friendly messages to the end user for common connection errors.
                $errorMessage = $_.Exception.Message

                switch -Regex ($errorMessage) {
                    "IDENTITY_UNAUTHORIZED_ENTITY" {
                        Write-LogMessage -Type ERROR -Message "Failed to connect to SDDC Manager `"$Global:SddcManagerFqdn`" using username `"$Global:SddcManagerUserName`". Please check your credentials."
                    }
                    "Operation timed out|timed out|timeout" {
                        Write-LogMessage -Type ERROR -Message "Connection to SDDC Manager `"$Global:SddcManagerFqdn`" timed out. Please check network connectivity and that SDDC Manager is running."
                    }
                    "connected party did not properly respond|connection attempt failed|established connection failed|nodename nor servname provided" {
                        Write-LogMessage -Type ERROR -Message "Cannot resolve SDDC Manager `"$Global:SddcManagerFqdn`". If this is a valid SDDC Manager FQDN, please check your DNS settings."
                    }
                    "The requested URL.*?/v1/tokens.*?was not found" {
                        Write-LogMessage -Type ERROR -Message "SDDC Manager `"$Global:SddcManagerFqdn`" did not return a valid response. Please check that `"$Global:SddcManagerFqdn`" is a valid SDDC Manager FQDN and if its services are healthy."
                    }
                    "The SSL connection could not be established" {
                        Write-LogMessage -Type ERROR -Message "SSL Connection error to SDDC Manager `"$Global:SddcManagerFqdn`". Please check that SDDC Manager has a CA signed certificate or Powershell trusts insecure certificates."
                    }
                    "Permission not found" {
                        Write-LogMessage -Type ERROR -Message "Username `"$Global:SddcManagerUserName`" does not have access to SDDC Manager."
                    }
                    "not recognized as a name of a cmdlet" {
                        Write-LogMessage -Type ERROR -Message "Could not find VCF.PowerCLI cmdlet Connect-VcfSddcManagerServer. Your VCF.PowerCLI installation may be incomplete."
                    }
                    "but the module could not be loaded" {
                        Write-LogMessage -Type ERROR -Message "VMware.Sdk.Vcf.SddcManager, the module containing the required Connect-VcfSddcManagerServer PowerCLI cmdlet could not be loaded.  Your VCF.PowerCLI environment may not be configured correctly.  Please investigate before re-running this script."
                    }
                    "TOKEN_BAD_REQUEST|Password cannot be null|Username cannot be null" {
                        Write-LogMessage -Type ERROR -Message "Failed to connect to SDDC Manager `"$Global:SddcManagerFqdn`". Username or password was empty. Please check your credentials and try again."
                    }
                    default {
                        Write-LogMessage -Type ERROR -Message "Failed to connect to SDDC Manager `"$Global:SddcManagerFqdn`". Please check your credentials and network connectivity."
                        Write-LogMessage -Type DEBUG -Message "Unhandled connection error: $errorMessage"
                    }
                }
            }

            if (-not $ConnectedToSddcManager) {
                if ($sddcManagerCredentialsJsonFileExists) {
                    Exit-WithCode -ExitCode $Script:ExitCodes.AUTHENTICATION_ERROR -Message "Please confirm your SDDC Manager FQDN and user credentials in $sddcManagerCredentialsJson and return to the script."
                }
                $decision = New-ChoiceMenu -Question "Would you like to re-enter your SDDC Manager FQDN and user credentials?" -DefaultAnswer yes
                if ($decision -ne 0) {
                    Exit-WithCode -ExitCode $Script:ExitCodes.USER_CANCELLED -Message "User cancelled SDDC Manager authentication."
                }
            }
        } while (-not $ConnectedToSddcManager)

        Write-LogMessage -Type INFO -AppendNewLine -Message "Successfully connected to SDDC Manager `"$Global:SddcManagerFqdn`" as `"$Global:SddcManagerUserName`"."
        $activeSddcConnForVersion = @($defaultSddcManagerConnections) | Where-Object { $_.IsConnected } | Select-Object -First 1
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "SDDC Manager `"$Global:SddcManagerFqdn`" version is `"$($activeSddcConnForVersion.ProductVersion)`"."

        # After successfully connecting to SDDC Manager, check that it's at the minimum required release.

        $sddcManagerVersion = Get-SddcManagerVersion

        if ([Version]($sddcManagerVersion) -lt [Version]($minimumVcfRelease)) {
            Write-LogMessage -Type ERROR -Message "SDDC Manager version $sddcManagerVersion detected on `"$Global:SddcManagerFqdn`". Version $minimumVcfRelease or later is required."
            Disconnect-SddcManager -NoPrompt -Silence
            Exit-WithCode -ExitCode $Script:ExitCodes.VERSION_ERROR -Message "SDDC Manager version $minimumVcfRelease or later is required."
        }

        # To avoid password reentry, the script will automatically create an SDDC Manager Credential JSON file.
        # based on user-inputted data. This action is called late in the script to ensure the credentials.
         # entered are correct.
        if (-not $sddcManagerCredentialsJsonFileExists) {
            Write-LogMessage -Type ADVISORY -AppendNewLine -Message "Your SDDC Manager login credentials may be saved to a file to allow non-interactive login in the future. This is not required, and the file may be safely removed at any time."
            Write-LogMessage -Type WARNING -Message "SECURITY WARNING: Credentials are saved as plaintext JSON. Protect this file with appropriate file system permissions (e.g., chmod 600 on Linux/macOS or restrict ACLs on Windows). Do not commit this file to source control."
            $decision = New-ChoiceMenu -Question "Would you like to save your SDDC login credentials in a JSON file?" -DefaultAnswer no
            # Selection zero equals yes.
            if ($decision -eq 0) {
                Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "User chose to save SDDC Manager credentials to JSON file."
                Write-LogMessage -Type INFO -AppendNewLine -Message "Writing credentials to `"$sddcManagerCredentialsJson`"..."
                $decodedPasswordInterimStep = [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($Global:SddcManagerPassword)
                $decodedSddcManagerPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($decodedPasswordInterimStep)
                [System.Runtime.InteropServices.Marshal]::ZeroFreeCoTaskMemUnicode($decodedPasswordInterimStep)

                $jsonHashTable = @{
                    'SddcManagerFqdn' = $Global:SddcManagerFqdn
                    'SddcManagerUserName' = $Global:SddcManagerUserName
                    'SddcManagerPassword' = $decodedSddcManagerPassword
                }
                $JsonOutput = $jsonHashTable | ConvertTo-Json
                # Zero the plaintext password variable before the file write so it is not held in scope beyond this point.
                $decodedSddcManagerPassword = $null
                try {
                    Set-Content -Path $sddcManagerCredentialsJson -Value $JsonOutput -ErrorAction Stop
                    Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Credentials written to `"$sddcManagerCredentialsJson`"."
                    # Restrict file permissions to the current user immediately after writing.
                    if ($IsLinux -or $IsMacOS) {
                        & chmod 600 $sddcManagerCredentialsJson
                        Write-LogMessage -Type DEBUG -Message "File permissions set to 600 on `"$sddcManagerCredentialsJson`"."
                    } else {
                        $acl = Get-Acl -Path $sddcManagerCredentialsJson -ErrorAction SilentlyContinue
                        if ($acl) {
                            $acl.SetAccessRuleProtection($true, $false)
                            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($currentUser, "FullControl", "Allow")
                            $acl.AddAccessRule($rule)
                            Set-Acl -Path $sddcManagerCredentialsJson -AclObject $acl -ErrorAction SilentlyContinue
                            Write-LogMessage -Type DEBUG -Message "File ACL restricted to current user on `"$sddcManagerCredentialsJson`"."
                        }
                    }
                } catch {
                    Write-LogMessage -Type ERROR -Message "Failed to write credentials file `"$sddcManagerCredentialsJson`": $($_.Exception.Message)"
                }
            } else {
                Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "User chose not to save SDDC Manager credentials to JSON file."
            }
        }
}
Function Get-SddcManagerAccessTokenExpiry {

    <#
        .SYNOPSIS
        Returns the TTL (Time To Live) in minutes of the SDDC Manager access token.

        .DESCRIPTION
        This function decodes the JWT access token and calculates the remaining time
        until expiration. This is used by connection management functions to determine
        when to refresh the token.

        Returns a structured result object containing either the TTL in minutes or
        an error if the token cannot be decoded.

        .OUTPUTS
        Hashtable with Success and either TtlMinutes or ErrorMessage/ErrorCode properties.
        On success: @{ Success = $true; TtlMinutes = <double> }
        On failure: @{ Success = $false; ErrorMessage = "..."; ErrorCode = "ERR_..." }

        .EXAMPLE
        $result = Get-SddcManagerAccessTokenExpiry
        if ($result.Success) {
            Write-Host "Token expires in $($result.TtlMinutes) minutes"
        } else {
            Write-Host "Failed to get token expiry: $($result.ErrorMessage)"
        }

        .NOTES
        Error Handling: This is a helper function that returns structured error objects.
        Callers must check the Success property and handle errors appropriately.
    #>

    # Use Get-Variable to safely access the connection list under Set-StrictMode,
    # since the variable may not exist yet if no connection has been established.
    # $defaultSddcManagerConnections is a collection (like $DefaultVIServers) — get the first connected entry.
    $sddcConnVar = Get-Variable -Name 'defaultSddcManagerConnections' -Scope Global -ErrorAction SilentlyContinue
    $sddcConn = if ($sddcConnVar -and $sddcConnVar.Value) {
        @($sddcConnVar.Value) | Where-Object { $_.IsConnected } | Select-Object -First 1
    } else { $null }

    # Exit immediately if there is no active connection.
    if (-not $sddcConn) {
        return Write-ErrorAndReturn `
            -ErrorMessage "No active SDDC Manager connection found." `
            -ErrorCode "ERR_TOKEN_EXPIRED"
    }

    # Retrieve the JWT access token via SessionSecret (VIConnection interface property).
    $accessToken = if ($sddcConn.PSObject.Properties['SessionSecret']) { $sddcConn.SessionSecret } else { $null }

    if (-not $accessToken) {
        return Write-ErrorAndReturn `
            -ErrorMessage "Unable to retrieve access token from SDDC Manager connection." `
            -ErrorCode "ERR_TOKEN_EXPIRED"
    }

    # Decode the JWT payload (second segment, index 1) — header (index 0) is unused.
    $sanitizedAccessToken = $accessToken.Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($sanitizedAccessToken.Length % 4) {
        0 { break }
        2 { $sanitizedAccessToken += '==' }
        3 { $sanitizedAccessToken += '=' }
    }

    try {
        $decodedAccessToken = [System.Text.Encoding]::UTF8.GetString([convert]::FromBase64String($sanitizedAccessToken)) | ConvertFrom-Json -ErrorAction Stop
    } catch [System.FormatException] {
        return Write-ErrorAndReturn `
            -ErrorMessage "Invalid Base64 format in access token" `
            -ErrorCode "ERR_TOKEN_EXPIRED"
    } catch [System.ArgumentException] {
        return Write-ErrorAndReturn `
            -ErrorMessage "Invalid JSON format in decoded access token" `
            -ErrorCode "ERR_TOKEN_EXPIRED"
    } catch {
        return Write-ErrorAndReturn `
            -ErrorMessage "Failed to decode access token: $($_.Exception.Message)" `
            -ErrorCode "ERR_TOKEN_EXPIRED"
    }

    # Convert expiry time to PowerShell DateTime.
    $originalTime = (Get-Date -Year 1970 -Month 1 -Day 1 -hour 0 -Minute 0 -Second 0 -Millisecond 0)
    $timeZone = Get-TimeZone
    $utcTime = $originalTime.AddSeconds($decodedAccessToken.Exp)
    $offsetTime = $timeZone.GetUtcOffset($(Get-Date)).TotalMinutes
    $localTime = $utcTime.AddMinutes($offsetTime)
    $timeToExpiry = ($localTime - (Get-Date))

    # Return TTL in minutes.
    return @{
        Success = $true
        TtlMinutes = $timeToExpiry.TotalMinutes
    }
}

Function Test-PowerCliMultipleVIServerMode {

    <#
        .SYNOPSIS
        Verifies that PowerCLI is configured for simultaneous connections to multiple vCenters.

        .DESCRIPTION
        Checks DefaultVIServerMode across all PowerCLI configuration scopes. Exits the script if
        Multiple mode is not configured. This check is deferred from startup to connection time so
        the menu appears immediately; by the time Connect-Vcenter runs, VCF.PowerCLI is already
        loaded by Connect-SddcManager, making Get-PowerCLIConfiguration fast.

        .EXAMPLE
        Test-PowerCliMultipleVIServerMode

        .OUTPUTS
        None
    #>

    [CmdletBinding()]
    Param ()

    Write-LogMessage -Type DEBUG -Message "Verifying PowerCLI DefaultVIServerMode is Multiple..."
    try {
        $anyMultipleMode = (Get-PowerCLIConfiguration -ErrorAction Stop).DefaultVIServerMode -contains "Multiple"
    } catch {
        if ($_.Exception.Message -match "is not recognized as a name of a cmdlet") {
            Write-LogMessage -Type ERROR -Message "Cannot find Get-PowerCLIConfiguration. Please ensure VCF.PowerCLI $minimumVcfPowerCliVersion or later is installed."
        } else {
            Write-LogMessage -Type ERROR -Message "Get-PowerCLIConfiguration failed: $($_.Exception.Message)"
        }
        Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
    }

    if (-not $anyMultipleMode) {
        Write-LogMessage -Type EXCEPTION -Message "PowerCLI must be configured to connect to multiple vCenters simultaneously."
        # Write-Host: guidance for corrective action uses Write-Host so the Set-PowerCLIConfiguration command is visible even when $Script:logOnly is set.
        Write-Host "Run: Set-PowerCLIConfiguration -DefaultVIServerMode Multiple"
        Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
    }

    Write-LogMessage -Type DEBUG -Message "PowerCLI DefaultVIServerMode is Multiple."
}

Function Test-SddcManagerConnection {

    <#
        .SYNOPSIS
        The function Test-SddcManagerConnection verifies that the script is connected to SDDC Manager.

        .DESCRIPTION
        This function checks if connected to SDDC Manager and attempts automatic reconnection if the token is expiring soon or cannot be validated on an existing connection object.

        .PARAMETER MinimumTtlMinutes
        Specifies the minimum token TTL in minutes before triggering reconnection. Default is 30 minutes.

        .EXAMPLE
        Test-SddcManagerConnection

        .EXAMPLE
        Test-SddcManagerConnection -MinimumTtlMinutes 15

        .OUTPUTS
        None (void)
        The function verifies connection validity and attempts reconnection if needed.
        Does not return a value but may trigger Connect-SddcManager.
    #>

    Param (
        [Parameter(Mandatory = $false)] [ValidateRange(1, 120)] [int]$MinimumTtlMinutes = 30
    )

    Write-LogMessage -Type DEBUG -Message "Testing SDDC Manager connection (Minimum TTL: $MinimumTtlMinutes minutes)..."

    # Get token TTL (returns hashtable with Success and TtlMinutes).
    $tokenResult = Get-SddcManagerAccessTokenExpiry

    # If token check succeeded, we have a valid connection.
    if ($tokenResult.Success) {
        $tokenTtl = $tokenResult.TtlMinutes
        # Token exists - check if it's expiring soon.
        if ($tokenTtl -lt $MinimumTtlMinutes) {
            Write-LogMessage -Type DEBUG -Message "SDDC Manager access token expires in $([math]::Round($tokenTtl, 1)) minutes (minimum $MinimumTtlMinutes minutes). Attempting reconnection..."
            Connect-SddcManager -Reconnect
        } else {
            Write-LogMessage -Type DEBUG -Message "SDDC Manager connection verified. Token TTL: $([math]::Round($tokenTtl, 1)) minutes."
        }
    } else {
        # Token TTL could not be read or connection state is ambiguous; stale IsConnected with an expired JWT must not skip re-auth.
        $sddcConnCheck = Get-Variable -Name 'defaultSddcManagerConnections' -Scope Global -ErrorAction SilentlyContinue
        $hasConnection = $sddcConnCheck -and $sddcConnCheck.Value -and (@($sddcConnCheck.Value) | Where-Object { $_.IsConnected } | Select-Object -First 1)
        if ($hasConnection) {
            Write-LogMessage -Type DEBUG -Message "SDDC Manager connection object is present but the access token could not be validated; forcing reconnection."
            Connect-SddcManager -Reconnect
        } else {
            Write-LogMessage -Type DEBUG -Message "No valid SDDC Manager connection detected. Initiating connection..."
            Connect-SddcManager
        }
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

        .OUTPUTS
        None
        This function does not return a value. It establishes vCenter connections or exits the script on failure.
    #>

    [CmdletBinding()]
    Param ()

    Write-LogMessage -Type DEBUG -Message "Entered Connect-Vcenter function..."

    # Force VxRail mode re-detection whenever a new vCenter connection is established.
    $Script:vxRailModeDetected = $false

    # Verify PowerCLI Multiple VIServer mode — deferred from startup so the menu appears immediately.
    # VCF.PowerCLI is already loaded by this point (Connect-SddcManager ran first), so this is fast.
    Test-PowerCliMultipleVIServerMode

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    # Cache domains and credentials once to avoid redundant API calls throughout function.
    Write-LogMessage -Type DEBUG -Message "Caching domain and credential information..."
    $allDomainsResult = Invoke-VcfGetDomains -ErrorAction SilentlyContinue
    [array]$allDomains = if ($allDomainsResult -and $allDomainsResult.PSObject.Properties['Elements']) { @($allDomainsResult.Elements) } else { @() }
    if (-not $allDomains) {
        Write-LogMessage -Type WARNING -Message "Unable to retrieve workload domains from SDDC Manager. SSO domain routing may be incomplete."
    }

    # Initialize access denied flag and attempt to retrieve credentials.
    $accessDenied = $false
    try {
        [array]$allCredentials = @((Invoke-VcfGetCredentials -AccountType SYSTEM -ResourceType PSC -ErrorAction Stop).Elements)
    } catch {
        switch -Regex ($_.Exception.Message) {
            "is not recognized as.*name of a cmdlet" {
                Write-LogMessage -Type ERROR -Message "VCF.PowerCLI cmdlet 'Invoke-VcfGetCredentials' not found. Please ensure VCF.PowerCLI $minimumVcfPowerCliVersion or later is installed."
                Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
            }
            "Forbidden" { $accessDenied = $true }
        }
        $allCredentials = @()
    }

    if (-not $allDomains) {
        Write-LogMessage -Type ERROR -Message "Unable to retrieve domain information from SDDC Manager."
        return
    }

    $mgmtDomain = $allDomains | Where-Object {$_.Type -eq "MANAGEMENT"} | Select-Object -First 1
    if (-not $mgmtDomain) {
        Write-LogMessage -Type ERROR -Message "No MANAGEMENT domain found in SDDC Manager. Cannot retrieve management SSO credentials."
        Show-AnyKey
        Show-MainMenu
        return
    }
    $mgmtSsoDomainElements = $allCredentials | Where-Object { $_.Resource.DomainNames -eq $($mgmtDomain.Name) -and $_.Username -match "@$($mgmtDomain.SsoName)" } | Select-Object -First 1

    Write-LogMessage -Type DEBUG -Message "Cached $($allDomains.Count) domain(s) and $($allCredentials.Count) credential(s)."

    # Intercept disconnected vCenter calls. Guard against $Global:DefaultViServers not existing before any vCenter connection.
    [array]$DisconnectedVcenters = @(Get-Variable -Name 'DefaultViServers' -Scope Global -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value | Where-Object IsConnected -eq $false | Select-Object -ExpandProperty Name)

    $reconnectedVcenters = @()

    if ($DisconnectedVcenters) {

        foreach ($VcenterName in $DisconnectedVcenters) {
            # Use cached credentials to avoid redundant API calls.
            $vcenterCred = $allCredentials | Where-Object { $_.Resource.ResourceName -eq $VcenterName } | Select-Object -First 1
            $vcenterUserName = if ($vcenterCred) { $vcenterCred.Username } else { $null }

            if (-not $vcenterUserName) {
                # Check if the domain uses a shared SSO (use cached domains).
                $vcenterDomain = $allDomains | Where-Object {$_.Vcenters.fqdn -eq $VcenterName} | Select-Object -First 1
                if ($vcenterDomain -and $vcenterDomain.IsManagementSsoDomain -eq $true) {
                    $vcenterUserName = $mgmtSsoDomainElements.Username
                    $secureVcenterPassword = ConvertTo-SecureString -String $mgmtSsoDomainElements.Password -AsPlainText -Force
                }
            } else {
                $vcenterPassword = $vcenterCred.Password
                $secureVcenterPassword = ConvertTo-SecureString -String $vcenterPassword -AsPlainText -Force
            }
            Remove-Variable -ErrorAction SilentlyContinue -Name VcenterPassword
            $vcenterCredential = New-Object System.Management.Automation.PSCredential($vcenterUserName, $secureVcenterPassword)

            $ConnectedToVcenterServer = $null
            try {
                $ConnectedToVcenterServer = Connect-VIServer -Server $VcenterName -Credential $vcenterCredential -ErrorAction Stop
            } catch {
                if ($_.Exception.Message -match "is not recognized as.*name of a cmdlet") {
                    Write-LogMessage -Type ERROR -Message "VCF.PowerCLI cmdlet 'Connect-VIServer' not found. Please ensure VMware.VimAutomation.Core module is loaded."
                    Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
                }
                Write-LogMessage -Type ERROR -Message "Failed to re-connect to vCenter `"$VcenterName`"."
                Write-LogMessage -Type ERROR -Message "$($_.Exception.InnerException.Message)"
            }

            if ($ConnectedToVcenterServer) {
                $reconnectedVcenters += $VcenterName
                Write-LogMessage -Type INFO -AppendNewLine -Message "Successfully reconnected to vCenter `"$VcenterName`"."
            }
        }
    }

    # List all connected vCenter(s). Guard against $Global:DefaultViServers not existing before any vCenter connection.
    [array]$ConnectedVcenters = @(Get-Variable -Name 'DefaultViServers' -Scope Global -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value | Where-Object IsConnected -eq $true | Select-Object -ExpandProperty Name)
    if ($ConnectedVcenters) {
        foreach ($VcenterName in $ConnectedVcenters) {
            # Don't perform a vC disconnect if we just reconnected that vCenter a moment before.
            if (-not $reconnectedVcenters.Contains($VcenterName)) {
                Write-LogMessage -Type ADVISORY -AppendNewLine -Message "Already connected to vCenter `"$VcenterName`"."
                Disconnect-Vcenter -VcenterName $VcenterName
            }
        }
    }

    if (-not $Script:Headless) {
        Write-Host "The following vCenter(s) were detected in SDDC Manager `"$Global:SddcManagerFqdn`": `n" -ForegroundColor Green
    }

    # Use cached domain information (already retrieved and validated at function start).
    $response = $allDomains | Sort-Object
    Write-LogMessage -Type DEBUG -Message "Response type: $($response.GetType().Name)"
    if ($response) {
        Write-LogMessage -Type DEBUG -Message "First workload domain name: $($response[0].Name)"
        Write-LogMessage -Type DEBUG -Message "First domain vCenter: $($response[0].Vcenters.fqdn)"
    }

    # Prepare a selection menu of options based on generated IDs.
    $vcenterDisplayObject = @()
    $vcenterIndex = 1

    # Sort vCenters by name before building display list.
    $sortedVcenters = $response | Sort-Object -Property { $_.Vcenters.fqdn }

    # Add header rows to the array (with explicit 2-space padding to match the calculated column behavior).
    $vcenterDisplayObject += [pscustomobject]@{
        'Id'                 = "  Id"
        'NumericId'          = $null
        'VcenterName'        = "vCenter"
        'WorkloadDomainName' = "Workload Domain"
    }

    $vcenterDisplayObject += [pscustomobject]@{
        'Id'                 = "  --"
        'NumericId'          = $null
        'VcenterName'        = "-------"
        'WorkloadDomainName' = "---------------"
    }

    # First option is to connect to all vCenters.
    $vcenterDisplayObject += [pscustomobject]@{
        'Id'                  = "  {0,2}" -f $vcenterIndex
        'NumericId'           = $vcenterIndex
        'VcenterName'         = "<ALL VCENTERS>"
        'WorkloadDomainName'  = "N/A"
    }

    foreach ($line in $sortedVcenters) {
        $vcenterIndex++
        Write-LogMessage -Type DEBUG -Message "Adding vCenter: $($line.Vcenters.fqdn) (Domain: $($line.Name))"
        $vcenterDisplayObject += [pscustomobject]@{
            'Id'                 = "  {0,2}" -f $vcenterIndex
            'NumericId'          = $vcenterIndex
            'VcenterName'        = $line.Vcenters.fqdn
            'WorkloadDomainName' = $line.Name
        }
    }

    # Only present a selection choice for interactive mode.
    if (-not $Script:Headless) {
        Write-LogMessage -Type DEBUG -Message "VcenterDisplayObject count: $(@($vcenterDisplayObject).Count)"
        Write-LogMessage -Type DEBUG -Message "Response Elements count: $(@($response).Count)"

        # Log vCenter list in JSON format for complete data (skip header rows and <ALL VCENTERS> option).
        if ($vcenterDisplayObject.Count -gt 3) {
            Write-LogMessage -Type DEBUG -Message "=== vCenter List ($(($vcenterDisplayObject.Count - 3)) vCenters) ==="
            $vcenterJson = $vcenterDisplayObject[3..($vcenterDisplayObject.Count - 1)] |
                Select-Object VcenterName, WorkloadDomainName | ConvertTo-Json -Depth 2
            foreach ($line in ($vcenterJson -split "`r?`n")) {
                if ($line) { Write-LogMessage -Type DEBUG -Message $line }
            }
            Write-LogMessage -Type DEBUG -Message "=== End of vCenter List ==="
        }

        Write-LogMessage -Type DEBUG -Message "Displaying vCenter selection table..."

        # Manually format the table to avoid Format-Table's first-row whitespace trimming bug.
        # PowerShell's Format-Table has a quirk where it strips leading whitespace from the first row
        # even when using -HideTableHeaders and calculated columns with expressions like @{Expression = " "}.
        # This causes inconsistent alignment where the first row (header) appears left-justified while
        # subsequent rows are properly indented. Using manual formatting with -f operator ensures
        # consistent 2-space left indentation across all rows.
        # Note: The Id field contains pre-formatted strings with leading spaces for display ("  Id", "   1"),
        # while NumericId contains the actual numeric values (1, 2) used for selection logic.
        foreach ($row in $vcenterDisplayObject) {
            Write-Host ("{0} {1,-29} {2}" -f $row.Id, $row.VcenterName, $row.WorkloadDomainName)
        }
        Write-Host "`nThis script can only transition vLCM baseline-managed clusters and standalone hosts for connected vCenter(s).`n" -ForegroundColor Yellow
    }

    # Verify management SSO credentials are available before entering the selection loop.
    # Operator and Viewer roles do not have access to SSO credentials.
    if (-not $mgmtSsoDomainElements) {
        if ($accessDenied -eq $true) {
            Write-LogMessage -Type ERROR -Message "Your SDDC Manager SSO user does not have sufficient access. Please reconnect to SDDC Manager as a user with the ADMIN role."
        } else {
            Write-LogMessage -Type ERROR -Message "Cannot retrieve vCenter credentials from SDDC Manager."
        }
        Show-AnyKey
        Show-MainMenu
        return
    }
    $mgmtSsoDomainUsername = $($mgmtSsoDomainElements).Username
    $mgmtSsoDomainPassword = ConvertTo-SecureString -String $($mgmtSsoDomainElements).Password -AsPlainText -Force

    # Destroy the variable that contains a non-secured password, now that it's no longer needed.
    Clear-Variable -Name MgmtSsoDomainElements

    # Headless operations automatically connects to all vCenter(s). Mock the <ALL VCENTERS> connection choice
    # to reduce complexity. Set once before the loop as headless mode never re-prompts.
    if ($Script:Headless) {
        $allVcentersEntry = $vcenterDisplayObject | Where-Object {$_.VcenterName -eq "<ALL VCENTERS>"} | Select-Object -First 1
        $VersionSelection = if ($allVcentersEntry) { $allVcentersEntry.NumericId } else { $null }
    }

    Do {

    if (-not $Script:Headless) {
        $VersionSelection = Read-Host "Enter an id, a comma-delimited list of ids of vCenters to connect to, or type 'c' to cancel (default: 1)"

        if ($VersionSelection -eq "c") {
            return
        }

        # Default to option 1 (all vCenters) when the user presses Enter without a selection.
        if ([string]::IsNullOrWhiteSpace($VersionSelection)) {
            $VersionSelection = "1"
        }

        Write-Host ""
    }

    # Check if the user selected to Connect to ALL VCENTERS.
    $selectedVcenterEntry = $vcenterDisplayObject | Where-Object {$_.NumericId -eq $VersionSelection} | Select-Object -First 1
    $selectedVcenterIds = @()
    if ($selectedVcenterEntry -and $selectedVcenterEntry.VcenterName -eq "<ALL VCENTERS>") {
        # The first index value is "<ALL-VCENTERS>" followed by individual vCenters.
        for ($i = 2; $i -le $vcenterIndex; $i+=1) {
            $selectedVcenterIds += $i
        }
    } else {
        $selectedVcenterIds = $VersionSelection.Split(",")
    }
    # Create an array of vCenters based on the user's selection.
    Write-LogMessage -Type INFO -PrependNewLine -Message "Preparing to connect to vCenter(s)..."
    $badId = $false
        foreach ($selectedVcenterId in ($selectedVcenterIds | Get-Unique)) {

        $vcenterEntry = $vcenterDisplayObject | Where-Object {$_.NumericId -eq $selectedVcenterId} | Select-Object -First 1
        $selectedVcenterName = if ($vcenterEntry) { $vcenterEntry.VcenterName } else { $null }
        if ([String]::IsNullOrEmpty($selectedVcenterName)) {
            Write-LogMessage -Type ERROR -Message "$selectedVcenterId identifier or delimiter not valid. Please re-enter your selection."
            $badId = $true
            # If the Id is bad immediately break and ask the user to re-enter their selection.
            break
        } else {
            # Check for bad user input (individual and all vCenter options are mutually exclusive).
            if ($selectedVcenterName -ne "<ALL VCENTERS>") {

                # Check if the selected Workload Domain uses the MGMT SSO domain (use cached domains).
                $VcenterName = $vcenterEntry.VcenterName
                $WorkloadDomainName = $vcenterEntry.WorkloadDomainName
                $workloadDomain = $allDomains | Where-Object {$_.Name -eq $WorkloadDomainName} | Select-Object -First 1
                if (-not $workloadDomain) {
                    Write-LogMessage -Type ERROR -Message "Workload domain `"$WorkloadDomainName`" not found in SDDC Manager. Skipping vCenter `"$VcenterName`"."
                    continue
                }
                $sharedSsoDomain = $workloadDomain.IsManagementSsoDomain

                if ($sharedSsoDomain -eq $true) {
                    $vcenterCredential = New-Object System.Management.Automation.PSCredential($mgmtSsoDomainUsername, $mgmtSsoDomainPassword)
                } else {
                    # Get isolated domain credentials from cached credentials.
                    $isolatedWldSsoDomainElements = $allCredentials | Where-Object { $_.Resource.DomainNames -eq $workloadDomain.Name -and $_.Username -match "@$($workloadDomain.SsoName)" } | Select-Object -First 1
                    if (-not $isolatedWldSsoDomainElements) {
                        Write-LogMessage -Type ERROR -Message "No credentials found for workload domain `"$WorkloadDomainName`". Skipping vCenter `"$VcenterName`"."
                        continue
                    }
                    $isolatedWldSsoDomainUsername = $isolatedWldSsoDomainElements.Username
                    $isolatedWldSsoDomainPassword = ConvertTo-SecureString -String $isolatedWldSsoDomainElements.Password -AsPlainText -Force
                    # Destroy the variable that contains the non-secured password, now that it's no longer needed.
                    Clear-Variable -Name IsolatedWldSsoDomainElements
                    $vcenterCredential = New-Object System.Management.Automation.PSCredential($isolatedWldSsoDomainUsername, $isolatedWldSsoDomainPassword)
                    # Zero the plaintext username variable after it has been consumed.
                    Remove-Variable -ErrorAction SilentlyContinue -Name isolatedWldSsoDomainUsername
                }

                $ConnectedToVcenterServer = $null
                try {
                    $ConnectedToVcenterServer = Connect-VIServer -Server $VcenterName -Credential $vcenterCredential -ErrorAction Stop
                } catch {
                    if ($_.Exception.Message -match "is not recognized as.*name of a cmdlet") {
                        Write-LogMessage -Type ERROR -Message "VCF.PowerCLI cmdlet 'Connect-VIServer' not found. Please ensure VMware.VimAutomation.Core module is loaded."
                        Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
                    }
                    Write-LogMessage -Type ERROR -Message "Failed to connect to vCenter `"$VcenterName`"."
                    Write-LogMessage -Type ERROR -Message "$($_.Exception.InnerException.Message)"
                }

                if ($ConnectedToVcenterServer) {
                    Write-LogMessage -Type INFO -Message "Successfully connected to vCenter `"$VcenterName`"."
                }

                } else {
                    Write-LogMessage -Type ERROR -Message "Individual vCenter and <ALL VCENTERS> option selected. Ignoring '<ALL VCENTERS>.'"
                    Write-Host ""
                }
                $badId = $false
            }
        }
    } While ($badId -eq $true)

    Write-Host ""

    # Detect whether this SDDC is VxRail-managed and set $Script:vxRailMode accordingly.
    Set-VxRailMode
}
Function Test-VcentersConnection {

    <#
        .SYNOPSIS
        Ensures vCenter connections are established and active.

        .DESCRIPTION
        This function checks for active vCenter connections and automatically attempts
        reconnection if any are missing or disconnected. It acts as an auto-healing
        helper function rather than a validation gate.

        The function performs two checks:
        1. Verifies that vCenter connection objects exist in $Global:DefaultViServers
        2. Checks that all vCenter servers have IsConnected = $true

        If either check fails, the function automatically calls Connect-Vcenter to
        establish or restore connections. This auto-healing behavior allows the script
        to recover from transient connection issues without user intervention.

        .EXAMPLE
        Test-VcentersConnection

        Checks vCenter connectivity and automatically reconnects if needed.

        .OUTPUTS
        Boolean
        Returns $true if all vCenter connections are active, $false if reconnection failed.

        .NOTES
        This function does not exit the script on failure - it attempts automatic
        reconnection instead. This is intentional auto-healing behavior for resilience.
    #>

    # Check if any vCenter(s) are known. Guard against $Global:DefaultViServers not existing before PowerCLI connects.
    Write-LogMessage -Type DEBUG -Message "Entered Test-VcentersConnection function..."

    [array]$defaultViServersVal = @(Get-Variable -Name 'DefaultViServers' -Scope Global -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value)

    if (@($defaultViServersVal).Count -eq 0) {
        Write-LogMessage -Type DEBUG -Message "No vCenter connections found. Initiating connection workflow..."
        Connect-Vcenter

        # Verify connection was established.
        [array]$defaultViServersVal = @(Get-Variable -Name 'DefaultViServers' -Scope Global -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value)
        if (@($defaultViServersVal).Count -eq 0) {
            Write-LogMessage -Type ERROR -Message "Failed to establish vCenter connections. Some operations may not be available."
            return $false
        }
        Write-LogMessage -Type DEBUG -Message "vCenter connections established successfully."
        return $true
    }

    # Check if any vCenter are in a disconnected state.
    [array]$DisconnectedVcenters = @($defaultViServersVal | Where-Object IsConnected -eq $false | Select-Object -ExpandProperty Name)

    if ($DisconnectedVcenters.Count -gt 0) {
        # Log each disconnected vCenter for visibility.
        foreach ($DisconnectedVcenter in $DisconnectedVcenters) {
            Write-LogMessage -Type ERROR -Message "vCenter `"$DisconnectedVcenter`" is disconnected."
        }

        Write-LogMessage -Type INFO -Message "Automatically reconnecting to vCenter(s)..."
        Connect-Vcenter

        # Verify reconnection was successful.
        [array]$defaultViServersVal = @(Get-Variable -Name 'DefaultViServers' -Scope Global -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value)
        [array]$stillDisconnected = @($defaultViServersVal | Where-Object IsConnected -eq $false | Select-Object -ExpandProperty Name)
        if ($stillDisconnected.Count -gt 0) {
            Write-LogMessage -Type ERROR -Message "Failed to reconnect to: $($stillDisconnected -join ', ')"
            return $false
        }

        Write-LogMessage -Type DEBUG -Message "All vCenter connections restored successfully."
        return $true
    }

    # All vCenters are connected - silent success.
    $ConnectedCount = $defaultViServersVal.Count
    $ConnectedVcenters = ($defaultViServersVal | ForEach-Object { $_.Name }) -join ", "
    Write-LogMessage -Type DEBUG -Message "vCenter connection verified. $ConnectedCount vCenter(s) connected: $ConnectedVcenters"
    # Ensure vxRailMode reflects the current vCenter connections even when Connect-Vcenter was not called.
    if (-not $Script:vxRailModeDetected) {
        Set-VxRailMode
    }
    return $true
}
#endregion

#region Baseline and Compliance
Function Get-BaselineManagedResourceList {

    <#
        .SYNOPSIS
        Internal helper function to discover baseline-managed clusters and standalone hosts.

        .DESCRIPTION
        This function queries SDDC Manager APIs to discover:
        1. Clusters that are baseline (VUM) managed (isImageBased = false)
        2. Standalone hosts that are baseline managed and not lifecycle managed

        The function caches domain lookups for performance and verifies standalone hosts
        by checking their vCenter cluster membership to avoid false positives.

        .OUTPUTS
        Array of PSCustomObject
        Returns an array of resource objects with the following properties:
        - ResourceId: The unique identifier for the resource
        - ResourceName: The name of the cluster or FQDN of the standalone host
        - ResourceType: Either "Cluster" or "Standalone Host"
        - WorkloadDomainId: The workload domain ID
        - WorkloadDomainName: The workload domain name

        .EXAMPLE
        $resources = Get-BaselineManagedResourceList
        foreach ($resource in $resources) {
            Write-Host "$($resource.ResourceType): $($resource.ResourceName)"
        }

        .NOTES
        This is an internal helper function used by Get-BaselineManagedResources and
        Show-ImageComplianceCheckResults to avoid code duplication.
    #>

    Write-LogMessage -Type DEBUG -Message "Entered Get-BaselineManagedResourceList function..."

    # Start timing the resource discovery process.
    $scanTimer = Start-ProcessTimer

    $resources = @()

    # Discover and process clusters.
    Write-LogMessage -Type DEBUG -Message "Retrieving baseline-managed clusters..."
    try {
        $clustersResult = Invoke-VcfGetClusters -IsImageBased $false -ErrorAction Stop
        [array]$clusters = if ($clustersResult -and $clustersResult.PSObject.Properties['Elements']) { @($clustersResult.Elements) } else { @() }
    } catch {
        switch -Regex ($_.Exception.Message) {
            "is not recognized as.*name of a cmdlet" {
                Write-LogMessage -Type ERROR -Message "VCF.PowerCLI cmdlet 'Invoke-VcfGetClusters' not found. Please ensure VCF.PowerCLI $minimumVcfPowerCliVersion or later is installed."
                Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
            }
            "The request was canceled|timeout" { Write-LogMessage -Type ERROR -Message "Network timeout connecting to SDDC Manager." }
            default { Write-LogMessage -Type ERROR -Message "Failed to retrieve clusters: $($_.Exception.Message)" }
        }
        [array]$clusters = @()
    }

    Write-LogMessage -Type DEBUG -Message "Found $($clusters.Count) total cluster(s), filtering for baseline-managed clusters..."

    if ($clusters) {
        # Cache domain lookups to avoid redundant API calls.
        Write-LogMessage -Type DEBUG -Message "Caching workload domain details for $($clusters.Count) cluster(s)..."
        $domainCache = @{}
        $uniqueDomainIds = $clusters.Domain.Id | Select-Object -Unique

        foreach ($domainId in $uniqueDomainIds) {
            if (-not $domainCache.ContainsKey($domainId)) {
                try {
                    $domainName = (Invoke-VcfGetDomain -id $domainId -ErrorAction Stop).Name
                } catch {
                    Write-LogMessage -Type WARNING -Message "Could not retrieve workload domain details for domain ID `"$domainId`": $($_.Exception.Message)"
                    $domainName = $null
                }
                $domainCache[$domainId] = $domainName
                Write-LogMessage -Type DEBUG -Message "Cached workload domain details: WLD Name: `"$domainName`" (WLD ID: `"$domainId`")"
            }
        }

        # Process each cluster using cached data.
        foreach ($cluster in $clusters) {
            $resources += [pscustomobject]@{
                WorkloadDomainId   = $cluster.Domain.Id
                WorkloadDomainName = $domainCache[$cluster.Domain.Id]
                ResourceId         = $cluster.Id
                ResourceName       = $cluster.Name
                ResourceType       = "Cluster"
            }
        }

        Write-LogMessage -Type DEBUG -Message "Processed $($clusters.Count) baseline-managed cluster(s)."
    }

    if (-not $clusters) {
        Write-LogMessage -Type DEBUG -Message "No baseline-managed clusters located."
    }

    # Discover and process standalone hosts.
    Write-LogMessage -Type DEBUG -Message "Retrieving baseline-managed standalone hosts..."
    $standaloneHostsResult = Invoke-VcfGetHosts -isStandalone $true -isLifeCycleManaged $false -ErrorAction SilentlyContinue
    [array]$standaloneHosts = if ($standaloneHostsResult -and $standaloneHostsResult.PSObject.Properties['Elements']) { @($standaloneHostsResult.Elements | Sort-Object -Property Fqdn) } else { @() }
    if (-not $standaloneHosts) {
        Write-LogMessage -Type DEBUG -Message "No baseline-managed standalone hosts found in SDDC Manager."
    }

    if ($standaloneHosts) {
        # Optimization: Get all VMHosts in one API call instead of per-host lookups.
        Write-LogMessage -Type DEBUG -Message "Retrieving all vCenter hosts for cluster membership verification..."
        $vmHostTimer = Start-ProcessTimer
        $allVmHosts = Get-VMHost -ErrorAction SilentlyContinue
        Stop-ProcessTimer -Timer $vmHostTimer -Operation "Get-VMHost (bulk retrieval)" -Interval "Seconds"

        # Create a hashtable for fast lookups (key = FQDN lowercase, value = VMHost object).
        $vmHostLookup = @{}
        if ($allVmHosts) {
            foreach ($vmHost in $allVmHosts) {
                $vmHostLookup[$vmHost.Name.ToLower()] = $vmHost
            }
            Write-LogMessage -Type DEBUG -Message "Built hashtable lookup for $($allVmHosts.Count) vCenter host(s)"
        }

        foreach ($hostDetail in $standaloneHosts) {
            # Verify host is truly standalone by checking cluster membership in vCenter.
            # The SDDC Manager API -isStandalone flag can incorrectly return clustered hosts in older versions.
            $vmHost = $vmHostLookup[$hostDetail.Fqdn.ToLower()]

            if ($vmHost -and $vmHost.Parent -and $vmHost.Parent.GetType().Name -eq "ClusterImpl") {
                # Host is actually in a cluster, skip it.
                Write-LogMessage -Type DEBUG -Message "Skipping host `"$($hostDetail.Fqdn)`" - detected as cluster member (Parent: $($vmHost.Parent.Name))"
                continue
            }

            $resources += [pscustomobject]@{
                WorkloadDomainId   = $hostDetail.Domain.Id
                WorkloadDomainName = $hostDetail.Domain.Name
                ResourceId         = $hostDetail.Id
                ResourceName       = $hostDetail.Fqdn
                ResourceType       = "Standalone Host"
            }
        }

        Write-LogMessage -Type DEBUG -Message "Processed $($standaloneHosts.Count) baseline-managed standalone host(s), $(@($resources | Where-Object {$_.ResourceType -eq 'Standalone Host'}).Count) verified as truly standalone."
    }

    if (-not $standaloneHosts) {
        Write-LogMessage -Type DEBUG -Message "No baseline-managed standalone hosts located."
    }

    # Stop timing and log performance metrics.
    Stop-ProcessTimer -Timer $scanTimer -Operation "Baseline-managed resource scan" -Interval "Seconds"
    Write-LogMessage -Type DEBUG -Message "Total baseline-managed resources discovered: $(@($resources).Count)"

    return @($resources)
}
Function Get-BaselineManagedResources {

    <#
        .SYNOPSIS
        The function Get-BaselineManagedResources displays vLCM baseline (VUM) managed resources.

        .DESCRIPTION
        This function queries two distinct APIs, one the v1 API to look for clusters that have isImageBased equal to
        false and then the v2 API for STAND_ALONE_HOSTS_WITH_BASELINE.

        .EXAMPLE
        Get-BaselineManagedResources -IdSelection 3

        Displays baseline-managed resources and allows selection by ID 3.

        .EXAMPLE
        Get-BaselineManagedResources -JsonOutputFile VlcmBaseManagedCluster.json

        Exports all baseline-managed resources to a JSON file including SDDC Manager image names.

        .EXAMPLE
        Get-BaselineManagedResources -JsonOutputFile resources.json -ExcludeSddcManagerImageName

        Exports baseline-managed resources to JSON without the SDDC Manager image name field.
        This is useful for generating input files for compliance checks using image seeding from vCenter.

        .PARAMETER IdSelection
        Specifies the Id of resources selected for transition to vLCM Image Management.

        .PARAMETER JsonOutputFile
        Specifies if the findings should be saved to a JSON file.

        .PARAMETER ExcludeSddcManagerImageName
        When specified with -JsonOutputFile, excludes the SDDC Manager image name from the JSON output.
        Useful when generating input for compliance checks that will use vCenter image seeding.

        .OUTPUTS
        None
        This function does not return a value. It displays baseline-managed resources interactively or exports to JSON.
    #>

    Param (
        [Parameter(Mandatory = $false)] [Switch]$ExcludeSddcManagerImageName,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$IdSelection,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$JsonOutputFile
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-BaselineManagedResources function..."

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection
    # Check if connected to vCenter(s). Return early if user cancels or connection fails.
    $vCenterConnected = Test-VcentersConnection
    if (-not $vCenterConnected) { return }

    # Id selection is only called when the array $Script:VlcmBaselineManagedResourcesDisplayObject has been populated only moments before.
    # by a scan for eligible resources.  Therefore, we can bypass re-generation of these resources.
    if ($IdSelection) {

        $selectedResources=@()

        foreach ($selectedResourceId in $IdSelection.Split(",")) {
            # Trim whitespace and skip empty entries.
            $selectedResourceId = $selectedResourceId.Trim()
            if ([String]::IsNullOrEmpty($selectedResourceId)) {
                continue
            }

            # Cache the lookup to avoid 6 redundant array searches.
            $selectedResource = $Script:VlcmBaselineManagedResourcesDisplayObject | Where-Object {$_.Id -eq $selectedResourceId} | Select-Object -First 1

            if (-not $selectedResource) {
                Write-LogMessage -Type WARNING -Message "Resource ID '$selectedResourceId' not found in display object. Skipping."
                continue
            }

            $selectedResources += [pscustomobject]@{
                'ResourceId'           = $selectedResource.ResourceId
                'ResourceName'         = $selectedResource.ResourceName
                'ResourceType'         = $selectedResource.ResourceType
                'WorkloadDomainId'     = $selectedResource.WorkloadDomainId
                'WorkloadDomainName'   = $selectedResource.WorkloadDomainName
                'ImageSeedingSupport'  = $selectedResource.ImageSeedingSupport
            }
        }
        return $selectedResources
    }

    $Script:VlcmBaselineManagedResourcesDisplayObject = @()
    $vlcmBaselineManagedResourceIndex = 1

    $Script:VlcmBaselineManagedResourcesDisplayObject += [pscustomobject]@{
        'Id'                   = "Id"
        'ResourceName'         = "Resource Name"
        'ResourceType'         = "Resource Type"
        'ResourceId'           = "Resource Id"
        'VcenterName'          = "vCenter Name"
        'WorkloadDomainName'   = "Workload Domain"
        'WorkloadDomainId'     = "Workload Domain Id"
        'ComplianceStatus'     = "Compliance Status"
        'SddcManagerImageName' = "SDDC Manager Image Name"
    }

    $Script:VlcmBaselineManagedResourcesDisplayObject += [pscustomobject]@{
        'Id'                   = "--"
        'ResourceName'         = "-------------"
        'ResourceType'         = "-------------"
        'ResourceId'           = "-"
        'VcenterName'          = "------------"
        'WorkloadDomainName'   = "---------------"
        'WorkloadDomainId'     = "-"
        'ComplianceStatus'     = "-----------------"
        'SddcManagerImageName' = "-----------------------"
    }
    if ($Script:Headless) {
        Write-LogMessage -Type INFO -AppendNewLine -Message "Scanning for vLCM baseline (VUM) managed clusters/standalone-hosts..."
    }

    # Initialize domain cache for display/interactive mode to avoid redundant API calls.
    $domainCache = @{}

    # Retrieve all clusters once and group by vCenter to avoid redundant API calls.
    try {
        $allClustersResult = Invoke-VcfGetClusters -IsImageBased $false -ErrorAction Stop
        [array]$allClusters = if ($allClustersResult -and $allClustersResult.PSObject.Properties['Elements']) { @($allClustersResult.Elements) } else { @() }
    } catch {
        switch -Regex ($_.Exception.Message) {
            "is not recognized as.*name of a cmdlet" {
                Write-LogMessage -Type ERROR -Message "VCF.PowerCLI cmdlet 'Invoke-VcfGetClusters' not found. Please ensure VCF.PowerCLI $minimumVcfPowerCliVersion or later is installed."
                Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
            }
            "The request was canceled|timeout" { Write-LogMessage -Type ERROR -Message "Network timeout connecting to SDDC Manager `"$Global:SddcManagerFqdn`"." }
            default { Write-LogMessage -Type ERROR -Message "Failed to retrieve clusters: $($_.Exception.Message)" }
        }
        [array]$allClusters = @()
    }

    # Retrieve all workload domains ONCE upfront for both cluster and standalone host processing.
    # This single bulk API call is more efficient than individual domain lookups.
    Write-LogMessage -Type DEBUG -Message "Retrieving all workload domains from SDDC Manager..."
    $allDomainsTimer = Start-ProcessTimer
    $allDomainsQueryResult = Invoke-VcfGetDomains -ErrorAction SilentlyContinue
    [array]$allDomains = if ($allDomainsQueryResult -and $allDomainsQueryResult.PSObject.Properties['Elements']) { @($allDomainsQueryResult.Elements) } else { @() }
    Stop-ProcessTimer -Timer $allDomainsTimer -Operation "Workload domains retrieval (bulk)" -Interval "Seconds"
    if (-not $allDomains) {
        Write-LogMessage -Type WARNING -Message "Unable to retrieve workload domains from SDDC Manager. Domain name lookups will be unavailable."
    }
    Write-LogMessage -Type DEBUG -Message "Retrieved $($allDomains.Count) workload domain(s) from SDDC Manager."

    # Initialize caches before cluster/standalone host processing so they are always declared.
    $clusterEsxSeedingCache = @{}
    $vcenterSeedingCache = @{}
    $esxSeedingCache = @{}

    if ($allClusters) {
        # Group clusters by vCenter FQDN for efficient processing.
        $clustersByVcenter = $allClusters | Group-Object -Property {$_.vCenter.fqdn}

        # Pre-populate domain cache from the bulk retrieval to avoid individual lookups.
        $domainCache = @{}
        if ($allDomains) {
            foreach ($domain in $allDomains) {
                $domainCache[$domain.Id] = $domain
            }
            Write-LogMessage -Type DEBUG -Message "Pre-populated domain cache with $($domainCache.Count) workload domain(s)."
        }

        # Build the connected vCenter list once before iterating to avoid repeated Get-Variable calls.
        [array]$connectedVcenterNames = @(Get-Variable -Name 'DefaultViServers' -Scope Global -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value | Select-Object -ExpandProperty Name)

        # Only process clusters for connected vCenters.
        foreach ($vcenterGroup in $clustersByVcenter) {
            $vcenterFqdn = $vcenterGroup.Name
            $clusters = $vcenterGroup.Group | Sort-Object -Property Name

            # Skip vCenters that aren't in our connected list.
            if ($vcenterFqdn -notin $connectedVcenterNames) {
                Write-LogMessage -Type DEBUG -Message "Skipping vCenter `"$vcenterFqdn`" - not in connected vCenter list."
                continue
            }

            foreach ($cluster in $clusters) {
                # Retrieve cluster compliance status (with API call, but relatively fast).
                try {
                    $clusterImageCompliance = Invoke-VcfGetClusterImageCompliance -Id ($cluster.Id) -ErrorAction Stop
                } catch {
                    # A 404 with CLUSTER_IMAGE_COMPLIANCE_NOT_FOUND is expected for clusters that have
                    # never had a compliance check run — not a real error.
                    if ($_.Exception.Message -match "CLUSTER_IMAGE_COMPLIANCE_NOT_FOUND") {
                        Write-LogMessage -Type DEBUG -Message "No compliance record found for cluster `"$($cluster.Name)`" (compliance check has not been run yet)."
                    } else {
                        Write-LogMessage -Type WARNING -Message "Could not retrieve image compliance for cluster `"$($cluster.Name)`": $($_.Exception.Message)"
                    }
                    $clusterImageCompliance = $null
                }
                $complianceStatus = if ($clusterImageCompliance -and $clusterImageCompliance.PSObject.Properties['Status']) { $clusterImageCompliance.Status } else { $null }
                if (-not $complianceStatus) {
                    $complianceStatus = "NOT_CHECKED_YET"
                }

                $SddcManagerImageName = if ($clusterImageCompliance -and $clusterImageCompliance.PSObject.Properties['ClusterImage'] -and $clusterImageCompliance.ClusterImage) { $clusterImageCompliance.ClusterImage.Name } else { $null }

                if ((-not $SddcManagerImageName) -and ($complianceStatus -ne "NOT_CHECKED_YET")) {
                    $SddcManagerImageName = "<Autogenerated-Image>"
                } elseif ((-not $SddcManagerImageName) -and ($complianceStatus -eq "NOT_CHECKED_YET")) {
                    $SddcManagerImageName = "N/A"
                }

                # Cache vCenter seeding support check (keyed by vCenter ID) for reuse with standalone hosts.
                if (-not $vcenterSeedingCache.ContainsKey($cluster.vCenter.Id)) {
                    $vcenterSeedingCache[$cluster.vCenter.Id] = Get-VcenterImageSeedingSupport -MinimumVcenterVersion $clusterVsphereImageSeedingSupport -VcenterId $cluster.vCenter.Id
                    Write-LogMessage -Type DEBUG -Message "Cached vCenter seeding support for vCenter ID $($cluster.vCenter.Id) : $($vcenterSeedingCache[$cluster.vCenter.Id])"
                }
                $vcenterImageSeedingSupported = $vcenterSeedingCache[$cluster.vCenter.Id]

                # Cache ESX seeding support check (keyed by cluster ID) to avoid redundant API calls.
                if (-not $clusterEsxSeedingCache.ContainsKey($cluster.Id)) {
                    $clusterEsxSeedingCache[$cluster.Id] = Get-EsxImageSeedingSupport -ClusterId $cluster.Id -MinimumEsxVersion $clusterVsphereImageSeedingSupport
                    Write-LogMessage -Type DEBUG -Message "Cached ESX seeding support for cluster `"$($cluster.Name)`" (ID: $($cluster.Id)) : $($clusterEsxSeedingCache[$cluster.Id])"
                }
                $esxImageSeedingSupported = $clusterEsxSeedingCache[$cluster.Id]

                if ($vcenterImageSeedingSupported -and $esxImageSeedingSupported ) {
                    $imageSeedingSupport = "AVAILABLE"
                } else {
                    $imageSeedingSupport = "UNAVAILABLE"
                }

                # Retrieve domain from pre-populated cache (no API call needed).
                $domain = $domainCache[$cluster.Domain.Id]

                $Script:VlcmBaselineManagedResourcesDisplayObject += [pscustomobject]@{
                    'Id'                   = $vlcmBaselineManagedResourceIndex
                    'ResourceName'         = $cluster.Name
                    'ResourceType'         = "Cluster"
                    'ResourceId'           = $cluster.Id
                    'VcenterName'          = $cluster.vCenter.fqdn
                    'ImageSeedingSupport'  = $imageSeedingSupport
                    'WorkloadDomainName'   = $domain.Name
                    'WorkloadDomainId'     = $domain.Id
                    'ComplianceStatus'     = $complianceStatus
                    'SddcManagerImageName' = $SddcManagerImageName
                }
                $vlcmBaselineManagedResourceIndex++
                if ($imageSeedingSupport -ne "N/A") {
                    Write-LogMessage -SuppressOutputToScreen -Type INFO -Message "Cluster `"$($cluster.Name)`" in Workload Domain `"$($domain.Name)`" under vCenter `"$($cluster.vCenter.fqdn)`" (image seeding support is $imageSeedingSupport) is vLCM baseline (VUM) managed."
                }
            }
        }
    }
    $clusterCount = ([int]$vlcmBaselineManagedResourceIndex - 1)

    Write-LogMessage -SuppressOutputToScreen -Type INFO -Message "$clusterCount vLCM baseline-managed cluster(s) located."

    # Note: $allDomains was already retrieved earlier for optimal performance.

    # $vcenterSeedingCache and $esxSeedingCache are initialized before cluster processing above.

    Write-LogMessage -Type DEBUG -Message "Searching for standalone hosts in connected vCenter(s)..."

    # Phase 1: Collect all standalone hosts and their metadata.
    $standaloneHostsToCheck = @()

    # Optimization: Get all VMHosts in one API call instead of per-host lookups.
    Write-LogMessage -Type DEBUG -Message "Retrieving all vCenter hosts for cluster membership verification (bulk retrieval optimization)..."
    $vmHostBulkTimer = Start-ProcessTimer
    $allVmHosts = Get-VMHost -ErrorAction SilentlyContinue
    Stop-ProcessTimer -Timer $vmHostBulkTimer -Operation "Get-VMHost (bulk retrieval for standalone host verification)" -Interval "Seconds"

    # Create a hashtable for fast lookups (key = FQDN lowercase, value = VMHost object).
    $vmHostLookup = @{}
    if ($allVmHosts) {
        foreach ($vmHost in $allVmHosts) {
            $vmHostLookup[$vmHost.Name.ToLower()] = $vmHost
        }
        Write-LogMessage -Type DEBUG -Message "Built hashtable lookup for $($allVmHosts.Count) vCenter host(s) for fast cluster membership checks"
    }

    # Search for standalone hosts by connected vCenter.
    foreach ($vcenter in @(Get-Variable -Name 'DefaultViServers' -Scope Global -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value | Select-Object -ExpandProperty Name | Sort-Object)) {
        $vcenterWorkloadDomains = $allDomains.Vcenters
        foreach ($vcenterWorkloadDomain in $vcenterWorkloadDomains) {
            if ($vcenter -eq $vcenterWorkloadDomain.Fqdn) {
                # Get the domain Id for the matched vCenter from cached data.
                $matchedDomain = $allDomains | Where-Object {$_.Vcenters.Fqdn -eq $vcenterWorkloadDomain.Fqdn} | Select-Object -First 1
                $domainId = if ($matchedDomain) { $matchedDomain.Id } else { $null }
                # Query all the standalone-hosts in this domain (Workload Domain -- equivalent to vCenter)
                Write-LogMessage -Type DEBUG -Message "Querying standalone hosts for workload domain ID: $domainId (vCenter: $vcenter)..."
                $standaloneHostsDomainResult = Invoke-VcfGetHosts -isStandalone $true -isLifeCycleManaged $false -DomainId $domainId -ErrorAction SilentlyContinue
                $responseRaw = if ($standaloneHostsDomainResult -and $standaloneHostsDomainResult.PSObject.Properties['Elements']) { $standaloneHostsDomainResult.Elements } else { $null }
                [array]$response = @($responseRaw | Where-Object { $_ } | Sort-Object -Property Fqdn)
                Write-LogMessage -Type DEBUG -Message "Found $($response.Count) standalone host(s) in workload domain $domainId."

                foreach ($hostDetail in $response) {

                    # Verify host is truly standalone by checking cluster membership in vCenter.
                    # The SDDC Manager API -isStandalone flag can incorrectly return clustered hosts in older versions.
                    # Use hashtable lookup instead of individual Get-VMHost calls for performance.
                    $vmHost = $vmHostLookup[$hostDetail.Fqdn.ToLower()]
                    if ($vmHost -and $vmHost.Parent -and $vmHost.Parent.GetType().Name -eq "ClusterImpl") {
                        # Host is actually in a cluster, skip it.
                        Write-LogMessage -Type DEBUG -Message "Skipping host `"$($hostDetail.Fqdn)`" - detected as cluster member (Parent: $($vmHost.Parent.Name))"
                        continue
                    }

                    # Cache vCenter seeding support check (keyed by vCenter ID).
                    $vcenterKey = $vcenterWorkloadDomain.Id
                    if (-not $vcenterSeedingCache.ContainsKey($vcenterKey)) {
                        $vcenterSeedingCache[$vcenterKey] = Get-VcenterImageSeedingSupport -MinimumVcenterVersion $standAloneHostVsphereImageSeedingSupport -VcenterId $vcenterWorkloadDomain.Id
                        Write-LogMessage -Type DEBUG -Message "Cached vCenter seeding support for vCenter ID $vcenterKey : $($vcenterSeedingCache[$vcenterKey])"
                    }
                    $vcenterImageSeedingSupported = $vcenterSeedingCache[$vcenterKey]

                    # Cache ESX seeding support check (keyed by ESX version string).
                    $esxKey = $hostDetail.EsxiVersion
                    if (-not $esxSeedingCache.ContainsKey($esxKey)) {
                        $esxSeedingCache[$esxKey] = Get-EsxImageSeedingSupport -EsxVersion $hostDetail.EsxiVersion -MinimumEsxVersion $standAloneHostVsphereImageSeedingSupport
                        Write-LogMessage -Type DEBUG -Message "Cached ESX seeding support for ESX version $esxKey : $($esxSeedingCache[$esxKey])"
                    }
                    $esxImageSeedingSupported = $esxSeedingCache[$esxKey]
                    if ($vcenterImageSeedingSupported -and $esxImageSeedingSupported ) {
                        $imageSeedingSupport = "AVAILABLE"
                    } else {
                        $imageSeedingSupport = "UNAVAILABLE"
                    }
                    $hostId = $hostDetail.Id

                    # Collect host information for parallel compliance checking.
                    $standaloneHostsToCheck += [PSCustomObject]@{
                        HostDetail = $hostDetail
                        HostId = $hostId
                        DomainId = $domainId
                        VcenterWorkloadDomain = $vcenterWorkloadDomain
                        ImageSeedingSupport = $imageSeedingSupport
                    }
                }
            }
        }
    }

    Write-LogMessage -Type DEBUG -Message "Found $($standaloneHostsToCheck.Count) standalone host(s) total."

    # Phase 2: Initiate all compliance queries in parallel.
    # Check if SDDC Manager version supports standalone host compliance.
    if (-not $Script:CachedSddcManagerVersion) {
        $Script:CachedSddcManagerVersion = Get-SddcManagerVersion
        Write-LogMessage -Type DEBUG -Message "Cached SDDC Manager version: $Script:CachedSddcManagerVersion"
    }
    $sddcManagerVersion = $Script:CachedSddcManagerVersion
    $supportsStandaloneHostCompliance = ([Version]$sddcManagerVersion -ge [Version]$minimumSahRelease)

    if ($supportsStandaloneHostCompliance -and $standaloneHostsToCheck.Count -gt 0) {
        Write-LogMessage -Type DEBUG -Message "Initiating compliance queries for $($standaloneHostsToCheck.Count) host(s)..."
        $ParallelTimer = [System.Diagnostics.Stopwatch]::StartNew()

        # Initiate all queries sequentially in the main runspace. VCF PowerCLI cmdlets
        # (Invoke-VcfQueryDomainImageCompliance, etc.) use the current session's SDDC Manager
        # connection; ForEach-Object -Parallel runs in separate runspaces that do not inherit
        # that connection, causing "You are not currently connected to any servers."
        $queryInitTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $allQueryResults = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($hostInfo in $standaloneHostsToCheck) {
            $hostDetail = $hostInfo.HostDetail
            $hostId = $hostInfo.HostId
            $domainId = $hostInfo.DomainId
            $singleQueryTimer = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # In the v2 API for 9.0, the only valid type is HOST.
                $TransitionResourceSpec = Initialize-VcfTransitionResourceSpec -Id $hostId -Type "HOST" -ErrorAction SilentlyContinue
                $domainImageComplianceQuerySpec = Initialize-VcfDomainImageComplianceQuerySpec -Resources $TransitionResourceSpec -ErrorAction SilentlyContinue
                $queryCompliance = Invoke-VcfQueryDomainImageCompliance -DomainId $domainId -DomainImageComplianceQuerySpec $domainImageComplianceQuerySpec -ErrorAction SilentlyContinue

                $singleQueryTimer.Stop()

                if ($queryCompliance -and $queryCompliance.QueryInfo -and $queryCompliance.QueryInfo.QueryId) {
                    $allQueryResults.Add([PSCustomObject]@{
                        HostInfo = $hostInfo
                        QueryId = $queryCompliance.QueryInfo.QueryId
                        DomainId = $domainId
                        Success = $true
                        HostFqdn = $hostDetail.Fqdn
                        Duration = $singleQueryTimer.Elapsed.TotalSeconds
                    })
                } else {
                    $allQueryResults.Add([PSCustomObject]@{
                        HostInfo = $hostInfo
                        QueryId = $null
                        DomainId = $domainId
                        Success = $false
                        HostFqdn = $hostDetail.Fqdn
                        Duration = $singleQueryTimer.Elapsed.TotalSeconds
                    })
                }
            } catch {
                $singleQueryTimer.Stop()
                $allQueryResults.Add([PSCustomObject]@{
                    HostInfo = $hostInfo
                    QueryId = $null
                    DomainId = $domainId
                    Success = $false
                    HostFqdn = $hostDetail.Fqdn
                    Duration = $singleQueryTimer.Elapsed.TotalSeconds
                    Error = $_.Exception.Message
                })
            }
        }

        $queryInitTimer.Stop()
        $successfulQueries = @($allQueryResults | Where-Object { $_.Success -eq $true })

        # Log individual query results
        foreach ($result in $allQueryResults) {
            if ($result.Success) {
                Write-LogMessage -Type DEBUG -Message "Query ID $($result.QueryId) received for host `"$($result.HostFqdn)`" (took $([Math]::Round($result.Duration, 2))s)."
            } else {
                if ($result.Error) {
                    Write-LogMessage -Type DEBUG -Message "Unable to initiate compliance query for host `"$($result.HostFqdn)`" (took $([Math]::Round($result.Duration, 2))s): $($result.Error)"
                } else {
                    Write-LogMessage -Type DEBUG -Message "Unable to initiate compliance query for host `"$($result.HostFqdn)`" (took $([Math]::Round($result.Duration, 2))s)."
                }
            }
        }

        Write-LogMessage -Type DEBUG -Message "Query initiation phase completed in $([Math]::Round($queryInitTimer.Elapsed.TotalSeconds, 2))s (average: $([Math]::Round($queryInitTimer.Elapsed.TotalSeconds / $standaloneHostsToCheck.Count, 2))s per host)."
        Write-LogMessage -Type DEBUG -Message "All queries initiated ($($successfulQueries.Count)/$($standaloneHostsToCheck.Count) successful). Polling for completion..."

        # Filter to only successful queries for polling
        $activeQueries = $successfulQueries

        # Allow time for all queries to be posted to SDDC Manager API.
        Start-Sleep -Milliseconds 500

        # Phase 3: Poll all queries together until all complete or timeout.
        $timeout = 60  # seconds
        $pollInterval = 100  # milliseconds
        $completedQueries = @{}

        $pollTimer = [System.Diagnostics.Stopwatch]::StartNew()
        while ($activeQueries.Count -gt 0 -and $pollTimer.Elapsed.TotalSeconds -lt $timeout) {
            $stillActive = @()

            foreach ($query in $activeQueries) {
                $queryInfo = Invoke-VcfGetDomainImageComplianceQueryResponse -DomainId $query.DomainId -QueryId $query.QueryId -ErrorAction SilentlyContinue

                $queryInfoStatus = if ($queryInfo -and $queryInfo.PSObject.Properties['QueryInfo'] -and $queryInfo.QueryInfo -and $queryInfo.QueryInfo.PSObject.Properties['Status']) { $queryInfo.QueryInfo.Status } else { $null }
                switch ($queryInfoStatus) {
                    "COMPLETED" {
                        $completedQueries[$query.QueryId] = $queryInfo
                        Write-LogMessage -Type DEBUG -Message "Query $($query.QueryId) completed for host `"$($query.HostInfo.HostDetail.Fqdn)`"."
                    }
                    "IN_PROGRESS" {
                        # Still in progress - keep polling.
                        $stillActive += $query
                    }
                    default {
                        # Failed or no response - mark as failed.
                        Write-LogMessage -Type DEBUG -Message "Query $($query.QueryId) failed for host `"$($query.HostInfo.HostDetail.Fqdn)`"."
                    }
                }
            }

            $activeQueries = $stillActive

            if ($activeQueries.Count -gt 0) {
                Start-Sleep -Milliseconds $pollInterval
            }
        }
        $pollTimer.Stop()

        $ParallelTimer.Stop()
        Write-LogMessage -Type DEBUG -Message "Parallel compliance check completed: $($completedQueries.Count)/$($standaloneHostsToCheck.Count) queries successful in $([Math]::Round($ParallelTimer.Elapsed.TotalSeconds, 2))s"

        # Phase 4: Process results and build display objects.
        foreach ($hostInfo in $standaloneHostsToCheck) {
            $hostDetail = $hostInfo.HostDetail
            $hostId = $hostInfo.HostId
            $domainId = $hostInfo.DomainId
            $vcenterWorkloadDomain = $hostInfo.VcenterWorkloadDomain
            $imageSeedingSupport = $hostInfo.ImageSeedingSupport

            # Find matching query result by hostId.
            # The structure is: Result.Elements.Resource.Id contains the host ID.
            $queryInfo = $null
            Write-LogMessage -Type DEBUG -Message "Looking for compliance result for host `"$($hostDetail.Fqdn)`" (ID: $hostId) in $($completedQueries.Count) completed queries..."

            foreach ($qid in $completedQueries.Keys) {
                $tempQueryInfo = $completedQueries[$qid]

                # Match by checking if this query's Result.Elements.Resource.Id matches our hostId.
                $tempElements = if ($tempQueryInfo -and $tempQueryInfo.PSObject.Properties['Result'] -and $tempQueryInfo.Result -and $tempQueryInfo.Result.PSObject.Properties['Elements']) { $tempQueryInfo.Result.Elements } else { $null }
                if ($tempElements -and $tempElements.PSObject.Properties['Resource'] -and $tempElements.Resource.Id -eq $hostId) {
                    $queryInfo = $tempQueryInfo
                    Write-LogMessage -Type DEBUG -Message "Match found! Query $qid corresponds to host `"$($hostDetail.Fqdn)`""
                    break
                }
            }

            $queryElements = if ($queryInfo -and $queryInfo.PSObject.Properties['Result'] -and $queryInfo.Result -and $queryInfo.Result.PSObject.Properties['Elements']) { $queryInfo.Result.Elements } else { $null }
            if ($queryElements) {
                # Check if the query returned an error (e.g., HOST_IMAGE_COMPLIANCE_NOT_FOUND).
                $queryErrors = if ($queryElements.PSObject.Properties['Errors']) { $queryElements.Errors } else { $null }
                if ($queryErrors -and @($queryErrors).Count -gt 0) {
                    $firstErrorMsg = if (@($queryErrors)[0].PSObject.Properties['Message']) { @($queryErrors)[0].Message } else { "<unknown>" }
                    Write-LogMessage -Type DEBUG -Message "Host `"$($hostDetail.Fqdn)`" has compliance error: $firstErrorMsg"
                    $complianceStatus = "NOT_CHECKED_YET"
                    $SddcManagerImageName = "N/A"
                } else {
                    # No errors - extract compliance status.
                    $complianceStatus = if ($queryElements.PSObject.Properties['Status']) { $queryElements.Status } else { $null }
                    if (-not $complianceStatus) {
                        $complianceStatus = "NOT_CHECKED_YET"
                    }

                    # Extract image name - could be in Image.Name or ImageDetails.BaseImage.Version.
                    $imageObj = if ($queryElements.PSObject.Properties['Image']) { $queryElements.Image } else { $null }
                    $SddcManagerImageName = if ($imageObj -and $imageObj.PSObject.Properties['Name']) { $imageObj.Name } else { $null }
                    if (-not $SddcManagerImageName) {
                        $imageDetails = if ($queryElements.PSObject.Properties['ImageDetails']) { $queryElements.ImageDetails } else { $null }
                        $baseImage = if ($imageDetails -and $imageDetails.PSObject.Properties['BaseImage']) { $imageDetails.BaseImage } else { $null }
                        if ($baseImage -and $baseImage.PSObject.Properties['Version'] -and $baseImage.Version) {
                            $SddcManagerImageName = "<Autogenerated-Image>"
                        } else {
                            $SddcManagerImageName = "N/A"
                        }
                    }
                }
            } else {
                Write-LogMessage -Type DEBUG -Message "No compliance result found for host `"$($hostDetail.Fqdn)`". Marking as NOT_CHECKED_YET."
                $complianceStatus = "NOT_CHECKED_YET"
                $SddcManagerImageName = "N/A"
            }

            # Reuse domain cache from cluster processing to avoid redundant API call.
            if (-not $domainCache.ContainsKey($domainId)) {
                $domainCache[$domainId] = Invoke-VcfGetDomain -id $domainId -ErrorAction SilentlyContinue
                Write-LogMessage -Type DEBUG -Message "Cached domain: $($domainCache[$domainId].Name) (ID: $domainId)"
            }

            $Script:VlcmBaselineManagedResourcesDisplayObject += [pscustomobject]@{
                'Id'                   = $vlcmBaselineManagedResourceIndex
                'ResourceName'         = $hostDetail.Fqdn
                'ResourceType'         = "Standalone Host"
                'ResourceId'           = $hostId
                'VcenterName'          = $vcenterWorkloadDomain.fqdn
                'ImageSeedingSupport'  = $imageSeedingSupport
                'WorkloadDomainName'   = $domainCache[$domainId].Name
                'WorkloadDomainId'     = $domainId
                'ComplianceStatus'     = $complianceStatus
                'SddcManagerImageName' = $SddcManagerImageName
            }

            Write-LogMessage -SuppressOutputToScreen -Type INFO -Message "Standalone Host `"$($hostDetail.Fqdn)`" in Workload Domain `"$($domainCache[$domainId].Name)`" under vCenter `"$($vcenterWorkloadDomain.fqdn)`" (image seeding support is $imageSeedingSupport) is vLCM baseline (VUM) managed."
            $vlcmBaselineManagedResourceIndex++
        }
    } else {
        # Either SDDC Manager doesn't support standalone host compliance or no hosts found.
        if (-not $supportsStandaloneHostCompliance) {
            Write-LogMessage -Type DEBUG -Message "Standalone host compliance queries require SDDC Manager $minimumSahRelease or later (current: $sddcManagerVersion). Marking all hosts as NOT_CHECKED_YET."
        }

        # Process hosts without compliance checks.
        foreach ($hostInfo in $standaloneHostsToCheck) {
            $hostDetail = $hostInfo.HostDetail
            $hostId = $hostInfo.HostId
            $domainId = $hostInfo.DomainId
            $vcenterWorkloadDomain = $hostInfo.VcenterWorkloadDomain
            $imageSeedingSupport = $hostInfo.ImageSeedingSupport

            $complianceStatus = "NOT_CHECKED_YET"
            $SddcManagerImageName = "N/A"

            # Reuse domain cache from cluster processing to avoid redundant API call.
            if (-not $domainCache.ContainsKey($domainId)) {
                $domainCache[$domainId] = Invoke-VcfGetDomain -id $domainId -ErrorAction SilentlyContinue
                Write-LogMessage -Type DEBUG -Message "Cached domain: $($domainCache[$domainId].Name) (ID: $domainId)"
            }

            $Script:VlcmBaselineManagedResourcesDisplayObject += [pscustomobject]@{
                'Id'                   = $vlcmBaselineManagedResourceIndex
                'ResourceName'         = $hostDetail.Fqdn
                'ResourceType'         = "Standalone Host"
                'ResourceId'           = $hostId
                'VcenterName'          = $vcenterWorkloadDomain.fqdn
                'ImageSeedingSupport'  = $imageSeedingSupport
                'WorkloadDomainName'   = $domainCache[$domainId].Name
                'WorkloadDomainId'     = $domainId
                'ComplianceStatus'     = $complianceStatus
                'SddcManagerImageName' = $SddcManagerImageName
            }

            Write-LogMessage -SuppressOutputToScreen -Type INFO -Message "Standalone Host `"$($hostDetail.Fqdn)`" in Workload Domain `"$($domainCache[$domainId].Name)`" under vCenter `"$($vcenterWorkloadDomain.fqdn)`" (image seeding support is $imageSeedingSupport) is vLCM baseline (VUM) managed."
            $vlcmBaselineManagedResourceIndex++
        }
    }

    if ($vlcmBaselineManagedResourceIndex -eq [int]1) {
        Write-LogMessage -Type ERROR -Message "No baseline managed resources detected."
        if ($Script:Headless) {
            return
        } else {
            Show-AnyKey
            Show-MainMenu
        }
    }

    # Sort baseline resources using natural sorting (alphabetically first, then numerically within same prefix), then reassign IDs sequentially (preserve header rows).
    $headerRows = $Script:VlcmBaselineManagedResourcesDisplayObject[0..1]
    $dataRows = $Script:VlcmBaselineManagedResourcesDisplayObject[2..($Script:VlcmBaselineManagedResourcesDisplayObject.Count - 1)] | Sort-Object -Property @{
        Expression = {
            # Extract prefix (non-numeric part) for primary sorting.
            if ($_.ResourceName -match '^([^\d]+)') {
                $matches[1]
            } else {
                $_.ResourceName
            }
        }
    }, @{
        Expression = {
            # Extract first numeric part for natural sorting within same prefix (e.g., "esx-7" → 7, "esx-10" → 10).
            if ($_.ResourceName -match '\d+') {
                [int]$matches[0]
            } else {
                0
            }
        }
    }, ResourceName

    # Reassign IDs sequentially after sorting.
    $id = 1
    foreach ($row in $dataRows) {
        $row.Id = $id
        $id++
    }

    $Script:VlcmBaselineManagedResourcesDisplayObject = $headerRows + $dataRows

    # Log the discovered resources in JSON format for easy reading and parsing.
    if ($Script:VlcmBaselineManagedResourcesDisplayObject.Count -gt 2) {
        Write-LogMessage -Type DEBUG -Message "=== vLCM Baseline (VUM) Managed Resources Discovered ($(($Script:VlcmBaselineManagedResourcesDisplayObject.Count - 2)) resources) ==="

        # Convert to JSON for clean, complete output (skip header rows).
        $resourcesJson = $Script:VlcmBaselineManagedResourcesDisplayObject[2..($Script:VlcmBaselineManagedResourcesDisplayObject.Count - 1)] |
            Select-Object ResourceName, ResourceType, VcenterName, WorkloadDomainName, ComplianceStatus, SddcManagerImageName |
            ConvertTo-Json -Depth 3

        # Log each line of JSON separately to maintain formatting.
        foreach ($line in ($resourcesJson -split "`r?`n")) {
            if ($line) { Write-LogMessage -Type DEBUG -Message $line }
        }

        Write-LogMessage -Type DEBUG -Message "=== End of Resource List ==="
    } else {
        Write-LogMessage -Type DEBUG -Message "No baseline-managed resources found to display."
    }

        if (-not $Script:Headless) {
         Write-Host "Displaying vLCM Baseline (VUM) Managed Clusters/Standalone Hosts in Connected vCenter(s):" -ForegroundColor Green;
         return $Script:VlcmBaselineManagedResourcesDisplayObject | Format-Table -Property @{Expression = " " }, Id, ResourceName, ResourceType, VcenterName, ComplianceStatus, SddcManagerImageName -Autosize -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }
        } else {
            if ($JsonOutputFile) {
                # The first two rows of the array contain header information.
                $id = 0
                $jsonHashTable = foreach($resource in $Script:VlcmBaselineManagedResourcesDisplayObject) {
                    if ($id -ge 2) {
                        $hash = [ordered]@{
                            ResourceName = $resource.ResourceName
                            ResourceType = $resource.ResourceType
                            WorkloadDomainName = $resource.WorkloadDomainName
                        }
                        if (-not $ExcludeSddcManagerImageName) {
                            $hash.SddcManagerImageName = $resource.SddcManagerImageName
                        }
                        $hash
                    }
                    $id++
                }
                $JsonOutput = $jsonHashTable | ConvertTo-Json
                if (Test-Path $JsonOutputFile) {
                    Write-LogMessage -Type WARNING -Message "Output file `"$JsonOutputFile`" already exists and will be overwritten."
                }
                Set-Content -Path $JsonOutputFile $JsonOutput
            }

            if (-not $Script:logOnly) {
            Write-LogMessage -Type INFO -AppendNewLine -Message "vLCM Baseline (VUM) Managed Clusters/Standalone Hosts:"
                if ($Script:Headless) {
                return $Script:VlcmBaselineManagedResourcesDisplayObject | Format-Table -Property @{Expression = " " }, ResourceName, ResourceType, VcenterName, WorkloadDomainName, ComplianceStatus, SddcManagerImageName -Autosize -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }
                } else {
                return $Script:VlcmBaselineManagedResourcesDisplayObject | Format-Table -Property @{Expression = " " }, ResourceName, ResourceType, VcenterName, WorkloadDomainName -Autosize -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") }
            }
        }
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

        .OUTPUTS
        None
        This function does not return a value. It deletes the image from SDDC Manager or exits on failure.
    #>

    Param (
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$SddcManagerImageName
    )

    Write-LogMessage -Type DEBUG -Message "Entered Remove-ImageFromSddcManager function..."

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    if (-not $Script:Headless) {

        $personalities = Invoke-VcfGetPersonalities -ErrorAction SilentlyContinue
        [array]$SddcManagerImageNames = if ($personalities -and $personalities.PSObject.Properties['Elements'] -and $personalities.Elements) { @($personalities.Elements | Select-Object -ExpandProperty PersonalityName) } else { @() }

        if ($SddcManagerImageNames) {

            $sddcManagerImageDisplayObject = @()
            $sddcManagerImageIndex = 1

            $sddcManagerImageDisplayObject += [pscustomobject]@{
                'Id'                   = "Id"
                'SddcManagerImageName' = "SDDC Manager Image Name"
            }
            $sddcManagerImageDisplayObject += [pscustomobject]@{
               'Id'                   = "--"
               'SddcManagerImageName' = "-----------------------"
            }

            # Sort image names alphabetically.
            $sortedImageNames = $SddcManagerImageNames | Sort-Object

            foreach ($SddcManagerImageName in $sortedImageNames) {
                $sddcManagerImageDisplayObject += [pscustomobject]@{
                    'Id'                   = $sddcManagerImageIndex
                    'SddcManagerImageName' = $SddcManagerImageName
                }
                $sddcManagerImageIndex++
            }
            Write-LogMessage -Type INFO -AppendNewLine -Message "Please only delete SDDC Manager images imported in error."

            # Log SDDC Manager images in JSON format (skip header rows).
            if ($sddcManagerImageDisplayObject.Count -gt 2) {
                Write-LogMessage -Type DEBUG -Message "=== SDDC Manager Images ($(($sddcManagerImageDisplayObject.Count - 2)) images) ==="
                $imagesJson = $sddcManagerImageDisplayObject[2..($sddcManagerImageDisplayObject.Count - 1)] |
                    Select-Object Id, SddcManagerImageName | ConvertTo-Json -Depth 2
                foreach ($line in ($imagesJson -split "`r?`n")) {
                    if ($line) { Write-LogMessage -Type DEBUG -Message $line }
                }
                Write-LogMessage -Type DEBUG -Message "=== End of SDDC Manager Images ==="
            }

            $sddcManagerImageDisplayObject | Format-Table -Property @{Expression = " " }, Id, SddcManagerImageName -Autosize -HideTableHeaders | Out-Host

            Do {
                $VersionSelection = Read-Host "Enter the id of the image you wish to delete, or press 'c' to cancel"
                if ($VersionSelection -eq "c") {
                    Write-LogMessage -Type INFO -PrependNewLine -Message "Cancellation requested. Returning to main menu."
                    Show-AnyKey
                    Show-MainMenu
                }
                $isValidId = ($VersionSelection -in @($sddcManagerImageDisplayObject.Id))
                if (-not $isValidId) {
                    Write-LogMessage -Type ERROR -Message "Invalid selection: $VersionSelection identifier not found."
                }
            } While (-not $isValidId)
            $selectedImage = $sddcManagerImageDisplayObject | Where-Object {$_.Id -eq $VersionSelection} | Select-Object -First 1
            $SddcManagerImageName = if ($selectedImage) { $selectedImage.SddcManagerImageName } else { $null }
        } else {
            Write-LogMessage -Type ERROR -Message "No images found in SDDC Manager `"$Global:SddcManagerFqdn`"."
            return
        }
    }

    try {
        $null = Invoke-VcfDeletePersonality -PersonalityName $SddcManagerImageName -ErrorAction Stop
        # Catch and explain the most common errors.
    } catch {
        switch -Regex ($_.Exception.Message) {
            "PERSONALITY_NOT_FOUND" {
                Write-LogMessage -Type ERROR -Message "vLCM image `"$SddcManagerImageName`" not found in SDDC Manager `"$Global:SddcManagerFqdn`"."
                Show-AnyKey
                Exit-WithCode -ExitCode $Script:ExitCodes.RESOURCE_NOT_FOUND
            }
            "Error calling DeletePersonality" {
                Write-LogMessage -Type ERROR -Message "Deletion operation for vLCM image `"$SddcManagerImageName`" failed with error: $($_.Exception.Message)."
                Show-AnyKey
                Exit-WithCode -ExitCode $Script:ExitCodes.OPERATION_FAILED
            }
            default {
                Write-LogMessage -Type ERROR -Message "Unexpected error deleting vLCM image `"$SddcManagerImageName`": $($_.Exception.Message)."
                Show-AnyKey
                Exit-WithCode -ExitCode $Script:ExitCodes.OPERATION_FAILED
            }
        }
    }
    # Confirm deletion by verifying the image is no longer present in SDDC Manager.
    $personalitiesResult = Invoke-VcfGetPersonalities -ErrorAction SilentlyContinue
    $personalities = if ($personalitiesResult -and $personalitiesResult.PSObject.Properties['Elements'] -and $personalitiesResult.Elements) {
        @($personalitiesResult.Elements | Select-Object -ExpandProperty PersonalityName)
    } else {
        @()
    }

    # If the API call itself failed entirely (null result, not just an empty list), warn but do not treat as failure.
    if (-not $personalitiesResult) {
        Write-LogMessage -Type WARNING -Message "Unable to retrieve personality list from SDDC Manager. Cannot confirm deletion of `"$SddcManagerImageName`", but no error was returned during deletion."
        return
    }

    # If the image is still present in the list, the deletion failed.
    if ($personalities -contains $SddcManagerImageName) {
        Write-LogMessage -Type ERROR -Message "vLCM image `"$SddcManagerImageName`" was not removed from SDDC Manager `"$Global:SddcManagerFqdn`"."
        Show-AnyKey
        Exit-WithCode -ExitCode $Script:ExitCodes.OPERATION_FAILED
    }

    Write-LogMessage -Type INFO -Message "Successfully deleted vLCM image `"$SddcManagerImageName`" from SDDC Manager `"$Global:SddcManagerFqdn`"."
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

        .OUTPUTS
        Boolean
        Returns $true if vCenter supports image catalogs (has REPOSITORY_IMAGES capability), $false otherwise.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$VcenterName
    )

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    try {
        $vcentersResult = Invoke-VcfGetVcenters -ErrorAction SilentlyContinue
        $vcenterDetails = if ($vcentersResult -and $vcentersResult.PSObject.Properties['Elements']) { $vcentersResult.Elements | Where-Object Fqdn -eq $VcenterName | Select-Object -First 1 } else { $null }
    } catch [Exception] {
        if ($_.Exception.Message -match "The request was canceled due to the configured HttpClient.Timeout") {
            Write-LogMessage -Type ERROR -Message "Network error. Cannot connect to vCenter `"$VcenterName`"."
        } else {
            Write-LogMessage -Type ERROR -Message $_.Exception.Message
        }
    }

    if (-not $vcenterDetails) {
        return
    }

    # Collect the capabilities of this domain based on its Domain ID.
    $domainId = if ($vcenterDetails.Domain) { $vcenterDetails.Domain.ID } else { $null }
    $capResult = if ($domainId) { Invoke-VcfGetDomainCapabilitiesByDomainId -id $domainId -ErrorAction SilentlyContinue } else { $null }
    [array]$domainCapabilities = if ($capResult -and $capResult.Capabilities) { @($capResult.Capabilities) } else { @() }
    # REPOSITORY_IMAGES capability indicates support for vCenter image catalog (vCenter 9+).
    if ($domainCapabilities -contains "REPOSITORY_IMAGES") {
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

        .OUTPUTS
        PSCustomObject
        Returns the vCenter image catalog object containing available images, or exits on failure.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$VcenterName
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-VcenterImageCatalog function..."

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    $vcentersResult2 = Invoke-VcfGetVcenters -ErrorAction SilentlyContinue
    $vcenterDetails = if ($vcentersResult2 -and $vcentersResult2.PSObject.Properties['Elements']) { $vcentersResult2.Elements | Where-Object Fqdn -eq $VcenterName | Select-Object -First 1 } else { $null }

    if (-not $vcenterDetails) {
        Write-LogMessage -Type ERROR -Message "Invalid vCenter name `"$VcenterName`"."
        return @()
    }

    $repositoryImageQuerySpec = Initialize-VcfRepositoryImageQuerySpec -VcenterIds $($vcenterDetails.ID) -ErrorAction SilentlyContinue

    $repositoryQueryResult = Invoke-VcfInitiateRepositoryImagesQuery -RepositoryImageQuerySpec $repositoryImageQuerySpec -ErrorAction SilentlyContinue
    $vcenterImageCatalog = if ($repositoryQueryResult -and $repositoryQueryResult.PSObject.Properties['Result'] -and $repositoryQueryResult.Result -and $repositoryQueryResult.Result.PSObject.Properties['Elements']) { $repositoryQueryResult.Result.Elements } else { $null }
    # Check if the image catalog contains any images, if so return said catalog object.
    if (-not $vcenterImageCatalog) {
        return @()
    }

    return $vcenterImageCatalog

}
Function Get-VcenterImages {

    <#
        .SYNOPSIS
        The function Get-VcenterImages shows vLCM Images in connected vCenter(s).

        .DESCRIPTION
        This function displays what vCenter clusters contain vLCM images and can be imported
        into SDDC Manager.

        .EXAMPLE
        Get-VcenterImages -JsonOutputFile ImageList.json

        .PARAMETER JsonOutputFile
        Specifies what file to save JSON output to.

        .OUTPUTS
        None
        This function does not return a value. It displays vCenter images interactively or exports to JSON.
    #>

    Param (
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$JsonOutputFile
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-VcenterImages function..."

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    # Check if connected to vCenter(s). Return early if user cancels or connection fails.
    $vCenterConnected = Test-VcentersConnection
    if (-not $vCenterConnected) {
        return @()
    }

    # Prepare list of vCenter clusters with vLCM Image Management.
    $imageManagedClusterDetails = @()
    $imageManagedClusters = 0

    Write-LogMessage -Type INFO -Message "Scanning vCenter(s) for vLCM images..."

    # Cache version check once before loop to avoid redundant API calls.
    $sddcManagerVersion = Get-SddcManagerVersion
    $supportsImageCatalogCheck = ([Version]$sddcManagerVersion) -gt ([Version]$minimumImageCatalogSupportRelease)

    # iterate through each connected vCenter.
    foreach ($VcenterName in @(Get-Variable -Name 'DefaultViServers' -Scope Global -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value | Select-Object -ExpandProperty Name | Sort-Object)) {

        # Verify if ImageCatalog support can be queried.  The very capability check is a SDDCm 9.0+ capability.
        if ($supportsImageCatalogCheck) {
            # Check if image catalog is supported.
            $vcenterImageCatalogSupport = Test-VcenterImageCatalogSupport -VcenterName $VcenterName
        } else {
            $vcenterImageCatalogSupport = $false
        }

        if ($vcenterImageCatalogSupport) {
            $vcenterImageCatalog = Get-VcenterImageCatalog -VcenterName $VcenterName
            [array]$vcenterImageCatalogNames = @($vcenterImageCatalog | Select-Object -ExpandProperty Name)
            foreach ($VcenterImageName in ($vcenterImageCatalogNames | Sort-Object)) {
                $imageManagedClusterDetails += [pscustomobject]@{
                    'VcenterImageName' = $VcenterImageName
                    'VcenterName' = $VcenterName
                }
            $imageManagedClusters++
            }
        } else {
            # only add LifecycleManaged clusters for the selected vCenter(s), to the managed clusters object.
            foreach ($VcenterImageName in (Get-Cluster -Server $VcenterName -ErrorAction SilentlyContinue | Where-Object {$_.ExtensionData.LifecycleManaged} | Select-Object -ExpandProperty Name | Sort-Object)) {
                    $imageManagedClusterDetails += [pscustomobject]@{
                    'VcenterImageName' = $VcenterImageName
                    'VcenterName' = $VcenterName
                    }
                $imageManagedClusters++
            }
        }
    }

    if ($imageManagedClusters -eq 0) {
        Write-LogMessage -Type ERROR -Message "No vLCM images detected in the connected vCenter(s)."
        Write-LogMessage -Type INFO -Message "Connect to a vCenter to create a new vLCM image."
        Write-LogMessage -Type INFO -Message "https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/managing-host-and-cluster-lifecycle-8-0.html"
        Show-AnyKey
        if (-not $Script:Headless) {
            Show-MainMenu
        }
        return
    }

    # Prepare a selection menu of options based on generated IDs.
    $clusterDisplayObject = @()
    $clusterIndex = 1

    $clusterDisplayObject += [pscustomobject]@{
        'Id'               = "Id"
        'VcenterImageName' = "vCenter Image Name"
        'VcenterName'      = "vCenter Name"
    }
    $clusterDisplayObject += [pscustomobject]@{
        'Id'               = "--"
        'VcenterImageName' = "------------------"
        'VcenterName'      = "------------"
    }

    # Sort by vCenter Image Name.
    $sortedImageManagedClusterDetails = $imageManagedClusterDetails | Sort-Object -Property VcenterImageName

    foreach ($line in $sortedImageManagedClusterDetails) {
        $clusterDisplayObject += [pscustomobject]@{
            'Id'               = $clusterIndex
            'VcenterImageName' = $line.VcenterImageName
            'VcenterName'      = $line.VcenterName
        }

        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "vLCM image `"$($line.VcenterImageName)`" found in vCenter `"$($line.VcenterName)`""
        $clusterIndex++
    }

    if (-not $Script:Headless) {
        return $clusterDisplayObject
    }

    if (-not $Script:logOnly) {
        Write-LogMessage -Type INFO -AppendNewLine -Message "vLCM images in attached vCenter(s):"

        # Log vCenter images in JSON format (skip header rows).
        if ($clusterDisplayObject.Count -gt 2) {
            Write-LogMessage -Type DEBUG -Message "=== vCenter vLCM Images ($(($clusterDisplayObject.Count - 2)) images) ==="
            $imagesJson = $clusterDisplayObject[2..($clusterDisplayObject.Count - 1)] |
                Select-Object VcenterImageName, VcenterName | ConvertTo-Json -Depth 2
            foreach ($line in ($imagesJson -split "`r?`n")) {
                if ($line) { Write-LogMessage -Type DEBUG -Message $line }
            }
            Write-LogMessage -Type DEBUG -Message "=== End of vCenter vLCM Images ==="
        }

        $clusterDisplayObject | Format-Table -Property @{Expression = " " }, VcenterImageName, VcenterName -Autosize -HideTableHeaders | Out-Host
    }

    if ($JsonOutputFile) {
        # The first two rows of the array contain header information.
        $id = 0
        $jsonHashTable = foreach($clusterMember in $clusterDisplayObject) {
        if ($id -ge 2) {
                @{
                    VcenterImageName = $clusterMember.VcenterImageName
                    VcenterName = $clusterMember.VcenterName
                }
            }
            $id++
        }
        $JsonOutput = $jsonHashTable | ConvertTo-Json
        if (Test-Path $JsonOutputFile) {
            Write-LogMessage -Type WARNING -Message "Output file `"$JsonOutputFile`" already exists and will be overwritten."
        }
        Set-Content -Path $JsonOutputFile $JsonOutput
    }
}
Function Import-ImageFromVcenter {

    <#
        .SYNOPSIS
        Pulls a vLCM image from vCenter into SDDC Manager.

        .DESCRIPTION
        This function calls Get-VcenterImages to get a list of clusters in the connected vCenters
        with the property extensionData.LifecycleManaged. It provides three modes: on-screen display
        (interactive), parameter-based (headless), and JSON input (headless).

        .PARAMETER JsonInputFile
        Specifies the JSON input file that contains at least one set of vCenter names and images.

        .PARAMETER Parallel
        When specified, image imports are parallelized; otherwise defaults to serial.

        .PARAMETER Silence
        When specified, suppresses console output.

        .PARAMETER VcenterImageName
        Specifies the source cluster or vLCM image name in vCenter.

        .PARAMETER VcenterName
        Specifies the source vCenter FQDN for the vLCM image.

        .EXAMPLE
        Import-ImageFromVcenter -VcenterImageName m01-cl01 -VcenterName m01-vc01.example.com

        .EXAMPLE
        Import-ImageFromVcenter -JsonInputFile ImagesToImport.json

        .EXAMPLE
        Import-ImageFromVcenter -JsonInputFile ImagesToImport.json -Parallel

        .OUTPUTS
        None
        This function does not return a value. It imports images from vCenter to SDDC Manager.
    #>

    Param (
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$JsonInputFile,
        [Parameter(Mandatory = $false)] [Switch]$Parallel,
        [Parameter(Mandatory = $false)] [Switch]$Silence,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$VcenterImageName,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$VcenterName
    )

    # Check if connected to SDDC Manager.
    Write-LogMessage -Type DEBUG -Message "Entered Import-ImageFromVcenter function..."

    Test-SddcManagerConnection
    # Check if connected to vCenter(s). Return early if the user cancels or connection fails.
    $vCenterConnected = Test-VcentersConnection
    if (-not $vCenterConnected) {
        return
    }

    Write-LogMessage -Type DEBUG -Message "VxRailMode check: `$Script:vxRailMode = $Script:vxRailMode"
    if ($Script:vxRailMode) {
        Write-LogMessage -Type ERROR -Message "VxRail only supports vLCM baseline to vLCM image transitions through image seeding."
        Show-AnyKey
        if (-not $Script:Headless) {
            Show-MainMenu
        }
        return
    }

    # Cache expensive lookups once at function start to avoid redundant API calls.
    $sddcManagerVersion = Get-SddcManagerVersion
    $supportsImageCatalogCheck = ([Version]$sddcManagerVersion) -gt ([Version]$minimumImageCatalogSupportRelease)

    Write-LogMessage -Type DEBUG -Message "SDDC Manager version: $sddcManagerVersion, Supports image catalog check: $supportsImageCatalogCheck"

    # In interactive mode, a user's ClusterName and vCenter are provided by selecting an Id from a menu.
    if (-not $Script:Headless) {
        $clusterDisplayObject  = Get-VcenterImages

        # Log vCenter images with IDs in JSON format (skip header rows).
        if ($clusterDisplayObject.Count -gt 2) {
            Write-LogMessage -Type DEBUG -Message "=== vCenter vLCM Images for Selection ($(($clusterDisplayObject.Count - 2)) images) ==="
            $imagesJson = $clusterDisplayObject[2..($clusterDisplayObject.Count - 1)] |
                Select-Object VcenterImageName, VcenterName | ConvertTo-Json -Depth 2
            foreach ($line in ($imagesJson -split "`r?`n")) {
                if ($line) { Write-LogMessage -Type DEBUG -Message $line }
            }
            Write-LogMessage -Type DEBUG -Message "=== End of vCenter vLCM Images ==="
        }

        $clusterDisplayObject | Format-Table -Property @{Expression = " " }, Id, VcenterImageName, VcenterName -Autosize -HideTableHeaders | Out-Host
        Do {
            # set (or reset in the event of invalid ID hit) an array of images to import into SDDC manager.
            $imagesToImportIntoSddcManager =@()
            $VersionSelection = Read-Host "Enter an id or comma-delimited list of ids of image(s) to import into SDDC Manager or press 'c' to cancel"
            if ($VersionSelection -eq "c") {
                return
            }
            foreach ($selectedImageId in $VersionSelection.Split(",")) {

                $isValidId = ($selectedImageId -in @($clusterDisplayObject.Id))
                # return from loop if invalid ID is entered.
                if (-not $isValidId) {
                    if ($selectedImageId -eq "") {
                        $selectedImageId = "<EMPTY>"
                    }
                    Write-LogMessage -Type ERROR -Message "Invalid selection: $selectedImageId identifier not found."
                    return
                }
                $selectedClusterEntry = $clusterDisplayObject | Where-Object {$_.Id -eq $selectedImageId} | Select-Object -First 1
                $imagesToImportIntoSddcManager += [pscustomobject]@{
                    VcenterName = if ($selectedClusterEntry) { $selectedClusterEntry.VcenterName } else { $null }
                    VcenterImageName = if ($selectedClusterEntry) { $selectedClusterEntry.VcenterImageName } else { $null }
                }

            }
        } While (-not $isValidId)
    }

    if ($Script:Headless) {
        if ($JsonInputFile) {
            $result = ConvertFrom-JsonSafely -JsonFilePath $JsonInputFile -VariableName "ImagesToImportIntoSddcManager"
            if (-not $result.Success) {
                Write-LogMessage -Type ERROR -Message "Failed to load JSON input file: $($result.ErrorMessage)"
                Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR
            }
            $imagesToImportIntoSddcManager = $result.JsonData

        } else {
            # turn the commandline parameter data into an array so the user-inputted data, either.
            # in parameter form or json, can be validated in the same way.
            $imagesToImportIntoSddcManager = [pscustomobject]@{
                VcenterName = $VcenterName
                VcenterImageName = $VcenterImageName
            }
        }

        foreach ($line in $imagesToImportIntoSddcManager) {
            # use the previously defined ClusterDisplayObject for vC to cluster mappings.
            if (-not $($line.VcenterName) -or -not $($line.VcenterImageName) ) {
                Write-LogMessage -Type ERROR -Message "$JsonInputFile missing VcenterImageName and/or VcenterName."
                Write-LogMessage -Type ERROR -Message  "Please review this line: $line"
                Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR
            }

            # check if vCenter is valid.
            $isConnectedVcenter = @(Get-Variable -Name 'DefaultViServers' -Scope Global -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value | Where-Object IsConnected -eq $true | Where-Object Name -eq $($line.VcenterName))

            if ($isConnectedVcenter.Count -eq 0) {
                Write-LogMessage -Type ERROR -Message "vCenter `"$($line.VcenterName)`" not found in list of connected vCenter(s)."
                Exit-WithCode -ExitCode $Script:ExitCodes.VCENTER_CONNECTION_ERROR
            }

            # Use cached version check to determine image catalog support.
            if ($supportsImageCatalogCheck) {
                $imageCatalogSupport = Test-VcenterImageCatalogSupport -VcenterName $($line.VcenterName)
            } else {
                $imageCatalogSupport = $false
            }
            # Validating that an image belongs to a specific vCenter is different for the image catalog vs legacy images.
            if ($imageCatalogSupport) {
                $vcenterImageCatalog = Get-VcenterImageCatalog -VcenterName ($line.VcenterName)
                $vcenterImageId = ($vcenterImageCatalog | Where-Object {$_.Name -eq $($line.VcenterImageName)}).RepositoryImageId.VcenterImageId
                if ([String]::IsNullOrEmpty($vcenterImageId)) {
                    Write-LogMessage -Type ERROR -Message "No vLCM image named `"$($line.VcenterImageName)`" found in vCenter `"$($line.VcenterName)`" image catalog."
                    Exit-WithCode -ExitCode $Script:ExitCodes.RESOURCE_NOT_FOUND
                }
            } else {
                # check if this cluster is found in the vCenter we're expecting.
                $vcenterClusterMatch = Get-Cluster -Server $($line.VcenterName) -ErrorAction SilentlyContinue | Where-Object Name -eq $($line.VcenterImageName)
                if ([String]::IsNullOrEmpty($vcenterClusterMatch)) {
                    Write-LogMessage -Type ERROR -Message "No cluster named `"$($line.VcenterImageName)`" found in vCenter `"$($line.VcenterName)`" with vLCM image management."
                    Exit-WithCode -ExitCode $Script:ExitCodes.RESOURCE_NOT_FOUND
                }
            }
            $personalitiesCheckResult = Invoke-VcfGetPersonalities -ErrorAction SilentlyContinue
            $response = if ($personalitiesCheckResult -and $personalitiesCheckResult.PSObject.Properties['Elements']) { $personalitiesCheckResult.Elements | Where-Object PersonalityName -eq $($line.VcenterImageName) | Select-Object -First 1 } else { $null }
            if ($response) {
                Write-LogMessage -Type ERROR -Message "An image named `"$($line.VcenterImageName)`" already exists in SDDC Manager `"$Global:SddcManagerFqdn`"."
                Write-LogMessage -Type INFO -Message "Please rename the source image in vCenter or delete the conflicting image from SDDC manager before retrying."
                Exit-WithCode -ExitCode $Script:ExitCodes.OPERATION_FAILED -Message "Duplicate image `"$($line.VcenterImageName)`" detected. Import aborted."
            }
        }
    }
    # line break on screen.
    if (-not $Script:Headless) {
        Write-Host ""
    }

    # Initialize progress tracking for batch operations.
    $totalImages = @($imagesToImportIntoSddcManager).Count
    $currentImageNum = 0

    foreach ($line in $imagesToImportIntoSddcManager) {
        $currentImageNum++

        # Show overall progress for batch imports (only if multiple images).
        if ($totalImages -gt 1 -and -not $Silence) {
            Write-Progress -Id 1 -Activity "Importing vLCM Images to SDDC Manager" `
                -Status "Processing image $currentImageNum of $totalImages`: $($line.VcenterImageName) from $($line.VcenterName)" `
                -PercentComplete ($currentImageNum * 100 / $totalImages)
        }

        # Lookup the VCF vCenter Id by iterating through all WLD vCenter IDs registered to SDDC Manager.
        $vcentersImportResult = Invoke-VcfGetVcenters -ErrorAction SilentlyContinue
        $matchedVcenter = if ($vcentersImportResult -and $vcentersImportResult.PSObject.Properties['Elements']) { $vcentersImportResult.Elements | Where-Object { $_.Fqdn -eq $($line.VcenterName)} | Select-Object -First 1 } else { $null }
        $vcenterId = if ($matchedVcenter) { $matchedVcenter.Id } else { $null }

        if (-not $vcenterId ) {
            Write-LogMessage -Type ERROR -Message "Could not locate vCenter `"$($line.VcenterName)`" in SDDC Manager `"$Global:SddcManagerFqdn`". Skipping image `"$($line.VcenterImageName)`"."
            continue
        }

        # Use cached version check to determine image catalog support.
        if ($supportsImageCatalogCheck) {
            # Check for vCenter Image catalog Support.
            $imageCatalogSupport = Test-VcenterImageCatalogSupport -VcenterName $($line.VcenterName)
        } else {
            $imageCatalogSupport = $false
        }

        if ($imageCatalogSupport) {
            $vcenterImageCatalog = Get-VcenterImageCatalog -VcenterName $($line.VcenterName)
            $vcenterImageId = ($vcenterImageCatalog | Where-Object {$_.Name -eq $($line.VcenterImageName)}).RepositoryImageId.VcenterImageId
            if ([String]::IsNullOrEmpty($vcenterImageId)) {
                Write-LogMessage -Type ERROR -Message "Could not identify vCenter image catalog name `"$($line.VcenterImageName)`" in vCenter `"$($line.VcenterName)`"."
                return
            } else {
                $personalityUploadSpecReferred = Initialize-VcfPersonalityUploadSpecReferred -VcenterId $vcenterId -VcenterImageId $vcenterImageId -ErrorAction SilentlyContinue
            }
        } else {
            # The vCenter cluster exists outside of SDDC manager and thus must be referenced by MorId.
            $clusterMorId = (Get-Cluster -Server $($line.VcenterName) -ErrorAction SilentlyContinue | Where-Object -Property Name -eq $($line.VcenterImageName)).ExtensionData.MoRef.Value
            if ([String]::IsNullOrEmpty($clusterMorId)) {
                Write-LogMessage -Type ERROR -Message "Could not identify cluster `"$($line.VcenterImageName)`" in vCenter `"$($line.VcenterName)`"."
                return
            } else {
                $personalityUploadSpecReferred = Initialize-VcfPersonalityUploadSpecReferred -ClusterMorId $clusterMorId -VcenterId $vcenterId -ErrorAction SilentlyContinue
            }
        }

        # Image name in vCenter will match image name in SDDC Manager.
        $personalityUploadSpec = Initialize-VcfPersonalityUploadSpec -Name $($line.VcenterImageName) -UploadMode "REFERRED" -UploadSpecReferredMode $personalityUploadSpecReferred -ErrorAction SilentlyContinue

        try {
            $response = Invoke-VcfUploadPersonality -PersonalityUploadSpec $personalityUploadSpec -ErrorAction Stop
        } catch {
            # Display friendly messages to the end user for common API errors.
            $errorMessage = $_.Exception.Message

            switch -Regex ($errorMessage) {
                "PERSONALITY_ALREADY_EXISTS" {
                    Write-LogMessage -Type ERROR -AppendNewLine -Message "An image named `"$($line.VcenterImageName)`" already exists in the SDDC Manager `"$Global:SddcManagerFqdn`"."
                    Write-LogMessage -Type INFO -Message "Please rename the source image in vCenter or delete the conflicting image from SDDC manager before retrying."
                }
                "PERSONALITY_UPLOAD_SPEC_INVALID_DATA" {
                    Write-LogMessage -Type ERROR -AppendNewLine -Message "An image named `"$($line.VcenterImageName)`" has an invalid spec.  Please contact support and provide this error message: $errorMessage"
                }
                default {
                    Write-LogMessage -Type ERROR -Message "Image import of `"$($line.VcenterImageName)`" failed with error message `"$errorMessage`"."
                }
            }
            return
        }

        Write-LogMessage -Type INFO -Message "Beginning import of vCenter vLCM image `"$($line.VcenterImageName)`" into SDDC Manager `"$Global:SddcManagerFqdn`"..."

        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "(Debugging information) Task Id is `"$($response.Id)`" for the import job of image name `"$($line.VcenterImageName)`" from vCenter `"$($line.VcenterName)`""

        # Parallel or Silence flag will disable polling for task to complete.
        # Skip polling if EITHER parallel OR silence is enabled.
        if (-not ($Parallel -or $Silence)) {
            $processTimer = Start-ProcessTimer
            Do {
                $TaskId = $response.Id

                # Query task status with error handling.
                try {
                    $taskResponse = Invoke-VcfGetTask -Id $TaskId -ErrorAction Stop
                    $taskStatus = $taskResponse.Status
                } catch {
                    # Differentiate between task not found (completed) vs API error.
                    if ($_.Exception.Message -match "NOT_FOUND|404|does not exist") {
                        Write-LogMessage -Type DEBUG -Message "Image import task $TaskId not found (completed and removed)"
                        $taskStatus = "SUCCESSFUL"  # Assume success if task was removed
                    } else {
                        Write-LogMessage -Type ERROR -Message "Failed to query image import task status: $($_.Exception.Message)"
                        Write-Progress -Id 1 -Completed
                        Write-Progress -Id 2 -Completed
                        throw  # Re-throw - API being down is critical
                    }
                }

                Test-SddcManagerConnection
                # Use Id 2 for individual import progress (nested under batch progress Id 1).
                Write-Progress -Id 2 -Activity "Importing image `"$($line.VcenterImageName)`"" -Status "$([math]::Round(($processTimer.Elapsed.TotalSeconds),0)) seconds elapsed (updates every 5 seconds)."
                Start-Sleep -Seconds 5
            } While ($taskStatus -eq 'IN_PROGRESS')

            Write-Progress -Id 2 -Completed
            Stop-ProcessTimer -Timer $processTimer -Operation "Image import of `"$($line.VcenterImageName)`" into `"$Global:SddcManagerFqdn`"" -Interval "Minutes"
            Write-Output ""

            switch ($taskStatus) {
                "SUCCESSFUL" {
                    Write-LogMessage -Type INFO -Message "Successfully created SDDC Manager image `"$($line.VcenterImageName)`" into SDDC Manager `"$Global:SddcManagerFqdn`""
                    if (-not $imageCatalogSupport) {
                        # With the image successfully imported, the temporary cluster can be deleted.
                        Remove-TemporaryCluster -TemporaryClusterName $($line.VcenterImageName) -TemporaryClusterVcenter $($line.VcenterName)
                    }
                }
                "FAILED" {
                    # Query task once and cache result to avoid redundant API calls.
                    try {
                        $taskDetails = Invoke-VcfGetTask -Id $TaskId -ErrorAction Stop
                    } catch {
                        Write-LogMessage -Type WARNING -Message "Could not retrieve task details for task `"$TaskId`": $($_.Exception.Message)"
                        $taskDetails = $null
                    }
                    $errorCode = if ($taskDetails -and $taskDetails.PSObject.Properties['Errors'] -and $taskDetails.Errors) { $taskDetails.Errors.ErrorCode } else { $null }
                    $errorMessage = if ($taskDetails -and $taskDetails.PSObject.Properties['Errors'] -and $taskDetails.Errors) { $taskDetails.Errors.Message } else { $null }
                    switch -Regex ($errorCode) {
                        "PERSONALITY_WITH_SAME_SPEC_EXISTS" {
                            Write-LogMessage -Type ERROR -AppendNewLine -Message "Image `"$($line.VcenterImageName)`" could not be imported — another image with the same manifest already exists in SDDC Manager `"$Global:SddcManagerFqdn`"."
                            Write-LogMessage -Type INFO -Message "Please delete the conflicting image from SDDC Manager or rename the source image in vCenter before retrying."
                        }
                        "PERSONALITY_EXPORT_FROM_VC_FAILED" {
                            Write-LogMessage -Type ERROR -AppendNewLine -Message "Image `"$($line.VcenterImageName)`" could not be exported from vCenter `"$($line.VcenterName)`"."
                            Write-LogMessage -Type INFO -Message "Verify that the image exists in vCenter and that SDDC Manager has connectivity to `"$($line.VcenterName)`". Check vCenter logs for additional details."
                        }
                        default {
                            Write-LogMessage -Type ERROR -AppendNewLine -Message "Image `"$($line.VcenterImageName)`" import failed (Task Id: `"$TaskId`")."
                            if ($errorCode) { Write-LogMessage -Type ERROR -Message "Error code: $errorCode." }
                            if ($errorMessage) { Write-LogMessage -Type ERROR -Message "Error message: $errorMessage." }
                        }
                    }
                }
                default {
                    Write-LogMessage -Type ERROR -Message $response
                    Write-LogMessage -Type ERROR -Message "Failed to import image task Id `"$TaskId`"."
                }
            }
        }
    }

    # Clean up batch progress indicator.
    if ($totalImages -gt 1 -and -not $Silence) {
        Write-Progress -Id 1 -Completed
    }
}
Function Get-ImageComplianceElements {

    <#
        .SYNOPSIS
        Returns the vLCM compliance elements for a specified standalone host.

        .DESCRIPTION
        This function requires a ResourceId (HostId) and WorkloadDomainId (DomainId) to return the valid output.

        .PARAMETER ResourceId
        Specifies the resource ID (host ID).

        .PARAMETER WorkloadDomainId
        Specifies the workload domain ID.

        .EXAMPLE
        Get-ImageComplianceElements -ResourceId 9e2bfce7-548e-4579-b8da-9a7108f797aa -WorkloadDomainId 0073d838-6d88-4747-8511-374445df2053

        .OUTPUTS
        PSCustomObject
        Returns compliance check elements (clusterId, softwareSpec, etc.) required for API calls, or $null on failure.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ResourceId,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$WorkloadDomainId
    )

    # Check if connected to SDDC Manager.
    Write-LogMessage -Type DEBUG -Message "Entered Get-ImageComplianceElements function..."

    Test-SddcManagerConnection

    # This is a 9.1 specific function.
    $sddcManagerVersion = Get-SddcManagerVersion
    if ( ([Version]$sddcManagerVersion) -lt ([Version]$minimumSahRelease) ) {
        Write-LogMessage -Type ERROR -Message "Standalone host transitions to vLCM image management are not supported in SDDC Manager version $sddcManagerVersion."
        return $null
    }

    $transitionResourceSpec = Initialize-VcfTransitionResourceSpec -Id $ResourceId -Type "HOST" -ErrorAction SilentlyContinue
    # Form the query spec.
    $domainImageComplianceQuerySpec = Initialize-VcfDomainImageComplianceQuerySpec -Resources $transitionResourceSpec -ErrorAction SilentlyContinue

    try {
        $queryCompliance = Invoke-VcfQueryDomainImageCompliance -DomainId $WorkloadDomainId -DomainImageComplianceQuerySpec $domainImageComplianceQuerySpec -ErrorAction Stop
    } catch {
        switch -Regex ($_.Exception.Message) {
            "is not recognized as.*name of a cmdlet" {
                Write-LogMessage -Type ERROR -Message "VCF.PowerCLI cmdlet 'Invoke-VcfQueryDomainImageCompliance' not found. Please ensure VCF.PowerCLI $minimumVcfPowerCliVersion or later is installed."
                Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
            }
            "NO_SAH_FOUND_IN_QUERY" { return $false }
            default { throw }
        }
    }

    # Allow time for query to be posted to SDDC Manager API.
    Start-Sleep -Seconds 1

    # QueryInfo contains a number of details on our host, including, the associated image name and its compliance with the image.
    $queryInfo = Invoke-VcfGetDomainImageComplianceQueryResponse -DomainId $WorkloadDomainId -QueryId $queryCompliance.QueryInfo.QueryId -ErrorAction SilentlyContinue

    # Poll for query completion status with timeout.
    $timeout = 60  # seconds
    $elapsed = 0
    $pollInterval = 500  # milliseconds

    While ($queryInfo -and $queryInfo.QueryInfo.Status -eq "IN_PROGRESS" -and $elapsed -lt ($timeout * 1000)) {
        Start-Sleep -Milliseconds $pollInterval
        $elapsed += $pollInterval

        # Re-query to get updated status.
        $queryInfo = Invoke-VcfGetDomainImageComplianceQueryResponse -DomainId $WorkloadDomainId -QueryId $queryCompliance.QueryInfo.QueryId -ErrorAction SilentlyContinue
    }

    if ($elapsed -ge ($timeout * 1000)) {
        Write-LogMessage -Type WARNING -Message "Compliance query for host resource ID '$ResourceId' timed out after $timeout seconds."
        return $null
    }

    if (-not $queryInfo -or -not $queryInfo.PSObject.Properties['Result'] -or -not $queryInfo.Result) {
        Write-LogMessage -Type WARNING -Message "Compliance query for host resource ID '$ResourceId' returned no result."
        return $null
    }

    $resultElements = if ($queryInfo.Result.PSObject.Properties['Elements']) { $queryInfo.Result.Elements } else { $null }
    $complianceStatus = if ($resultElements -and $resultElements.PSObject.Properties['Status']) { $resultElements.Status } else { $null }

    if (-not $complianceStatus) {
        $hostFqdn = (Invoke-VcfGetHost -Id $ResourceId -ErrorAction SilentlyContinue).Fqdn
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Standalone host $hostFqdn has no image compliance results."
        return "<NO_COMPLIANCE_RESULTS>"
    }
    return $resultElements
}
Function Get-ResourceId {

    <#
        .SYNOPSIS
        Retrieves the resource ID (Cluster ID or Host ID) for a given resource name.

        .DESCRIPTION
        This helper function looks up a cluster or standalone host by name within a workload domain
        and returns its unique identifier. It verifies SDDC Manager connectivity and validates
        that the workload domain exists before attempting the lookup.

        For standalone hosts, this function also checks the SDDC Manager version to ensure
        standalone host operations are supported (requires VCF 5.2.2+ / SDDC Manager 9.0+).

        Returns a structured error object if the resource is not found or if there's an API error.

        .PARAMETER ResourceType
        The type of resource: "Cluster" or "Standalone Host".

        .PARAMETER ResourceName
        The name of the cluster or the FQDN of the standalone host.

        .PARAMETER WorkloadDomainName
        The name of the workload domain containing the resource.

        .OUTPUTS
        Hashtable with Success and either ResourceId or ErrorMessage/ErrorCode properties.
        On success: @{ Success = $true; ResourceId = "<guid>"; ResourceType = "..." }
        On failure: @{ Success = $false; ErrorMessage = "..."; ErrorCode = "ERR_..." }

        .EXAMPLE
        $result = Get-ResourceId -ResourceName "m01-cl01" -ResourceType "Cluster" -WorkloadDomainName "m01"
        if ($result.Success) {
            $clusterId = $result.ResourceId
        } else {
            Write-LogMessage -Type ERROR -Message $result.ErrorMessage
            Exit-WithCode -ExitCode $Script:ExitCodes.RESOURCE_NOT_FOUND
        }

        .EXAMPLE
        $result = Get-ResourceId -ResourceName "esx-01.example.com" -ResourceType "Standalone Host" -WorkloadDomainName "m01"
        if ($result.Success) {
            $hostId = $result.ResourceId
        }

        .NOTES
        Error Handling: This is a helper function that returns structured error objects.
        Callers must check the Success property and handle errors appropriately.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateSet("Cluster","Standalone Host")] [String]$ResourceType,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ResourceName,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$WorkloadDomainName
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-ResourceId function..."

    Write-LogMessage -Type DEBUG -Message "Looking up $ResourceType resource `"$ResourceName`" in domain `"$WorkloadDomainName`"."

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    # Get workload domain ID.
    $domainResult = Get-WorkloadDomainId -WorkloadDomainName $WorkloadDomainName
    if (-not $domainResult.Success) {
        Write-LogMessage -Type DEBUG -Message "Failed to get workload domain ID"
        return $domainResult  # Propagate domain lookup error
    }
    $workloadDomainId = $domainResult.WorkloadDomainId
    Write-LogMessage -Type DEBUG -Message "Retrieved workload domain ID: $workloadDomainId"

    try {
        if ($ResourceType -eq "Cluster") {
            Write-LogMessage -Type DEBUG -Message "Searching for cluster in SDDC Manager (calling Invoke-VcfGetClusters API)"
            # Look up cluster by name in the specified workload domain.
            $clustersLookupResult = Invoke-VcfGetClusters -ErrorAction SilentlyContinue
            $matchedCluster = if ($clustersLookupResult -and $clustersLookupResult.PSObject.Properties['Elements']) { $clustersLookupResult.Elements | Where-Object { $_.Domain.Id -eq $workloadDomainId -and $_.Name -eq $ResourceName } | Select-Object -First 1 } else { $null }
            $resourceId = if ($matchedCluster) { $matchedCluster.Id } else { $null }

            if (-not $resourceId) {
                Write-LogMessage -Type DEBUG -Message "Cluster `"$ResourceName`" not found in domain"
                return Write-ErrorAndReturn `
                    -ErrorMessage "Cluster '$ResourceName' not found in workload domain '$WorkloadDomainName'." `
                    -ErrorCode "ERR_CLUSTER_NOT_FOUND"
            }

        } else {
            Write-LogMessage -Type DEBUG -Message "Searching for standalone host in SDDC Manager"
            # Standalone Host - check SDDC Manager version first.
            $sddcManagerVersion = Get-SddcManagerVersion
            Write-LogMessage -Type DEBUG -Message "SDDC Manager version: $sddcManagerVersion (minimum required: $minimumSahRelease)"
            if ([Version]$sddcManagerVersion -lt [Version]$minimumSahRelease) {
                Write-LogMessage -Type DEBUG -Message "SDDC Manager version too old for standalone host support"
                return Write-ErrorAndReturn `
                    -ErrorMessage "Standalone Host transitions to vLCM image management require SDDC Manager $minimumSahRelease or later. Current version: $sddcManagerVersion" `
                    -ErrorCode "ERR_VERSION_UNSUPPORTED"
            }

            Write-LogMessage -Type DEBUG -Message "Calling Invoke-VcfGetHosts API for domain: $workloadDomainId"
            # Look up host by FQDN in the specified workload domain.
            $hostsLookupResult = Invoke-VcfGetHosts -ErrorAction SilentlyContinue -DomainId $workloadDomainId
            $matchedHost = if ($hostsLookupResult -and $hostsLookupResult.PSObject.Properties['Elements']) { $hostsLookupResult.Elements | Where-Object { $_.Fqdn -eq $ResourceName } | Select-Object -First 1 } else { $null }
            $resourceId = if ($matchedHost) { $matchedHost.Id } else { $null }

            if (-not $resourceId) {
                Write-LogMessage -Type DEBUG -Message "Standalone host `"$ResourceName`" not found in domain"
                return Write-ErrorAndReturn `
                    -ErrorMessage "Standalone host '$ResourceName' not found in workload domain '$WorkloadDomainName'." `
                    -ErrorCode "ERR_HOST_NOT_FOUND"
            }
        }

        Write-LogMessage -Type DEBUG -Message "Successfully found $ResourceType `"$ResourceName`" with ID: $resourceId"
        return @{
            Success = $true
            ResourceId = $resourceId
            ResourceType = $ResourceType
        }

    } catch {
        Write-LogMessage -Type DEBUG -Message "Exception retrieving resource: $($_.Exception.Message)"
        return Write-ErrorAndReturn `
            -ErrorMessage "Failed to retrieve $ResourceType '$ResourceName': $($_.Exception.Message)" `
            -ErrorCode "ERR_OPERATION_FAILED"
    }
}
Function Get-ComplianceDetailsForResource {

    <#
        .SYNOPSIS
        Retrieves image compliance details for a single cluster or standalone host resource.

        .DESCRIPTION
        This helper function queries SDDC Manager for image compliance details. For clusters, it performs
        a direct API call. For standalone hosts, it initiates a compliance query and polls for completion.
        Returns a structured result object containing compliance status, image name, and detailed findings.

        .PARAMETER Resource
        A PSCustomObject containing resource details with properties:
        - ResourceType: "Cluster" or "Standalone Host"
        - ResourceId: The SDDC Manager resource UUID
        - ResourceName: The friendly resource name
        - WorkloadDomainId: The workload domain UUID
        - WorkloadDomainName: The workload domain name

        .PARAMETER QueryTimeoutSeconds
        Maximum time (in seconds) to wait for standalone host compliance query completion.
        Default: 60. Valid range: 1-3600.

        .PARAMETER QueryPollingIntervalMilliseconds
        How often (in milliseconds) to check standalone host compliance query status.
        Default: 500. Valid range: 100-5000.

        .EXAMPLE
        $result = Get-ComplianceDetailsForResource -Resource $resourceObject
        if ($result.Success) {
            Write-Host "Status: $($result.RollUpStatus)"
        }

        .OUTPUTS
        Hashtable with keys:
        - Success: Boolean indicating if query succeeded
        - SddcManagerImageName: Name of the vLCM image
        - RollUpStatus: Overall compliance status (COMPLIANT, NON_COMPLIANT, INCOMPATIBLE, UNKNOWN)
        - ImageComplianceDetails: Detailed compliance findings object
        - JsonResponse: JSON string of full compliance details
        - ErrorMessage: Error description if Success=$false
    #>

    Param (
        [Parameter(Mandatory = $true)] [PSCustomObject]$resource,
        [Parameter(Mandatory = $false)] [ValidateRange(1, 3600)] [Int]$queryTimeoutSeconds = 60,
        [Parameter(Mandatory = $false)] [ValidateRange(100, 5000)] [Int]$queryPollingIntervalMilliseconds = 500
    )

    $result = @{
        Success = $false
        SddcManagerImageName = $null
        RollUpStatus = $null
        ImageComplianceDetails = $null
        JsonResponse = $null
        ErrorMessage = $null
    }

    switch ($resource.ResourceType) {
    "Cluster" {
        # Query compliance details for cluster.
        try {
            $imageComplianceDetails = Invoke-VcfGetClusterImageCompliance -Id $($resource.ResourceId) -ErrorAction Stop
        } catch {
            if ($_.Exception.Message -match "CLUSTER_IMAGE_COMPLIANCE_NOT_FOUND") {
                $result.ErrorMessage = "No image compliance results available"
                return $result
            }
            $result.ErrorMessage = $_.Exception.Message
            return $result
        }

        if ([String]::IsNullOrEmpty($imageComplianceDetails)) {
            $result.ErrorMessage = "Could not locate image compliance check results for $($resource.ResourceType) `"$($resource.ResourceName)`" in workload domain `"$($resource.WorkloadDomainName)`""
            return $result
        }

        $result.SddcManagerImageName = if ($imageComplianceDetails.PSObject.Properties['ClusterImage'] -and $imageComplianceDetails.ClusterImage) { $imageComplianceDetails.ClusterImage.Name } else { $null }
        $result.RollUpStatus = if ($imageComplianceDetails.PSObject.Properties['Status']) { $imageComplianceDetails.Status } else { $null }
        $result.ImageComplianceDetails = $imageComplianceDetails
        $result.JsonResponse = $imageComplianceDetails | ConvertTo-Json -Depth 3
        $result.Success = $true
    }
    "Standalone Host" {
        # Query compliance details for standalone host.
        $TransitionResourceSpec = Initialize-VcfTransitionResourceSpec -Id $resource.ResourceId -Type "HOST" -ErrorAction SilentlyContinue

        # Form query spec.
        $domainImageComplianceQuerySpec = Initialize-VcfDomainImageComplianceQuerySpec -Resources $TransitionResourceSpec -ErrorAction SilentlyContinue

        try {
            $queryCompliance = Invoke-VcfQueryDomainImageCompliance -DomainId $resource.WorkloadDomainId -DomainImageComplianceQuerySpec $domainImageComplianceQuerySpec -ErrorAction Stop
        } catch {
            if ($_.Exception.Message -match "NO_SAH_FOUND_IN_QUERY") {
                $result.ErrorMessage = "No standalone host found in query"
                return $result
            }
            # Re-throw if it's a different error.
            throw
        }

        # Allow time for query to be posted to SDDC Manager API.
        Start-Sleep -Seconds 1

        # QueryInfo contains a number of details on our host, including the associated image name and its compliance with the image.
        $queryInfo = Invoke-VcfGetDomainImageComplianceQueryResponse -DomainId $resource.WorkloadDomainId -QueryId $queryCompliance.QueryInfo.QueryId -ErrorAction SilentlyContinue

        # Poll for query completion status with timeout.
        $elapsed = 0
        $timeoutMilliseconds = $queryTimeoutSeconds * 1000

        While ($queryInfo -and $queryInfo.QueryInfo.Status -eq "IN_PROGRESS" -and $elapsed -lt $timeoutMilliseconds) {
            Start-Sleep -Milliseconds $queryPollingIntervalMilliseconds
            $elapsed += $queryPollingIntervalMilliseconds

            # Re-query to get updated status.
            $queryInfo = Invoke-VcfGetDomainImageComplianceQueryResponse -DomainId $resource.WorkloadDomainId -QueryId $queryCompliance.QueryInfo.QueryId -ErrorAction SilentlyContinue
        }

        if ($elapsed -ge $timeoutMilliseconds) {
            $result.ErrorMessage = "Compliance query timed out after $queryTimeoutSeconds seconds"
            return $result
        }

        if (-not $queryInfo -or -not $queryInfo.PSObject.Properties['Result'] -or -not $queryInfo.Result) {
            $result.ErrorMessage = "Compliance query returned no result"
            return $result
        }

        # Result.Elements is a List<ImageComplianceResult>. Select the first element for this host's result.
        $resultElementsList = if ($queryInfo.Result.PSObject.Properties['Elements']) { $queryInfo.Result.Elements } else { $null }
        $resultElements = if ($resultElementsList) { @($resultElementsList)[0] } else { $null }

        $complianceStatus = if ($resultElements -and $resultElements.PSObject.Properties['Status']) { $resultElements.Status } else { $null }
        if ([String]::IsNullOrWhiteSpace($complianceStatus)) {
            $result.ErrorMessage = "No image compliance results available"
            return $result
        }

        $imageObj = if ($resultElements.PSObject.Properties['Image']) { $resultElements.Image } else { $null }
        [array]$imageComplianceDetails = if ($resultElements.PSObject.Properties['ImageComplianceDetails'] -and $resultElements.ImageComplianceDetails) { @($resultElements.ImageComplianceDetails) } else { @() }

        $result.SddcManagerImageName = if ($imageObj -and $imageObj.PSObject.Properties['Name']) { $imageObj.Name } else { $null }
        $result.RollUpStatus = $complianceStatus
        $result.ImageComplianceDetails = $imageComplianceDetails
        $result.JsonResponse = $resultElements | ConvertTo-Json -Depth 3
        $result.Success = $true
    }
    } # end switch

    return $result
}
Function Show-ImageComplianceCheckResults {

    <#
        .SYNOPSIS
        Displays a cluster or standalone host's compliance status against a vLCM image.

        .DESCRIPTION
        This function is called by Invoke-ImageComplianceCheck and headless parameters. After the results have been stored
        in the database, this function displays the summarized results (and the full results in JSON in a file on the user's
        system) of the full check results.

        .PARAMETER QueryPollingIntervalMilliseconds
        How often (in milliseconds) to check standalone host compliance query status. Default: 500. Valid range: 100-5000.

        .PARAMETER QueryTimeoutSeconds
        Maximum time (in seconds) to wait for standalone host compliance query completion. Default: 60. Valid range: 1-3600.

        .PARAMETER ResourceName
        Specifies the cluster or standalone host name for baseline managed resource.

        .PARAMETER ResourceType
        Specifies the resource type: Cluster or Standalone Host.

        .PARAMETER ShowAllResources
        When specified, displays results for all baseline managed resources.

        .PARAMETER ShowExtendedResults
        When specified, displays the full (rather than summarized) resource compatibility results on screen.

        .PARAMETER WorkloadDomainName
        Specifies the workload domain name containing the baseline managed cluster or host.

        .EXAMPLE
        Show-ImageComplianceCheckResults -ResourceName m01-cl01 -ResourceType Cluster -WorkloadDomainName m01

        .EXAMPLE
        Show-ImageComplianceCheckResults -ResourceName m01-cl01 -ResourceType Cluster -WorkloadDomainName m01 -ShowExtendedResults

        .EXAMPLE
        Show-ImageComplianceCheckResults -ShowAllResources

        .OUTPUTS
        None
        This function does not return a value. It displays compliance check results in a formatted table.
    #>

    Param (
        [Parameter(Mandatory = $false)] [ValidateRange(100, 5000)] [Int]$QueryPollingIntervalMilliseconds = 500,
        [Parameter(Mandatory = $false)] [ValidateRange(1, 3600)] [Int]$QueryTimeoutSeconds = 60,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$ResourceName,
        [Parameter(Mandatory = $false)] [ValidateSet("Cluster", "Standalone Host")] [String]$ResourceType,
        [Parameter(Mandatory = $false)] [Switch]$ShowAllResources,
        [Parameter(Mandatory = $false)] [Switch]$ShowExtendedResults,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$WorkloadDomainName
    )

    # Check if connected to SDDC Manager.
    Write-LogMessage -Type DEBUG -Message "Entered Show-ImageComplianceCheckResults function..."

    Test-SddcManagerConnection

    $baseLineManagedResourceCount = 0

    # Applies to a single resource.
    if (-not $ShowAllResources) {

        # Derive a workload domain Id from the workload domain name.
        $domainResult = Get-WorkloadDomainId -WorkloadDomainName $WorkloadDomainName
        if (-not $domainResult.Success) {
            Write-LogMessage -Type ERROR -Message $domainResult.ErrorMessage
            Exit-WithCode -ExitCode $Script:ExitCodes.RESOURCE_NOT_FOUND
        }
        $workloadDomainId = $domainResult.WorkloadDomainId

        $resourceResult = Get-ResourceId -ResourceType $ResourceType -ResourceName $ResourceName -WorkloadDomainName $WorkloadDomainName
        if (-not $resourceResult.Success) {
            Write-LogMessage -Type ERROR -Message $resourceResult.ErrorMessage
            Exit-WithCode -ExitCode $Script:ExitCodes.RESOURCE_NOT_FOUND
        }
        $resourceId = $resourceResult.ResourceId

        $baselineManagedResources = [pscustomobject]@{
            WorkloadDomainId = $workloadDomainId
            WorkloadDomainName = $WorkloadDomainName
            ResourceId = $resourceId
            ResourceName = $ResourceName
            ResourceType = $ResourceType
        }
        $baseLineManagedResourceCount++
    } else {
        # Use shared helper function to discover baseline-managed resources.
        $baselineManagedResources = Get-BaselineManagedResourceList
        $baseLineManagedResourceCount = @($baselineManagedResources).Count

        if ($baseLineManagedResourceCount -eq [int]0) {
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "No baseline managed resources (clusters or standalone hosts) located."
        } else {
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "$baseLineManagedResourceCount baseline managed resources located."
        }
    }

    foreach ($resource in $baselineManagedResources) {
        # Query compliance details using helper function.
        $complianceResult = Get-ComplianceDetailsForResource -Resource $resource -QueryTimeoutSeconds $QueryTimeoutSeconds -QueryPollingIntervalMilliseconds $QueryPollingIntervalMilliseconds

        # Handle query failures. Note: switch/continue does not propagate to the enclosing foreach,
        # so if/elseif is used here to ensure skipped resources actually continue the foreach loop.
        if (-not $complianceResult.Success) {
            if ($complianceResult.ErrorMessage -match "^No standalone host found in query$") {
                # Silent skip - expected for some resources.
                continue
            } elseif ($complianceResult.ErrorMessage -match "timed out") {
                Write-LogMessage -Type WARNING -Message "Compliance query for $($resource.ResourceType) `"$($resource.ResourceName)`" timed out after $QueryTimeoutSeconds seconds. Skipping resource."
                continue
            } elseif ($complianceResult.ErrorMessage -match "^No image compliance results available$") {
                Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "$($resource.ResourceType) `"$($resource.ResourceName)`" has no image compliance results."
                continue
            } else {
                Write-LogMessage -Type ERROR -Message "Could not locate image compliance check results for $($resource.ResourceType) `"$($resource.ResourceName)`" in workload domain `"$($resource.WorkloadDomainName)`""
                Write-LogMessage -Type ERROR -Message "Error: $($complianceResult.ErrorMessage)"
                return
            }
        }

        # Extract results from helper function. Always coerce ImageComplianceDetails to an array
        # so $null | Where-Object never executes the scriptblock with $_ = $null.
        $SddcManagerImageName = $complianceResult.SddcManagerImageName
        $rollUpStatus = $complianceResult.RollUpStatus
        [array]$imageComplianceDetails = @($complianceResult.ImageComplianceDetails)
        $jsonResponse = $complianceResult.JsonResponse

        # If there's a null ClusterImage.Name host-seeding was used.
        if ($null -eq $SddcManagerImageName) {
            $SddcManagerImageName = "Autogenerated-Image"
        }

        Write-LogMessage -Type INFO -AppendNewLine -PrependNewLine -Message "$($resource.ResourceType) `"$($resource.ResourceName)`" in Workload Domain `"$($resource.WorkloadDomainName)`" has status `"$rollUpStatus`"."

        switch ($rollUpStatus) {
            "COMPLIANT" {
                Write-LogMessage -Type INFO -Message "Neither maintenance mode or a reboot is required to transition `"$($resource.ResourceName)`" to vLCM image management."
            }
            "NON_COMPLIANT" {
                # Omit -AppendNewLine here; the compatibility summary block uses Write-Host "" once so spacing stays one blank line before the Summary for all roll-up statuses.
                Write-LogMessage -Type WARNING -Message "Remediation involving maintenance mode or a reboot, or both, is required for $($resource.ResourceName) to transition to vLCM image management."
            }
            "INCOMPATIBLE" {
                Write-LogMessage -Type ERROR -Message "Remediation cannot proceed, this image is incompatible with the current state of `"$($resource.ResourceName)`"."
                Write-LogMessage -Type ERROR -Message "Please review INCOMPATIBLE findings, resolve the findings through a new or modified image, and re-try the compliance check."
            }
            "UNAVAILABLE" {
                Write-LogMessage -Type WARNING -Message "Compliance status is UNAVAILABLE for `"$($resource.ResourceName)`". The image or host state may have changed since the last compliance check. Please re-run the compliance check."
            }
            "UNKNOWN" {
                Write-LogMessage -Type WARNING -Message "Compatibility could not be determined for `"$($resource.ResourceName)`". Please ensure all resources are available then re-run the compliance check."
            }
            default {
                Write-LogMessage -Type WARNING -Message "Unrecognised compliance status `"$rollUpStatus`" for `"$($resource.ResourceName)`"."
            }
        }

        $resourceFindingSeverities = "ERROR", "WARNING", "UNAVAILABLE", "INFO"
        $complianceFindings = 0
            $complianceFindingsDisplayObject = @()

            $complianceFindingsDisplayObject += [pscustomobject]@{
                'ComponentName'   = "Component Name"
                'ComponentVendor' = "Component Vendor"
                'CvChange'        = "Version Change"
                'Message'         = "Message"
                'Impact'          = "Impact"
                'Severity'        = "Severity"
            }

            $complianceFindingsDisplayObject += [pscustomobject]@{
                'ComponentName'   = "--------------"
                'ComponentVendor' = "----------------"
                'CvChange'        = "--------------"
                'Message'         = "--------"
                'Impact'          = "------"
                'Severity'        = "--------"
            }

            # Create a horizontal line separator to make it easier to view each result.
            # It starts two character in to match the non-separator lines.
            $separator = $("-" * ($($Host.UI.RawUI.WindowSize.Width) -2))

        foreach ($severity in $resourceFindingSeverities) {

                # Determine all the unique findings for the severity in question.
            if ($resource.ResourceType -eq "Cluster") {
                $uniqueFindingsPerSeverity = $imageComplianceDetails.ImageComplianceDetails | Where-Object { $_.PSObject.Properties['Severity'] -and $_.Severity -eq $severity -and $_.Impact -ne "NO_IMPACT" } | `
                    Select-Object ComponentName,ComponentType,ComponentCurrentVersion,ComponentTargetVersion,ComponentVendor,Message,Impact |`
                Sort-Object -Property Message,ComponentName | Get-Unique -AsString
            } else {
                $uniqueFindingsPerSeverity = $imageComplianceDetails | Where-Object { $_.PSObject.Properties['Severity'] -and $_.Severity -eq $severity -and $_.Impact -ne "NO_IMPACT" } | `
                Select-Object ComponentName,ComponentType,ComponentCurrentVersion,ComponentTargetVersion,ComponentVendor,Message,Impact |`
                Sort-Object -Property Message,ComponentName | Get-Unique -AsString
            }

                foreach ($uniqueFinding in $uniqueFindingsPerSeverity ) {
                    # If the current and target version are the same (even if null), treat as non-change.
                    if ($($uniqueFinding.ComponentCurrentVersion) -eq $($uniqueFinding.ComponentTargetVersion)) {
                        $cvChange = "No"
                    } else {
                        $cvChange = "Yes"
                    }
                    if ([String]::IsNullOrEmpty($uniqueFinding.Message)) {
                        $message = "None"
                    } else {
                        $message = $uniqueFinding.Message
                    }
                    if ([String]::IsNullOrEmpty($uniqueFinding.Impact)) {
                        $impact = "N/A"
                    } else {
                        $impact = $uniqueFinding.Impact
                    }
                    if ([String]::IsNullOrEmpty($uniqueFinding.ComponentName)) {
                        $componentName = "N/A"
                    } else {
                        $componentName = $uniqueFinding.ComponentName
                    }

                    if ([String]::IsNullOrEmpty($uniqueFinding.ComponentVendor)) {
                        $componentVendor = "N/A"
                    } else {
                        $componentVendor = $uniqueFinding.ComponentVendor
                    }
                    $complianceFindingsDisplayObject += [pscustomobject]@{
                        'ComponentName'    = $componentName
                        'ComponentVendor'  = $componentVendor
                        'CvChange'         = $cvChange
                        'Message'          = $message
                        'Impact'           = $impact
                        'Severity'         = $severity
                    }
                $complianceFindings++
            }
        }

        if ($complianceFindings -ne [int]0) {
            Write-LogMessage -Type INFO -AppendNewLine -Message "Summary of compatibility check for $($resource.ResourceType) `"$($resource.ResourceName)`" in Workload Domain `"$($resource.WorkloadDomainName)`" against image `"$SddcManagerImageName`""

            # Sort findings by Severity (descending priority) then ComponentName. Data rows only (no separators).
            $headerRows = $complianceFindingsDisplayObject[0..1]
            $dataRowsOnly = $complianceFindingsDisplayObject[2..($complianceFindingsDisplayObject.Count - 1)]
            $sortedDataRows = $dataRowsOnly | Sort-Object -Property @{
                Expression = {
                    # Sort by severity priority: INCOMPATIBLE=1, ERROR=2, WARNING=3, INFO=4.
                    switch ($_.Severity) {
                        "INCOMPATIBLE" { 1 }
                        "ERROR" { 2 }
                        "WARNING" { 3 }
                        "INFO" { 4 }
                        default { 5 }
                    }
                }
            }, ComponentName
            # Interleave separator lines between rows so they display as dividers, not at the end.
            $sortedComplianceFindings = @($headerRows)
            foreach ($row in $sortedDataRows) {
                $sortedComplianceFindings += "  $separator"
                $sortedComplianceFindings += $row
            }

            $sortedComplianceFindings | Format-Table -Wrap:$false -Property @{Expression = " " }, ComponentName, ComponentVendor, CvChange, Impact, Severity, Message -HideTableHeaders | Out-Host
        }

            # Display detailed findings for critical issues (defined as incompatible).
            # Cluster compliance objects store findings under .ImageComplianceDetails; standalone hosts are the findings directly.
            $findingsSource = if ($resource.ResourceType -eq "Cluster") { $imageComplianceDetails.ImageComplianceDetails } else { $imageComplianceDetails }
            [array]$incompatibleResults = if ($findingsSource) { @($findingsSource | Where-Object { $_.PSObject.Properties['Severity'] -and $_.Severity -eq "INCOMPATIBLE" }) } else { @() }
            if ($incompatibleResults) {
                Write-LogMessage -Type INFO -PrependNewLine -Message "Please carefully review the following INCOMPATIBLE findings:"
                $uniqueIncompatibleMessages = @($incompatibleResults | Select-Object -Unique Message) | Select-Object -ExpandProperty Message
                foreach ($uniqueIncompatibleMessage in $uniqueIncompatibleMessages) {
                    [array]$matchedFindings = @($incompatibleResults | Where-Object { $_.Message -eq $uniqueIncompatibleMessage })
                    $entities = $matchedFindings | Select-Object -ExpandProperty EntityName
                    [array]$componentTypes = @($matchedFindings | Select-Object -ExpandProperty ComponentType | Get-Unique)
                    $componentType = $componentTypes[0]
                    Write-LogMessage -Type ADVISORY -PrependNewLine -Message "ESX hosts: $([String]$entities -replace(" ",", ")) report the following Message in component `"$componentType`" : `n`n`"$uniqueIncompatibleMessage`""
                }
            }

        $jsonLogFile = Join-Path -Path $logFolder -ChildPath "resource-compatibility-for-$($resource.ResourceName)-on-$($resource.WorkloadDomainName)-with-$SddcManagerImageName.json"

            # Write the json Response to a discrete file for ease of parsing.
        Set-Content -Path $jsonLogFile $jsonResponse

            # Also write the content to log file for troubleshooting with support.
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "=== START Compliance results for $($resource.ResourceName) using $SddcManagerImageName ==="
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message $jsonResponse
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "=== END Compliance results for $($resource.ResourceName) using $SddcManagerImageName ==="

            # Inform the user where to find the full the compliance findings.
        Write-LogMessage -Type INFO -PrependNewLine -Message "Full compliance findings stored for $($resource.ResourceType) `"$($resource.ResourceName)`" in Workload Domain `"$($resource.WorkloadDomainName)`" have been saved to $jsonLogFile "

            if ($ShowExtendedResults) {
                Write-Host "`nDisplaying Full Results:" -ForegroundColor Cyan
                Write-Output $jsonResponse | more
            }

        if (-not $Silence) {
            Write-Host -Object "`n==============="
        }
    }
    if ($baseLineManagedResourceCount -eq [int]0) {
        Write-LogMessage -Type INFO -AppendNewLine -Message "No baseline managed resources located and thus not displaying any image compatibility results."
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

        .OUTPUTS
        None
        This function does not return a value. It displays SDDC Manager images interactively or prints them to console.
    #>

    Param (
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$IdSelection,
        [Parameter(Mandatory = $false)] [Switch]$ShowAll,
        [Parameter(Mandatory = $false)] [Switch]$ShowId
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-SddcManagerImages function..."

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    if ($Script:vxRailMode) {
        Write-LogMessage -Type ERROR -Message "VxRail only supports vLCM baseline to vLCM image transitions through image seeding and cannot make use of images imported into SDDC Manager."
        Show-AnyKey
        if (-not $Script:Headless) {
            Show-MainMenu
        }
        return
    }

    # show images (personalities) already present in SDDC Manager.
    $personalitiesListResult = Invoke-VcfGetPersonalities -ErrorAction SilentlyContinue
    $response = if ($personalitiesListResult -and $personalitiesListResult.PSObject.Properties['Elements']) { $personalitiesListResult.Elements } else { $null }

    if (-not $response) {
        Write-LogMessage -Type ERROR -Message "No vLCM images found in SDDC Manager `"$Global:SddcManagerFqdn`"."
        Show-AnyKey
        if (-not $Script:Headless) {
            Show-MainMenu
        }
    } else {
        $imageNameIndex = 1
        $imageNameDisplayObject = @()

        $imageNameDisplayObject += [pscustomobject]@{
            'Id'                   = 'Id'
            'SddcManagerImageName' = "SDDC Manager Image Name"
            'ImageId'              = "Image Id"
            'BaseImageVersion'     = "Base Image"
            'ImageComponents'      = "Components"
            'ImageAddOns'          = "Addons"
            'ImageHardwareSupport' = "Hardware Support"
        }

        $imageNameDisplayObject += [pscustomobject]@{
            'Id'                   = "--"
            'SddcManagerImageName' = "-----------------------"
            'ImageId'              = "----------"
            'BaseImageVersion'     = "----------"
            'ImageComponents'      = "----------"
            'ImageAddOns'          = "-------"
            'ImageHardwareSupport' = "----------------"
        }

        # Sort images by PersonalityName alphabetically.
        $sortedResponse = $response | Sort-Object -Property PersonalityName

        foreach ($line in $sortedResponse) {

            # The full spec for each image may be sourced from vCenter through SDDC Manager.
            if ($Env:SkipCertificateCheck) {
                $vcenterJsonOutput = (Invoke-WebRequest -SkipCertificateCheck $($line.VsphereExportedJsonPath)).Content
            } else {
                try {
                    $vcenterJsonOutput = (Invoke-WebRequest $($line.VsphereExportedJsonPath)).Content
                } catch {
                    if ($_.Exception.Message -match "SSL connection could not be established") {
                        Write-LogMessage -Type ERROR -Message "SSL connection trust issue with SDDC Manager. If this is expected, please run `$Env:SkipCertificateCheck=`"enabled`" and re-run the script."
                        Exit-WithCode -ExitCode $Script:ExitCodes.CONNECTION_ERROR
                    } else {
                        Write-LogMessage -Type ERROR -Message "Failed to retrieve image specification: $($_.Exception.Message)."
                        Exit-WithCode -ExitCode $Script:ExitCodes.OPERATION_FAILED
                    }
                }
            }
            # Write the json Response to a discrete file in the log folder for ease of parsing.
            $jsonLogFile = Join-Path -Path $logFolder -ChildPath "$($line.PersonalityName).json"
            Set-Content -Path $jsonLogFile $vcenterJsonOutput
            $imageAddOnData = if ($line.SoftwareInfo -and $line.SoftwareInfo.PSObject.Properties['AddOn'] -and $line.SoftwareInfo.AddOn) { $line.SoftwareInfo.AddOn } else { $null }
            if (-not $imageAddOnData) {
                $imageAddOns = "N/A"
            } else {
                $imageAddOns = @()
                foreach ($imageAddOnItem in $imageAddOnData) {
                    $imageAddOns += "$($imageAddOnItem.DisplayName): $($imageAddOnItem.DisplayVersion)"
                }
                if (-not $imageAddOns) { $imageAddOns = "N/A" }
            }

            $imageComponentsSource = if ($line.SoftwareInfo -and $line.SoftwareInfo.PSObject.Properties['Components'] -and $line.SoftwareInfo.Components) {
                $comp = $line.SoftwareInfo.Components
                if ($comp.PSObject.Properties['Values']) { $comp.Values } else { $null }
            } else { $null }
            if (-not $imageComponentsSource) {
                $imageComponents = "N/A"
            } else {
                $imageComponents = @()
                foreach ($imageComponent in $imageComponentsSource) {
                    $imageComponents += "$($imageComponent.Details.DisplayName): $($imageComponent.Details.DisplayVersion)"
                }
                if (-not $imageComponents) { $imageComponents = "N/A" }
            }

            $imageHardwareSupportSource = if ($line.SoftwareInfo -and $line.SoftwareInfo.PSObject.Properties['HardwareSupport'] -and $line.SoftwareInfo.HardwareSupport) {
                $hwSupport = $line.SoftwareInfo.HardwareSupport
                if ($hwSupport.PSObject.Properties['Packages'] -and $hwSupport.Packages -and $hwSupport.Packages.PSObject.Properties['Values']) {
                    $hwSupport.Packages.Values
                } else { $null }
            } else { $null }
            if (-not $imageHardwareSupportSource) {
                $imageHardwareSupport = "N/A"
            } else {
                $imageHardwareSupport = @()
                foreach ($imageHardwareSupportItem in $imageHardwareSupportSource) {
                    $imageHardwareSupport += "$($imageHardwareSupportItem.Pkg): $($imageHardwareSupportItem._Version)"
                }
                if (-not $imageHardwareSupport) { $imageHardwareSupport = "N/A" }
            }

            $imageNameDisplayObject += [pscustomobject]@{
                'Id'                   = $imageNameIndex
                'SddcManagerImageName' = $line.PersonalityName
                'ImageId'              = $line.PersonalityId
                'BaseImageVersion'     = if ($line.SoftwareInfo -and $line.SoftwareInfo.PSObject.Properties['BaseImage'] -and $line.SoftwareInfo.BaseImage -and $line.SoftwareInfo.BaseImage.PSObject.Properties['Version']) { $line.SoftwareInfo.BaseImage.Version } else { $null }
                'ImageComponents'      = $imageComponents
                'ImageAddOns'          = $imageAddOns
                'ImageHardwareSupport' = $imageHardwareSupport
            }
        $imageNameIndex++
        }

        if (((-not $Script:logOnly) -and ($Script:Headless)) -or ($ShowAll)){
            Write-LogMessage -Type INFO -Message "vLCM images available in SDDC Manager `"$Global:SddcManagerFqdn`":"

            # Log SDDC Manager images in JSON format (skip header rows).
            if ($imageNameDisplayObject.Count -gt 2) {
                Write-LogMessage -Type DEBUG -Message "=== SDDC Manager vLCM Images ($(($imageNameDisplayObject.Count - 2)) image(s)) ==="
                $imagesJson = $imageNameDisplayObject[2..($imageNameDisplayObject.Count - 1)] |
                    Select-Object SddcManagerImageName, BaseImageVersion, ImageComponents, ImageAddOns, ImageHardwareSupport | ConvertTo-Json -Depth 2
                foreach ($line in ($imagesJson -split "`r?`n")) {
                    if ($line) { Write-LogMessage -Type DEBUG -Message $line }
                }
                Write-LogMessage -Type DEBUG -Message "=== End of SDDC Manager vLCM Images ==="
            }

            $imageNameDisplayObject | Format-Table -Property @{Expression = {$_.SddcManagerImageName}; n='Prop'; width = 25 }, BaseImageVersion, ImageComponents, ImageAddOns, ImageHardwareSupport -HideTableHeaders | Out-Host
        }
        if (-not $Script:Headless) {
            if ($IdSelection) {
                $selectedImageName = ($imageNameDisplayObject | Where-Object {$_.Id -eq $IdSelection}).SddcManagerImageName
                if (-not $selectedImageName) {
                    return "ERROR_INVALID_SELECTION"
                } else {
                    return $selectedImageName
                }
            }             elseif ($ShowId) {
                Write-LogMessage -Type INFO -Message "vLCM images available in SDDC Manager `"$Global:SddcManagerFqdn`":"

                # Log SDDC Manager images in JSON format (skip header rows).
                if ($imageNameDisplayObject.Count -gt 2) {
                    Write-LogMessage -Type DEBUG -Message "=== SDDC Manager vLCM Images ($(($imageNameDisplayObject.Count - 2)) images) ==="
                    $imagesJson = $imageNameDisplayObject[2..($imageNameDisplayObject.Count - 1)] |
                        Select-Object Id, SddcManagerImageName, BaseImageVersion, ImageComponents, ImageAddOns, ImageHardwareSupport | ConvertTo-Json -Depth 2
                    foreach ($line in ($imagesJson -split "`r?`n")) {
                        if ($line) { Write-LogMessage -Type DEBUG -Message $line }
                    }
                    Write-LogMessage -Type DEBUG -Message "=== End of SDDC Manager vLCM Images ==="
                }

                $imageNameDisplayObject | Format-Table -Property @{Expression = {$_.Id}; n='Prop'; width = 5 }, SddcManagerImageName, BaseImageVersion, ImageComponents, ImageAddOns, ImageHardwareSupport -HideTableHeaders | Out-Host
            }
        }
    }
}
Function Get-SddcType {

    <#
        .SYNOPSIS
        The function returns the SDDC Type of the vCenter.

        .DESCRIPTION
        The function seeks to identify if the SDDC Type is VCF (VSRN) or VCF-VxRail (VxRail) and returns the value.
        All connected vCenters are queried; "VCF-VxRail" is returned immediately if any vCenter reports that type,
        preventing a non-VxRail vCenter from masking the true deployment type in multi-vCenter environments.

        .EXAMPLE
        Get-SddcType

        .OUTPUTS
        String
        Returns the SDDC type: "VCF-VxRail" or the first non-null type found, or "NONE" for non-VCF environments.
    #>

    # Check if connected to SDDC Manager.
    Write-LogMessage -Type DEBUG -Message "Entered Get-SddcType function..."

    Test-SddcManagerConnection

    $firstNonNullType = $null
    foreach ($vcenter in $Global:DefaultVIServers) {
        try {
            $sddcType = (Get-AdvancedSetting -Server $vcenter -Entity $vcenter -ErrorAction Stop | Where-Object {$_.Name -eq "config.SDDC.Deployed.Type"}).Value
        } catch {
            Write-LogMessage -Type WARNING -Message "Could not retrieve SDDC type from vCenter `"$($vcenter.Name)`": $($_.Exception.Message)"
            continue
        }
        # A VxRail identification from any vCenter takes precedence over all other responses.
        if ($sddcType -eq "VCF-VxRail") {
            return $sddcType
        }
        if ($sddcType -and -not $firstNonNullType) {
            $firstNonNullType = $sddcType
        }
    }

    # Return the first non-null type found, or "NONE" for non-VCF environments.
    if ($firstNonNullType) {
        return $firstNonNullType
    }
    return "NONE"
}

Function Set-VxRailMode {

    <#
        .SYNOPSIS
        Queries the SDDC type and updates $Script:vxRailMode accordingly.

        .DESCRIPTION
        Calls Get-SddcType against all connected vCenters and sets $Script:vxRailMode to $true when any
        vCenter reports "VCF-VxRail". Extracted as a shared helper so that both Connect-Vcenter and
        Test-VcentersConnection ensure the flag is accurate regardless of which code path established
        the vCenter connections.

        .EXAMPLE
        Set-VxRailMode
    #>

    $sddcType = Get-SddcType
    Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "SDDC Mode for `"$Global:SddcManagerFqdn`" identified as `"$sddcType`"."
    if ($sddcType -eq "VCF-VxRail") {
        $Script:vxRailMode = $true
        Write-LogMessage -Type DEBUG -Message "VxRail mode enabled (SDDC Type: $sddcType)."
    } else {
        $Script:vxRailMode = $false
        Write-LogMessage -Type DEBUG -Message "VxRail mode disabled (SDDC Type: $sddcType)."
    }
    $Script:vxRailModeDetected = $true
}
Function Wait-ComplianceCheckCompletion {

    <#
        .SYNOPSIS
        Polls a compliance check task until completion or timeout.

        .DESCRIPTION
        This function monitors a compliance check task by polling SDDC Manager at regular intervals.
        It displays progress updates, checks for timeout conditions, and validates task completion.
        The function returns the final task status and indicates whether a timeout occurred.
        Transient network errors are retried silently until the overall timeoutSeconds is reached.

        .PARAMETER ApiFailureLogIntervalCount
        Number of consecutive network failures between repeated WARNING log entries. The first failure is always logged.

        .PARAMETER HostCount
        Optional. For batched operations, the number of hosts in the batch. Used for display purposes.

        .PARAMETER PollingIntervalSeconds
        How often (in seconds) to check task status.
        Default: 5. Valid range: 1-300 seconds.

        .PARAMETER ResourceName
        The name of the resource being checked (cluster name or host FQDN). Used for logging and display.

        .PARAMETER ResourceType
        The type of resource: "Cluster", "Standalone Host", or "Standalone Host Batch".

        .PARAMETER TaskId
        The SDDC Manager task ID to monitor (returned from Invoke-VcfUpdateCluster or Invoke-VcfUpdateDomain).

        .PARAMETER TaskPollStallWarningSeconds
        Threshold in seconds between poll iterations that triggers a stall warning in the log. Default is 300.

        .PARAMETER TimeoutSeconds
        Maximum time (in seconds) to wait for task completion before timing out.
        Default: 7200 (2 hours). Valid range: 60-86400 seconds.

        .PARAMETER WorkloadDomainName
        The workload domain name containing the resource. Used for logging.

        .EXAMPLE
        $result = Wait-ComplianceCheckCompletion -TaskId "abc-123" -ResourceName "sfo-m01-cl01" -ResourceType "Cluster" -WorkloadDomainName "sfo-m01" -TimeoutSeconds 3600 -PollingIntervalSeconds 10
        if (-not $result.TimedOut) {
            Write-Host "Task completed with status: $($result.Status)"
        }

        .OUTPUTS
        PSCustomObject with properties:
        - Status: Final task status ("Successful", "Failed", "In Progress", etc.)
        - TimedOut: Boolean indicating if timeout occurred
        - TaskResponse: Full task response object from Invoke-VcfGetTask
    #>

    Param (
        [Parameter(Mandatory = $false)] [ValidateRange(1, 100)] [Int]$ApiFailureLogIntervalCount = 5,
        [Parameter(Mandatory = $false)] [Int]$hostCount = 0,
        [Parameter(Mandatory = $false)] [ValidateRange(1, 300)] [Int]$pollingIntervalSeconds = 5,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ResourceName,
        [Parameter(Mandatory = $true)] [ValidateSet("Cluster", "Standalone Host", "Standalone Host Batch")] [String]$ResourceType,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$TaskId,
        [Parameter(Mandatory = $false)] [ValidateRange(30, 3600)] [Int]$TaskPollStallWarningSeconds = 300,
        [Parameter(Mandatory = $false)] [ValidateRange(60, 86400)] [Int]$timeoutSeconds = 7200,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$WorkloadDomainName
    )

    Write-LogMessage -Type DEBUG -Message "Entered Wait-ComplianceCheckCompletion function for task ID: $TaskId"

    # Start timing the operation.
    $processTimer = Start-ProcessTimer
    $timedOut = $false
    $taskStatus = "Unknown"
    $consecutiveApiFailures = 0

    # Determine display message based on resource type.
    if ($ResourceType -eq "Standalone Host Batch") {
        $displayName = $ResourceName  # Already formatted as user-friendly batch name
        $operationName = "Batched compliance check for $hostCount host(s)"
        $activityMessage = "Batch compatibility check in progress"
        $logPrefix = "Batch compliance check in progress for $hostCount host(s)"
    } else {
        $displayName = "$ResourceType `"$ResourceName`""
        $operationName = "$ResourceType `"$ResourceName`" compliance check"
        $activityMessage = "Compatibility check in progress"
        $logPrefix = "Resource compatibility check in progress for $ResourceType `"$ResourceName`" in Workload Domain `"$WorkloadDomainName`""
    }

    # Poll until task completes or times out.
    Do {
        $preCheckTime = $([math]::Round(($processTimer.Elapsed.TotalSeconds), 0))

        # Check for timeout before the API call so persistent network failures cannot bypass this guard.
        if ($processTimer.Elapsed.TotalSeconds -gt $timeoutSeconds) {
            Write-LogMessage -Type ERROR -PrependNewLine -Message "Compliance check for $displayName exceeded timeout of $([math]::Round($timeoutSeconds / 60, 0)) minutes. Current status: $taskStatus"
            Write-Progress -Completed
            Stop-ProcessTimer -Timer $processTimer -Operation "$operationName (TIMEOUT)" -Interval "Minutes"
            $timedOut = $true
            break  # Exit the Do-While loop.
        }

        # Query task status with error handling (shared 404 mapping with transition poll loops).
        $taskFetch = Get-VcfTaskStateOrCompletedFromQueue -TaskId $TaskId
        if ($taskFetch.HadApiFailure) {
            $consecutiveApiFailures++
            if ($consecutiveApiFailures -eq 1 -or ($consecutiveApiFailures % $ApiFailureLogIntervalCount -eq 0)) {
                Write-LogMessage -Type WARNING -Message "Network error querying task $TaskId (consecutive failures: $consecutiveApiFailures) — retrying in $pollingIntervalSeconds second(s): $($taskFetch.ErrorRecord.Exception.Message)"
            }
            Start-Sleep -Seconds $pollingIntervalSeconds
            continue
        }
        if ($consecutiveApiFailures -gt 0) {
            Write-LogMessage -Type INFO -Message "SDDC Manager connection restored after $consecutiveApiFailures consecutive network error(s) for task $TaskId."
            $consecutiveApiFailures = 0
        }
        $taskResponse = $taskFetch.TaskResponse
        $taskStatus = $taskFetch.TaskStatus

        # Ensure access token has sufficient TTL before continuing.
        Test-SddcManagerConnection

        # Display progress to user.
        Write-Progress -Activity $activityMessage -Status "$([math]::Round(($processTimer.Elapsed.TotalSeconds), 0)) seconds elapsed (updates every $pollingIntervalSeconds seconds)."
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "$logPrefix - $([math]::Round(($processTimer.Elapsed.TotalSeconds), 0)) seconds elapsed."
        Start-Sleep -Seconds $pollingIntervalSeconds

        # Check for unusual delay between polls (may indicate system issues).
        $postCheckTime = $([math]::Round(($processTimer.Elapsed.TotalSeconds), 0))
        if (([int]$preCheckTime + $TaskPollStallWarningSeconds) -lt ([int]$postCheckTime)) {
            Write-LogMessage -Type WARNING -SuppressOutputToScreen -Message "More than $TaskPollStallWarningSeconds seconds have elapsed between task progress checks. This is unusual."
        }

    } While ($taskStatus -eq 'In Progress' -or $taskStatus -eq 'Unknown')

    # Clean up progress display.
    Write-Progress -Completed

    # Stop timer and log completion.
    if (-not $timedOut) {
        Stop-ProcessTimer -Timer $processTimer -Operation $operationName -Interval "Minutes"
        # Short sleep before proceeding to catch state transition edge cases.
        Start-Sleep -Seconds 3
    }

    # Retrieve final task response.
    try {
        $taskResponse = Invoke-VcfGetTask -Id $TaskId -ErrorAction Stop
    } catch {
        if ($_.Exception.Message -match "NOT_FOUND|404|does not exist") {
            Write-LogMessage -Type DEBUG -Message "Final task query: Task $TaskId not found (completed and removed)"
            # Create minimal response object for completed task
            $taskResponse = [PSCustomObject]@{
                Status = "SUCCESSFUL"
                Id = $TaskId
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Failed to retrieve final task status: $($_.Exception.Message)"
            # Create error response object
            $taskResponse = [PSCustomObject]@{
                Status = "UNKNOWN"
                Id = $TaskId
            }
        }
    }

    # Return result object.
    return [PSCustomObject]@{
        Status = $taskResponse.Status
        TimedOut = $timedOut
        TaskResponse = $taskResponse
    }
}
Function Invoke-BatchedComplianceCheck {

    <#
        .SYNOPSIS
        Executes a batched compliance check for multiple standalone hosts.

        .DESCRIPTION
        This function processes multiple standalone hosts in a single API call to SDDC Manager,
        improving efficiency when checking compliance for multiple hosts in the same workload domain
        with the same image or all using image seeding. The function validates each host, creates
        resource specifications, executes the batched compliance check, and displays results.

        .PARAMETER BatchHosts
        Array of host objects to process in this batch. Each object should contain ResourceId,
        ResourceName, WorkloadDomainId, and WorkloadDomainName properties.

        .PARAMETER BatchKey
        Internal batch identifier used for grouping (format: "Domain_<id>_Image_<name>" or "Domain_<id>_ImageSeeding").

        .PARAMETER ImageName
        Optional. The name of the SDDC Manager image to check against. Required if not using image seeding.

        .PARAMETER Personalities
        The personalities object retrieved from SDDC Manager (contains image definitions).
        Used to look up the image ID from the image name.

        .PARAMETER TimeoutSeconds
        Maximum time (in seconds) to wait for batch completion before timing out.
        Default: 7200 (2 hours). Valid range: 60-86400 seconds.

        .PARAMETER PollingIntervalSeconds
        How often (in seconds) to check batch status during polling.
        Default: 5. Valid range: 1-300 seconds.

        .PARAMETER Parallel
        When specified, skips polling and returns immediately after starting the batch.
        Use -CheckTaskStatus to monitor progress later.

        .PARAMETER Silence
        Suppresses console output (logs only). Automatically enabled when using -Parallel.

        .EXAMPLE
        Invoke-BatchedComplianceCheck -BatchHosts $hostArray -BatchKey "Domain_abc123_ImageSeeding" -Personalities $personalities -TimeoutSeconds 3600

        .EXAMPLE
        Invoke-BatchedComplianceCheck -BatchHosts $hostArray -BatchKey "Domain_abc123_Image_esx803" -ImageName "esx-803-vendor" -Personalities $personalities -Parallel

        .OUTPUTS
        Boolean
        Returns $true if the batch was processed successfully (or skipped due to validation), $false if a critical error occurred.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [Array]$batchHosts,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$batchKey,
        [Parameter(Mandatory = $false)] [String]$imageName,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [Object]$personalities,
        [Parameter(Mandatory = $false)] [ValidateRange(60, 86400)] [Int]$timeoutSeconds = 7200,
        [Parameter(Mandatory = $false)] [ValidateRange(1, 300)] [Int]$pollingIntervalSeconds = 5,
        [Parameter(Mandatory = $false)] [Switch]$Parallel,
        [Parameter(Mandatory = $false)] [Switch]$Silence
    )

    Write-LogMessage -Type DEBUG -Message "Entered Invoke-BatchedComplianceCheck function for batch key: $batchKey"

    $hostCount = $batchHosts.Count

    # Determine if this batch uses image seeding or explicit image.
    # Infer from batch key to handle cases where ImageSeedingWorkflow may not be set correctly.
    $firstHost = $batchHosts[0]
    $WorkloadDomainName = $firstHost.WorkloadDomainName
    $batchUsesImageSeeding = $batchKey -match "_ImageSeeding"

    # Get image name if not using image seeding.
    if (-not $batchUsesImageSeeding) {
        $batchImageName = $imageName
        if ([string]::IsNullOrEmpty($batchImageName)) {
            Write-LogMessage -Type ERROR -Message "No image name provided for batch in workload domain `"$WorkloadDomainName`". Skipping batch."
            return $true  # Return true to indicate batch was handled (skipped).
        }
    }

    # Create user-friendly batch display name.
    if ($batchUsesImageSeeding) {
        $batchDisplayName = "Workload Domain `"$WorkloadDomainName`" with Image Seeding"
    } else {
        $batchDisplayName = "Workload Domain `"$WorkloadDomainName`" with Image `"$batchImageName`""
    }

    Write-LogMessage -Type INFO -PrependNewLine -Message "Processing batch: $batchDisplayName ($hostCount standalone host(s))..."

    # Get imageId if not using image seeding.
    if (-not $batchUsesImageSeeding) {
        $matchedPersonality = if ($personalities -and $personalities.PSObject.Properties['Elements'] -and $personalities.Elements) { $personalities.Elements | Where-Object -Property PersonalityName -eq $batchImageName | Select-Object -First 1 } else { $null }
        $imageId = if ($matchedPersonality) { $matchedPersonality.PersonalityId } else { $null }
        if (-not $imageId) {
            Write-LogMessage -Type ERROR -Message "Image `"$batchImageName`" not found for batch. Skipping $batchDisplayName."
            return $true  # Return true to indicate batch was handled (skipped).
        }
    }

    # Validate all hosts in batch and create resource specs.
    $validatedHosts = @()
    $TransitionResourceSpecs = New-Object System.Collections.Generic.List[object]

    foreach ($hostResource in $batchHosts) {
        $resourceId = $hostResource.ResourceId
        $ResourceName = $hostResource.ResourceName
        $hostWorkloadDomainName = $hostResource.WorkloadDomainName

        # Validate host status.
        $hostQueryResult2 = Invoke-VcfGetHosts -Fqdn $ResourceName -IsStandalone $true -ErrorAction SilentlyContinue
        $hostQueryResult = if ($hostQueryResult2 -and $hostQueryResult2.PSObject.Properties['Elements']) { $hostQueryResult2.Elements | Select-Object -First 1 } else { $null }
        $standAloneHostConfigurationStatus = if ($hostQueryResult) { $hostQueryResult.ConfigurationStatus } else { $null }
        if ($standAloneHostConfigurationStatus -notin @("ACTIVE", "ASSIGNED")) {
            if (-not $standAloneHostConfigurationStatus) {
                $standAloneHostConfigurationStatus = "<UNKNOWN>"
            }
            Write-LogMessage -Type WARNING -Message "Host `"$ResourceName`" has status `"$standAloneHostConfigurationStatus`". Excluding from batch."
            continue
        }

        # Check for duplicate tasks (suppress verbose warnings for batch processing).
        $duplicateTask = Find-ExistingTask -ClusterTaskType "VLCM_COMPLIANCE_CHECK" -Operation "compliance check" -ResourceId $resourceId -ResourceName $ResourceName -ResourceType "Standalone Host" -WorkloadDomainName $hostWorkloadDomainName -StandAloneHostTaskType "DOMAIN_VLCM_COMPLIANCE_CHECK" -SuppressVerboseWarning
        if ($duplicateTask) {
            Write-LogMessage -Type WARNING -Message "Host `"$ResourceName`" has duplicate compliance check task. Excluding from batch."
            continue
        }

        # Host passed validation - create resource spec and add to batch.
        $TransitionResourceSpec = Initialize-VcfTransitionResourceSpec -Id $resourceId -Type "HOST" -ErrorAction SilentlyContinue
        $TransitionResourceSpecs.Add($TransitionResourceSpec)
        $validatedHosts += $hostResource
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Host `"$ResourceName`" validated and added to batch."
    }

    # Check if we have any validated hosts to process.
    if ($validatedHosts.Count -eq 0) {
        Write-LogMessage -Type WARNING -Message "All hosts in batch were excluded during validation (already processing, inactive status, or other issues). Skipping $batchDisplayName."
        return $true  # Return true to indicate batch was handled (skipped).
    }

    Write-LogMessage -Type DEBUG -Message "Batch contains $($validatedHosts.Count) validated host(s) out of $hostCount total."

    # Create the image compliance check spec with multiple resources.
    if ($batchUsesImageSeeding) {
        $imageComplianceCheckSpec = Initialize-VcfImageComplianceCheckSpec -Resources $TransitionResourceSpecs -ErrorAction SilentlyContinue
    } else {
        $imageComplianceCheckSpec = Initialize-VcfImageComplianceCheckSpec -ImageId $imageId -Resources $TransitionResourceSpecs -ErrorAction SilentlyContinue
    }

    # Use first validated host's workload domain for the API call.
    $workloadDomainId = $validatedHosts[0].WorkloadDomainId
    $WorkloadDomainName = $validatedHosts[0].WorkloadDomainName

    $domainUpdateSpec = Initialize-VcfDomainUpdateSpec -ImageComplianceCheckSpec $imageComplianceCheckSpec -ErrorAction SilentlyContinue

    # Execute the batched compliance check.
    try {
        $response = Invoke-VcfUpdateDomain -Id $workloadDomainId -DomainUpdateSpec $domainUpdateSpec -ErrorAction Stop

        # Check for invalid response type
        if ($response -match "VMware.Bindings.Vcf.SddcManager.Model.Personality") {
            throw "Invalid response type received: Personality object instead of Task"
        }

        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Batched compliance check initiated for $($validatedHosts.Count) host(s) with Task ID: `"$($response.Id)`"."
    } catch {
        Write-LogMessage -Type ERROR -PrependNewLine -AppendNewLine -Message "Batched compliance check failed for $batchDisplayName."
        $taskErrorsMessage = $_.Exception.Message -replace "^.*`"message`":`"" -replace "`"\}"
        Write-LogMessage -Type ERROR -AppendNewLine -Message "Error Message: $taskErrorsMessage"
        return $false  # Return false to indicate critical error.
    }

    # Log success.
    $hostNames = ($validatedHosts | ForEach-Object { $_.ResourceName }) -join ", "
    if ($batchUsesImageSeeding) {
        Write-LogMessage -Type INFO -Message "Auto-generating vLCM images and checking compliance for $($validatedHosts.Count) host(s): $hostNames"
    } else {
        Write-LogMessage -Type INFO -Message "Checking compliance for $($validatedHosts.Count) host(s) against image `"$batchImageName`": $hostNames"
    }

    # Skip polling if in parallel mode.
    if ($Parallel) {
        Start-Sleep -Seconds 2
        return $true
    }

    # Parallel or Silence flag will disable polling for task to complete.
    if (-not $Parallel -and -not $Silence) {

        # Poll for batch completion using the centralized function.
        $waitResult = Wait-ComplianceCheckCompletion `
            -TaskId $response.Id `
            -ResourceName $batchDisplayName `
            -ResourceType "Standalone Host Batch" `
            -WorkloadDomainName $WorkloadDomainName `
            -TimeoutSeconds $timeoutSeconds `
            -PollingIntervalSeconds $pollingIntervalSeconds `
            -HostCount $validatedHosts.Count

        # Skip to next batch if timeout occurred.
        if ($waitResult.TimedOut) {
            return $true  # Return true to continue processing other batches.
        }

        # Validate task completion and display results.
        $taskResult = Test-TaskStatus -Response $waitResult.TaskResponse -ResourceType "Standalone Host Batch" -ResourceName $batchDisplayName -WorkloadDomainName $WorkloadDomainName

        if ($taskResult -ne "Failed") {
            # Display results for each host in the batch.
            foreach ($hostResource in $validatedHosts) {
                Show-ImageComplianceCheckResults -ResourceName $hostResource.ResourceName -ResourceType "Standalone Host" -WorkloadDomainName $hostResource.WorkloadDomainName
            }
        }
    }

    return $true  # Return true to indicate successful batch processing.
}
Function Invoke-ImageComplianceCheck {

    <#
        .SYNOPSIS
        The function Invoke-ImageComplianceCheck starts a compliance check of a cluster/standalone-host against a specific vLCM image.

        .DESCRIPTION
        The function ensure that the compliance check runs to completion before calling Show-ImageComplianceCheckResults to display
        the results to the user.

        .EXAMPLE
        Invoke-ImageComplianceCheck -ResourceName m01-cl01 -ResourceType StandaloneHost -WorkloadDomainName m01 -SddcManagerImageName esx-803-vendor

        .EXAMPLE
        Invoke-ImageComplianceCheck -JsonInputFile Clusters.json

        .EXAMPLE
        Invoke-ImageComplianceCheck -JsonInputFile Clusters.json -Parallel

        .EXAMPLE
        Invoke-ImageComplianceCheck -ResourceName m01-cl01 -ResourceType Cluster -WorkloadDomainName m01 -SddcManagerImageName esx-803-vendor -TimeoutSeconds 3600 -PollingIntervalSeconds 10

        .EXAMPLE
        Invoke-ImageComplianceCheck -JsonInputFile Clusters.json -BatchStandaloneHosts $false

        .EXAMPLE
        Invoke-ImageComplianceCheck -JsonInputFile Clusters.json -MaxBatchSize 10

        .PARAMETER BatchStandaloneHosts
        Batches standalone hosts within the same workload domain and using the same image (or all using image seeding) into a single API call.
        This can significantly improve performance when checking multiple standalone hosts.
        Batches are automatically split based on MaxBatchSize (default 25 hosts per batch).
        Note: Batches cannot span workload domain boundaries.
        Default is enabled ($true). To disable batching, use -BatchStandaloneHosts $false.

        .PARAMETER JsonInputFile
        Specifies the json input file that contains at least one set of cluster names, workload domains, and an image.
        JsonInputFile and ClusterName/WorkloadDomainName/SddcManagerImageName are mutually exclusive.

        .PARAMETER MaxBatchSize
        Specifies the maximum number of standalone hosts to include in a single batch.
        API limitation requires this to be 25 or fewer. Defaults to 25.

        .PARAMETER Parallel
        Specifies if the compliance checks should be parallelized.  If not specified, defaults to serial.

        .PARAMETER PollingIntervalSeconds
        Specifies the polling interval in seconds for checking compliance check status. Defaults to 5 seconds.

        .PARAMETER ResourceName
        Specifies cluster/standalone host to run a compatibility check against.

        .PARAMETER ResourceType
        Specifies the resource type to run the compatibility check against: Cluster or StandaloneHost.  Defaults to Cluster.

        .PARAMETER SddcManagerImageName
        Specifies which image the cluster should be checked against.

        .PARAMETER Silence
        Specifies if progress polling should be suppressed (useful for automation/background processing).

        .PARAMETER TimeoutSeconds
        Specifies the timeout in seconds for compliance check polling. Defaults to 7200 seconds (2 hours).

        .PARAMETER WorkloadDomainName
        Specifies which workload domain the cluster belongs to.

        .OUTPUTS
        None
        This function does not return a value. It performs compliance checks and displays results.
    #>

    Param (
        [Parameter(Mandatory = $false)] [Bool]$batchStandaloneHosts = $true,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$JsonInputFile,
        [Parameter(Mandatory = $false)] [ValidateRange(1, 25)] [Int]$maxBatchSize = 25,
        [Parameter(Mandatory = $false)] [Switch]$Parallel,
        [Parameter(Mandatory = $false)] [ValidateRange(1, 300)] [Int]$pollingIntervalSeconds = 5,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$ResourceName,
        [Parameter(Mandatory = $false)] [ValidateSet("Cluster","Standalone Host")] [String]$ResourceType,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$SddcManagerImageName,
        [Parameter(Mandatory = $false)] [Switch]$Silence,
        [Parameter(Mandatory = $false)] [ValidateRange(60, 86400)] [Int]$timeoutSeconds = 7200,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$WorkloadDomainName
    )

    Write-LogMessage -Type DEBUG -Message "Entered Invoke-ImageComplianceCheck function..."

    # ============================================================================
    # SECTION 1: CONNECTION VALIDATION
    # ============================================================================
    # Verify connections to both SDDC Manager and vCenter(s) before proceeding.
    # These are prerequisites for all compliance check operations.

    Test-SddcManagerConnection
    # Return early if the user cancels or vCenter connection fails.
    $vCenterConnected = Test-VcentersConnection
    if (-not $vCenterConnected) {
        return
    }

    # ============================================================================
    # SECTION 2: PARAMETER RESOLUTION
    # ============================================================================
    # This section handles three input modes:
    # 1. Interactive Mode (headless = disabled): User selects resources and images from menus
    # 2. JSON Input Mode: Resources defined in JSON file
    # 3. Command-line Mode: Resources specified via parameters
    #
    # Output: $ResourceNameInputs array containing resource details for processing
    # ============================================================================

    # --- INTERACTIVE MODE: Resource Selection ---
    # Display baseline-managed resources and prompt user to select one or more by ID.
    if (-not $Script:Headless) {
        Write-LogMessage -Type INFO -AppendNewLine -Message "Scanning for vLCM baseline (VUM) managed clusters/standalone-hosts..."
        $processTimer = Start-ProcessTimer
        $resourceListOutput = Get-BaselineManagedResources
        Stop-ProcessTimer -Timer $processTimer -Operation "Scan for vLCM baseline (VUM) managed clusters/standalone hosts" -Interval "Seconds"
        Write-Host $resourceListOutput
        Write-Host "`nSelect the vLCM baseline cluster(s)/standalone-host(s) to check for compliance with vLCM image management.`n"

        # Interactive resource selection loop (repeat until valid selection made).
        $selectedResourceDetails = @()
        Do {
            $idSelection = Read-Host "Enter an id, a comma-delimited list of ids, or 'c' to cancel"
            # fail fast in canceled.
            if ($idSelection -eq 'c') {
                Write-LogMessage -Type INFO -PrependNewLine -Message "Cancellation requested. Returning to main menu."
                Show-AnyKey
                break
            }
            # Check if the Id selection is non-null.
            if ($idSelection) {
                $processTimer = Start-ProcessTimer
                $selectedResourceDetails = @(Get-BaselineManagedResources -IdSelection $idSelection)
                Stop-ProcessTimer -Timer $processTimer -Operation "Image seeding support check in compliance check workflow complete" -Interval "Milliseconds"
            }
            # If no resources were returned then no Id / ResourceId mapping was found.
            if ($selectedResourceDetails.Count -eq 0) {
                if ($idSelection -eq "") {
                    $idSelection = "<EMPTY>"
                }
                Write-LogMessage -Type ERROR -Message "Invalid id $idSelection chosen. Please try again."
            }
        } while ($selectedResourceDetails.Count -eq 0)

        if ($selectedResourceDetails.Count -eq 0) {
            Show-MainMenu
            return
        }

        # --- INTERACTIVE MODE: Image Seeding Eligibility Check ---
        # Image seeding allows auto-generation of vLCM images from baseline configurations.
        # Requires all selected resources and their vCenters to be at version 8.0.3 or later.
        Write-LogMessage -Type INFO -PrependNewLine -Message "Checking for image seeding support..."

        # Check if all selected resources support image seeding (ESXi 8.0.3+ and vCenter 8.0.3+).
        $hostSeedIneligible = $false
        foreach ($resource in $selectedResourceDetails) {
            if ($resource.ImageSeedingSupport -eq "UNAVAILABLE") {
                $hostSeedIneligible = $true
            }
        }

        # --- INTERACTIVE MODE: VxRail vs. Standard Mode Handling ---
        # VxRail systems require image seeding (no manual image selection allowed).
        # Standard VCF allows choice between image seeding or manual image selection.
        if ($Script:vxRailMode) {
            if ($hostSeedIneligible) {
                Write-LogMessage -Type ERROR -Message "VxRail only supports vLCM baseline to vLCM image transitions through image seeding which requires all clusters and vCenters be upgraded to 8.0.3 or later."
                Show-AnyKey
                continue
            } else {
                $imageSeedingWorkflow = $true
            }
        } else {
            $imageSeedingSelection = -1
            if (-not $hostSeedIneligible) {
                Write-Output ""
                $imageSeedingSelection = New-ChoiceMenu -Question "All selected clusters and standalone-hosts are eligible for image seeding.  Would you like to auto-generate vLCM images for them using image seeding?" -DefaultAnswer yes
            } else {
                $imageSeedingWorkflow = $false
            }

            Write-Output ""
            # Check first if the user answered yes (option 0, the default) they want to proceed.
            if ($imageSeedingSelection -eq 0) {
                Write-LogMessage -Type INFO -Message "Image seeding workflow selected."
                $imageSeedingWorkflow = $true
            } else {
                $imageSeedingWorkflow = $false
            }
        }

        # --- INTERACTIVE MODE: Manual Image Selection ---
        # If image seeding is not used, prompt user to select an image from SDDC Manager's repository.
        # This section is skipped if $imageSeedingWorkflow is true.
        if (-not $imageSeedingWorkflow) {
                Get-SddcManagerImages -ShowId

        # Interactive image selection loop (repeat until valid selection made).
        Do {
            Write-Output ""
            $idSelection = Read-Host "Please enter the id of an image or press 'c' to cancel"
            # fail fast in canceled.
            if ($idSelection -eq 'c') {
                Write-LogMessage -Type INFO -PrependNewLine -Message "Cancellation requested. Returning to main menu."
                Show-AnyKey
                break
            }
            # Check if the Id selection is non-null.
            if ($idSelection) {
                $SddcManagerImageName = Get-SddcManagerImages -IdSelection $idSelection
            }
            # If ClusterName is null then no Id / ClusterName mapping was found.
            if ($SddcManagerImageName -eq "ERROR_INVALID_SELECTION") {
                if ($idSelection -eq "") {
                    $idSelection = "<EMPTY>"
                }
                Write-LogMessage -Type ERROR -Message "Invalid Id $idSelection chosen. Please try again."
            }
        } while (($SddcManagerImageName -eq "ERROR_INVALID_SELECTION"))

        if ([String]::IsNullOrEmpty($SddcManagerImageName)) {
            Show-MainMenu
            return
        }
        }
    } else {
        # --- HEADLESS MODE: JSON or Command-line Parameters ---
        # Process input from either JSON file or command-line parameters.
        # Both are normalized into $ResourceNameInputs array for unified processing.
        if ($JsonInputFile) {
            $result = ConvertFrom-JsonSafely -JsonFilePath $JsonInputFile -VariableName "ResourceNameInputs"
            if (-not $result.Success) {
                Write-LogMessage -Type ERROR -Message "Failed to load JSON input file: $($result.ErrorMessage)"
                Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR
            }
            $ResourceNameInputs = $result.JsonData
        }  else {
            # Turn the commandline parameter data into an array so the user-inputted data, either.
            # in parameter form or json, can be validated in the same way.

            $ResourceNameInputs = [pscustomobject]@{
                SddcManagerImageName = $SddcManagerImageName
                WorkloadDomainName = $WorkloadDomainName
                ResourceName = $ResourceName
                ResourceType = $ResourceType
            }
        }

        # --- HEADLESS MODE: Parameter Validation and Resource Resolution ---
        # Validate each resource entry and resolve IDs from names.
        # Also check image seeding eligibility for each resource.
        $selectedResourceDetails = @()

        foreach ($line in $ResourceNameInputs) {
            # Derive a workload domain Id from the workload domain name.
            $domainResult = Get-WorkloadDomainId -WorkloadDomainName $line.WorkloadDomainName
            if (-not $domainResult.Success) {
                Write-LogMessage -Type ERROR -Message $domainResult.ErrorMessage
                Exit-WithCode -ExitCode $Script:ExitCodes.RESOURCE_NOT_FOUND
            }
            $workloadDomainId = $domainResult.WorkloadDomainId

            $resourceResult = Get-ResourceId -ResourceType $line.ResourceType -ResourceName $line.ResourceName -WorkloadDomainName $line.WorkloadDomainName
            if (-not $resourceResult.Success) {
                Write-LogMessage -Type ERROR -Message $resourceResult.ErrorMessage
                Exit-WithCode -ExitCode $Script:ExitCodes.RESOURCE_NOT_FOUND
            }
            $resourceId = $resourceResult.ResourceId

            # Check to see if the resource is already image managed (and thus not eligible for this workflow).
            $isImageManaged = $null
            switch ($ResourceType) {
                "Cluster" {
                    $imageManagedClustersResult = Invoke-VcfGetClusters -IsImageBased $true -ErrorAction SilentlyContinue
                    $isImageManaged = if ($imageManagedClustersResult -and $imageManagedClustersResult.PSObject.Properties['Elements']) { $imageManagedClustersResult.Elements | Where-Object Id -eq $resourceId | Select-Object -First 1 } else { $null }
                }
                "Standalone Host" {
                    $imageManagedHostsResult = Invoke-VcfGetHosts -isStandalone $true -isLifeCycleManaged $true -ErrorAction SilentlyContinue
                    $isImageManaged = if ($imageManagedHostsResult -and $imageManagedHostsResult.PSObject.Properties['Elements']) { $imageManagedHostsResult.Elements | Where-Object Id -eq $resourceId | Select-Object -First 1 } else { $null }
                }
            }

            if ($isImageManaged) {
                Write-LogMessage -Type ERROR -Message "$($line.ResourceType) `"$($line.ResourceName)`" in `"$($line.WorkloadDomainName)`" is already vLCM Image managed. Skipping."
                continue
            }

            $lineSddcManagerImageName = if ($line.PSObject.Properties['SddcManagerImageName']) { $line.SddcManagerImageName } else { $null }

            if ($Script:vxRailMode) {
                if ($lineSddcManagerImageName) {
                    Write-LogMessage -Type ERROR -Message "VxRail only supports vLCM baseline to vLCM image transitions through image seeding."
                    Write-LogMessage -Type INFO -Message "Please remove the SddcManagerImageName parameter(s) from your JSON input file to utilize image seeding."
                    return
                }
            }

            if ($Script:Headless) {
                # if image name is not specified, image seeding workflow is invoked.
                if ([String]::IsNullOrEmpty($lineSddcManagerImageName)) {
                    # Reuse $workloadDomainId from line 4465 - already retrieved above.
                    $domainResult = Invoke-VcfGetDomain -id $workloadDomainId -ErrorAction SilentlyContinue
                    $vcenterId = if ($domainResult -and $domainResult.Vcenters) { ($domainResult.Vcenters | Select-Object -First 1).Id } else { $null }
                    # ESX and vCenter both have to be at the required version to support image seeding.
                    $vcenterImageSeedingSupported = Get-VcenterImageSeedingSupport -MinimumVcenterVersion $clusterVsphereImageSeedingSupport -VcenterId $vcenterId
                    if ($line.ResourceType -eq "Cluster") {
                        $esxImageSeedingSupported = Get-EsxImageSeedingSupport -ClusterId $resourceId -MinimumEsxVersion $clusterVsphereImageSeedingSupport
                    } else {
                        # For standalone hosts, we already have the ESX version.
                        $esxVersion = (Invoke-VcfGetHost -Id $resourceId -ErrorAction SilentlyContinue).EsxiVersion
                        $esxImageSeedingSupported = Get-EsxImageSeedingSupport -EsxVersion $esxVersion -MinimumEsxVersion $standAloneHostVsphereImageSeedingSupport
                    }

                    if ($vcenterImageSeedingSupported -and $esxImageSeedingSupported) {
                        $imageSeedingWorkflow = $true
                        if (-not $Script:vxRailMode) {
                            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "No SDDC Manager image named specified for `"$($line.ResourceName)`" and `"$($line.WorkloadDomainName)`", but image seeding is supported."
                        }
                    } else {
                        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "No SDDC Manager image named specified in JSON stanza including `"$($line.ResourceName)`" and `"$($line.WorkloadDomainName)`", and image seeding is not supported."
                        if ($Script:vxRailMode) {
                            Write-LogMessage -Type ERROR -Message "$($line.ResourceType) `"$($line.ResourceName)`": please upgrade your sBOM to support image seeding. Skipping."
                        } else {
                            Write-LogMessage -Type ERROR -Message "$($line.ResourceType) `"$($line.ResourceName)`": please upgrade your sBOM to support image seeding or assign a SddcManagerImageName. Skipping."
                        }
                        continue
                    }
                } else {
                    # SddcManagerImageName found in array.
                    $imageSeedingWorkflow = $false
                }
            }

            # If we haven't entered the image seeding workflow, check to make sure the image is correct.
            if (-not $imageSeedingWorkflow) {
                # Verify image name exists in SDDC Manager.
                $personalitiesVerifyResult = Invoke-VcfGetPersonalities -ErrorAction SilentlyContinue
                $response = if ($personalitiesVerifyResult -and $personalitiesVerifyResult.PSObject.Properties['Elements']) { $personalitiesVerifyResult.Elements | Where-Object PersonalityName -eq $lineSddcManagerImageName | Select-Object -First 1 } else { $null }
                if (-not $response) {
                    Write-LogMessage -Type ERROR -Message "Image name `"$lineSddcManagerImageName`" not found in SDDC Manager. Skipping $($line.ResourceType) `"$($line.ResourceName)`"."
                    continue
                }
            }

            $selectedResourceDetails += [pscustomobject]@{
                'ResourceId'           = $resourceId
                'ResourceName'         = $($line.ResourceName)
                'ResourceType'         = $($line.ResourceType)
                'WorkloadDomainId'     = $workloadDomainId
                'WorkloadDomainName'   = $($line.WorkloadDomainName)
                'SddcManagerImageName' = $lineSddcManagerImageName
                'ImageSeedingWorkflow' = $imageSeedingWorkflow
            }
        }
    }

    # Begin common processing mode for headless and interactive mode.
    # Cache personalities once for all resources to avoid redundant API calls.
    $personalities = Invoke-VcfGetPersonalities -ErrorAction SilentlyContinue

    # When batching is enabled, group standalone hosts by image before processing
    # Maintains FIFO (First In, First Out) order from $selectedResourceDetails
    # ============================================================================
    # SECTION 3: BATCH PREPARATION (Optional)
    # ============================================================================
    # If batching is enabled, group standalone hosts with matching workload domains
    # and images into batches (up to 25 hosts per batch per API limitation).
    # Clusters are always processed individually, never batched.
    # ============================================================================

    if ($batchStandaloneHosts) {
        Write-LogMessage -Type DEBUG -Message "Standalone host batching enabled - hosts with same image will be processed together."

        # Build resources to process in FIFO order from $selectedResourceDetails
        $resourcesToProcess = @()
        $hostBatchGroups = @{}
        $batchKeysInOrder = @()  # Track first occurrence order of each batch key

        foreach ($resource in $selectedResourceDetails) {
            if ($resource.ResourceType -eq "Cluster") {
                # Clusters are processed individually - add directly in order
                $resourcesToProcess += $resource
            } else {
                # Standalone hosts - group by BOTH workload domain AND image/seeding
                # Batches cannot span workload domain boundaries

                # In interactive mode, use global variables; in headless mode, use resource properties
                if ($Script:Headless) {
                    $resourceImageSeeding = $resource.ImageSeedingWorkflow
                    $resourceImageName = $resource.SddcManagerImageName
                } else {
                    # Interactive mode uses globally selected values for all resources
                    $resourceImageSeeding = $imageSeedingWorkflow
                    $resourceImageName = $SddcManagerImageName
                }

                if ($resourceImageSeeding) {
                    $batchKey = "Domain_$($resource.WorkloadDomainId)_ImageSeeding"
                } elseif ([string]::IsNullOrEmpty($resourceImageName)) {
                    # Fallback: if no image name provided, treat as image seeding
                    Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Host `"$($resource.ResourceName)`" has no image name specified. Treating as image seeding workflow."
                    $batchKey = "Domain_$($resource.WorkloadDomainId)_ImageSeeding"
                } else {
                    $batchKey = "Domain_$($resource.WorkloadDomainId)_Image_$resourceImageName"
                }

                # Track first occurrence of this batch key to maintain FIFO order
                if (-not $hostBatchGroups.ContainsKey($batchKey)) {
                    $hostBatchGroups[$batchKey] = @()
                    $batchKeysInOrder += $batchKey  # Remember the order we first saw this key
                }
                $hostBatchGroups[$batchKey] += $resource
            }
        }

        # Add batched standalone hosts in the order their first host was encountered (FIFO)
        # Split batches larger than maxBatchSize (API limitation)
        foreach ($batchKey in $batchKeysInOrder) {
            $hostsInGroup = $hostBatchGroups[$batchKey]
            $totalHosts = $hostsInGroup.Count

            if ($totalHosts -le $maxBatchSize) {
                # Single batch - fits within limit
                $resourcesToProcess += [PSCustomObject]@{
                    IsBatch = $true
                    BatchKey = $batchKey
                    BatchHosts = $hostsInGroup
                    ResourceType = "Standalone Host Batch"
                }
            } else {
                # Multiple batches needed - split into chunks of 25
                $batchNumber = 1
                for ($i = 0; $i -lt $totalHosts; $i += $maxBatchSize) {
                    $batchChunk = $hostsInGroup[$i..[Math]::Min($i + $maxBatchSize - 1, $totalHosts - 1)]
                    $resourcesToProcess += [PSCustomObject]@{
                        IsBatch = $true
                        BatchKey = "${batchKey}_Part${batchNumber}"
                        BatchHosts = $batchChunk
                        ResourceType = "Standalone Host Batch"
                    }
                    Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Split '$batchKey' into batch part $batchNumber with $($batchChunk.Count) host(s) (max 25 per batch)."
                    $batchNumber++
                }
            }
        }
    } else {
        # Non-batching mode - process all resources individually in original FIFO order
        $resourcesToProcess = $selectedResourceDetails
    }

    # ============================================================================
    # SECTION 4: MAIN EXECUTION LOOP
    # ============================================================================
    # Process each resource (or batch of resources) for compliance checking.
    # Flow:
    # 1. If batched standalone hosts → Call Invoke-BatchedComplianceCheck
    # 2. If individual resource → Process sequentially or in parallel based on -Parallel flag
    # ============================================================================

    foreach($selectedResource in $resourcesToProcess) {
        # --- BATCH PROCESSING PATH ---
        # Batched standalone hosts use the extracted helper function
        if ($selectedResource.PSObject.Properties['IsBatch'] -and $selectedResource.IsBatch) {
            # Process batched standalone hosts
            $batchHosts = $selectedResource.BatchHosts
            $batchKey = $selectedResource.BatchKey

            # Refresh token before batch processing.
            Test-SddcManagerConnection

            # Determine image name for the batch.
            $batchImageName = $null
            if ($batchKey -notmatch "_ImageSeeding") {
                # In interactive mode, use global variable; in headless mode, use first host's property.
                if ($Script:Headless) {
                    $batchImageName = $batchHosts[0].SddcManagerImageName
                } else {
                    $batchImageName = $SddcManagerImageName
                }
            }

            # Call the extracted batch processing function.
            $null = Invoke-BatchedComplianceCheck `
                -BatchHosts $batchHosts `
                -BatchKey $batchKey `
                -ImageName $batchImageName `
                -Personalities $personalities `
                -TimeoutSeconds $timeoutSeconds `
                -PollingIntervalSeconds $pollingIntervalSeconds `
                -Parallel:$Parallel `
                -Silence:$Silence

            # Continue to next resource (batch function handles all logic internally).
            continue
        }

        # --- INDIVIDUAL RESOURCE PROCESSING PATH ---
        # Process clusters or standalone hosts one at a time.
        # Includes validation, duplicate check, API call, and optional polling.
        $resourceId = $selectedResource.ResourceId
        $ResourceName = $selectedResource.ResourceName
        $ResourceType = $selectedResource.ResourceType
        $workloadDomainId = $selectedResource.WorkloadDomainId
        $WorkloadDomainName = $selectedResource.WorkloadDomainName
        if ($Script:Headless) {
            $imageSeedingWorkflow = $selectedResource.ImageSeedingWorkflow
            if (-not $imageSeedingWorkflow) {
                $SddcManagerImageName = $selectedResource.SddcManagerImageName
            }
        }

        # Validate cluster health from SDDC Manager standpoint.

        if ($ResourceType -eq "Cluster") {
            $clusterResult = Invoke-VcfGetCluster -Id $resourceId -ErrorAction SilentlyContinue
            $clusterStatus = if ($clusterResult) { $clusterResult.Status } else { $null }

            if (-not $clusterStatus) {
                Write-LogMessage -Type ERROR -Message "$ResourceType `"$ResourceName`" could not be retrieved from SDDC Manager. Skipping."
                continue
            }
            if ($clusterStatus -ne "ACTIVE") {
                Write-LogMessage -Type ERROR -Message "$ResourceType `"$ResourceName`" has status `"$clusterStatus`" and the workflow cannot proceed."
                continue
            } else {
                Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "$ResourceType `"$ResourceName`" has status $clusterStatus. The workflow can proceed."
            }
        }

        # Before beginning a compliance check, make sure another compliance check against that resource isn't already under way so we can fail fast.
        $duplicateTask = Find-ExistingTask -ClusterTaskType "VLCM_COMPLIANCE_CHECK" -Operation "compliance check" -ResourceId $resourceId -ResourceName $ResourceName -ResourceType $ResourceType -WorkloadDomainName $WorkloadDomainName -StandAloneHostTaskType "DOMAIN_VLCM_COMPLIANCE_CHECK"
        # Skip this entity of we found a duplicate task Id.
        if ($duplicateTask) {
            Write-LogMessage -Type ERROR -SuppressOutputToScreen -Message "$ResourceType `"$ResourceName`" failed duplicate compliance task check."
            continue
        } else {
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "$ResourceType `"$ResourceName`" passed duplicate compliance task check."
        }

        $imageId = $null
        if (-not $imageSeedingWorkflow) {
            # Utilize the user-provided personality name to generate the PersonalityID required for.
            # running a compliance check against a cluster Id.
            $matchedPersonality = if ($personalities -and $personalities.PSObject.Properties['Elements'] -and $personalities.Elements) { $personalities.Elements | Where-Object -Property PersonalityName -eq $SddcManagerImageName | Select-Object -First 1 } else { $null }
            $imageId = if ($matchedPersonality) { $matchedPersonality.PersonalityId } else { $null }

            if (-not $imageId ) {
                Write-LogMessage -Type ERROR -Message "$SddcManagerImageName Image not found"
                return
            }
        }

        # Cluster and standalone hosts use different compliance checks as they utilize different APIs (v1 vs v2).
        if ($ResourceType -eq "Cluster") {
            # In the image seeding workflow, no ClusterImageId is passed.
            if ($imageSeedingWorkflow) {
                $clusterComplianceCheckSpec = Initialize-VcfClusterImageComplianceCheckSpec -ErrorAction SilentlyContinue
            } else {
                $clusterComplianceCheckSpec = Initialize-VcfClusterImageComplianceCheckSpec -ClusterImageId $imageId -ErrorAction SilentlyContinue
            }
            $clusterUpdateSpec = Initialize-VcfClusterUpdateSpec -ClusterImageComplianceCheckSpec $clusterComplianceCheckSpec -ErrorAction SilentlyContinue

            Write-LogMessage -Type DEBUG -Message "API Call: Invoke-VcfUpdateCluster -Id $resourceId (compliance check for cluster `"$ResourceName`" with ImageId: $imageId)"
            try {
                $response = Invoke-VcfUpdateCluster -Id $resourceId -ClusterUpdateSpec $clusterUpdateSpec -ErrorAction Stop

                # Check for invalid response type
                if ($response -match "VMware.Bindings.Vcf.SddcManager.Model.Personality") {
                    throw "Invalid response type received: Personality object instead of Task"
                }
            } catch {
                Write-LogMessage -Type ERROR -PrependNewLine -AppendNewLine -Message "Check vLCM compliance for $ResourceType `"$ResourceName`" failed."
                $taskErrorsMessage = $_.Exception.Message -replace "^.*`"message`":`"" -replace "`"\}"

                switch -Regex ($_.Exception.Message) {
                    "VLCM_COMPLIANCE_CHECK" {
                        Write-LogMessage -Type ERROR -AppendNewLine -Message "Cannot proceed with compliance check of $ResourceType `"$ResourceName`" in `"$WorkloadDomainName`". Skipping check."
                        Write-LogMessage -Type ERROR -AppendNewLine -Message "Error Message: $taskErrorsMessage"
                    }
                    "CLUSTER_IMAGE_VERSION_MISMATCH" {
                        Write-LogMessage -Type INFO -AppendNewLine -Message "The ESX base image chosen does not match the version currently used by $ResourceType `"$ResourceName`" in `"$WorkloadDomainName`". Skipping check."
                        Write-LogMessage -Type ERROR -AppendNewLine -Message "Error Message: $taskErrorsMessage"
                    }
                    default {
                        Write-LogMessage -Type ERROR -AppendNewLine -Message "Error Message: $taskErrorsMessage"
                    }
                }
                continue
            }
        } else {
            $hostQueryResult3 = Invoke-VcfGetHosts -Fqdn $ResourceName -IsStandalone $true -ErrorAction SilentlyContinue
            $hostQueryResult = if ($hostQueryResult3 -and $hostQueryResult3.PSObject.Properties['Elements']) { $hostQueryResult3.Elements | Select-Object -First 1 } else { $null }
            $standAloneHostConfigurationStatus = if ($hostQueryResult) { $hostQueryResult.ConfigurationStatus } else { $null }
            if ($standAloneHostConfigurationStatus -notin @("ACTIVE", "ASSIGNED")) {
                if (-not $standAloneHostConfigurationStatus) {
                    $standAloneHostConfigurationStatus = "<UNKNOWN>"
                }
                Write-LogMessage -Type ERROR -PrependNewLine -Message "$ResourceType `"$ResourceName`" has status `"$standAloneHostConfigurationStatus`". The workflow cannot proceed."
                continue
            } else {
                Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "$ResourceType `"$ResourceName`" has status `"$standAloneHostConfigurationStatus`". The workflow can proceed."
            }
            $TransitionResourceSpec = Initialize-VcfTransitionResourceSpec -Id $resourceId -Type "HOST" -ErrorAction SilentlyContinue
            if ($imageSeedingWorkflow) {
                # When image seeding is used, we do not pass the ImageId parameter.
                $imageComplianceCheckSpec = Initialize-VcfImageComplianceCheckSpec -Resources $TransitionResourceSpec -ErrorAction SilentlyContinue
             } else {
                $imageComplianceCheckSpec = Initialize-VcfImageComplianceCheckSpec -ImageId $imageId -Resources $TransitionResourceSpec -ErrorAction SilentlyContinue
            }
            $domainUpdateSpec = Initialize-VcfDomainUpdateSpec -ImageComplianceCheckSpec $imageComplianceCheckSpec -ErrorAction SilentlyContinue
            Write-LogMessage -Type DEBUG -Message "API Call: Invoke-VcfUpdateDomain -Id $workloadDomainId (compliance check for host `"$ResourceName`" with ImageId: $imageId)"
            try {
                $response = Invoke-VcfUpdateDomain -Id $workloadDomainId -DomainUpdateSpec $domainUpdateSpec -ErrorAction Stop

                # Check for invalid response type
                if ($response -match "VMware.Bindings.Vcf.SddcManager.Model.Personality") {
                    throw "Invalid response type received: Personality object instead of Task"
                }

                Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Compliance check for $ResourceType `"$ResourceName`" in workload domain `"$WorkloadDomainName`" running with Message: `"$($response.LocalizableDescriptionPack.Message)`", Task Name: `"$($response.LocalizableDescriptionPack.MessageKey)`", Task ID: `"$($response.Id)`"."
            } catch {
                Write-LogMessage -Type ERROR -PrependNewLine -AppendNewLine -Message "Check vLCM compliance for cluster `"$ResourceName`" failed."
                $taskErrorsMessage = $_.Exception.Message -replace "^.*`"message`":`"" -replace "`"\}"

                switch -Regex ($_.Exception.Message) {
                    "VLCM_COMPLIANCE_CHECK" {
                        Write-LogMessage -Type ERROR -AppendNewLine -Message "Cannot proceed with compliance check of $ResourceType `"$ResourceName`" in `"$WorkloadDomainName`". Skipping check."
                        Write-LogMessage -Type INFO -Message "Error Message: $taskErrorsMessage"
                    }
                    "SAH_VERSION_MISMATCHES_WITH_IMAGE_VERSION" {
                        Write-LogMessage -Type INFO -AppendNewLine -Message "The ESX base image chosen does not match the version currently used by $ResourceType `"$ResourceName`" in `"$WorkloadDomainName`". Skipping check."
                        Write-LogMessage -Type INFO -Message "Error Message: $taskErrorsMessage"
                    }
                    default {
                        Write-LogMessage -Type ERROR -Message "Error Message: $taskErrorsMessage"
                    }
                }
                continue
            }
        }

        # Log start of compliance check with appropriate formatting for parallel vs serial mode.
        $logParams = @{
            Type = 'INFO'
            PrependNewLine = (-not $Parallel)
        }
        if ($SddcManagerImageName) {
            Write-LogMessage @logParams -Message "Beginning compliance check for $ResourceType `"$ResourceName`" in workload domain `"$WorkloadDomainName`" against image `"$SddcManagerImageName`"..."
        } else {
            Write-LogMessage @logParams -Message "Auto-generating a vLCM image for $ResourceType `"$ResourceName`" in workload domain `"$WorkloadDomainName`" and beginning compliance check ..."
        }
        # Perform a brief sleep between each invocation in parallel mode to allow prior task state to settle.
        # This prevents API rate limiting and ensures tasks are properly registered before the next request.
        if ($Parallel) {
            Start-Sleep -Seconds 2
        }

        # Provide a task Id in the logs for debugging purposes.
        if ($SddcManagerImageName) {
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "$ResourceType `"$ResourceName`" in Workload Domain `"$WorkloadDomainName`" checked against image `"$SddcManagerImageName`" initiated using Task Id `"$($response.Id)`"."
        } else {
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "$ResourceType `"$ResourceName`" in Workload Domain `"$WorkloadDomainName`" checked against auto-generated image initiated using Task Id `"$($response.Id)`"."
        }

        $complianceTasksResult = Invoke-VcfGetTasks -TaskType VLCM_COMPLIANCE_CHECK -ErrorAction SilentlyContinue
        $complianceChecks = if ($complianceTasksResult -and $complianceTasksResult.PSObject.Properties['Elements'] -and $complianceTasksResult.Elements) {
            @($complianceTasksResult.Elements | Where-Object { $_.PSObject.Properties['Status'] -and $_.Status -eq "In Progress" }).Count
        } else { 0 }
        if ($complianceChecks) {
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Currently $complianceChecks compliance check(s) is/are being processed by SDDC Manager."
        }

        # Parallel or Silence flag will disable polling for task to complete.
        # Skip polling if EITHER parallel OR silence is enabled.
        $shouldPoll = -not ($Parallel -or $Silence)
        if ($shouldPoll) {

            # Poll for task completion using the centralized function.
            $waitResult = Wait-ComplianceCheckCompletion `
                -TaskId $response.Id `
                -ResourceName $ResourceName `
                -ResourceType $ResourceType `
                -WorkloadDomainName $WorkloadDomainName `
                -TimeoutSeconds $timeoutSeconds `
                -PollingIntervalSeconds $pollingIntervalSeconds

            # Skip to next resource if timeout occurred.
            if ($waitResult.TimedOut) {
                continue
            }

            # Validate task completion.
            $taskResult = Test-TaskStatus -Response $waitResult.TaskResponse -ResourceType $ResourceType -ResourceName $ResourceName -WorkloadDomainName $WorkloadDomainName
            if ($taskResult -eq "Failed") {
                continue
            }

            # Display the stored results of the aforementioned compliance check.
            Show-ImageComplianceCheckResults -ResourceName $ResourceName -ResourceType $ResourceType -WorkloadDomainName $WorkloadDomainName
        }
    }
}
#endregion

#region Transition and Tasks
Function Invoke-HostRemediationOptionsConfig {

    <#
        .SYNOPSIS
        The function Invoke-HostRemediationOptionsConfig creates and checks remediation policies.

        .DESCRIPTION
        The function is optionally used during the transition process to override the default remediation policies to carry out the process for
        clusters and standalone hosts alike without the user having to manually adjust the policies in vCenter.

        .PARAMETER Action
        Specifies the action (Check or Create).

        .PARAMETER HostRemediationOptionsJson
        Specifies what file to accept as JSON input for config validation.

        .PARAMETER JsonOutputFile
        Specifies what file to save JSON output to for config creation.

        .EXAMPLE
        Invoke-HostRemediationOptionsConfig -Action Check -HostRemediationOptionsJson HostRemediationOptions.json

        .EXAMPLE
        Invoke-HostRemediationOptionsConfig -Action Create -JsonOutputFile HostRemediationOptions.json

        .OUTPUTS
        None
        This function does not return a value. It validates or creates host remediation options files.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateSet("Check","Create")] [String]$action,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$hostRemediationOptionsJson,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$JsonOutputFile
    )

    Write-LogMessage -Type DEBUG -Message "Entered Invoke-HostRemediationOptionsConfig function..."

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    # For check options, first validate that the required fields are present before continuing further..
    if ($action -eq "Check") {

        try {
            $jsonContent = Get-Content $hostRemediationOptionsJson -ErrorAction Stop
            $hostRemediationOptionsConfig = $jsonContent | ConvertFrom-Json -ErrorAction Stop

            # Validate that required properties exist.
            if (-not $hostRemediationOptionsConfig.PSObject.Properties['RemediationFailureAction']) {
                throw "Required property 'RemediationFailureAction' not found in HostRemediationOptionsConfig file."
            }
            if (-not $hostRemediationOptionsConfig.PSObject.Properties['RemediationRetryDelay']) {
                throw "Required property 'RemediationRetryDelay' not found in HostRemediationOptionsConfig file."
            }
            if (-not $hostRemediationOptionsConfig.PSObject.Properties['RemediationRetryCount']) {
                throw "Required property 'RemediationRetryCount' not found in HostRemediationOptionsConfig file."
            }
            if (-not $hostRemediationOptionsConfig.PSObject.Properties['PreRemediationPowerAction']) {
                throw "Required property 'PreRemediationPowerAction' not found in HostRemediationOptionsConfig file."
            }
            if (-not $hostRemediationOptionsConfig.PSObject.Properties['QuickBootEnabled']) {
                throw "Required property 'QuickBootEnabled' not found in HostRemediationOptionsConfig file."
            }

            $remediationFailureAction = $hostRemediationOptionsConfig.RemediationFailureAction
            $remediationRetryDelay = $hostRemediationOptionsConfig.RemediationRetryDelay
            $remediationRetryCount = $hostRemediationOptionsConfig.RemediationRetryCount
            $preRemediationPowerAction = $hostRemediationOptionsConfig.PreRemediationPowerAction
            $quickBootEnabled = $hostRemediationOptionsConfig.QuickBootEnabled

        } catch [System.ArgumentException] {
            Write-LogMessage -Type ERROR -Message "Invalid JSON format in file `"$hostRemediationOptionsJson`"."
            Write-LogMessage -Type ERROR -Message "Error details: $($_.Exception.Message)"
            Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR
        } catch [System.IO.FileNotFoundException] {
            Write-LogMessage -Type ERROR -Message "HostRemediationOptionsConfig file `"$hostRemediationOptionsJson`" not found."
            Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR
        } catch [System.UnauthorizedAccessException] {
            Write-LogMessage -Type ERROR -Message "Access denied reading HostRemediationOptionsConfig file `"$hostRemediationOptionsJson`"."
            Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR
        } catch {
            Write-LogMessage -Type ERROR -Message "Failed to parse HostRemediationOptionsConfig file `"$hostRemediationOptionsJson`"."
            Write-LogMessage -Type ERROR -Message "Error details: $($_.Exception.Message)"
            Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR
        }
    }

    # Line break for improved readability.
    if ($Script:Headless -and $action -eq "Create") {
        Write-Host ""
    }

    # The Looping structure will only apply to Create operations.  Check operations will exit as soon as a invalid value is detected, as.
    # remediation requires modifying the JsonInput file.  In additional Read-Host operations are only applicable to Creation operations.
    # as no user input is required for Check operations.
    Do {
        if ($action -eq "Create") {
            $remediationFailureAction = Read-Host "Enter your preferred remediation action (FAIL or RETRY) or press 'c' to cancel (default: FAIL)"
            if ([string]::IsNullOrWhiteSpace($remediationFailureAction)) {
                $remediationFailureAction = "FAIL"
            }
        }

        $remediationFailureAction = $remediationFailureAction.ToUpper()
        switch ($remediationFailureAction) {
        'RETRY' {
            Write-Host ""
            Do {
                if ($action -eq "Create") {
                    $remediationRetryCount = Read-Host "Enter the number of times to retry the failed operation (between 3 and 100) or press 'c' to cancel"
                }
                # Check for a cancel request before checking the type.
                if ($remediationRetryCount -eq 'c') {
                    return
                } elseif (-not $remediationRetryCount) {
                    Write-LogMessage -Type ERROR -AppendNewLine -Message "RemediationRetryCount value cannot be blank."
                    $remediationRetryCount = $null
                } elseif ($remediationRetryCount -notmatch "^\d+$") {
                    Write-LogMessage -Type ERROR -AppendNewLine -Message "RemediationRetryCount $remediationRetryCount is not an integer number."
                    $remediationRetryCount = $null
                } elseif ([int]$remediationRetryCount -lt 3 -or [int]$remediationRetryCount -gt 100) {
                    Write-LogMessage -Type ERROR -AppendNewLine -Message "RemediationRetryCount $remediationRetryCount is outside the accepted value range (between 3 and 100)."
                    $remediationRetryCount = $null
                }
                if ($null -eq $remediationRetryCount -and $action -eq "Check") {
                    return
                }
            } While ($null -eq $remediationRetryCount)

            # Line break for improved readability between loops.
            if ($action -eq "Create") {
                Write-Host ""
            }

            Do {
                if ($action -eq "Create") {
                    $remediationRetryDelay = Read-Host "Enter the seconds to wait between retry operations (between 300 and 3600) or press 'c' to cancel"
                }
                # Check for a cancel request before checking the type.
                if ($remediationRetryDelay -eq 'c') {
                    return
                } elseif (-not $remediationRetryDelay) {
                    Write-LogMessage -Type ERROR -AppendNewLine -Message "This value cannot be blank."
                    $remediationRetryDelay = $null
                } elseif ($remediationRetryDelay -notmatch "^\d+$") {
                    Write-LogMessage -Type ERROR -AppendNewLine -Message "RemediationRetryDelay $remediationRetryDelay is not an integer number."
                    $remediationRetryDelay = $null
                } elseif ([int]$remediationRetryDelay -lt 300 -or [int]$remediationRetryDelay -gt 3600) {
                    Write-LogMessage -Type ERROR -AppendNewLine -Message "RemediationRetryDelay $remediationRetryDelay is outside the acceptable value range (between 300 and 3600)."
                    $remediationRetryDelay = $null
                }
                if ($null -eq $remediationRetryDelay -and $action -eq "Check") {
                    return
                }
            } While ($null -eq $remediationRetryDelay)
        }
        'C' { return }
        'FAIL' {
            # The API expects these values to be zero for FAIL operations.
            switch ($action) {
                "Check" {
                    if ($remediationRetryDelay -ne "0") {
                         Write-LogMessage -Type ERROR -AppendNewLine -Message "RemediationRetryDelay set to $remediationRetryDelay.  This value must be 0 set to a `"FAIL`" RemediationFailureAction."
                         return
                    }
                    if ($remediationRetryCount -ne "0") {
                         Write-LogMessage -Type ERROR -AppendNewLine -Message "RemediationRetryCount set to $remediationRetryCount.  This value must be set to 0 for a `"FAIL`" RemediationFailureAction."
                         return
                    }
                }
                "Create" {
                    $remediationRetryDelay = 0
                    $remediationRetryCount = 0
                }
            }
        }
        # No action is required at this stage for fail. We must only protect against a user entering something other than fail here to proceed.
        default {
            Write-LogMessage -Type ERROR -AppendNewLine -Message "Please enter FAIL or RETRY."
            $remediationFailureAction = $null
        }
        } # end switch ($remediationFailureAction)
        if ($null -eq $remediationFailureAction -and $action -eq "Check") {
            return
        }

    } while ($null -eq $remediationFailureAction)

    # Line break for improved readability between loops.
    if ($action -eq "Create") {
        Write-Host ""
    }

    Do {
        if ($action -eq "Create") {
            $preRemediationPowerAction = Read-Host "Choose a pre-remediation power action (DO_NOT_CHANGE_VMS_POWER_STATE, POWER_OFF_VMS, SUSPEND_VMS, SUSPEND_VMS_TO_MEMORY) or press 'c' to cancel (default: DO_NOT_CHANGE_VMS_POWER_STATE)"
            if ([string]::IsNullOrWhiteSpace($preRemediationPowerAction)) {
                $preRemediationPowerAction = "DO_NOT_CHANGE_VMS_POWER_STATE"
            }
            $preRemediationPowerAction = $preRemediationPowerAction.ToUpper()
        }

        $validPowerActions = @("POWER_OFF_VMS", "SUSPEND_VMS", "DO_NOT_CHANGE_VMS_POWER_STATE", "SUSPEND_VMS_TO_MEMORY")
        $regexPattern = ($validPowerActions | ForEach-Object { [regex]::Escape($_) }) -join '|'

        if ($preRemediationPowerAction -eq 'C') {
            return
        } elseif ($preRemediationPowerAction -notmatch "^$regexPattern$") {
            Write-LogMessage -Type ERROR -AppendNewLine -Message "Please enter one of: DO_NOT_CHANGE_VMS_POWER_STATE, POWER_OFF_VMS, SUSPEND_VMS, SUSPEND_VMS_TO_MEMORY."
            $preRemediationPowerAction = $null
        }
        if ($null -eq $preRemediationPowerAction -and $action -eq "Check") {
            return
        }
    } while ($null -eq $preRemediationPowerAction)

    # Quick boot logic.
    if ($action -eq "Create") {
        # Line break for improved readability.
        Write-Host ""
        Do {

            $quickBootSelection = Read-Host "Enable Quick Boot? Enter yes or no, or press 'c' to cancel (default: no)"
            if ([string]::IsNullOrWhiteSpace($quickBootSelection)) {
                $quickBootSelection = "No"
            }

            if ($quickBootSelection -eq 'c') {
                return
            } elseif ($quickBootSelection -inotmatch "^(Yes|No)$") {
                Write-LogMessage -Type ERROR -AppendNewLine -Message "Please enter yes or no."
                $quickBootSelection = $null
            }
            if ($null -eq $quickBootSelection -and $action -eq "Check") {
                return
            }
        } While ($null -eq $quickBootSelection)

        # Transform into a boolean to make it easier to apply later on.
        switch ($quickBootSelection) {
            "Yes" { $quickBootEnabled = $true }
            "No"  { $quickBootEnabled = $false }
        }
    }

    # The last value to validate is QuickBootEnabled at which case we exit success or failure.
    if ($action -eq "Check") {
        if ($quickBootEnabled -isnot [bool]) {
            Write-LogMessage -Type WARNING -AppendNewLine -Message "QuickBootEnabled was set to $quickBootEnabled. It must be set to `"true`" or `"false`"."
            return
        } else {
            Write-LogMessage -Type INFO -Message "No errors detected in HostRemediationOptionsConfig file `"$hostRemediationOptionsJson`"."
        }
        return
    }


    # Create a hashtable of all our choices in order to apply them during the transition phase.
    $hostRemediationOptions = @{
        "RemediationFailureAction" = $remediationFailureAction
        "RemediationRetryDelay" = $remediationRetryDelay
        "RemediationRetryCount" = $remediationRetryCount
        "PreRemediationPowerAction" = $preRemediationPowerAction
        "QuickBootEnabled" = $quickBootEnabled
    }

    # Log the data we've collected thus far.
    switch ($remediationFailureAction) {
        'RETRY' { Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "The $remediationFailureAction hostRemediationOptions action selected with $remediationRetryCount retries at $remediationRetryDelay second delay with preRemediationPowerAction $preRemediationPowerAction is QuickBootEnabled $quickBootEnabled." }
        'FAIL'  { Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "The $remediationFailureAction hostRemediationOptions action selected with preRemediationPowerAction $preRemediationPowerAction and QuickBootEnabled $quickBootEnabled." }
    }
    if (-not $Script:Headless) {
        return $hostRemediationOptions
    } else {
        if ($JsonOutputFile) {
            $jsonResponse = $hostRemediationOptions | ConvertTo-Json
            if (Test-Path $JsonOutputFile) {
                Write-LogMessage -Type WARNING -Message "Output file `"$JsonOutputFile`" already exists and will be overwritten."
            }
            Set-Content -Path $JsonOutputFile $jsonResponse
        } else {
            Write-LogMessage -Type ERROR -Message "Invoke-HostRemediationOptionsConfig function called in headless mode without a JSON output file.  Nothing to do."
        }
    }
}
Function Invoke-BatchedTransition {

    <#
        .SYNOPSIS
        Processes standalone host transitions in batches by workload domain for improved performance.

        .DESCRIPTION
        This helper function groups standalone hosts by workload domain and processes up to 25 hosts
        per domain in a single API call. This significantly reduces task overhead and improves
        performance for multi-host environments.

        The function performs validation for each host (status, compliance, image existence, duplicate
        tasks) before including it in the batch. Only valid hosts are transitioned together.

        This function is called by Invoke-TransitionBaselineManagedResource to centralize batch
        processing logic and reduce code duplication.

        .PARAMETER HostRemediationOptionsSpec
        The remediation options spec to apply to all batched hosts.

        .PARAMETER JsonInputFile
        JSON input file path (affects error handling in headless mode).

        .PARAMETER MaxBatchSize
        Maximum number of hosts per batch (default: 25, enforced by API).

        .PARAMETER Parallel
        If true, skip polling for task completion.

        .PARAMETER PollingIntervalSeconds
        Seconds between batch transition task polls (default: 5). Valid range: 1-300.

        .PARAMETER SelectedResourceDetails
        Array of resource objects containing host information (ResourceId, ResourceName, ResourceType, WorkloadDomainId, WorkloadDomainName).

        .PARAMETER Silence
        If true, skip polling for task completion.

        .PARAMETER TaskPollStallWarningSeconds
        Seconds between poll iterations that triggers a stall warning in the log (default: 300).

        .PARAMETER TimeoutSeconds
        Maximum seconds to wait for a batch task to complete before logging a timeout error (default: 14400).

        .EXAMPLE
        $batchedIds = Invoke-BatchedTransition -SelectedResourceDetails $standaloneHosts -HostRemediationOptionsSpec $remediation -MaxBatchSize 25

        .OUTPUTS
        Array
        Returns array of ResourceIds that were processed in batches (to prevent duplicate processing).
    #>

    Param (
        [Parameter(Mandatory = $true)] $HostRemediationOptionsSpec,
        [Parameter(Mandatory = $false)] [String]$JsonInputFile,
        [Parameter(Mandatory = $false)] [ValidateRange(1, 25)] [Int]$MaxBatchSize = 25,
        [Parameter(Mandatory = $false)] [Bool]$Parallel = $false,
        [Parameter(Mandatory = $false)] [ValidateRange(1, 300)] [Int]$PollingIntervalSeconds = 5,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [Array]$SelectedResourceDetails,
        [Parameter(Mandatory = $false)] [Bool]$Silence = $false,
        [Parameter(Mandatory = $false)] [ValidateRange(30, 3600)] [Int]$TaskPollStallWarningSeconds = 300,
        [Parameter(Mandatory = $false)] [ValidateRange(1, [Int]::MaxValue)] [Int]$TimeoutSeconds = 14400
    )

    Write-LogMessage -Type DEBUG -Message "Entered Invoke-BatchedTransition function with $($SelectedResourceDetails.Count) host(s)..."

    $batchedHostIds = @()
    [array]$standaloneHosts = @($SelectedResourceDetails | Where-Object {$_.ResourceType -eq "Standalone Host"})

    if ($standaloneHosts.Count -eq 0) {
        Write-LogMessage -Type DEBUG -Message "No standalone hosts to batch. Returning empty array."
        return $batchedHostIds
    }

    Write-LogMessage -Type INFO -Message "Standalone host batching enabled - hosts in same workload domain will be transitioned together."

    # Group standalone hosts by workload domain ID (batches cannot span domains).
    $hostsByDomain = @{}
    foreach ($currentHost in $standaloneHosts) {
        $domainId = $currentHost.WorkloadDomainId

        if (-not $hostsByDomain.ContainsKey($domainId)) {
            $hostsByDomain[$domainId] = @()
        }
        $hostsByDomain[$domainId] += $currentHost
    }

    # Create batches (max 25 hosts per batch).
    $batches = @()
    foreach ($domainId in $hostsByDomain.Keys) {
        $hostsInDomain = $hostsByDomain[$domainId]
        $domainName = $hostsInDomain[0].WorkloadDomainName

        # Split into batches of up to $MaxBatchSize hosts.
        for ($i = 0; $i -lt $hostsInDomain.Count; $i += $MaxBatchSize) {
            $endIndex = [Math]::Min($i + $MaxBatchSize - 1, $hostsInDomain.Count - 1)
            $batchHosts = $hostsInDomain[$i..$endIndex]

            $batches += [PSCustomObject]@{
                WorkloadDomainId = $domainId
                WorkloadDomainName = $domainName
                Hosts = $batchHosts
            }
        }
    }

    # Process each batch.
    foreach ($batch in $batches) {
        $batchSize = $batch.Hosts.Count
        $batchDisplayName = "Workload Domain `"$($batch.WorkloadDomainName)`" ($batchSize standalone host(s))"

        Write-LogMessage -Type INFO -PrependNewLine -Message "Processing batch: $batchDisplayName..."

        # Refresh access token once before validating batch.
        Test-SddcManagerConnection

        # Validate all hosts in batch before proceeding.
        $validHosts = @()
        $excludedNoCompliance = @()
        $excludedBadStatus = @()
        $excludedImageNotFound = @()
        $excludedDuplicate = @()
        Write-LogMessage -Type DEBUG -Message "Validating batch of $($batch.Hosts.Count) host(s) in workload domain `"$($batch.WorkloadDomainName)`"..."

        foreach ($currentHost in $batch.Hosts) {
            $resourceId = $currentHost.ResourceId
            $ResourceName = $currentHost.ResourceName
            $WorkloadDomainName = $currentHost.WorkloadDomainName

            # Check host status (must be ACTIVE or ASSIGNED).
            $hostDetails = Invoke-VcfGetHost -Id $resourceId -ErrorAction SilentlyContinue
            if (-not $hostDetails) {
                Write-LogMessage -Type ERROR -Message "Host `"$ResourceName`" excluded from batch: Could not retrieve host details from SDDC Manager."
                $excludedBadStatus += $ResourceName
                continue
            }
            if ($hostDetails.Status -notin @("ACTIVE", "ASSIGNED")) {
                Write-LogMessage -Type ERROR -Message "Host `"$ResourceName`" excluded from batch: Host status is $($hostDetails.Status), expected ACTIVE or ASSIGNED."
                $excludedBadStatus += $ResourceName
                continue
            }

            # Check if compliance check has been run.
            $response = Get-ImageComplianceElements -ResourceId $resourceId -WorkloadDomainId $batch.WorkloadDomainId

            if (-not $response -or $response -eq "<NO_COMPLIANCE_RESULTS>") {
                Write-LogMessage -Type DEBUG -Message "Host `"$ResourceName`" excluded from batch: Compliance check has not been run."
                $excludedNoCompliance += $ResourceName
                continue
            }

            # Check if image exists (only for non-seeded images).
            $imageId = if ($response -and $response.PSObject.Properties['Image'] -and $response.Image -and $response.Image.PSObject.Properties['Id']) { $response.Image.Id } else { $null }
            if ($imageId) {
                $imageFound = Invoke-VcfGetPersonality -PersonalityId $imageId -ErrorAction SilentlyContinue
                if (-not $imageFound) {
                    Write-LogMessage -Type DEBUG -Message "Host `"$ResourceName`" excluded from batch: Image not found in SDDC Manager."
                    $excludedImageNotFound += $ResourceName
                    continue
                }
            }

            # Check for duplicate transition tasks.
            $duplicateTask = Find-ExistingTask -ClusterTaskType "VLCM_TRANSITION" -Operation "transition task" -ResourceId $resourceId -ResourceName $ResourceName -ResourceType "Standalone Host" -WorkloadDomainName $WorkloadDomainName -StandAloneHostTaskType "DOMAIN_VLCM_TRANSITION"

            if ($duplicateTask -eq $true) {
                Write-LogMessage -Type DEBUG -Message "Host `"$ResourceName`" excluded from batch: Duplicate transition task in progress."
                $excludedDuplicate += $ResourceName
                continue
            }

            # Host is valid - add to batch.
            $validHosts += $currentHost
        }

        # Log validation results.
        Write-LogMessage -Type DEBUG -Message "Batch validation complete: $($validHosts.Count) of $($batch.Hosts.Count) host(s) passed validation"
        if ($excludedNoCompliance.Count -gt 0) {
            Write-LogMessage -Type WARNING -Message "$($excludedNoCompliance.Count) host(s) excluded - compliance check has not been run: $($excludedNoCompliance -join ', '). Run -ComplianceCheck first."
        }
        if ($excludedBadStatus.Count -gt 0) {
            Write-LogMessage -Type ERROR -Message "$($excludedBadStatus.Count) host(s) excluded - unexpected host status: $($excludedBadStatus -join ', ')."
        }
        if ($excludedImageNotFound.Count -gt 0) {
            Write-LogMessage -Type ERROR -Message "$($excludedImageNotFound.Count) host(s) excluded - assigned image not found in SDDC Manager: $($excludedImageNotFound -join ', ')."
        }
        if ($excludedDuplicate.Count -gt 0) {
            Write-LogMessage -Type WARNING -Message "$($excludedDuplicate.Count) host(s) excluded - transition task already in progress: $($excludedDuplicate -join ', ')."
        }

        # Skip batch if no valid hosts.
        if ($validHosts.Count -eq 0) {
            Write-LogMessage -Type ERROR -Message "No hosts in $batchDisplayName could be transitioned. See warnings above for details."
            # Track ALL batched host IDs (including invalid) to prevent retrying.
            foreach ($currentHost in $batch.Hosts) {
                $batchedHostIds += $currentHost.ResourceId
            }
            continue
        }

        # Log if some hosts were excluded during validation.
        if ($validHosts.Count -lt $batch.Hosts.Count) {
            $excludedCount = $batch.Hosts.Count - $validHosts.Count
            Write-LogMessage -Type WARNING -Message "Excluded $excludedCount host(s) from batch due to validation failures. Included $($validHosts.Count) host(s). Review DEBUG logs for exclusion details."
        }

        # Create List<TransitionResourceSpec> for all valid hosts.
        $TransitionResourceSpecList = New-Object 'System.Collections.Generic.List[object]'

        foreach ($currentHost in $validHosts) {
            $TransitionResourceSpec = Initialize-VcfTransitionResourceSpec -Id $currentHost.ResourceId -Type "HOST" -ErrorAction SilentlyContinue
            $TransitionResourceSpecList.Add($TransitionResourceSpec)
        }

        # Create transition spec with list of hosts (using provided remediation options).
        $transitionSpec = Initialize-VcfTransitionSpec -Resources $TransitionResourceSpecList -HostRemediationOptions $HostRemediationOptionsSpec -ErrorAction SilentlyContinue
        $domainUpdateSpec = Initialize-VcfDomainUpdateSpec -TransitionSpec $transitionSpec -ErrorAction SilentlyContinue

        # Invoke batch transition.
        Write-LogMessage -Type INFO -Message "Initiating batch transition for $($validHosts.Count) host(s) in workload domain `"$($batch.WorkloadDomainName)`"..."
        Write-LogMessage -Type DEBUG -Message "API Call: Invoke-VcfUpdateDomain -Id $($batch.WorkloadDomainId) with $($TransitionResourceSpecList.Count) host resource(s)"

        $response = $null
        try {
            $response = Invoke-VcfUpdateDomain -Id $batch.WorkloadDomainId -DomainUpdateSpec $domainUpdateSpec -ErrorAction Stop
        } catch {
            # Catch the most common workflow errors and provide guidance.
            $errorMessage = $_.Exception.Message

            switch -Regex ($errorMessage) {
                "vSphere Lifecycle Manager Images operation is currently working on this resource" {
                    Write-LogMessage -Type ERROR -Message "The batch transition for workload domain `"$($batch.WorkloadDomainName)`" is already in progress."
                }
                "is already managed using vSphere Lifecycle Manager Images" {
                    Write-LogMessage -Type ERROR -Message "One or more hosts in workload domain `"$($batch.WorkloadDomainName)`" have already been transitioned to image management."
                }
                default {
                    Write-LogMessage -Type ERROR -Message "An unexpected error occurred during batch transition."
                    Write-LogMessage -Type ERROR -Message $errorMessage
                }
            }

            if (-not $Script:Headless) {
                Show-AnyKey
                break
            } else {
                if ($JsonInputFile) {
                    Write-LogMessage -Type INFO -Message "Moving onto next batch..."
                } else {
                    Exit-WithCode -ExitCode $Script:ExitCodes.OPERATION_FAILED
                }
            }
        }

        # Parallel or Silence flag will disable polling for task to complete.
        # Skip polling if EITHER parallel OR silence is enabled.
        if ($response -and -not ($Parallel -or $Silence)) {
            Test-SddcManagerConnection
            $initialTaskResult = Invoke-VcfGetTask -Id $response.Id -ErrorAction SilentlyContinue
            $initialTotalStepCount = if ($initialTaskResult -and $initialTaskResult.SubTasks) { @($initialTaskResult.SubTasks).Count } else { 0 }
            $batchTaskId = $response.Id

            $batchStepLog = {
                param(
                    [Int]$CurrentStepCount,
                    [Int]$ElapsedSeconds,
                    [String]$InProgressStepName,
                    [Int]$PollingIntervalSeconds,
                    [Int]$TotalStepCount
                )
                $batchPct = if ($TotalStepCount -gt 0) { $CurrentStepCount / $TotalStepCount * 100 } else { 0 }
                Write-Progress -Id 1 -Activity "Completed step $CurrentStepCount of $TotalStepCount       " -Status "Processing: $InProgressStepName" -PercentComplete $batchPct
                Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Batch transition step $CurrentStepCount of $TotalStepCount for $($validHosts.Count) host(s) in Workload Domain `"$($batch.WorkloadDomainName)`" underway. $ElapsedSeconds seconds elapsed."
                Write-Progress -Id 2 -Activity "Batch transition in progress" -Status "$ElapsedSeconds seconds elapsed (updates every $PollingIntervalSeconds seconds)."
            }

            $pollResult = Invoke-VcfTransitionSubTaskPollLoop `
                -InitialTotalStepCount $initialTotalStepCount `
                -PollingIntervalSeconds $PollingIntervalSeconds `
                -TaskId $batchTaskId `
                -TaskNotFoundDebugMessage "Batch transition task $batchTaskId not found (completed and removed)" `
                -TaskPollStallWarningSeconds $TaskPollStallWarningSeconds `
                -TimeoutLogMessage "Batch transition polling timed out after $TimeoutSeconds seconds for workload domain `"$($batch.WorkloadDomainName)`"." `
                -TimeoutSeconds $TimeoutSeconds `
                -WriteStepProgressLog $batchStepLog

            $processTimer = $pollResult.ProcessTimer
            $taskStatus = $pollResult.TaskStatus
            $TaskId = $batchTaskId

            Stop-ProcessTimer -Timer $processTimer -Operation "Batch Transition Operation" -Interval "Minutes"

            $jsonResponse = $response | ConvertTo-Json
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message $jsonResponse

            switch -Regex ($taskStatus) {
                '^Failed$|^FAILED$' {
                    try {
                        $failedTask = (Invoke-VcfGetTask -Id $TaskId -ErrorAction Stop | Select-Object -Expand SubTasks | Where-Object -Property Status -eq "FAILED") | Select-Object -First 1
                    } catch {
                        Write-LogMessage -Type WARNING -Message "Could not retrieve subtask details for task `"$TaskId`": $($_.Exception.Message)"
                        $failedTask = $null
                    }
                    Write-LogMessage -Type ERROR -Message "Batch transition was unsuccessful for $($validHosts.Count) host(s) in Workload Domain `"$($batch.WorkloadDomainName)`"."
                    if ($failedTask) {
                        Write-LogMessage -Type ERROR -Message "Failed Task Name: $($failedTask.Name)"
                        Write-LogMessage -Type ERROR -Message "Subtask $($failedTask.Name) with Task Id $TaskId failed."
                        if ($null -ne $($failedTask.errors)) {
                            Write-LogMessage -Type ERROR -Message "Error: $($failedTask.errors)."
                        }
                        if ($null -ne $($failedTask.errors.errorCode)) {
                            Write-LogMessage -Type ERROR -Message "Error code: $($failedTask.Errors.ErrorCode)."
                        }
                    }
                }
                '^Successful$|^SUCCESSFUL$' { Write-LogMessage -Type INFO -Message "Batch transition completed successfully for $($validHosts.Count) host(s) in Workload Domain `"$($batch.WorkloadDomainName)`"." }
                '^Timed Out$' {
                    # Timeout details were already logged by Invoke-VcfTransitionSubTaskPollLoop.
                }
            }
        }

        # Track ALL batched host IDs (valid and invalid) for later skipping to prevent retrying hosts that failed validation.
        foreach ($currentHost in $batch.Hosts) {
            $batchedHostIds += $currentHost.ResourceId
        }
    }

    return $batchedHostIds
}

Function Get-VcfTaskStateOrCompletedFromQueue {

    <#
        .SYNOPSIS
        Retrieves an SDDC Manager task by Id for polling loops, treating a missing task as completed.

        .DESCRIPTION
        Shared by Invoke-VcfTransitionSubTaskPollLoop and Wait-ComplianceCheckCompletion so 404 handling and logging stay aligned.

        .PARAMETER TaskId
        SDDC Manager task Id.

        .PARAMETER TaskNotFoundDebugMessage
        DEBUG message when the task is not found (empty uses a standard message including the task Id).

        .OUTPUTS
        PSCustomObject with HadApiFailure, ErrorRecord, TaskResponse, and TaskStatus.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$TaskId,
        [Parameter(Mandatory = $false)] [String]$TaskNotFoundDebugMessage = ""
    )

    if ([String]::IsNullOrWhiteSpace($TaskNotFoundDebugMessage)) {
        $TaskNotFoundDebugMessage = "Task $TaskId not found in SDDC Manager (may have completed and been removed from queue)"
    }

    try {
        $taskResponse = Invoke-VcfGetTask -Id $TaskId -ErrorAction Stop
        return [PSCustomObject]@{
            ErrorRecord   = $null
            HadApiFailure = $false
            TaskResponse  = $taskResponse
            TaskStatus    = $taskResponse.Status
        }
    } catch {
        if ($_.Exception.Message -match "NOT_FOUND|404|does not exist") {
            Write-LogMessage -Type DEBUG -Message $TaskNotFoundDebugMessage
            return [PSCustomObject]@{
                ErrorRecord   = $null
                HadApiFailure = $false
                TaskResponse  = $null
                TaskStatus    = "SUCCESSFUL"
            }
        }
        return [PSCustomObject]@{
            ErrorRecord   = $_
            HadApiFailure = $true
            TaskResponse  = $null
            TaskStatus    = "Unknown"
        }
    }
}

Function Invoke-VcfTransitionSubTaskPollLoop {

    <#
        .SYNOPSIS
        Polls an SDDC Manager VLCM transition task that reports progress via sub-tasks until completion, timeout, or API failure.

        .DESCRIPTION
        Consolidates duplicated Do/While polling used by Invoke-BatchedTransition and Wait-TransitionCompletion so timeout handling,
        token refresh, vCenter session refresh cadence, and stall warnings stay consistent.
        Transient network errors are retried silently until the overall TimeoutSeconds is reached.

        .PARAMETER ApiFailureLogIntervalCount
        Number of consecutive network failures between repeated WARNING log entries. The first failure is always logged.

        .PARAMETER InitialTotalStepCount
        Sub-task count from the first Invoke-VcfGetTask result (may be zero until the task populates sub-tasks).

        .PARAMETER PollingIntervalSeconds
        Sleep interval between polls.

        .PARAMETER TaskId
        SDDC Manager task Id to poll.

        .PARAMETER TaskNotFoundDebugMessage
        DEBUG log line when the task returns 404 (task completed and removed).

        .PARAMETER TaskPollStallWarningSeconds
        Elapsed seconds between polls that triggers a WARNING in the log if exceeded.

        .PARAMETER TimeoutLogMessage
        ERROR message written when the overall timeout is exceeded.

        .PARAMETER TimeoutSeconds
        Maximum seconds to poll before timing out.

        .PARAMETER WriteStepProgressLog
        ScriptBlock invoked each iteration with -CurrentStepCount, -ElapsedSeconds, -InProgressStepName, -PollingIntervalSeconds, and -TotalStepCount.

        .OUTPUTS
        PSCustomObject with TaskStatus, TimedOut, ProcessTimer, TaskResponse, and TotalStepCount.
    #>

    Param (
        [Parameter(Mandatory = $false)] [ValidateRange(1, 100)] [Int]$ApiFailureLogIntervalCount = 5,
        [Parameter(Mandatory = $false)] [Int]$InitialTotalStepCount = 0,
        [Parameter(Mandatory = $true)] [ValidateRange(1, 300)] [Int]$PollingIntervalSeconds,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$TaskId,
        [Parameter(Mandatory = $false)] [String]$TaskNotFoundDebugMessage = "",
        [Parameter(Mandatory = $false)] [ValidateRange(30, 3600)] [Int]$TaskPollStallWarningSeconds = 300,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$TimeoutLogMessage,
        [Parameter(Mandatory = $true)] [ValidateRange(1, [Int]::MaxValue)] [Int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)] [ScriptBlock]$WriteStepProgressLog
    )

    $processTimer = Start-ProcessTimer
    $taskStatus = "Unknown"
    $taskResponse = $null
    $pollCount = 0
    $consecutiveApiFailures = 0
    [Int]$totalStepCount = $InitialTotalStepCount

    Do {
        $preCheckTime = $([math]::Round(($processTimer.Elapsed.TotalSeconds), 0))

        if ($processTimer.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
            Write-LogMessage -Type ERROR -Message $TimeoutLogMessage
            if ($consecutiveApiFailures -gt 0) {
                Write-LogMessage -Type WARNING -Message "SDDC Manager was unreachable for the last $consecutiveApiFailures consecutive poll(s) when the timeout was reached for task $TaskId. The transition may still be running."
            }
            Write-Progress -Id 1 -Completed
            Write-Progress -Id 2 -Completed
            return [PSCustomObject]@{
                ProcessTimer   = $processTimer
                TaskResponse   = $taskResponse
                TaskStatus     = "Timed Out"
                TimedOut       = $true
                TotalStepCount = $totalStepCount
            }
        }

        $taskFetch = Get-VcfTaskStateOrCompletedFromQueue -TaskId $TaskId -TaskNotFoundDebugMessage $TaskNotFoundDebugMessage
        if ($taskFetch.HadApiFailure) {
            $consecutiveApiFailures++
            if ($consecutiveApiFailures -eq 1 -or ($consecutiveApiFailures % $ApiFailureLogIntervalCount -eq 0)) {
                Write-LogMessage -Type WARNING -Message "Network error querying task $TaskId (consecutive failures: $consecutiveApiFailures) — retrying in $PollingIntervalSeconds second(s): $($taskFetch.ErrorRecord.Exception.Message)"
            }
            Start-Sleep -Seconds $PollingIntervalSeconds
            continue
        }
        if ($consecutiveApiFailures -gt 0) {
            Write-LogMessage -Type INFO -Message "SDDC Manager connection restored after $consecutiveApiFailures consecutive network error(s) for task $TaskId."
            $consecutiveApiFailures = 0
        }
        $taskResponse = $taskFetch.TaskResponse
        $taskStatus = $taskFetch.TaskStatus
        if ($null -eq $taskResponse -and $taskStatus -eq "SUCCESSFUL") {
            break
        }

        Test-SddcManagerConnection

        $pollCount++
        if ($pollCount % 6 -eq 0) {
            Write-LogMessage -Type DEBUG -Message "Periodic vCenter session refresh check (poll $pollCount)."
            Test-VcentersConnection | Out-Null
        }

        $currentStepCount = @($taskResponse.SubTasks | Where-Object -Property Status -eq "SUCCESSFUL").Count
        $inProgressCandidates = @($taskResponse.SubTasks | Where-Object -Property Status -eq "IN_PROGRESS")
        $inProgressStepName = "Waiting..."
        if ($inProgressCandidates.Count -gt 0) {
            $inProgressSubTask = $inProgressCandidates[0]
            $nameProperty = $inProgressSubTask.PSObject.Properties["Name"]
            if (-not $nameProperty) {
                $nameProperty = $inProgressSubTask.PSObject.Properties["name"]
            }
            if ($nameProperty) {
                $inProgressStepName = [String]$nameProperty.Value
            }
        }

        if ($totalStepCount -eq 0 -and $taskResponse.SubTasks) {
            $totalStepCount = @($taskResponse.SubTasks).Count
        }

        $elapsedRounded = [math]::Round($processTimer.Elapsed.TotalSeconds, 0)
        & $WriteStepProgressLog -CurrentStepCount $currentStepCount -ElapsedSeconds $elapsedRounded -InProgressStepName $inProgressStepName -PollingIntervalSeconds $PollingIntervalSeconds -TotalStepCount $totalStepCount

        Start-Sleep -Seconds $PollingIntervalSeconds

        $postCheckTime = $([math]::Round(($processTimer.Elapsed.TotalSeconds), 0))
        if (([int]$preCheckTime + $TaskPollStallWarningSeconds) -lt ([int]$postCheckTime)) {
            Write-LogMessage -Type WARNING -SuppressOutputToScreen -Message "More than $TaskPollStallWarningSeconds seconds have elapsed between task progress checks. This is unusual."
        }

    } While ($taskStatus -eq "In Progress" -or $taskStatus -eq "Unknown")

    Write-Progress -Id 1 -Completed
    Write-Progress -Id 2 -Completed

    return [PSCustomObject]@{
        ProcessTimer   = $processTimer
        TaskResponse   = $taskResponse
        TaskStatus     = $taskStatus
        TimedOut       = $false
        TotalStepCount = $totalStepCount
    }
}

Function Wait-TransitionCompletion {

    <#
        .SYNOPSIS
        Polls for completion of a vLCM transition task and displays progress to the user.

        .DESCRIPTION
        This helper function monitors a transition task's progress, displaying real-time updates
        via Write-Progress and logging status changes. It handles task completion, failures,
        and provides retry options for failed transitions.

        This function is called by Invoke-TransitionBaselineManagedResource. Polling is implemented in Invoke-VcfTransitionSubTaskPollLoop.

        .PARAMETER PollingIntervalSeconds
        Seconds to sleep between task status polls. Default is 5 seconds.

        .PARAMETER ResourceName
        The name of the resource being transitioned (cluster or host).

        .PARAMETER ResourceType
        The type of resource ("Cluster" or "Standalone Host").

        .PARAMETER TaskId
        The task ID to monitor for completion.

        .PARAMETER TaskPollStallWarningSeconds
        Seconds between poll iterations that triggers a stall warning in the log (default: 300).

        .PARAMETER TimeoutSeconds
        Maximum seconds to wait before aborting the poll loop. Default is 14400 (4 hours).
        Transitions can take many hours; set this value higher if your environment requires it.

        .PARAMETER WorkloadDomainName
        The workload domain containing the resource.

        .EXAMPLE
        Wait-TransitionCompletion -TaskId "abc-123" -ResourceName "m01-cl01" -ResourceType "Cluster" -WorkloadDomainName "m01"

        .EXAMPLE
        Wait-TransitionCompletion -TaskId "abc-123" -ResourceName "m01-cl01" -ResourceType "Cluster" -WorkloadDomainName "m01" -TimeoutSeconds 28800 -PollingIntervalSeconds 10

        .OUTPUTS
        String
        Returns the final task status ("Successful", "Failed", "Unknown", "Timed Out", "Cancelled")
    #>

    Param (
        [Parameter(Mandatory = $false)] [ValidateRange(5, 86400)] [Int]$PollingIntervalSeconds = 5,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ResourceName,
        [Parameter(Mandatory = $true)] [ValidateSet("Cluster", "Standalone Host")] [String]$ResourceType,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$TaskId,
        [Parameter(Mandatory = $false)] [ValidateRange(30, 3600)] [Int]$TaskPollStallWarningSeconds = 300,
        [Parameter(Mandatory = $false)] [ValidateRange(300, 86400)] [Int]$TimeoutSeconds = 14400,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$WorkloadDomainName
    )

    Write-LogMessage -Type DEBUG -Message "Entered Wait-TransitionCompletion function for $ResourceType `"$ResourceName`"..."

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    # Determine the total number of transition steps required.
    $initialTaskResult = Invoke-VcfGetTask -Id $TaskId -ErrorAction SilentlyContinue
    $initialTotalStepCount = if ($initialTaskResult -and $initialTaskResult.SubTasks) { @($initialTaskResult.SubTasks).Count } else { 0 }

    $transitionStepLog = {
        param(
            [Int]$CurrentStepCount,
            [Int]$ElapsedSeconds,
            [String]$InProgressStepName,
            [Int]$PollingIntervalSeconds,
            [Int]$TotalStepCount
        )
        $pct = if ($TotalStepCount -gt 0) { $CurrentStepCount / $TotalStepCount * 100 } else { 0 }
        Write-Progress -Id 1 -Activity "Completed step $CurrentStepCount of $TotalStepCount       " -Status "Processing: $InProgressStepName" -PercentComplete $pct
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "$ResourceType transition step $CurrentStepCount of $TotalStepCount of `"$ResourceName`" in Workload Domain `"$WorkloadDomainName`" underway.  $ElapsedSeconds seconds elapsed."
        Write-Progress -Id 2 -Activity "$ResourceType transition in progress" -Status "$ElapsedSeconds seconds elapsed (updates every $PollingIntervalSeconds seconds)."
    }

    $pollResult = Invoke-VcfTransitionSubTaskPollLoop `
        -InitialTotalStepCount $initialTotalStepCount `
        -PollingIntervalSeconds $PollingIntervalSeconds `
        -TaskId $TaskId `
        -TaskPollStallWarningSeconds $TaskPollStallWarningSeconds `
        -TimeoutLogMessage "Wait-TransitionCompletion timed out after $TimeoutSeconds seconds for $ResourceType `"$ResourceName`" in Workload Domain `"$WorkloadDomainName`"." `
        -TimeoutSeconds $TimeoutSeconds `
        -WriteStepProgressLog $transitionStepLog

    $processTimer = $pollResult.ProcessTimer
    $taskStatus = $pollResult.TaskStatus

    if ($pollResult.TimedOut) {
        return "Timed Out"
    }

    Stop-ProcessTimer -Timer $processTimer -Operation "Transition Operation" -Interval "Minutes"

    # Handle task completion status.
    switch -Regex ($taskStatus) {
        '^Failed$|^FAILED$' {
            # There should only be one failed task, as the workflow will fail out when the first task fails. However, just in case, we want to return
            # a single task, so return just one task for safety.
            try {
                $failedTask = (Invoke-VcfGetTask -Id $TaskId -ErrorAction Stop | Select-Object -Expand SubTasks | Where-Object -Property Status -eq "FAILED") | Select-Object -First 1
            } catch {
                Write-LogMessage -Type WARNING -Message "Could not retrieve subtask details for task `"$TaskId`": $($_.Exception.Message)"
                $failedTask = $null
            }

            Write-LogMessage -Type ERROR -Message "Transition was unsuccessful for $ResourceType `"$ResourceName`" in Workload Domain `"$WorkloadDomainName`"."
            if ($failedTask) {
                Write-LogMessage -Type ERROR -Message "Failed Task Name: $($failedTask.Name)"
                Write-LogMessage -Type ERROR -Message "Subtask $($failedTask.Name) with Task Id $TaskId failed."

                if ($null -ne $($failedTask.errors)) {
                    Write-LogMessage -Type ERROR -Message "Error: $($failedTask.errors)."
                }
                if ($null -ne $($failedTask.errors.errorCode)) {
                    Write-LogMessage -Type ERROR -Message "Error code: $($failedTask.Errors.ErrorCode)."
                }
                if ($null -ne $($failedTask.errors.Message)) {
                    Write-LogMessage -Type ERROR -Message "Error Message: $($failedTask.Errors.Message)."
                }
            }

            Write-LogMessage -Type INFO -PrependNewLine -Message "Full details of the transition have been written to $Script:LogFile."
            Write-LogMessage -Type INFO -PrependNewLine -Message "When the findings have been remediated, the workflow can be retried."

            $decision = New-ChoiceMenu -Question "Would you like to retry the transition for $ResourceType `"$ResourceName`" in workload domain `"$WorkloadDomainName`" now?" -DefaultAnswer yes

            # If user chooses yes, retry the task.
            if ($decision -eq 0) {
                # Retry the transition task.
                Invoke-TransitionBaselineManagedResource -RetryTransition -FailedTaskId $TaskId
            } else {
                Show-AnyKey
            }

            # Short sleep before proceeding to next step to catch state transition edge case.
            Start-Sleep -Seconds 3
        }
        '^Successful$|^SUCCESSFUL$' {
            Write-LogMessage -Type INFO -Message "$ResourceType `"$ResourceName`" in Workload Domain `"$WorkloadDomainName`" has been successfully converted to vLCM image management."
        }
        "Unknown|Timed Out|Timed_Out|Cancelled" {
            Write-LogMessage -Type INFO -Message "$ResourceType `"$ResourceName`" in Workload Domain `"$WorkloadDomainName`" vLCM image application exited with status `"$taskStatus`". Unable to determine if the task completed or not."
        }
    }

    Write-LogMessage -Type INFO -PrependNewLine -Message "Full details of the transition written to $Script:LogFile."

    return $taskStatus
}
Function Invoke-TransitionBaselineManagedResource {

    <#
        .SYNOPSIS
        The function Invoke-TransitionBaselineManagedResource applies a vLCM image to cluster members or a standalone host.

        .DESCRIPTION
        The interface use of this function provides user feedback (on sub-steps completed, time elapsed) as it's a long process. If the
        process fails the user may retry immediately, or later (discovering the task through another function).

        .EXAMPLE
        Invoke-TransitionBaselineManagedResource -ResourceName m01-cl01 -ResourceType cluster -WorkloadDomainName m01 -ImageName vsphere803.

        .EXAMPLE
        Invoke-TransitionBaselineManagedResource -ResourceName esx-01.example.com -ResourceType "Standalone host" -WorkloadDomainName m01 -ImageName vsphere803.

        .EXAMPLE
        Invoke-TransitionBaselineManagedResource -JsonInput ResourcesToTransition.json

        .EXAMPLE
        Invoke-TransitionBaselineManagedResource -JsonInput ResourcesToTransition.json -Parallel

        .PARAMETER BatchStandaloneHosts
        Specifies whether to batch standalone hosts in the same workload domain together (default is $true).

        .PARAMETER FailedTaskId
        Specifies the task Id of a failed transition task.

        .PARAMETER HostRemediationOptionsJson
        Specifies a HostRemediationOptionsFile (JSON format).

        .PARAMETER JsonInputFile
        Specifies the json input file that contains at least one set of cluster/standalone host names and workload domains.

        .PARAMETER MaxBatchSize
        Specifies the maximum number of hosts per batch (valid range: 1-25, default is 25).

        .PARAMETER Parallel
        Specifies if cluster/standalone should be transitioned to vLCM image management in parallel (default is serial).

        .PARAMETER ResourceName
        Specifies cluster or standalone host to transition.

        .PARAMETER ResourceType
        Specifies if the resource is a cluster or standalone host.

        .PARAMETER RetryTransition
        Specifies if the transition task should be retried.

        .PARAMETER Silence
        Specifies if progress polling should be suppressed (useful for automation/background processing).

        .PARAMETER WorkloadDomainName
        Specifies which workload domain the cluster/standalone belongs to.

        .OUTPUTS
        None
        This function does not return a value. It transitions resources to vLCM image management.
    #>

    Param (
        [Parameter(Mandatory = $false)] [Bool]$BatchStandaloneHosts = $true,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$FailedTaskId,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$HostRemediationOptionsJson,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$JsonInputFile,
        [Parameter(Mandatory = $false)] [ValidateRange(1, 25)] [Int]$maxBatchSize = 25,
        [Parameter(Mandatory = $false)] [Switch]$Parallel,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$ResourceName,
        [Parameter(Mandatory = $false)] [ValidateSet("Cluster","Standalone Host")] [String]$ResourceType,
        [Parameter(Mandatory = $false)] [Switch]$RetryTransition,
        [Parameter(Mandatory = $false)] [Switch]$Silence,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$WorkloadDomainName
    )

    Write-LogMessage -Type DEBUG -Message "Entered Invoke-TransitionBaselineManagedResource function..."

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    # The retry transition workflow resumes an existing task rather than starts a new one.
    if ($RetryTransition) {
        try {
            $response = Invoke-VcfRetryTask -Id $FailedTaskId
        } catch {
            if ( $_.Exception.Message -match "TA_TASK_CAN_NOT_BE_RETRIED" ) {
                Write-LogMessage -Type ERROR -Message "Task cannot be retried."
                return
            } else {
                Write-LogMessage -Type ERROR -Message "Error is: $($_.Exception.Message)"
                return
            }
        }
    } else {
        # Menu-driven workflow.
        if (-not $Script:Headless) {
            # Refresh and display a list of vLCM baseline managed clusters.
            Write-LogMessage -Type INFO -AppendNewLine -Message "Scanning for vLCM baseline (VUM) managed clusters/standalone hosts..."
            $processTimer = Start-ProcessTimer
            $resourceListOutput = Get-BaselineManagedResources
            Stop-ProcessTimer -Timer $processTimer -Operation "Listing all baseline managed clusters and standalone hosts within transition workflow" -Interval "Seconds"
            Write-Host $resourceListOutput
        Write-Host "`nSelect the vLCM baseline clusters/standalone hosts to transition to vLCM image management.`n"
        $selectedResourceDetails = @()
        Do {
            $idSelection = Read-Host "Enter an id, a comma-delimited list of ids in order, or 'c' to cancel"

            # Fail fast if the user cancels the operation.
            if ($idSelection -eq 'c') {
                Write-LogMessage -Type INFO -AppendNewLine -Message "Cancellation requested. Returning to main menu."
                Show-AnyKey
                break
            }
            # Check if the Id selection is non-null.
            if ($idSelection) {
                $selectedResourceDetails = @(Get-BaselineManagedResources -IdSelection $idSelection)
            }
            # If no resources were returned then no Id / ResourceId mapping was found.
            if ($selectedResourceDetails.Count -eq 0) {
                if ($idSelection -eq "") {
                    $idSelection = "<EMPTY>"
                }
                Write-LogMessage -Type ERROR -Message "Invalid Id `"$idSelection`" chosen. Please try again."
            }
        } while ($selectedResourceDetails.Count -eq 0)

        Write-Host "`nConfirm you have reviewed the image compliance findings stored in `"$logFolder`" before proceeding.`n" -ForegroundColor Yellow
        $decision = New-ChoiceMenu -Question "Would you like to continue?" -DefaultAnswer no
        Write-Output ""
        # If the user declined to proceed, return to menu.
        if ($decision -eq 1) {
            # Format the message based on single or multiple resources.
            if ($selectedResourceDetails.Count -eq 1) {
                $resourceMessage = "$($selectedResourceDetails.ResourceType) `"$($selectedResourceDetails.ResourceName)`""
            } else {
                $ResourceType = $selectedResourceDetails[0].ResourceType
                $resourceNames = ($selectedResourceDetails.ResourceName) -join ", "
                $resourceMessage = "$ResourceType(s) `"$resourceNames`""
            }
            Write-LogMessage -Type INFO -Message "$resourceMessage transition to vLCM image management not accepted."
            Show-AnyKey
            break
        } else {
            # Format the message based on single or multiple resources.
            if ($selectedResourceDetails.Count -eq 1) {
                $resourceMessage = "$($selectedResourceDetails.ResourceType) `"$($selectedResourceDetails.ResourceName)`""
            } else {
                $ResourceType = $selectedResourceDetails[0].ResourceType
                $resourceNames = ($selectedResourceDetails.ResourceName) -join ", "
                $resourceMessage = "$ResourceType(s) `"$resourceNames`""
            }
            Write-LogMessage -Type INFO -AppendNewLine -Message "$resourceMessage transition to vLCM image management accepted."
        }
        # We leverage multiple decisions in this function.
        Remove-Variable -ErrorAction SilentlyContinue -Name Decision
        $decision = New-ChoiceMenu -Question "Would you like to use the default host remediation options?" -DefaultAnswer yes
        Write-Output ""
        $hostRemediationOptions = $null
        # If the user wants custom remediation options, launch configuration.
        if ($decision -eq 1) {
            Write-LogMessage -Type INFO -AppendNewLine -Message "For more information on host remediation, please visit: https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere-sdks-tools/8-0/automation-sdks-programming-guide/managing-the-lifecycle-of-hosts-and-clusters/configuring-remediation-settings.html"
            $hostRemediationOptions = Invoke-HostRemediationOptionsConfig -Action Create
        } else {
            Write-LogMessage -Type INFO -AppendNewLine -Message "Proceeding with default host remediation options as defined in vCenter..."
        }

    } else {

        # If a headless operation is called with the -HostRemediationOptionsJson argument, process the JSON. The common
        # Portions of the script will utilize the array.
        $hostRemediationOptions = $null
        if ($HostRemediationOptionsJson) {
            $result = ConvertFrom-JsonSafely -JsonFilePath $HostRemediationOptionsJson -VariableName "HostRemediationOptions"
            if (-not $result.Success) {
                Write-LogMessage -Type ERROR -Message "Failed to load host remediation options JSON: $($result.ErrorMessage)"
                Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR
            }
            $hostRemediationOptions = $result.JsonData
            # Convert true/false strings into booleans.
            switch ($hostRemediationOptions.QuickBootEnabled) {
                "true"  { $hostRemediationOptions.QuickBootEnabled = $true }
                "false" { $hostRemediationOptions.QuickBootEnabled = $false }
            }
        }
        # Headless (CLI workflow).  Extract resources from CLI inputs or JSON.
        Write-LogMessage -Type INFO -Message "Preparing for cluster/standalone-host transition(s)..."
        if ($JsonInputFile) {
            $result = ConvertFrom-JsonSafely -JsonFilePath $JsonInputFile -VariableName "ResourceNameInputs"
            if (-not $result.Success) {
                Write-LogMessage -Type ERROR -Message "Failed to load JSON input file: $($result.ErrorMessage)"
                Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR
            }
            $ResourceNameInputs = $result.JsonData
        } else {
            $ResourceNameInputs = [pscustomobject]@{
                WorkloadDomainName = $WorkloadDomainName
                ResourceName = $ResourceName
                ResourceType = $ResourceType
            }
        }

        # Initiate an array for selected resources before it's populated via for loop.
        $selectedResourceDetails = @()

        # Validate JSON parameters and commandline parameters before adding them to an array matching the structure.
        # The purpose of this is to save the user the trouble of looking up the cluster/host ID.
        foreach ($line in $ResourceNameInputs) {

            $domainResult = Get-WorkloadDomainId -WorkloadDomainName $line.WorkloadDomainName
            if (-not $domainResult.Success) {
                Write-LogMessage -Type ERROR -Message $domainResult.ErrorMessage
                Exit-WithCode -ExitCode $Script:ExitCodes.RESOURCE_NOT_FOUND
            }
            $workloadDomainId = $domainResult.WorkloadDomainId

            $resourceResult = Get-ResourceId -ResourceType $line.ResourceType -ResourceName $line.ResourceName -WorkloadDomainName $line.WorkloadDomainName
            if (-not $resourceResult.Success) {
                Write-LogMessage -Type ERROR -Message $resourceResult.ErrorMessage
                Exit-WithCode -ExitCode $Script:ExitCodes.RESOURCE_NOT_FOUND
            }
            $resourceId = $resourceResult.ResourceId

            $selectedResourceDetails += [pscustomobject]@{
                'ResourceId'          = $resourceId
                'ResourceName'        = $($line.ResourceName)
                'ResourceType'        = $($line.ResourceType)
                'WorkloadDomainId'    = $workloadDomainId
                'WorkloadDomainName'  = $($line.WorkloadDomainName)
            }
        }
    }

    # Prepare for transition itself.
    # Cache remediation options to avoid recomputing for each resource.
    $hostRemediationOptionsSpec = $null
    $clusterRemediationOptionsSpec = $null
    if ($hostRemediationOptions) {
        # For standalone hosts (includes PreRemediationPowerAction).
        $remediationFailureActionSpec = Initialize-VcfRemediationFailureAction -RetryDelay $hostRemediationOptions.RemediationRetryDelay -RetryCount $hostRemediationOptions.RemediationRetryCount -Action $hostRemediationOptions.RemediationFailureAction -ErrorAction SilentlyContinue
        $hostRemediationOptionsSpec = Initialize-VcfHostRemediationOptionsSpec -RemediationFailureAction $remediationFailureActionSpec -PreRemediationPowerAction $hostRemediationOptions.PreRemediationPowerAction -EnableQuickBoot $hostRemediationOptions.QuickBootEnabled -ErrorAction SilentlyContinue

        # For clusters (uses different API without PreRemediationPowerAction).
        # Clusters with FAIL action and RetryDelay=0 are rejected by API - use null instead.
        if ($hostRemediationOptions.RemediationFailureAction -eq 'FAIL' -and $hostRemediationOptions.RemediationRetryDelay -eq 0) {
            Write-LogMessage -Type DEBUG -Message "Cluster remediation: FAIL action with RetryDelay=0 detected. Setting clusterRemediationOptionsSpec to null (API doesn't accept RetryDelay=0)."
            $clusterRemediationOptionsSpec = $null
        } else {
            $clusterRemediationOptionsSpec = Initialize-VcfRemediationOptionsSpec -RemediationFailureAction $remediationFailureActionSpec -EnableQuickBoot $hostRemediationOptions.QuickBootEnabled -ErrorAction SilentlyContinue
        }
    } else {
        # If no remediation options are provided, use the default FAIL action with RetryDelay=0 and RetryCount=0.
        $remediationFailureActionSpec = Initialize-VcfRemediationFailureAction -RetryDelay 0 -RetryCount 0 -Action FAIL -ErrorAction SilentlyContinue
        $hostRemediationOptionsSpec = Initialize-VcfHostRemediationOptionsSpec -RemediationFailureAction $remediationFailureActionSpec -ErrorAction SilentlyContinue
        $clusterRemediationOptionsSpec = $null
    }

    # Check transition task status once before processing resources.
    $transitionTasksResult = Invoke-VcfGetTasks -TaskType VLCM_TRANSITION -ErrorAction SilentlyContinue
    $transitionChecks = if ($transitionTasksResult -and $transitionTasksResult.PSObject.Properties['Elements'] -and $transitionTasksResult.Elements) {
        @($transitionTasksResult.Elements | Where-Object { $_.PSObject.Properties['Status'] -and $_.Status -eq "In Progress" }).Count
    } else { 0 }
    if ($transitionChecks) {
        Write-LogMessage -Type INFO -Message "Currently $transitionChecks transition check(s) is/are being processed by SDDC Manager."
    }

    # Batch processing for standalone hosts (enabled by default).
    # Process batches using centralized function and track batched host IDs to prevent duplicate processing.
    $batchedHostIds = @()
    if ($BatchStandaloneHosts) {
        $batchedHostIds = Invoke-BatchedTransition `
            -SelectedResourceDetails $selectedResourceDetails `
            -HostRemediationOptionsSpec $hostRemediationOptionsSpec `
            -MaxBatchSize $maxBatchSize `
            -Parallel $Parallel `
            -Silence $Silence `
            -JsonInputFile $JsonInputFile
    }

    foreach($selectedResource in $selectedResourceDetails) {
        # Skip if this host was already processed in a batch.
        if ($BatchStandaloneHosts -and $selectedResource.ResourceType -eq "Standalone Host" -and $selectedResource.ResourceId -in $batchedHostIds) {
            Write-LogMessage -Type DEBUG -Message "Skipping host `"$($selectedResource.ResourceName)`" - already processed in batch."
            continue
        }

        # Refresh the access token before moving onto a new resource.
        Test-SddcManagerConnection

        $resourceId = $selectedResource.ResourceId
        $ResourceName = $selectedResource.ResourceName
        $ResourceType = $selectedResource.ResourceType
        $WorkloadDomainName = $selectedResource.WorkloadDomainName

        # Check if the compliance check has run, if not, fail fast.
        $imageId = $null
        switch ($ResourceType) {
            "Cluster" {
                $response = Invoke-VcfGetClusterImageCompliance -Id $resourceId -ErrorAction SilentlyContinue
                $imageId = if ($response -and $response.PSObject.Properties['ClusterImage'] -and $response.ClusterImage) { $response.ClusterImage.Id } else { $null }
            }
            "Standalone Host" {
                # Use cached workload domain ID from $selectedResource.
                $workloadDomainId = $selectedResource.WorkloadDomainId
                $response = Get-ImageComplianceElements -ResourceId $resourceId -WorkloadDomainId $workloadDomainId
                $imageId = if ($response -and $response.PSObject.Properties['Image'] -and $response.Image) { $response.Image.Id } else { $null }
            }
        }

        # Validate compliance check results.
        if (-not $response -or $response -eq "<NO_COMPLIANCE_RESULTS>") {
            Write-LogMessage -Type ERROR -Message "$ResourceType compliance check hasn't been run on `"$ResourceName`" in workload domain `"$WorkloadDomainName`"."
            Write-LogMessage -Type INFO -Message "This check must be run on each $ResourceType before it can be converted to vLCM image management."
            Write-LogMessage -Type INFO -Message "Skipping $ResourceType `"$ResourceName`" in workload domain `"$WorkloadDomainName`"..."
            continue
        }

        # Only perform this check if the SDDC Manager image is defined rather than auto-generated.
        if ($imageId) {
            # Verify Image still exists.
            $imageFound = Invoke-VcfGetPersonality -PersonalityId $imageId -ErrorAction SilentlyContinue

            if (-not $imageFound) {
                Write-LogMessage -Type ERROR -Message "Cannot find the vLCM image in SDDC Manager associated with $ResourceType `"$ResourceName`" during the last compliance check."
                Write-LogMessage -Type ERROR -Message "The image may have been removed in error.  Please re-run the compliance check on another image, or after re-uploading"
                Write-LogMessage -Type ERROR -Message "The missing image."
                continue
            }
        }

        if ($hostRemediationOptions) {
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "The following HostRemediationOptions will be applied: RemediationFailureAction: $($hostRemediationOptions.RemediationFailureAction), RemediationRetryDelay: $($hostRemediationOptions.RemediationRetryDelay), RemediationRetryCount: $($hostRemediationOptions.RemediationRetryCount), PreRemediationPowerAction: $($hostRemediationOptions.PreRemediationPowerAction), QuickBootEnabled: $($hostRemediationOptions.QuickBootEnabled)"
        }

        # Before beginning a transition check, make sure another transition check against that resource isn't already under way so we can fail fast.
        $duplicateTask = Find-ExistingTask -ClusterTaskType "VLCM_TRANSITION" -Operation "transition task" -ResourceId $resourceId -ResourceName $ResourceName -ResourceType $ResourceType -WorkloadDomainName $WorkloadDomainName -StandAloneHostTaskType "DOMAIN_VLCM_TRANSITION"

        # Skip this entity if we found a duplicate task Id.
        if ($duplicateTask -eq $true) {
            Write-LogMessage -Type ERROR -SuppressOutputToScreen -Message "$ResourceType `"$ResourceName`" failed duplicate transition task check."
            continue
        } else {
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "$ResourceType `"$ResourceName`" passed duplicate transition task check."
        }

        switch ($ResourceType) {
        "Standalone Host" {
            $TransitionResourceSpec = Initialize-VcfTransitionResourceSpec -Id $resourceId -Type "HOST" -ErrorAction SilentlyContinue
            # Use pre-computed remediation options.
            $transitionSpec = Initialize-VcfTransitionSpec -Resources $TransitionResourceSpec -HostRemediationOptions $hostRemediationOptionsSpec -ErrorAction SilentlyContinue
            $domainUpdateSpec = Initialize-VcfDomainUpdateSpec -TransitionSpec $transitionSpec -ErrorAction SilentlyContinue

            $response = $null
            try {
                $response = Invoke-VcfUpdateDomain -Id $workloadDomainId -DomainUpdateSpec $domainUpdateSpec -ErrorAction Stop
            } catch {
                # Catch the most common workflow errors and provide guidance.
                $errorMessage = $_.Exception.Message

                switch -Regex ($errorMessage) {
                    "vSphere Lifecycle Manager Images operation is currently working on this resource" {
                        Write-LogMessage -Type ERROR -Message "The transition of $ResourceType `"$ResourceName`" in Workload Domain `"$WorkloadDomainName`" to vLCM image management is already in progress."
                    }
                    "is already managed using vSphere Lifecycle Manager Images" {
                        Write-LogMessage -Type ERROR -Message "$ResourceType `"$ResourceName`" in Workload Domain `"$WorkloadDomainName`" has already been transitioned to image management."
                    }
                    default {
                        Write-LogMessage -Type ERROR -Message "An unexpected error occurred."
                        Write-LogMessage -Type ERROR -Message $errorMessage
                    }
                }

                if (-not $Script:Headless) {
                    Show-AnyKey
                    Show-MainMenu
                } else {
                    if ($JsonInputFile) {
                        Write-LogMessage -Type INFO -Message "Moving onto next resource..."
                    } else {
                        Exit-WithCode -ExitCode $Script:ExitCodes.OPERATION_FAILED
                    }
                }
            }
        }
        "Cluster" {
            # Use pre-computed cluster remediation options.
            if ($clusterRemediationOptionsSpec) {
                $clusterTransitionSpec = Initialize-VcfClusterTransitionSpec -RemediationOptionsSpec $clusterRemediationOptionsSpec -ErrorAction SilentlyContinue
            } else {
                $clusterTransitionSpec = Initialize-VcfClusterTransitionSpec -ErrorAction SilentlyContinue
            }
            $clusterUpdateSpec = Initialize-VcfClusterUpdateSpec -ClusterTransitionSpec $clusterTransitionSpec -ErrorAction SilentlyContinue

            Write-LogMessage -Type DEBUG -Message "API Call: Invoke-VcfUpdateCluster -Id $resourceId for cluster `"$ResourceName`""
            try {
                $response = Invoke-VcfUpdateCluster -Id $resourceId -ClusterUpdateSpec $clusterUpdateSpec -ErrorAction Stop
            } catch {
                # Catch the most common workflow errors and provide guidance.
                $errorMessage = $_.Exception.Message

                switch -Regex ($errorMessage) {
                    "vSphere Lifecycle Manager Images operation is currently working on this resource" {
                        Write-LogMessage -Type ERROR -Message "The transition of $ResourceType `"$ResourceName`" in Workload Domain `"$WorkloadDomainName`" to vLCM image management is already in progress."
                    }
                    "is already managed using vSphere Lifecycle Manager Images" {
                        Write-LogMessage -Type ERROR -Message "$ResourceType `"$ResourceName`" in Workload Domain `"$WorkloadDomainName`" has already been transitioned to image management."
                    }
                    default {
                        Write-LogMessage -Type ERROR -Message "An unexpected error occurred."
                        Write-LogMessage -Type ERROR -Message $errorMessage
                    }
                }

                if (-not $Script:Headless) {
                    Show-AnyKey
                    Show-MainMenu
                } else {
                    if ($JsonInputFile) {
                        Write-LogMessage -Type INFO -Message "Moving onto next resource..."
                    } else {
                        Exit-WithCode -ExitCode $Script:ExitCodes.GENERAL_ERROR
                    }
                }
                return  # Exit the function after error handling
            }
        }
        } # end switch ($ResourceType)

        Write-LogMessage -Type INFO -Message "Beginning vLCM image transition for $ResourceType `"$ResourceName`" in Workload Domain `"$WorkloadDomainName`"."
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "vLCM image transition for $ResourceType `"$ResourceName`" in Workload Domain `"$WorkloadDomainName`" initiated using Task ID `"$($response.Id)`"."

        # Write the full details on the transition to the log file.
        $jsonResponse = $response | ConvertTo-Json
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message $jsonResponse

        # Parallel or Silence flag will disable polling for task to complete.
        # Skip polling if EITHER parallel OR silence is enabled.
        if (-not ($Parallel -or $Silence)) {
            # Poll for task completion using the centralized function.
            Wait-TransitionCompletion `
                -TaskId $response.Id `
                -ResourceName $ResourceName `
                -ResourceType $ResourceType `
                -WorkloadDomainName $WorkloadDomainName | Out-Null
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

        .OUTPUTS
        None
        This function does not return a value. It deletes the temporary cluster from vCenter.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$temporaryClusterName,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$temporaryClusterVcenter
    )

    Write-LogMessage -Type DEBUG -Message "Entered Remove-TemporaryCluster function..."

    # Check if connected to vCenter.
    $null = Test-VcentersConnection

    # headless operations require input validation, which is otherwise handled, in interactive operations,.
    # by the issuing function.
    if ($Script:Headless) {

        $isConnectedVcenter = @(Get-Variable -Name 'DefaultViServers' -Scope Global -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value | Where-Object IsConnected -eq $true | Where-Object Name -eq $temporaryClusterVcenter)
        if ($isConnectedVcenter.Count -eq 0) {
            Write-LogMessage -Type ERROR -Message "vCenter `"$temporaryClusterVcenter`" not found in list of connected vCenters."
            Exit-WithCode -ExitCode $Script:ExitCodes.CONNECTION_ERROR
        }

        # check if the cluster exists in the chosen vCenter.
        $response = Get-Cluster -Server $temporaryClusterVcenter -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $temporaryClusterName} | Select-Object -First 1
        if (-not $response) {
            Write-LogMessage -Type ERROR -Message "Cluster `"$temporaryClusterName`" does not exist in vCenter `"$temporaryClusterVcenter`"."
            Exit-WithCode -ExitCode $Script:ExitCodes.RESOURCE_NOT_FOUND
        }
    }

    [array]$clusterHostMembersFound = @(Get-Cluster -Server $temporaryClusterVcenter -Name $temporaryClusterName -ErrorAction SilentlyContinue | Get-VMHost | Select-Object -ExpandProperty Name | Sort-Object)

    # Do not delete a cluster that has ESX hosts.
    if ($clusterHostMembersFound.Count -eq 0) {
        Write-LogMessage -Type INFO -Message "Safety check passed - No ESX hosts detected in cluster `"$temporaryClusterName`" in vCenter `"$temporaryClusterVcenter`"."
        try {
            Remove-Cluster -Server $temporaryClusterVcenter -Cluster $temporaryClusterName -Confirm:$false -ErrorAction Stop
        } catch {
            Write-LogMessage -Type ERROR -Message "Remove-Cluster threw an exception for `"$temporaryClusterName`" in `"$temporaryClusterVcenter`": $($_.Exception.Message)"
            Exit-WithCode -ExitCode $Script:ExitCodes.OPERATION_FAILED
        }

        $response = Get-Cluster -Server $temporaryClusterVcenter -Name $temporaryClusterName -ErrorAction SilentlyContinue
        if ($response) {
            Write-LogMessage -Type ERROR -Message "Cluster `"$temporaryClusterName`" in vCenter `"$temporaryClusterVcenter`" could not be deleted."
            Exit-WithCode -ExitCode $Script:ExitCodes.OPERATION_FAILED
        } else {
            Write-LogMessage -Type INFO -Message "Deleted cluster `"$temporaryClusterName`" in vCenter `"$temporaryClusterVcenter`"."
        }

    } else {
        Write-LogMessage -Type WARNING -AppendNewLine -Message "The script will not delete cluster `"$temporaryClusterName`" in vCenter `"$temporaryClusterVcenter`" due to the presence of existing hosts."
        foreach ( $esxHost in $clusterHostMembersFound) {
            Write-LogMessage -Type INFO -Message "ESX host `"$esxHost`" found in cluster `"$temporaryClusterName`""
        }
    }
}
#endregion

#region Status and Disconnect
Function Show-TaskStatus {

    <#
        .SYNOPSIS
        The function Show-TaskStatus displays the status of a type of task.

        .DESCRIPTION
        The function assists headless, silent operations where a task need not complete before
        the issuing command returns. Supports two task types: ComplianceCheck and SddcManagerImageUpload.
        For ComplianceCheck tasks, the function displays the most recent compliance check for each
        cluster and standalone host. Batched compliance checks (multiple hosts) are displayed with
        one entry per host. Results are sorted naturally by resource name.

        .EXAMPLE
        Show-TaskStatus -TaskType SddcManagerImageUpload

        .EXAMPLE
        Show-TaskStatus -TaskType ComplianceCheck

        .PARAMETER TaskType
        Specifies the type of task to display. Valid values are:
        - ComplianceCheck: Displays vLCM image compliance check tasks
        - SddcManagerImageUpload: Displays SDDC Manager image upload tasks

        .OUTPUTS
        None
        This function does not return a value. It displays task status information in a table format.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateSet("ComplianceCheck", "SddcManagerImageUpload")] [String]$TaskType
    )

    Write-LogMessage -Type DEBUG -Message "Entered Show-TaskStatus function..."
    Write-LogMessage -Type DEBUG -Message "=== Operation: Show Task Status for `"$TaskType`" Tasks ==="

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection

    Write-LogMessage -type INFO -Message "Scanning for $TaskType tasks..."

    switch ($TaskType) {
        "SddcManagerImageUpload" {
            $uploadTasksResult = Invoke-VcfGetTasks -ErrorAction SilentlyContinue
            $response = if ($uploadTasksResult -and $uploadTasksResult.PSObject.Properties['Elements'] -and $uploadTasksResult.Elements) { @($uploadTasksResult.Elements) | Where-Object { try { $_.Type -eq "PERSONALITY_UPLOAD" } catch { $false } } } else { $null }
        }
        "ComplianceCheck" {
            # Cache all resources once for efficient lookup later.
            Write-LogMessage -Type DEBUG -Message "Caching cluster and host information for efficient lookups..."
            $allClustersResult = Invoke-VcfGetClusters -ErrorAction SilentlyContinue
            $allClusters = if ($allClustersResult -and $allClustersResult.PSObject.Properties['Elements']) { $allClustersResult.Elements } else { $null }
            $allHostsResult = Invoke-VcfGetHosts -ErrorAction SilentlyContinue
            $allStandaloneHosts = if ($allHostsResult -and $allHostsResult.PSObject.Properties['Elements']) { $allHostsResult.Elements | Where-Object { $_.PSObject.Properties['IsStandalone'] -and $_.IsStandalone -eq $true } } else { $null }
            if (-not $allClusters -and -not $allStandaloneHosts) {
                Write-LogMessage -Type WARNING -Message "Unable to retrieve clusters or hosts from SDDC Manager. Task status display may be incomplete."
            }

            # Get resource Ids for clusters and hosts that are standalone.
            $resourceIds = @()
            if ($allClusters) { $resourceIds += @($allClusters | Select-Object -ExpandProperty Id) }
            if ($allStandaloneHosts) { $resourceIds += @($allStandaloneHosts | Select-Object -ExpandProperty Id) }

            # Get all compliance check tasks once (instead of per-resource).
            Write-LogMessage -Type DEBUG -Message "Retrieving all compliance check tasks..."
            $complianceTasksAllResult = Invoke-VcfGetTasks -ErrorAction SilentlyContinue
            [array]$allComplianceTasks = if ($complianceTasksAllResult -and $complianceTasksAllResult.PSObject.Properties['Elements'] -and $complianceTasksAllResult.Elements) {
                @($complianceTasksAllResult.Elements) | Where-Object { try { $_.Type -in ("VLCM_COMPLIANCE_CHECK","DOMAIN_VLCM_COMPLIANCE_CHECK") } catch { $false } }
            } else { @() }
            if (-not $allComplianceTasks) {
                Write-LogMessage -Type DEBUG -Message "No compliance check tasks found in SDDC Manager."
            }

            $response = @()
            foreach ($resourceId in $resourceIds) {
                # Filter the already-retrieved tasks (use -contains to handle both single and batched tasks).
                $latestTask = $allComplianceTasks | Where-Object { $_.PSObject.Properties['Resources'] -and $_.Resources.ResourceId -contains $resourceId } | Sort-Object CreationTimestamp | Select-Object -Last 1
                if ($latestTask) {
                    $response += $latestTask | Select-Object Name,Status,CreationTimestamp,CompletionTimestamp,Errors,Resources,Id
                }
            }

            # Deduplicate by Task ID (batched tasks will appear once per host in the batch).
            $response = $response | Sort-Object -Property Id -Unique
        }
    }

    # Exit if no results for the task type.
    if (-not ($response)) {
            Write-LogMessage -type INFO -Message "No $TaskType tasks found in `"$Global:SddcManagerFqdn`"."
            Show-AnyKey
            if (-not $Script:Headless) {
                Show-MainMenu
            }
            return
    } else {
        # Create lookup hashtables for O(1) resource name resolution (if ComplianceCheck).
        if ($TaskType -eq "ComplianceCheck") {
            Write-LogMessage -Type DEBUG -Message "Building resource name lookup tables..."
            $clusterLookup = @{}
            foreach ($cluster in $allClusters) {
                $clusterLookup[$cluster.Id] = $cluster.Name
            }

            $hostLookup = @{}
            foreach ($standaloneHost in $allStandaloneHosts) {
                $hostLookup[$standaloneHost.Id] = $standaloneHost.Fqdn
            }
        }

        $tasks = @()

        $tasks += [pscustomobject]@{
            'Name'                    = "Name"
            'ResourceType'            = "Type"
            'TaskStatus'              = "Status"
            'TaskCreationTimestamp'   = "Task Start Time"
            'TaskCompletionTimestamp' = "Task End Time"
            'TaskErrorMessage'        = "Error Message"
        }

        $tasks += [pscustomobject]@{
            'Name'                    = "----"
            'ResourceType'            = "-------------"
            'TaskStatus'              = "------"
            'TaskCreationTimestamp'   = "---------------"
            'TaskCompletionTimestamp' = "-------------"
            'TaskErrorMessage'        = "-------------"
        }

        # Log raw task responses for diagnostics.
        if ($response) {
            Write-LogMessage -Type DEBUG -Message "=== Raw Task Responses ($(@($response).Count) tasks) ==="
        }

        foreach ($line in $response) {

            # Determine resource type for better readability in logs.
            if ($TaskType -eq "ComplianceCheck") {
                if ($line.name -match "Check image compliance of cluster") {
                    $ResourceType = "Cluster"
                } else {
                    $ResourceType = "Standalone Host"
                }
            } else {
                $ResourceType = "Cluster"
            }

            # Create enhanced task object with ResourceType for JSON logging.
            # Handle multiple ResourceIds (for batch tasks) by joining them.
            # Filter out Domain resources, only include Cluster/Esxi resources.
            if ($line.Resources) {
                $resourceIds = ($line.Resources | Where-Object { $_.Type -in @("Cluster", "Esxi") } | ForEach-Object { $_.ResourceId }) | Where-Object { $_ }
                if ($resourceIds) {
                    $resourceIdString = $resourceIds -join ", "

                    # Resolve ResourceIds to friendly names using cached lookups.
                    $resourceNames = @()
                    foreach ($resId in $resourceIds) {
                        if ($clusterLookup -and $clusterLookup.ContainsKey($resId)) {
                            $resourceNames += $clusterLookup[$resId]
                        } elseif ($hostLookup -and $hostLookup.ContainsKey($resId)) {
                            $resourceNames += $hostLookup[$resId]
                        } else {
                            $resourceNames += "<UNKNOWN>"
                        }
                    }
                    $ResourceNamesString = $resourceNames -join ", "
                } else {
                    $resourceIdString = "N/A"
                    $ResourceNamesString = "N/A"
                }
            } else {
                $resourceIdString = "N/A"
                $ResourceNamesString = "N/A"
            }

            $taskLogObject = [ordered]@{
                Name              = $line.Name
                ResourceType      = $ResourceType
                ResourceId        = $resourceIdString
                ResourceNames     = $ResourceNamesString
                Status            = $line.Status
                CreationTimestamp = $line.CreationTimestamp
                CompletionTimestamp = $line.CompletionTimestamp
                Errors            = $line.Errors
                Id                = $line.Id
            }
            # Log line-by-line for consistency with formatted output.
            $taskJson = $taskLogObject | ConvertTo-Json
            foreach ($jsonLine in ($taskJson -split "`r?`n")) {
                if ($jsonLine) { Write-LogMessage -Type DEBUG -Message $jsonLine }
            }

            # Replace null data with more useful information.
            if ([String]::IsNullOrEmpty($line.CreationTimestamp)) {
                $taskStatus = "<NOT_CHECKED_YET>"
                $taskCreationTimestamp = "N/A"
            } else {
                $taskStatus = $line.Status
                $taskCreationTimestamp = $line.CreationTimestamp
            }

            if ([String]::IsNullOrEmpty($line.Errors)) {
                $taskError = "N/A"
            } else {
                $taskError = $line.Errors.Message
            }

            if ([String]::IsNullOrEmpty($line.CompletionTimestamp)) {
                $taskCompletionTimestamp = "N/A"
            } else {
                $taskCompletionTimestamp = $line.CompletionTimestamp
            }

            # Turn line.id into a variable for readability.
            $TaskId = $line.Id

            # $taskHandled is set to $true by branches that add their own rows,
            # preventing the generic add below from creating a duplicate entry.
            $taskHandled = $false

            switch ($TaskType) {
            "SddcManagerImageUpload" {
                $ResourceName = $line.Name -replace "vSphere Lifecycle Manager Image Upload "
            }
            "ComplianceCheck" {
                if ($line.name -match "Check image compliance of cluster") {
                    # Cluster compliance check - get resource ID from task.
                    try {
                        $taskDetails = Invoke-VcfGetTask -id $TaskId -ErrorAction Stop
                        $clusterResource = if ($taskDetails -and $taskDetails.Resources) { $taskDetails.Resources | Where-Object {$_.Type -eq "Cluster"} | Select-Object -First 1 } else { $null }
                        $resourceId = if ($clusterResource) { $clusterResource.ResourceId } else { $null }
                    } catch {
                        if ($_.Exception.Message -match "NOT_FOUND|404|does not exist") {
                            Write-LogMessage -Type DEBUG -Message "Task $TaskId not found (completed and removed). Skipping display."
                            $taskHandled = $true
                        } else {
                            $errorMsg = $_.Exception.Message
                            Write-LogMessage -Type WARNING -Message "Failed to retrieve task details for ${taskId}: $errorMsg"
                            $resourceId = $null
                        }
                    }

                    if (-not $taskHandled) {
                        if (-not $resourceId) {
                            $ResourceName = "<UNKNOWN>"
                        } else {
                            # Use cached lookup instead of API call.
                            $ResourceName = $clusterLookup[$resourceId]
                            if (-not $ResourceName) { $ResourceName = "<UNKNOWN>" }
                        }
                    }
                } else {
                    # Standalone host task - may be a single host or a batch.
                    try {
                        $taskDetails = Invoke-VcfGetTask -id $TaskId -ErrorAction Stop
                        $esxiResources = if ($taskDetails -and $taskDetails.Resources) { @($taskDetails.Resources | Where-Object {$_.Type -eq "ESXi"}) } else { @() }
                        $resourceIds = @($esxiResources | Select-Object -ExpandProperty ResourceId)
                    } catch {
                        if ($_.Exception.Message -match "NOT_FOUND|404|does not exist") {
                            Write-LogMessage -Type DEBUG -Message "Task $TaskId not found (completed and removed). Skipping display."
                            $taskHandled = $true
                        } else {
                            $errorMsg = $_.Exception.Message
                            Write-LogMessage -Type WARNING -Message "Failed to retrieve task details for ${taskId}: $errorMsg"
                            $resourceIds = @("<UNKNOWN>")
                        }
                    }

                    if (-not $taskHandled) {
                        if (-not $resourceIds) { $resourceIds = @("<UNKNOWN>") }

                        # Create one task entry per host (handles both single and batch tasks).
                        foreach ($resourceId in $resourceIds) {
                            $ResourceName = if ($resourceId -eq "<UNKNOWN>") { "<UNKNOWN>" } else { $hostLookup[$resourceId] }
                            if (-not $ResourceName) { $ResourceName = "<UNKNOWN>" }

                            $tasks += [pscustomobject]@{
                                'Name'                    = $ResourceName
                                'ResourceType'            = "Standalone Host"
                                'TaskStatus'              = $taskStatus
                                'TaskCreationTimestamp'   = $taskCreationTimestamp
                                'TaskCompletionTimestamp' = $taskCompletionTimestamp
                                'TaskErrorMessage'        = $taskError
                            }
                        }
                        $taskHandled = $true
                    }
                }
            }
            } # end switch ($TaskType)

            if ($taskHandled) { continue }

            # Determine resource type for table display.
            switch ($TaskType) {
                "SddcManagerImageUpload" { $displayResourceType = "Image Upload" }
                "ComplianceCheck"        { $displayResourceType = "Cluster" }
                default                  { $displayResourceType = "Unknown" }
            }

            $tasks += [pscustomobject]@{
                'Name'                    = $ResourceName
                'ResourceType'            = $displayResourceType
                'TaskStatus'              = $taskStatus
                'TaskCreationTimestamp'   = $taskCreationTimestamp
                'TaskCompletionTimestamp' = $taskCompletionTimestamp
                'TaskErrorMessage'        = $taskError
            }
        }

        # Close raw task responses section.
        if ($response) {
            Write-LogMessage -Type DEBUG -Message "=== End of Raw Task Responses ==="
        }

        # Only show the tabular view if the -silent option is not used.
        if (-not $Script:logOnly) {
           # Separate header rows (first 2 items) from data rows, sort data with natural sorting, then recombine.
           $headerRows = $tasks[0..1]
           # Natural sort: extract numeric portion from name for proper numeric ordering (esx-9 before esx-10).
           $dataRows = $tasks[2..($tasks.Count - 1)] | Sort-Object -Property @{Expression = {
               if ($_.Name -match '(\d+)') {
                   [int]$matches[1]
               } else {
                   0
               }
           }}, Name
           $sortedTasks = $headerRows + $dataRows

           # Log task status in JSON format, grouped by resource type (skip header rows).
           if ($dataRows.Count -gt 0) {
               Write-LogMessage -Type DEBUG -Message "=== Task Status ($($dataRows.Count) tasks) ==="

               # Group tasks by ResourceType for clearer logging.
               $groupedTasks = $dataRows | Group-Object -Property ResourceType

               foreach ($group in $groupedTasks) {
                   $ResourceTypeLabel = $group.Name
                   $taskCount = $group.Count
                   Write-LogMessage -Type DEBUG -Message "--- $ResourceTypeLabel Tasks ($taskCount) ---"

                   foreach ($task in $group.Group) {
                       $taskJson = $task | Select-Object Name, ResourceType, TaskStatus, TaskCreationTimestamp, TaskCompletionTimestamp, TaskErrorMessage | ConvertTo-Json
                       foreach ($line in ($taskJson -split "`r?`n")) {
                           if ($line) { Write-LogMessage -Type DEBUG -Message $line }
                       }
                   }
               }

               Write-LogMessage -Type DEBUG -Message "=== End of Task Status ==="
           }

           $sortedTasks | Format-Table -Property @{Expression = " " }, Name, ResourceType, TaskStatus, TaskCreationTimestamp, TaskCompletionTimestamp, TaskErrorMessage -Autosize -HideTableHeaders | Out-String | ForEach-Object { Write-Host $_.TrimEnd() }
        }
    }
}
Function Show-ResourceTransitionStatus {

    <#
        .SYNOPSIS
        The function Show-ResourceTransitionStatus displays the transition status of a cluster or standalone host.

        .DESCRIPTION
        The function assists headless operations (especially in silent mode) where the call returns before
        the transition is complete.

        .EXAMPLE
        Show-ResourceTransitionStatus ResourceName m01-cl01 -ResourceType Cluster -WorkloadDomainName m01

        .EXAMPLE
        Show-ResourceTransitionStatus -ReturnSummary

        .PARAMETER ResourceName
        Specifies which cluster standalone host's transition results to display.

        .PARAMETER ResourceType
        Specifies if the resource if a cluster or standalone host

        .PARAMETER ReturnSummary
        Specifies the option to display the status of all cluster transitions.

        .PARAMETER WorkloadDomainName
        Specifies which workload domain the cluster or standalone host belongs to.

        .OUTPUTS
        None
        This function does not return a value. It displays resource transition status information.
    #>

    Param (
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$ResourceName,
        [Parameter(Mandatory = $false)] [ValidateSet("Cluster","Standalone Host")] [String]$ResourceType,
        [Parameter(Mandatory = $false)] [Switch]$ReturnSummary,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$WorkloadDomainName
    )

    Write-LogMessage -Type DEBUG -Message "Entered Show-ResourceTransitionStatus function..."
    if ($ReturnSummary) {
        Write-LogMessage -Type DEBUG -Message "=== Operation: Show Resource Transition Status (Summary) ==="
    } else {
        Write-LogMessage -Type DEBUG -Message "=== Operation: Show Resource Transition Status for `"$ResourceType`" `"$ResourceName`" ==="
    }

    # Check if connected to SDDC Manager.
    Test-SddcManagerConnection
    if ($ReturnSummary) {
        Write-LogMessage -Type INFO -Message "Scanning for cluster/standalone hosts transition status messages..."
    } else {
        Write-LogMessage -Type INFO -Message "Scanning for details on transition status of $ResourceType `"$ResourceName`" in workload domain `"$WorkloadDomainName`"..."
    }

    if ($ReturnSummary) {
        $transitionResourceIds = @()
        # Get a list of all ResourceIDs that have a VLCM_TRANSITION task (cluster related) or DOMAIN_VLCM_TRANSITION task (SAH).
        # By performing two lookups, we avoid including Domain IDs.
        $clusterTasksResult = Invoke-VcfGetTasks -ErrorAction SilentlyContinue
        [array]$clusterTransitionTasks = if ($clusterTasksResult -and $clusterTasksResult.PSObject.Properties['Elements'] -and $clusterTasksResult.Elements) { @($clusterTasksResult.Elements) | Where-Object { try { $_.Type -eq "VLCM_TRANSITION" } catch { $false } } } else { @() }
        $transitionResourceIds += @($clusterTransitionTasks | Where-Object { try { $_.Resources } catch { $false } } | ForEach-Object { $_.Resources } | Where-Object { try { $_.Type -eq "Cluster" } catch { $false } } | Select-Object -ExpandProperty ResourceId | Sort-Object -Unique)
        $domainTasksResult = Invoke-VcfGetTasks -ErrorAction SilentlyContinue
        [array]$domainTransitionTasks = if ($domainTasksResult -and $domainTasksResult.PSObject.Properties['Elements'] -and $domainTasksResult.Elements) { @($domainTasksResult.Elements) | Where-Object { try { $_.Type -eq "DOMAIN_VLCM_TRANSITION" } catch { $false } } } else { @() }
        $transitionResourceIds += @($domainTransitionTasks | Where-Object { try { $_.Resources } catch { $false } } | ForEach-Object { $_.Resources } | Where-Object { try { $_.Type -eq "ESXi" } catch { $false } } | Select-Object -ExpandProperty ResourceId | Sort-Object -Unique)

        if (-not $transitionResourceIds) {
            Write-LogMessage -type INFO -Message "No cluster or standalone host transition tasks found in SDDC Manager `"$Global:SddcManagerFqdn`"."
            return
        }
        $resourceStatus = @()

        $resourceStatus += [pscustomobject]@{
            'ResourceName'            = "Resource Name"
            'ResourceType'            = "Resource Type"
            'WorkloadDomainName'      = "Workload Domain"
            'TransitionStatus'        = "Task Status"
            'TaskId'                  = "Task Id"
            'TaskCreationTimeStamp'   = "Task Start Time"
            'TaskCompletionTimeStamp' = "Task End Time"
        }

        $resourceStatus += [pscustomobject]@{
            'ResourceName'            = "-------------"
            'ResourceType'            = "-------------"
            'WorkloadDomainName'      = "---------------"
            'TransitionStatus'        = "-----------"
            'TaskId'                  = "--------"
            'TaskCreationTimeStamp'   = "---------------"
            'TaskCompletionTimeStamp' = "-------------"
        }
        foreach ($resourceId in $transitionResourceIds) {
            # This single query covers a lot of ground, but database structures and filters ensure validity.
            # DOMAIN_VLCM_TRANSITION is only valid for SAH queries, while VLCM_TRANSITION is only valid for VLCM_TRANSITION cluster queries.
            # There are two resourceIds per valid task, one for domain and one for cluster or ESX (depending on the type). The ResourceID filter ensures we match the correct one.
            # Use -contains to handle both single and batched tasks.
            $allTasksResult = Invoke-VcfGetTasks -ErrorAction SilentlyContinue
            [array]$allTaskElements = if ($allTasksResult -and $allTasksResult.PSObject.Properties['Elements'] -and $allTasksResult.Elements) {
                @($allTasksResult.Elements) | Where-Object { try { $null -ne $_.Type -and $null -ne $_.Resources } catch { $false } }
            } else { @() }
            $response = $allTaskElements | Where-Object { try { $_.Type -in ("DOMAIN_VLCM_TRANSITION","VLCM_TRANSITION") -and $_.Resources.ResourceId -contains $resourceId } catch { $false } } | Sort-Object -Desc CreationTimestamp | Select-Object -First 1
            $clusterTypeFound = if ($response -and $response.Resources) { $response.Resources | Where-Object { try { $_.Type -eq "Cluster" } catch { $false } } } else { $null }
            if ($clusterTypeFound) {
                $clusterResult = Invoke-VcfGetCluster -Id $resourceId -ErrorAction SilentlyContinue
                $derivedResourceName = if ($clusterResult) { $clusterResult.Name } else { $null }
                $workloadDomainId = if ($clusterResult -and $clusterResult.Domain) { $clusterResult.Domain.Id } else { $null }
                $derivedWorkloadDomainName = if ($workloadDomainId) { (Invoke-VcfGetDomain -Id $workloadDomainId -ErrorAction SilentlyContinue).Name } else { $null }
                $derivedResourceType = "Cluster"
            } else {
                $hostResult = Invoke-VcfGetHost -Id $resourceId -ErrorAction SilentlyContinue
                $derivedResourceName = if ($hostResult) { $hostResult.Fqdn } else { $null }
                $derivedWorkloadDomainName = if ($hostResult -and $hostResult.Domain) { $hostResult.Domain.Name } else { $null }
                $derivedResourceType = "Standalone Host"
            }
            if (-not $response ) {
                $transitionStatus = "N/A"
            } else {
                $transitionStatus = $response.Status
            }
            # A "1/1/1" date means the task is not yet complete. Display "N/A" for better readability.
            if (($($response.CompletionTimeStamp) -eq "1/1/0001 12:00:00 AM") -or  ([String]::IsNullOrEmpty($response.CompletionTimestamp))) {
                $taskCompletionTimestamp = "N/A"
            } else {
                $taskCompletionTimestamp = $($response.CompletionTimeStamp)
            }

            $resourceStatus += [pscustomobject]@{
                'ResourceName'            = $derivedResourceName
                'ResourceType'            = $derivedResourceType
                'WorkloadDomainName'      = $derivedWorkloadDomainName
                'TransitionStatus'        = $transitionStatus
                'TaskId'                  = if ($response) { $response.Id } else { $null }
                'TaskCreationTimeStamp'   = if ($response) { $response.CreationTimeStamp } else { $null }
                'TaskCompletionTimeStamp' = $taskCompletionTimestamp
            }
        }

        # Sort transition status by ResourceName with natural sorting (preserve header rows).
        $headerRows = $resourceStatus[0..1]
        $dataRows = $resourceStatus[2..($resourceStatus.Count - 1)] | Sort-Object -Property @{
            Expression = {
                # Extract prefix (non-numeric part).
                if ($_.ResourceName -match '^(.+?)(\d+)') {
                    $matches[1]
                } else {
                    $_.ResourceName
                }
            }
        }, @{
            Expression = {
                # Extract first number for numerical sort.
                if ($_.ResourceName -match '(\d+)') {
                    [int]$matches[1]
                } else {
                    0
                }
            }
        }, ResourceName
        $sortedResourceStatus = $headerRows + $dataRows

        # Log resource transition status in JSON format (skip header rows).
        if ($dataRows.Count -gt 0) {
            Write-LogMessage -Type DEBUG -Message "=== Resource Transition Status ($($dataRows.Count) resources) ==="
            $statusJson = $dataRows | Select-Object ResourceName, ResourceType, WorkloadDomainName, TransitionStatus, TaskCreationTimeStamp, TaskCompletionTimeStamp, TaskId | ConvertTo-Json -Depth 2
            foreach ($line in ($statusJson -split "`r?`n")) {
                if ($line) { Write-LogMessage -Type DEBUG -Message $line }
            }
            Write-LogMessage -Type DEBUG -Message "=== End of Resource Transition Status ==="
        }

        $sortedResourceStatus | Format-Table -Property @{Expression = " " }, ResourceName, ResourceType, WorkloadDomainName, TransitionStatus, TaskCreationTimeStamp, TaskCompletionTimeStamp -Autosize -HideTableHeaders | Out-String | ForEach-Object { Write-Host $_.TrimEnd() }
    }

    if ($ResourceName -and $WorkloadDomainName) {

        $domainsStatusResult = Invoke-VcfGetDomains -ErrorAction SilentlyContinue
        $response = if ($domainsStatusResult -and $domainsStatusResult.PSObject.Properties['Elements']) { $domainsStatusResult.Elements | Where-Object Name -eq $WorkloadDomainName | Select-Object -First 1 } else { $null }
        if (-not $response) {
            Write-LogMessage -Type ERROR -Message "Workload domain `"$WorkloadDomainName`" does not exist"
            Exit-WithCode -ExitCode $Script:ExitCodes.RESOURCE_NOT_FOUND
        }
        $resourceResult = Get-ResourceId -ResourceType $ResourceType -ResourceName $ResourceName -WorkloadDomainName $WorkloadDomainName
        if (-not $resourceResult.Success) {
            Write-LogMessage -Type ERROR -Message $resourceResult.ErrorMessage
            Exit-WithCode -ExitCode $Script:ExitCodes.RESOURCE_NOT_FOUND
        }
        $resourceId = $resourceResult.ResourceId

        # Use -contains to handle both single and batched tasks.
        $responseTasksResult = Invoke-VcfGetTasks -ErrorAction SilentlyContinue
        [array]$responseTaskElements = if ($responseTasksResult -and $responseTasksResult.PSObject.Properties['Elements'] -and $responseTasksResult.Elements) {
            @($responseTasksResult.Elements) | Where-Object { try { $null -ne $_.Type -and $null -ne $_.Resources } catch { $false } }
        } else { @() }
        $response = $responseTaskElements | Where-Object { try { $_.Type -in ("DOMAIN_VLCM_TRANSITION","VLCM_TRANSITION") -and $_.Resources.ResourceId -contains $resourceId } catch { $false } } | Sort-Object -Desc CreationTimestamp | Select-Object -First 1

        if (-not $response) {
            Write-LogMessage -Type ERROR -Message "No $ResourceType transition task found for `"$ResourceName`" in Workload Domain `"$WorkloadDomainName`"."
            Exit-WithCode -ExitCode $Script:ExitCodes.RESOURCE_NOT_FOUND
        }

        Write-LogMessage -Type INFO -Message "The vLCM image transition details for vLCM image transition task for $ResourceType `"$ResourceName`" in Workload Domain `"$WorkloadDomainName`":"

        if ($response.Errors) {
            Write-LogMessage -Type INFO -Message "The $ResourceType transition for `"$ResourceName`" failed with error: $($response.Errors)"
        }
        [array]$subTasks = if ($response.SubTasks) { @($response.SubTasks) } else { @() }
        $inProgressTask = $subTasks | Where-Object -Property Status -eq "IN_PROGRESS" | Select-Object -First 1
        if ($inProgressTask -and $inProgressTask.Name) {
            Write-LogMessage -Type INFO -Message "The current sub-step is being processed: $($inProgressTask.Name)"
        }
        $totalStepCount = @($subTasks).Count
        $currentStepCount = @($subTasks | Where-Object -Property Status -eq "SUCCESSFUL").Count

        Write-LogMessage -Type INFO -Message "$currentStepCount steps out of $totalStepCount steps completed."
        Write-LogMessage -Type INFO -Message "Status of the transition is: $($response.Status)"
        if ($($response.Status) -eq "Failed") {
            # Use -contains to handle both single and batched tasks.
            $failedTasksResult = Invoke-VcfGetTasks -ErrorAction SilentlyContinue -TaskStatus "Failed"
            [array]$failedTaskElements = if ($failedTasksResult -and $failedTasksResult.PSObject.Properties['Elements'] -and $failedTasksResult.Elements) { @($failedTasksResult.Elements) | Where-Object { try { $null -ne $_.Type -and $null -ne $_.Resources } catch { $false } } } else { @() }
            $failedTask = $failedTaskElements | Where-Object { try { $_.Type -in ("DOMAIN_VLCM_TRANSITION","VLCM_TRANSITION") -and $_.Resources.ResourceId -contains $resourceId } catch { $false } } | Where-Object { try { $_.SubTasks.Status -eq "Failed" } catch { $false } } | Select-Object -First 1
            if ($failedTask -and $failedTask.SubTasks) {
                $failedSubTask = $failedTask.SubTasks | Where-Object { $_.Errors } | Select-Object -First 1
                if ($failedSubTask -and $failedSubTask.Errors -and $failedSubTask.Errors.Message) {
                    Write-LogMessage -Type INFO -Message "Subtask failure message: $($failedSubTask.Errors.Message)"
                }
            }
            if ($failedTask) {
                Write-LogMessage -Type INFO -Message "You may re-try transition by running the script with the arguments `"-RetryTransition -TaskId `"$($failedTask.ID)`"."
            }
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

        .OUTPUTS
        None
        This function does not return a value. It disconnects from SDDC Manager.
    #>

    Param (
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$overrideQuestion,
        [Parameter(Mandatory = $false)] [Switch]$NoPrompt,
        [Parameter(Mandatory = $false)] [Switch]$Silence
    )

    Write-LogMessage -Type DEBUG -Message "Entered Disconnect-SddcManager function..."

    $sddcConn = Get-Variable -Name 'defaultSddcManagerConnections' -ErrorAction SilentlyContinue
    if (-not ($sddcConn -and $sddcConn.Value -and (@($sddcConn.Value) | Where-Object { $_.IsConnected } | Select-Object -First 1))) {
        if (-not $Silence) {
            Write-LogMessage -Type INFO -Message "No SDDC Manager connection detected."
        }
    } else {
        # Declare SDDC Manager variable so the name can be logged after disconnection.
        $Global:SddcManagerFqdn = $sddcConn.Value.Name

        $decision = -1
        if (-not $NoPrompt) {
            if ($overrideQuestion) {
                $decision = New-ChoiceMenu -Question "$overrideQuestion" -DefaultAnswer no
            } else {
                $decision = New-ChoiceMenu -Question "Would you like to disconnect from `"$Global:SddcManagerFqdn`"" -DefaultAnswer no
            }
        }

        # Check if the user chose option 0, yes do disconnect from vCenter.
        if (($decision -eq 0) -or $NoPrompt) {
            $activeSddcConnForDisconnect = @($defaultSddcManagerConnections) | Where-Object { $_.IsConnected } | Select-Object -First 1
            Disconnect-VcfSddcManagerServer -Server $activeSddcConnForDisconnect.Name
            if ($?) {
                if ($Silence) {
                    Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Successfully disconnected from SDDC Manager `"$Global:SddcManagerFqdn`"."
                } else {
                    Write-LogMessage -Type INFO -AppendNewLine -Message "Successfully disconnected from SDDC Manager `"$Global:SddcManagerFqdn`"."
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

        .OUTPUTS
        None
        This function does not return a value. It disconnects from all vCenter servers.
    #>

    Param (
        [Parameter(Mandatory = $false)] [Switch]$Silence,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$VcenterName

    )

    Write-LogMessage -Type DEBUG -Message "Entered Disconnect-Vcenter function..."

    if ($VcenterName) {
        Disconnect-VIServer -Server $VcenterName -Force -Confirm:$false -ErrorAction SilentlyContinue
        if ($Silence) {
            Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Successfully disconnected from vCenter `"$VcenterName`"."
        } else {
           Write-LogMessage -Type INFO -AppendNewLine -Message "Successfully disconnected from vCenter `"$VcenterName`"."
        }
        return
    }

    [array]$ConnectedVcenters = @(Get-Variable -Name 'DefaultViServers' -Scope Global -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value | Where-Object IsConnected -eq $true | Select-Object -ExpandProperty Name)

    if ($ConnectedVcenters) {

        foreach ($VcenterName in $ConnectedVcenters) {
            Disconnect-VIServer -Server $VcenterName -Force -Confirm:$false -ErrorAction SilentlyContinue
            if ($?) {
                if ($Silence) {
                    Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Successfully disconnected from vCenter `"$VcenterName`"."
                } else {
                    Write-LogMessage -Type INFO -AppendNewLine -Message "Successfully disconnected from vCenter `"$VcenterName`"."
                }
            } else {
                Write-LogMessage -Type ERROR -Message "Failed to disconnect from vCenter `"$VcenterName`"."
            }
        }

        # Handle an edge case where non-tracked vCenters are connected.
        [array]$stillConnected = @(Get-Variable -Name 'DefaultViServers' -Scope Global -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value | Where-Object IsConnected -eq $true)
        if ($stillConnected.Count -gt 0) {
            Disconnect-VIServer -Server * -Force -Confirm:$false -ErrorAction SilentlyContinue
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

        .OUTPUTS
        None
        This function does not return a value. It displays incomplete tasks in a formatted table.
    #>


    # Check if connected to SDDC Manager.
    Write-LogMessage -Type DEBUG -Message "Entered Show-IncompleteTasks function..."

    Test-SddcManagerConnection

    # It is sufficient to just look for a failed task, as there's precisely one task Id per cluster.
    # transition. The task Id can be resumed, but another one cannot be spawned. Therefore a cluster.
    # cannot have a task with status failed and another with status successful.

    $incompleteTasksResult = Invoke-VcfGetTasks -TaskType "VLCM_TRANSITION" -TaskStatus "Failed" -ErrorAction SilentlyContinue
    $response = if ($incompleteTasksResult -and $incompleteTasksResult.PSObject.Properties['Elements']) { $incompleteTasksResult.Elements } else { $null }

    if (-not $response) {
        Write-LogMessage -Type INFO -Message "No failed vLCM transition tasks found."
        Show-AnyKey
        if (-not $Script:Headless) {
            Show-MainMenu
        }
        return
    }

    $vlcmTransitionDisplayObject = @()
    $vlcmTransitionIndex = 1

    $vlcmTransitionDisplayObject += [pscustomobject]@{
        'Id'                  = 'Id'
        'ClusterName'         = "Cluster Name"
        'WorkloadDomainName'  = "Workload Domain"
        'TaskId'              = "Task Id"
        'TaskCompletionTime'  = "Task Completion Time"
    }

    $vlcmTransitionDisplayObject += [pscustomobject]@{
        'Id'                  = "--"
        'ClusterName'         = "------------"
        'WorkloadDomainName'  = "---------------"
        'TaskId'              = "-------"
        'TaskCompletionTime'  = "--------------------"
    }

    foreach ($line in $response) {
        $clusterId = ($line.Resources | Where-Object { $_.Type -eq "Cluster" } | Select-Object -First 1).ResourceId
        if (-not $clusterId) { $clusterId = ($line.Resources | Select-Object -First 1 | Select-Object -ExpandProperty ResourceId) }
        $cluster = if ($clusterId) { Invoke-VcfGetCluster -Id $clusterId -ErrorAction SilentlyContinue } else { $null }
        $clusterName = if ($cluster) { $cluster.Name } else { "<UNKNOWN>" }
        $domainId = if ($cluster -and $cluster.Domain) { $cluster.Domain.Id } else { $null }
        $WorkloadDomainName = if ($domainId) { (Invoke-VcfGetDomain -Id $domainId -ErrorAction SilentlyContinue).Name } else { "<UNKNOWN>" }
        $vlcmTransitionDisplayObject += [pscustomobject]@{
            'Id'                 = $vlcmTransitionIndex
            'ClusterName'        = $clusterName
            'WorkloadDomainName' = $WorkloadDomainName
            'TaskId'             = $line.Id
            'TaskCompletionTime' = $line.CompletionTimeStamp
        }
        Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "`"$clusterName`" transition task found with Id $($line.Id) from $($line.CompletionTimeStamp)"
        $vlcmTransitionIndex++
    }
    # If VlcmTransitionIndex is not incremented from the default value no failures were found.
    if ($vlcmTransitionIndex -eq "1") {
        Write-LogMessage -Type INFO -Message "No failed vLCM cluster transition tasks located."
        Show-AnyKey
        if (-not $Script:Headless) {
            Show-MainMenu
        }
        return
    }

    # Sort failed transitions by ClusterName with natural sorting (preserve header rows).
    $headerRows = $vlcmTransitionDisplayObject[0..1]
    $dataRows = $vlcmTransitionDisplayObject[2..($vlcmTransitionDisplayObject.Count - 1)] | Sort-Object -Property @{
        Expression = {
            if ($_.ClusterName -match '(.+?)(\d+)$') {
                [int]$matches[2]
            } else {
                0
            }
        }
    }, ClusterName
    $vlcmTransitionDisplayObject = $headerRows + $dataRows

    # headless output is almost identical to non-headless (only the Id is elided)
    if ($Script:Headless) {
        Write-Host "Clusters that were not successfully transitioned to vLCM image management:`n" -ForegroundColor Green;
        $vlcmTransitionDisplayObject | Format-Table -Property @{Expression = " " }, ClusterName, WorkloadDomainName, TaskId, TaskCompletionTime  -Autosize -HideTableHeaders | Out-Host
        Exit-WithCode -ExitCode $Script:ExitCodes.SUCCESS
    }
    Write-LogMessage -Type INFO -AppendNewLine -Message "Cluster transition resumption workflow:"
    Write-Host "Clusters that were not successfully transitioned to vLCM image management:`n" -ForegroundColor Green;
    $vlcmTransitionDisplayObject | Format-Table -Property @{Expression = " " }, Id, ClusterName, WorkloadDomainName, TaskId, TaskCompletionTime  -Autosize -HideTableHeaders | Out-Host

    Do {
        Write-Output ""
        $VersionSelection = Read-Host "Enter the id of an image or press 'c' to cancel"

        if ($VersionSelection -eq "c") {
            Show-AnyKey
             Show-MainMenu
        }
        $isValidId = ($VersionSelection -in $($vlcmTransitionDisplayObject.Id))
        if (-not $isValidId) {
            Write-LogMessage -Type ERROR -Message "Invalid selection. $VersionSelection identifier not found."
        }
        } While (-not $isValidId)

    $selectedTask = $vlcmTransitionDisplayObject | Where-Object {$_.Id -eq $VersionSelection} | Select-Object -First 1
    $failedTaskId = if ($selectedTask) { $selectedTask.TaskId } else { $null }
    $failedClusterName = if ($selectedTask) { $selectedTask.ClusterName } else { $null }

    Write-LogMessage -Type INFO -Message "Preparing to retry vLCM image transition for `"$failedClusterName`" using task ID `"$failedTaskId`"."
    Invoke-TransitionBaselineManagedResource -RetryTransition -FailedTaskId $failedTaskId
}
#endregion

#region Environment and Menus
Function Get-InstalledPowerCliModules {

    <#
        .SYNOPSIS
        Returns a hashtable of the highest installed versions of relevant PowerCLI modules.

        .DESCRIPTION
        Performs a single Get-Module -ListAvailable scan for all five relevant PowerCLI packages.
        The hashtable is keyed by module name; each value is the highest-version ModuleInfo object
        found on PSModulePath. Returns an empty hashtable if no matching modules are installed.

        Results are cached in $Script:InstalledPowerCliModules for the lifetime of the session so
        that Get-EnvironmentSetup and Get-Preconditions (both called at startup) share one scan.

        .OUTPUTS
        [hashtable]
        Keys: VCF.PowerCLI, VMware.PowerCLI, VMware.VimAutomation.Core, VMware.VimAutomation.Common,
        VMware.VimAutomation.Sdk. Any absent module is simply absent from the hashtable.
    #>

    [CmdletBinding()]
    [OutputType([hashtable])]
    Param ()

    if ($null -ne $Script:InstalledPowerCliModules) {
        return $Script:InstalledPowerCliModules
    }

    $moduleNames = @('VCF.PowerCLI', 'VMware.PowerCLI', 'VMware.VimAutomation.Core', 'VMware.VimAutomation.Common', 'VMware.VimAutomation.Sdk')
    $modules = @{}
    Get-Module -ListAvailable -Name $moduleNames -ErrorAction SilentlyContinue |
        Sort-Object -Property Version -Descending |
        Group-Object -Property Name |
        ForEach-Object { $modules[$_.Name] = $_.Group[0] }
    $Script:InstalledPowerCliModules = $modules
    return $modules
}

Function Get-EnvironmentSetup {

    <#
        .SYNOPSIS
        The function Get-EnvironmentSetup logs user environment details.

        .DESCRIPTION
        The function facilitates troubleshooting by populating each day's log files with useful runtime details.

        .EXAMPLE
        Get-EnvironmentSetup

        .OUTPUTS
        None
        This function does not return a value. It logs environment setup information.
    #>

    Write-LogMessage -Type DEBUG -Message "Entered Get-EnvironmentSetup function..."

    $powerShellRelease = $($PSVersionTable.PSVersion).ToString()

    $envModules = Get-InstalledPowerCliModules

    $vcfPowerCliRelease = if ($envModules['VCF.PowerCLI']) { $envModules['VCF.PowerCLI'].Version } else { $null }
    $vmwarePowerCliRelease = if ($envModules['VMware.PowerCLI']) { $envModules['VMware.PowerCLI'].Version } else { $null }
    $vimCoreRelease = if ($envModules['VMware.VimAutomation.Core']) { $envModules['VMware.VimAutomation.Core'].Version } else { $null }
    $vimCommonRelease = if ($envModules['VMware.VimAutomation.Common']) { $envModules['VMware.VimAutomation.Common'].Version } else { $null }
    $vimSdkRelease = if ($envModules['VMware.VimAutomation.Sdk']) { $envModules['VMware.VimAutomation.Sdk'].Version } else { $null }

    $operatingSystem = $($PSVersionTable.OS)
    $macOsVersion = $null
    $windowsVersion = $null

    # Work-around for MacOS which displays Darwin kernel release from $($PSVersionTable.OS). However, if this call fails, revert to what we know.
    if ($isMacOS) {
        try {
            $macOsVersion = & sw_vers -productVersion
        } catch {
            Write-LogMessage -Type DEBUG -Message "Failed to get macOS version: $_"
        }
    }
    if ($macOsVersion) {
        $operatingSystem = $macOsVersion
    }

    # See if we can get better visibility into the Windows release.
    if ($isWindows) {
        try {
            $windowsVersion = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).Caption
        } catch {
            Write-LogMessage -Type DEBUG -Message "Failed to get Windows version: $_"
        }
    }
    if ($windowsVersion) {
        $operatingSystem = $windowsVersion
    }

    Show-Version -Silence

    Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Client PowerShell version is $powerShellRelease"

    if ($vcfPowerCliRelease) { Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Client VCF.PowerCLI version is $vcfPowerCliRelease." }
    if ($vmwarePowerCliRelease) { Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Client VMware.PowerCLI version is $vmwarePowerCliRelease." }
    if ($vimCoreRelease) { Write-LogMessage -Type DEBUG -Message "VMware.VimAutomation.Core version is $vimCoreRelease." }
    if ($vimCommonRelease) { Write-LogMessage -Type DEBUG -Message "VMware.VimAutomation.Common version is $vimCommonRelease." }
    if ($vimSdkRelease) { Write-LogMessage -Type DEBUG -Message "VMware.VimAutomation.Sdk version is $vimSdkRelease." }
    if (-not $vcfPowerCliRelease -and -not $vmwarePowerCliRelease) {
        Write-LogMessage -Type ERROR -SuppressOutputToScreen -Message "Client PowerCLI not installed."
    }

    Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Client Operating System is $operatingSystem"

}
Function Get-Preconditions {

    <#
        .SYNOPSIS
        The function Get-Preconditions checks to if the script's preconditions are met.

        .DESCRIPTION
        The function will exit if any conditions are not met.

        .PARAMETER SkipVersionCheck
        When specified, skips the VCF.PowerCLI version compatibility check. The module must still
        be installed; only the minimum-version comparison is bypassed. Use only when you are certain
        your installed version is compatible.

        .EXAMPLE
        Get-Preconditions

        .EXAMPLE
        Get-Preconditions -SkipVersionCheck

        .OUTPUTS
        None
        This function does not return a value. It checks preconditions and exits if any fail.
   #>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)] [Switch]$SkipVersionCheck
    )

    # PowerCLI Module and Version Check.
    Write-LogMessage -Type DEBUG -Message "Entered Get-Preconditions function (SkipVersionCheck: $SkipVersionCheck)..."

    # VCF.PowerCLI 9 ships VMware.VimAutomation.Core (and Common/Sdk) at the 13.4-era version.
    # VMware.PowerCLI 13.3 ships those same submodules at the 13.3-era version. Having both umbrella
    # packages installed causes version ambiguity and potential type conflicts. Anything below 13.4
    # in a shared submodule indicates a VMware.PowerCLI 13.3 installation may be interfering.
    $minimumSubmoduleVersion = [version]'13.4.0'

    $foundModules = Get-InstalledPowerCliModules

    $vcfPowerCliModule = $foundModules['VCF.PowerCLI']
    $vmwarePowerCliModule = $foundModules['VMware.PowerCLI']
    $vimCoreModule = $foundModules['VMware.VimAutomation.Core']
    $vimCommonModule = $foundModules['VMware.VimAutomation.Common']
    $vimSdkModule = $foundModules['VMware.VimAutomation.Sdk']

    # VMware.PowerCLI alone is not sufficient — only VCF.PowerCLI is supported.
    if ($vmwarePowerCliModule -and -not $vcfPowerCliModule) {
        Write-LogMessage -Type EXCEPTION -AppendNewLine -Message "VMware.PowerCLI version $($vmwarePowerCliModule.Version) detected. This script requires VCF.PowerCLI $minimumVcfPowerCliVersion or later. Please upgrade."
        Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
    }

    # VCF.PowerCLI must be installed.
    if (-not $vcfPowerCliModule) {
        Write-LogMessage -Type EXCEPTION -AppendNewLine -Message "VCF.PowerCLI not found. Please install VCF.PowerCLI $minimumVcfPowerCliVersion or later."
        Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
    }

    # VCF.PowerCLI must meet the minimum version requirement.
    $installedVersion = $vcfPowerCliModule.Version
    if ($env:PESTER_TEST_MODE -ne "1" -and -not $SkipVersionCheck -and $installedVersion -lt [Version]$minimumVcfPowerCliVersion) {
        Write-LogMessage -Type EXCEPTION -AppendNewLine -Message "VCF.PowerCLI version $installedVersion is installed. This script requires VCF.PowerCLI $minimumVcfPowerCliVersion or later. Please upgrade."
        Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
    }

    # Conflict check: VMware.PowerCLI 13.3 ships 13.3-era submodules (VMware.VimAutomation.Core 13.3.x,
    # VMware.VimAutomation.Common 13.3.x, VMware.VimAutomation.Sdk 13.3.x) that conflict with the
    # 13.4-era submodules required by VCF.PowerCLI 9. PowerShell loads the highest available version,
    # so 13.4 wins when both are present, but the VMware.PowerCLI 13.3 manifest remains and can cause
    # unexpected behaviour. Advise removal of the conflicting umbrella package.
    if ($vmwarePowerCliModule -and [version]$vmwarePowerCliModule.Version -lt $minimumSubmoduleVersion) {
        Write-LogMessage -Type WARNING -Message "VMware.PowerCLI $($vmwarePowerCliModule.Version) is installed alongside VCF.PowerCLI $installedVersion. VMware.PowerCLI 13.3 ships 13.3-era submodule versions (e.g. VMware.VimAutomation.Core 13.3.x) that conflict with VCF.PowerCLI 9's required 13.4-era submodules."
        Write-LogMessage -Type ADVISORY -Message "To eliminate potential submodule conflicts: Uninstall-Module -Name VMware.PowerCLI -AllVersions"
    }

    # Submodule version check: if VMware.VimAutomation.Core (the key shared submodule) is below 13.4,
    # the 13.3-era version may be what PowerShell actually loads, breaking VCF.PowerCLI 9 compatibility.
    foreach ($submoduleEntry in @(
        [pscustomobject]@{ Name = 'VMware.VimAutomation.Core';   Module = $vimCoreModule }
        [pscustomobject]@{ Name = 'VMware.VimAutomation.Common'; Module = $vimCommonModule }
        [pscustomobject]@{ Name = 'VMware.VimAutomation.Sdk';    Module = $vimSdkModule }
    )) {
        if ($submoduleEntry.Module -and [version]$submoduleEntry.Module.Version -lt $minimumSubmoduleVersion) {
            Write-LogMessage -Type WARNING -Message "$($submoduleEntry.Name) $($submoduleEntry.Module.Version) is the highest available version. VCF.PowerCLI 9 requires $($submoduleEntry.Name) 13.4 or later — a VMware.PowerCLI 13.3 installation may be overriding the required submodule version."
        }
    }

    if ($env:PESTER_TEST_MODE -eq "1") {
        Write-LogMessage -Type DEBUG -Message "Running in test mode - skipping VCF.PowerCLI version check."
    } elseif ($SkipVersionCheck) {
        Write-LogMessage -Type WARNING -Message "VCF.PowerCLI version check skipped (-SkipPowercliVersionCheck). Installed: $installedVersion. Required: $minimumVcfPowerCliVersion. Proceed with caution."
    } else {
        Write-LogMessage -Type DEBUG -Message "VCF.PowerCLI version $installedVersion meets minimum requirement ($minimumVcfPowerCliVersion)."
    }

    # VCF.PowerCLI cmdlet availability is validated by the version check above.
    # A verified minimum version guarantees the required cmdlets are present; calling Get-Command
    # on the full cmdlet list forces a 26-second module assembly load on first run before the
    # menu appears. Any missing cmdlet will surface at first use with a clear error message.
    #
    # Get-PowerCLIConfiguration (Multiple VIServer mode check) is deferred to Connect-Vcenter
    # via Test-PowerCliMultipleVIServerMode. The VCF.PowerCLI module is already loaded by the
    # time Connect-Vcenter runs (Connect-SddcManager uses Connect-VcfSddcManagerServer first),
    # so the check takes milliseconds instead of forcing an early 26-second first-load here.

    $currentPSVersion = ($PSVersionTable.PSVersion.Major),($PSVersionTable.PSVersion.Minor) -join "."

    If ( $currentPSVersion -lt $pSVersionMinVersion ) {
        Write-LogMessage -Type EXCEPTION -Message "Powershell $pSVersionMinVersion or higher is required."
        Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
    }

    # Windows 2012 and below do not support the default TLS cyphers required for recent versions of Powershell and PowerCLI.
    if ($isWindows) {
        if ([Environment]::OSVersion.Version.Major -lt 10) {
          Write-LogMessage -Type EXCEPTION -Message "Windows Server 2016+ or Windows 10+ required."
          Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR
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

        .OUTPUTS
        None
        This function does not return a value. It displays the script version and exits.
    #>

    Param (
        [Parameter(Mandatory = $false)] [Switch]$Silence
    )
    Write-LogMessage -Type DEBUG -Message "Entered Show-Version function..."

    Write-LogMessage -Type INFO -SuppressOutputToScreen:$Silence -Message "Version: $scriptVersion"
}
Function Invoke-LogCollection {

    <#
        .SYNOPSIS
        Creates a timestamped zip archive of all log files in the logs subdirectory.

        .DESCRIPTION
        Collects all *.log files from $Script:LogFolder and compresses them into a zip file
        saved alongside the script. Each collected file is listed in the output, followed by
        the full path to the created archive.

        .EXAMPLE
        Invoke-LogCollection

        .OUTPUTS
        [bool]
        Returns $true when the archive is created successfully.
        Returns $false when the log folder is missing, contains no log files, or archive creation fails.
    #>

    Write-LogMessage -Type DEBUG -Message "Entered Invoke-LogCollection function..."

    if (-not (Test-Path -LiteralPath $Script:LogFolder -PathType Container)) {
        Write-LogMessage -Type ERROR -Message "Log folder not found: $Script:LogFolder"
        return $false
    }

    [array]$logFiles = @(Get-ChildItem -LiteralPath $Script:LogFolder -Filter "*.log" -File -ErrorAction SilentlyContinue)
    if ($logFiles.Count -eq 0) {
        Write-LogMessage -Type WARNING -Message "No log files found in: $Script:LogFolder"
        return $false
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $zipFileName = "VcfBaselineClusterTransition-logs-$stamp.zip"
    $zipDestinationPath = Join-Path -Path $PSScriptRoot -ChildPath $zipFileName

    # Remove any pre-existing zip at the same path to allow Compress-Archive to create cleanly.
    if (Test-Path -LiteralPath $zipDestinationPath -PathType Leaf) {
        Remove-Item -LiteralPath $zipDestinationPath -Force -ErrorAction SilentlyContinue
    }

    Write-LogMessage -Type INFO -Message "Collecting $($logFiles.Count) log file(s) into archive..."

    try {
        Compress-Archive -Path $logFiles.FullName -DestinationPath $zipDestinationPath -ErrorAction Stop

        foreach ($logFile in $logFiles) {
            Write-LogMessage -Type INFO -Message "  Added: $($logFile.Name)"
        }
        Write-LogMessage -Type INFO -AppendNewLine -Message "Log archive saved to: $zipDestinationPath"
        return $true
    } catch {
        Write-LogMessage -Type ERROR -Message "Failed to create log archive: $($_.Exception.Message)"
        return $false
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

        .OUTPUTS
        None
        This function does not return a value. It displays help information and exits.
    #>

    Write-LogMessage -Type DEBUG -Message "Entered Show-Help function..."

    Write-Output "`nIf no parameters are specified, a menu-driven interface is presented.`n"
    Write-Output "Options:`n"
    Write-Output "-CheckHostRemediationOptionsFile      # Validate HostRemediationOptions override file for use with the transition step."
    Write-Output "   -JsonInput <JSON file>             #   * Mandatory parameter: Json input file containing the HostRemediationOptions configuration.`n"
    Write-Output "-CheckTaskStatus                      # Check to see if a task has completed"
    Write-Output "   -Silence                           #   * Optional parameter: Silence."
    Write-Output "   -TaskType <type>                   #   * Mandatory Parameter: valid types include SddcManagerImageUpload and ComplianceCheck.`n"
    Write-Output "-CheckTransitions                     # Check status of resource transitions to image management."
    Write-Output "   -ResourceName <Resource Name>      #   * Optional parameter: Resource Name: <cluster or standalone host name."
    Write-Output "   -ResourceType <Resource Type>      #   * Optional parameter: Resource Type: <`"Cluster`" or `"Standalone Host`">."
    Write-Output "   -Silence                           #   * Optional parameter: Silence."
    Write-Output "   -WorkloadDomainName <WLD>          #   * Optional parameter: Workload Domain Name.`n"
    Write-Output "-CollectLogs                          # Create a timestamped zip archive of all log files in the logs subdirectory."
    Write-Output "                                      #   Output: <script dir>/VcfBaselineClusterTransition-logs-<timestamp>.zip`n"
    Write-Output "-ComplianceCheck                      # Check if a cluster is compatible with an image."
    Write-Output "   -ResourceName <Resource Name>      #   * Optional parameter if JsonInput is not specified: Resource Name."
    Write-Output "   -ResourceType <Resource Type>      #   * Optional parameter if JsonInput is not specified: Resource Type (`"Cluster`" or `"Standalone Host`")."
    Write-Output "   -SddcManagerImageName <ImageName>  #   * Optional parameter if JsonInput is not specified (or image seeding used): Image Name."
    Write-Output "   -JsonInput <JSON file>             #   * Optional parameter if Cluster/SddcManager is not specified: JsonInput."
    Write-Output "   -Parallel                          #   * Optional parameter: parallelize the cluster compliance checks (used in combination with -JsonInput)"
    Write-Output "   -Silence                           #   * Optional parameter: Silence."
    Write-Output "   -WorkloadDomainName <WLD>          #   * Optional parameter if JsonInput is not specified: Workload Domain Name.`n"
    Write-Output "-Connect                              # Connect to SDDC Manager and Workload Domain vCenter(s)."
    Write-Output "   -Silence                           #   * Optional parameter: Silence."
    Write-Output "   -JsonInput <credential file>       #   * Optional parameter: override for credential file (default: SddcManagerCredentials.json).`n"
    Write-Output "-CreateHostRemediationOptionsFile     # Create a HostRemediationOptions override file for use with the transition step."
    Write-Output "   -JsonOutput <JSON file>            #   * Mandatory parameter: json output file to save the HostRemediationOptions configuration.`n"
    Write-Output "-DeleteImageFromSddcManager           # Delete Image from SDDC Manager (use in case of misnamed image)."
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
    Write-Output "   -Parallel                          #   * Optional parameter: parallelize cluster transition (used in combination with -JsonInput)."
    Write-Output "   -Silence                           #   * Optional parameter: Silence."
    Write-Output "   -VcenterImageName <Image Name>     #   * Optional parameter: Source vCenter vLCM Image / Cluster Name."
    Write-Output "   -VcenterName <vCenter FQDN>        #   * Optional parameter: vCenter Fully Qualified Domain Name.`n"
    Write-Output "-ReviewComplianceResults              # Review the results of a cluster compliance check"
    Write-Output "   -ResourceName <Resource Name>      #   * Optional parameter: Resource Name."
    Write-Output "   -ResourceType <Resource Type>      #   * Optional parameter: Cluster or Standalone Host."
    Write-Output "   -ShowAllResources                  #   * Optional parameter: Show summary of all baseline-managed clusters and standalone-hosts."
    Write-Output "   -ShowExtendedResults               #   * Optional parameter: show full compliance findings."
    Write-Output "   -Silence                           #   * Optional parameter: Silence."
    Write-Output "   -WorkloadDomainName <WLD>          #   * Optional parameter: Workload Domain Name.`n"
    Write-Output "-RetryTransition                      # Retry a cluster transition to image management,"
    Write-Output "   -TaskId <Task Id>                  #    * Mandatory parameter: Task id of failed transition.`n"
    Write-Output "-ShowBaselineResources                # vLCM image management in vCenter and SDDC Manager."
    Write-Output "   -ExcludeSddcManagerImageName       #   * Optional parameter: Don't include the SDDC Manager Image Name in the JSON output."
    Write-Output "   -JsonOutput <Output file>          #   * Optional parameter: Save vLCM baseline cluster and standalone host details to a json file."
    Write-Output "   -Silence                           #   * Optional parameter: Silence.`n"
    Write-Output "-ShowImagesInSddcManager              # Show all vLCM Images in SDDC Manager."
    Write-Output "   -Silence                           #   * Optional parameter: Silence.`n"
    Write-Output "-ShowImagesInVcenter                  # Show all vLCM Images in vCenter(s)."
    Write-Output "   -JsonOutput <Output file>          #   * Optional parameter: output vCenter vLCM image details to a json file."
    Write-Output "   -Silence                           #   * Optional parameter: Silence.`n"
    Write-Output "-TransitionResource                   # Transition vLCM baseline (VUM) cluster to vLCM image management."
    Write-Output "   -HostRemediationOptionsFile <JSON> #   * Optional parameter:  Specify host remediation options override file."
    Write-Output "   -ResourceName <Resource Name>      #   * Mandatory parameter: Cluster Name or Standalone Host Name."
    Write-Output "   -ResourceType <Resource Type>      #   * Mandatory parameter: `"Cluster`" or `"Standalone Host`"."
    Write-Output "   -JsonInput <JSON file>             #   * Optional json input file for multiple cluster/standalone host transitions."
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

        .OUTPUTS
        None
        This function does not return a value. It displays the interactive menu and processes user selection.
    #>


    Write-LogMessage -Type DEBUG -Message "Entered Show-MainMenu function..."

    $errout = ""

    while ($true) {
        $sddcConn = Get-Variable -Name 'defaultSddcManagerConnections' -ErrorAction SilentlyContinue
        $activeSddcConn = if ($sddcConn -and $sddcConn.Value) { @($sddcConn.Value) | Where-Object { $_.IsConnected } | Select-Object -First 1 } else { $null }
        if ($activeSddcConn) {
            $connectionBanner = " [Connected to: $($activeSddcConn.Name)]"
        } else {
            $connectionBanner = ""
        }

        Clear-Host
        Write-Host -Object "`nvLCM Baseline (VUM) to vLCM Image Cluster/Standalone Host Transition Menu.`n" -ForegroundColor Cyan
        Write-Host -NoNewline -Object " 1. Connect to SDDC Manager and select vCenter."  -ForegroundColor White
        Write-Host -Object "$connectionBanner" -ForegroundColor Green
        Write-Host -Object " 2. Import vLCM images from vCenter(s) into SDDC Manager." -ForegroundColor White
        Write-Host -Object " 3. Check existing cluster(s)/standalone host(s)' vLCM image compliance." -ForegroundColor White
        Write-Host -Object " 4. Transition vLCM baseline cluster/standalone host to vLCM image management." -ForegroundColor White
        Write-Host -Object " 5. (Optional) Disconnect from vCenter(s) and SDDC Manager." -ForegroundColor White
        Write-Host -Object " 6. (Optional) Retry incomplete transition tasks." -ForegroundColor White
        Write-Host -Object " 7. (Optional) Delete SDDC Manager image." -ForegroundColor White
        Write-Host -Object " 8. (Optional) Show script version." -ForegroundColor White
        Write-Host -Object " 9. (Optional) Show resource transition status." -ForegroundColor White
        Write-Host -Object " 10. (Optional) Show compliance check status." -ForegroundColor White
        Write-Host -Object " 11. (Optional) Show vLCM images in SDDC Manager." -ForegroundColor White
        Write-Host -Object " 12. (Optional) Collect logs for support (zip logs folder)." -ForegroundColor White
        Write-Host -Object " Q. Press Q to Quit" -ForegroundColor Cyan
        if ($errout) { Write-Host -Object $errout -ForegroundColor Red }
        $menuInput = Read-Host -Prompt ' (1-12 or Q)'
        $menuInput = $menuInput -replace "`t|`n|`r",""
        Switch ($menuInput)
        {
            1
            {
                Clear-Host
                Connect-SddcManager
                Connect-Vcenter
                Show-AnyKey
                break
            }
            2
            {
                Clear-Host
                Import-ImageFromVcenter
                Show-AnyKey
                break
            }
            3
            {
                Clear-Host
                Invoke-ImageComplianceCheck
                Show-AnyKey
                break
            }
            4
            {
                Clear-Host
                Invoke-TransitionBaselineManagedResource
                Show-AnyKey
                break
            }
            5
            {
                Clear-Host
                Disconnect-SddcManager -OverrideQuestion "Would you like to disconnect from SDDC Manager and vCenter(s)?"
                # If disconnected from SDDC Manager, in turn disconnect from dependent vCenters.
                if (-not $Global:DefaultSddcManagerConnections) {
                Disconnect-Vcenter
                }
                Show-AnyKey
                break
            }
            6
            {
                Clear-Host
                Show-IncompleteTasks
                Show-AnyKey
                break
            }
            7
            {
                Clear-Host
                Remove-ImageFromSddcManager
                Show-AnyKey
                break
            }
            8
            {
                Clear-Host
                Show-Version
                Show-AnyKey
                break
            }
            9
            {
                Clear-Host
                Show-ResourceTransitionStatus -ReturnSummary
                Show-AnyKey
                break
            }
            10
            {
                Clear-Host
                Show-TaskStatus -TaskType ComplianceCheck
                Show-AnyKey
                break
            }
            11
            {
                Clear-Host
                Get-SddcManagerImages -ShowAll
                Show-AnyKey
                break
            }
            12
            {
                Clear-Host
                Invoke-LogCollection | Out-Null
                Show-AnyKey
                break
            }
            Q
            {
                Disconnect-SddcManager -NoPrompt -Silence
                Disconnect-Vcenter -Silence
                Remove-Variable -ErrorAction SilentlyContinue -Name SddcManagerPassword -Scope Global
                Remove-Variable -ErrorAction SilentlyContinue -Name SddcManagerUserName -Scope Global
                Remove-Variable -ErrorAction SilentlyContinue -Name SddcManagerFqdn -Scope Global
                Remove-Variable -ErrorAction SilentlyContinue -Name VxRailMode -Scope Script
                Exit
            }
            Default
            {
                $errout = 'Invalid option please try again...'
            }
        }
    }
}

# Variables and Constants
$Global:ProgressPreference = 'Continue'
# $pSStyle is only available in PowerShell 7.2+; guard against accidental loading in older shells.
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $pSStyle.Progress.Style = "`e[93;1m"
}
# Powershell 7.2 is the minimum required for the script to function, however, 7.2 is EOS.
$pSVersionMinVersion = '7.2'
$minimumVcfPowerCliVersion = '9.1.0.25380678'
$minimumVcfRelease = '5.2.2.0'
$minimumSahRelease = '9.1.0.0'
$minimumImageCatalogSupportRelease = '9.0.0.0'
$clusterVsphereImageSeedingSupport = "8.0.3"
$standAloneHostVsphereImageSeedingSupport = "8.0.3"
$Script:logOnly = $false
$Script:InstalledPowerCliModules = $null

New-LogFile
Get-Preconditions -SkipVersionCheck:$SkipPowercliVersionCheck

# Perform comprehensive parameter validation
try {
    Test-ParameterValidation
} catch {
    Write-LogMessage -Type ERROR -Message "Parameter validation failed: $($_.Exception.Message)"
    Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR
}

if ($Help) {
    Show-Help
    Exit-WithCode -ExitCode $Script:ExitCodes.SUCCESS
}

# Assume headless mode until all conditions have been checked.
$Script:Headless = $true

# Initialize VxRail mode detection (set to False until Connect-Vcenter determines otherwise).
$Script:vxRailMode = $false
$Script:vxRailModeDetected = $false
$sddcManagerCredentialsJson = Join-Path -Path $PSScriptRoot -ChildPath "SddcManagerCredentials.json"

# If Silence is set, the Write-LogMessage function will not send output to the screen.
if ($Silence) {
    $Script:logOnly = $true
}

switch ($true) {
    $CollectLogs {
        $collectionSucceeded = Invoke-LogCollection
        Exit-WithCode -ExitCode $(if ($collectionSucceeded) { $Script:ExitCodes.SUCCESS } else { $Script:ExitCodes.GENERAL_ERROR })
        break
    }

    $Connect {
        if ($JsonInput) {
            $sddcManagerCredentialsJson = $JsonInput
        }
        Connect-SddcManager
        Connect-Vcenter
        Write-LogMessage -Type INFO -AppendNewLine -Message "Successfully connected to SDDC Manager and vCenter(s)."
        break
    }

    $Disconnect {
        Disconnect-Vcenter
        Disconnect-SddcManager -NoPrompt
        Remove-Variable -ErrorAction SilentlyContinue -Name SddcManagerPassword -Scope Global
        Remove-Variable -ErrorAction SilentlyContinue -Name SddcManagerUserName -Scope Global
        Remove-Variable -ErrorAction SilentlyContinue -Name SddcManagerFqdn -Scope Global
        Remove-Variable -ErrorAction SilentlyContinue -Name VxRailMode -Scope Script
        Exit-WithCode -ExitCode $Script:ExitCodes.SUCCESS
        break
    }

    $CheckHostRemediationOptionsFile {
        if (-not $JsonInput) {
            Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -CheckHostRemediationOptionsFile requires the following arguments:"
            Write-LogMessage -Type ERROR -Message " -JsonInput <HostRemediationOption.json>"
            Exit-WithCode -ExitCode $Script:ExitCodes.INVALID_ARGUMENTS
        } else {
            Invoke-HostRemediationOptionsConfig -Action Check -HostRemediationOptionsJson $JsonInput
        }
        break
    }

    $CheckTransitions {
        if ($ResourceName -and $WorkloadDomainName -and $ResourceType) {
            Show-ResourceTransitionStatus -ResourceName $ResourceName -WorkloadDomainName $WorkloadDomainName -ResourceType $ResourceType
        } else {
            Show-ResourceTransitionStatus -ReturnSummary
        }
        break
    }

    $CheckTaskStatus {
        if ($TaskType) {
            Show-TaskStatus -TaskType $TaskType
        } else {
            Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -CheckTaskStatus requires a -TaskType argument"
            Exit-WithCode -ExitCode $Script:ExitCodes.INVALID_ARGUMENTS
        }
        break
    }

    $ComplianceCheck {
        # Check for JSON Input first.
        if ($JsonInput) {
            $JsonInputExists = Test-Path $JsonInput
            # We can only proceed if the JsonInput file exists.
            if ($JsonInputExists) {
                if ($Parallel) {
                    Invoke-ImageComplianceCheck -JsonInputFile $JsonInput -Parallel
                } else {
                   Invoke-ImageComplianceCheck -JsonInputFile $JsonInput
                }
            } else {
                Write-LogMessage -Type ERROR -Message "JsonInput file `"$JsonInput`" not found."
                Exit-WithCode -ExitCode $Script:ExitCodes.FILE_NOT_FOUND
            }
        # If JSON input is not specified, we need ClusterName/WorkloadDomainName/SddcManagerImageName specified.
        } elseif ((-not $ResourceName) -or (-not $WorkloadDomainName) -or (-not $ResourceType)) {
            Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -ComplianceCheck requires the following arguments:"
            Write-LogMessage -Type ERROR -Message " -ResourceName <Resource Name>"
            Write-LogMessage -Type ERROR -Message " -ResourceType <`"Cluster`" or `"Standalone Host`">"
            Write-LogMessage -Type ERROR -Message " -WorkloadDomainName <Workload Domain Name>"
            Write-LogMessage -Type ERROR -Message " -SddcManagerImageName <Image Name in SDDC Manager> (Required if image seeding isn't used)"
        } elseif (-not $SddcManagerImageName) {
            Invoke-ImageComplianceCheck -ResourceName $ResourceName -ResourceType $ResourceType -WorkloadDomainName $WorkloadDomainName
        } else {
            Invoke-ImageComplianceCheck -ResourceName $ResourceName -ResourceType $ResourceType -WorkloadDomainName $WorkloadDomainName -SddcManagerImageName $SddcManagerImageName
        }
        break
    }

    $CreateHostRemediationOptionsFile {
        if ($Silence) {
            # Re-enable logging to log the following error message.
            $Script:logOnly = $false
            Write-LogMessage -Type ERROR -Message  "Parameter `"-Silence`" cannot be used with this option as the feature is interactive. Please remove the `"-Silence`" flag and re-run the command.  Exiting."
            Exit-WithCode -ExitCode $Script:ExitCodes.INVALID_ARGUMENTS
        } elseif (-not $JsonOutput) {
            Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -CreateHostRemediationOptionsFile requires the following arguments:"
            Write-LogMessage -Type ERROR -Message " -JsonOutput <HostRemediationOption.json>"
            Exit-WithCode -ExitCode $Script:ExitCodes.INVALID_ARGUMENTS
        } else {
            Invoke-HostRemediationOptionsConfig -Action Create -JsonOutputFile $JsonOutput
        }
        break
    }

    $DeleteImageFromSddcManager {
        if (-not $SddcManagerImageName) {
            Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -DeleteImageFromSddcManager requires the following arguments:"
            Write-LogMessage -Type ERROR -Message " -SddcManagerImageName <Sddc Manager Image Name>"
            Exit-WithCode -ExitCode $Script:ExitCodes.INVALID_ARGUMENTS
        } else {
            Remove-ImageFromSddcManager -SddcManagerImageName $SddcManagerImageName
        }
        break
    }

    $DeleteTemporaryCluster {
        if ($clusterName -and $VcenterName) {
            Remove-TemporaryCluster -TemporaryClusterName $clusterName -TemporaryClusterVcenter $VcenterName
        } else {
            Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -DeleteTemporaryCluster requires the following arguments:"
            Write-LogMessage -Type ERROR -Message " -ClusterName <Cluster Name>"
            Write-LogMessage -Type ERROR -Message " -VcenterName <vCenter FQDN>"
            Exit-WithCode -ExitCode $Script:ExitCodes.INVALID_ARGUMENTS
        }
        break
    }

    $ImportImagesFromVcenter {
        if ($JsonInput) {
            $JsonInputExists = Test-Path $JsonInput
            if ($JsonInputExists) {
                if ($Parallel) {
                    Import-ImageFromVcenter -JsonInputFile $JsonInput -Parallel
                } else {
                    if ($Silence) {
                         # Re-enable logging to log the following error message.
                        $Script:logOnly = $false
                        Write-LogMessage -Type ERROR -Message "Parameter `"-Silence`" cannot be used with serialized processing. Please remove the `"-Silence`" flag and re-run the command.  Exiting."
                        Exit-WithCode -ExitCode $Script:ExitCodes.INVALID_ARGUMENTS
                    } else {
                        Import-ImageFromVcenter -JsonInputFile $JsonInput
                    }
                }
            } else {
                Write-LogMessage -Type ERROR -Message "JsonInput $JsonInput not found"
                Exit-WithCode -ExitCode $Script:ExitCodes.FILE_NOT_FOUND
            }
        } elseif ((-not $VcenterImageName) -or (-not $VcenterName)) {
            Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -ImportImagesFromVcenter requires the following arguments:"
            Write-LogMessage -Type ERROR -Message " -VcenterImageName <Source vCenter vLCM Image / Cluster Name>"
            Write-LogMessage -Type ERROR -Message " -VcenterName <vCenter Fully Qualified Domain Name>"
            Exit-WithCode -ExitCode $Script:ExitCodes.INVALID_ARGUMENTS
        } else {
            if ($Silence) {
                Import-ImageFromVcenter -VcenterImageName $VcenterImageName -VcenterName $VcenterName -Silence
            } else {
                Import-ImageFromVcenter -VcenterImageName $VcenterImageName -VcenterName $VcenterName
            }
        }
        break
    }

    $ReviewComplianceResults {
        if ($ShowAllResources) {
            if ($ShowExtendedResults) {
                Show-ImageComplianceCheckResults -ShowAllResources -ShowExtendedResults
            } else {
                Show-ImageComplianceCheckResults -ShowAllResources
            }

        } elseif ($ResourceName -and $WorkloadDomainName -and $ResourceType) {
            if ($ShowExtendedResults) {
                Show-ImageComplianceCheckResults -ResourceName $ResourceName -ResourceType $ResourceType -WorkloadDomainName $WorkloadDomainName -ShowExtendedResults
            } else {
                Show-ImageComplianceCheckResults -ResourceName $ResourceName -ResourceType $ResourceType -WorkloadDomainName $WorkloadDomainName
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -ReviewComplianceResults requires the following arguments:"
            Write-LogMessage -Type ERROR -Message " -ResourceName <Resource Name>"
            Write-LogMessage -Type ERROR -Message " -ResourceType <`"Cluster`" or `"Standalone Host`">"
            Write-LogMessage -Type ERROR -Message " -WorkloadDomainName <Workload Domain Name>"
            Exit-WithCode -ExitCode $Script:ExitCodes.INVALID_ARGUMENTS
        }
        break
    }

    $RetryTransition {
        # Check for required parameters.
        if (-not $TaskId) {
            Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -RetryTransition requires argument:"
            Write-LogMessage -Type ERROR -Message " -TaskId <Failed Task Id>"
            Exit-WithCode -ExitCode $Script:ExitCodes.INVALID_ARGUMENTS
        } else {
            $retryTasksResult = Invoke-VcfGetTasks -ErrorAction SilentlyContinue -TaskStatus "Failed"
            [array]$retryTaskElements = if ($retryTasksResult -and $retryTasksResult.PSObject.Properties['Elements'] -and $retryTasksResult.Elements) { @($retryTasksResult.Elements) | Where-Object { try { $null -ne $_.Type } catch { $false } } } else { @() }
            $response = $retryTaskElements | Where-Object { try { $_.Type -in ("DOMAIN_VLCM_TRANSITION","VLCM_TRANSITION") -and $_.Id -eq $TaskId } catch { $false } } | Select-Object -First 1
            if ($response) {
                Invoke-TransitionBaselineManagedResource -RetryTransition -FailedTaskId $TaskId
            } else {
                Write-LogMessage -Type ERROR -Message "TaskId $TaskId does not correspond to a failed VLCM_TRANSITION or DOMAIN_VLCM_TRANSITION task."
            }
        }
        break
    }

    $ShowBaselineResources {
        if ($JsonOutput -and $ExcludeSddcManagerImageName) {
            Get-BaselineManagedResources -JsonOutputFile $JsonOutput -ExcludeSddcManagerImageName
        } elseif ($JsonOutput) {
            Get-BaselineManagedResources -JsonOutputFile $JsonOutput
        } else {
            Get-BaselineManagedResources
        }
        break
    }

    $ShowImagesInSddcManager {
        Get-SddcManagerImages
        break
    }

    $ShowImagesInVcenter {
        if ($JsonOutput) {
            Get-VcenterImages -JsonOutputFile $JsonOutput
        } else {
            Get-VcenterImages
        }
        break
    }

    $TransitionResource {
        # HostRemediationOptionsFile can apply to JsonInput and single cluster/standalone host inputs, so test first.
        $hostRemediationOptionsExists = $false
        if ($HostRemediationOptionsFile) {
            $hostRemediationOptionsExists = Test-Path $HostRemediationOptionsFile
            if (-not $hostRemediationOptionsExists) {
                Write-LogMessage -Type ERROR -Message "HostRemediationOptionsFile `"$HostRemediationOptionsFile`" not found."
                Exit-WithCode -ExitCode $Script:ExitCodes.FILE_NOT_FOUND
            }
        }
        if ($JsonInput) {
            $JsonInputExists = Test-Path $JsonInput
            if ($JsonInputExists) {
                if ($Parallel -and $hostRemediationOptionsExists) {
                    Invoke-HostRemediationOptionsConfig -Action Check -HostRemediationOptionsJson $HostRemediationOptionsFile
                    Invoke-TransitionBaselineManagedResource -JsonInputFile $JsonInput -Parallel -HostRemediationOptionsJson $HostRemediationOptionsFile
                } elseif ($Parallel) {
                    Invoke-TransitionBaselineManagedResource -JsonInputFile $JsonInput -Parallel
                } elseif ($hostRemediationOptionsExists) {
                    Invoke-HostRemediationOptionsConfig -Action Check -HostRemediationOptionsJson $HostRemediationOptionsFile
                    Invoke-TransitionBaselineManagedResource -JsonInputFile $JsonInput -HostRemediationOptionsJson $HostRemediationOptionsFile
                } else {
                    Invoke-TransitionBaselineManagedResource -JsonInputFile $JsonInput
                }
            }
        } elseif ((-not $ResourceName) -or (-not $WorkloadDomainName) -or (-not $ResourceType)) {
            Write-LogMessage -Type ERROR -Message "Error: $($MyInvocation.MyCommand.Name) -TransitionResource requires the following arguments:"
            Write-LogMessage -Type ERROR -Message " -ResourceName <Cluster Name or Standalone Host Name>"
            Write-LogMessage -Type ERROR -Message " -ResourceType <`"Cluster`" or `"Standalone Host`">"
            Write-LogMessage -Type ERROR -Message " -WorkloadDomainName <Workload Domain Name>"
        } elseif ($ResourceName -and $WorkloadDomainName -and $ResourceType) {
            if ($hostRemediationOptionsExists) {
                # First make sure that the HostRemediationOptionsFile is valid.
                Invoke-HostRemediationOptionsConfig -Action Check -HostRemediationOptionsJson $HostRemediationOptionsFile
                Invoke-TransitionBaselineManagedResource -ResourceName $ResourceName -ResourceType $ResourceType -WorkloadDomainName $WorkloadDomainName -HostRemediationOptionsJson $HostRemediationOptionsFile
        } else {
                Invoke-TransitionBaselineManagedResource -ResourceName $ResourceName -ResourceType $ResourceType -WorkloadDomainName $WorkloadDomainName
            }
        }
        break
    }

    $Version {
        Show-Version
        break
    }

    default {
        # If no options specified, enter interactive mode.
        $Script:Headless = $false
        Show-MainMenu
    }
}
#endregion
