# VUM to vLCM Transition for VMware Cloud Foundation

[![PowerShell](https://img.shields.io/badge/PowerShell-7.2%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/License-Broadcom-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-1.0.0.0.60-orange.svg)](CHANGELOG.md)
[![GitHub Clones](https://img.shields.io/badge/dynamic/json?color=success&label=Clone&query=count&url=https://gist.githubusercontent.com/nathanthaler/cf28a7a69217ecfa5e5ac5f23fcb37ef/raw/clone.json&logo=github)](https://gist.githubusercontent.com/nathanthaler/cf28a7a69217ecfa5e5ac5f23fcb37ef/raw/clone.json)
![Downloads](https://img.shields.io/github/downloads/vmware/powershell-script-for-vmware-cloud-foundation-vum-to-vlcm/total?label=Release%20Downloads)



## Common features for VCF 9.x and 5.2.x
The vLCM Baseline (VUM) to vLCM Image transition script provides the customer three mechanisms.

1. Interactive mode (text-user interface) with single or multi-selection of clusters, with check and transition jobs executed serially.
2. Command line mode using in-line parameters with single cluster selection.
3. Command line mode using JSON input with single or multi-selection of clusters, with check and transition jobs executed in parallel.

## VCF 5.2.2 specific features

* VxRail Support (image seeding only).
* Optional Image seeding support for VSRN.
* vLCM Baseline to vLCM Image transition for non-Supervisor, non-hetero clusters with 5.x sBOMs.

## VCF 9.0.x specific features

* Support for vSphere Supervisor clusters.

## Prerequisites

1. SDDC Manager 5.2.2+ / 9.0.0.0+
2. VCF.PowerCLI 9
3. Powershell 7.2+

## Installing VCF.PowerCLI 9

1. Install-Module -Name VCF.PowerCLI
2. Set-PowerCLIConfiguration -InvalidCertificateAction Ignore
3. Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

## 5.2.2 Specific instructions

### Compliance check with image seeding: Menu option

* Choose Option 3 as you normally would.

```Powershell
vLCM Baseline (VUM) to vLCM Image Cluster Transition Menu.

 1. Connect to SDDC Manager and select vCenter. [Connected to: vcf01.sfo.rainpole.io]
 2. Import vLCM images from vCenter(s) into SDDC Manager.
 3. Check existing cluster(s)`' vLCM image compliance.
 4. Transition vLCM baseline (VUM) cluster to vLCM image management.
 5. (Optional) Disconnect from vCenter(s) and SDDC Manager.
 6. (Optional) Retry incomplete transition tasks.
 7. (Optional) Delete SDDC Manager Image.
 8. (Optional) Show script version.
 9. (Optional) Show cluster transition status.
 10. (Optional) Show vLCM images in SDDC Manager.
 Q. Press Q to Quit

 (1-10 or Q): 3
```

* New behavior: if you select clusters that are controlled by vCenter 8.0.3 and whose first host runs ESX 8.0.3,
the default will be to use image seeding, in which case the image will be auto-generated.   This option is not required,
hence the non-default option to chose an image.  Please note: the menu driven interface is simplified by design: if a user
chooses two clusters both of which support image seeding, the option to utilize image seeding will be presented, however,
if only one cluster supports it, the option will be suppressed.

```Powershell
Displaying vLCM baseline (VUM) managed clusters in connected vCenter(s):

  Id Cluster Name vCenter Name                 Workload Domain    Compliance Status SDDC Manager Image Name
  -- ------------ ------------                 ---------------    ----------------- -----------------------
  1  m01-cl01     m01-vc01.example.com         m01                NON_COMPLIANT     N/A
  2  w01-cl01     w01-vc01.example.com         w01                NON_COMPLIANT     N/A

Enter an id, a comma-delimited list of ids, or 'c' to cancel: 1,2

All clusters are eligible for host seeding.  Would you like to auto generate a vLCM image for them using
host seeding?
[Y] Yes  [N] No  [?] Help (default is "Y"):
```

* Moving onto step 4, the clusters will show up as having a auto-generated image associated with them.

```Powershell
vLCM Baseline (VUM) to vLCM Image Cluster Transition Menu.

 1. Connect to SDDC Manager and select vCenter. [Connected to: vcf01.sfo.rainpole.io]
 2. Import vLCM images from vCenter(s) into SDDC Manager.
 3. Check existing cluster(s)`' vLCM image compliance.
 4. Transition vLCM baseline (VUM) cluster to vLCM image management.
 5. (Optional) Disconnect from vCenter(s) and SDDC Manager.
 6. (Optional) Retry incomplete transition tasks.
 7. (Optional) Delete SDDC Manager Image.
 8. (Optional) Show script version.
 9. (Optional) Show cluster transition status.
 10. (Optional) Show vLCM images in SDDC Manager.
 Q. Press Q to Quit

 (1-10 or Q): 4
...
Displaying vLCM baseline (VUM) managed clusters in connected vCenter(s):

  Id Cluster Name vCenter Name                 Workload Domain    Compliance Status SDDC Manager Image Name
  -- ------------ ------------                 ---------------    ----------------- -----------------------
  1  m01-cl01     m01-vc01.example.com         m01                NON_COMPLIANT     <Autogenerated-Image>
  2  w01-cl01     w01-vc01.example.com         w01                NON_COMPLIANT     <Autogenerated-Image>

[INFO] Select the vLCM baseline clusters to transition to vLCM image management.
...
```

### Compliance check with image seeding: JSON option

* Normally, the compliance check JSON payload requires three values for each cluster:  ClusterName, WorkloadDomainName, and SddcManagerImageName.  However, if SddcManagerImageName is not presented, the script will assume image seeding mode.  If the cluster does not support image seeding mode, the script will skip that cluster as it cannot process it without an image.

* The script invocation itself does not change, only the payload.

```Powershell

> Get-Content ./BaselineClusters.json
[
  {
    "ClusterName": "m01-cl01",
    "WorkloadDomainName": "m01"
  },
  {
    "ClusterName": "w01-cl01",
    "WorkloadDomainName": "w01"
  }
]
```

### Compliance check with image seeding: parameter option

* As with the JSON option, if SddcManagerImageName is not specified as a parameter name with a value, image seeding is assumed and if the cluster does not support said option, the script will exit with an error.

```Powershell
./VcfBaselineClusterTransition.ps1 -ComplianceCheck -ClusterName m01-cl01 -WorkloadDomainName w01
```

### Official guides

- [9.0 VUM to vLCM Admin Guide](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-0/deployment/upgrading-cloud-foundation/upgrade-the-management-domain-to-vmware-cloud-foundation-5-2/vlcm-baseline-to-vlcm-image-cluster-transition-.html)
- [5.2.2 VUM to vLCM Admin Guide](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-5-2-and-earlier/5-2/vmware-cloud-foundation-lifecycle-management/vlcm-baseline-to-vlcm-image-cluster-transition-522-lifecycle/transition-vlcm-baseline-clusters-to-vlcm-image-clusters-using-powercli-522-lifecycle.html)

### Support

- For product issues, please open a standard Broadcom support case.
- For bugs or enhancement requests with this script, please open a [github issue](https://github.com/vmware/powershell-script-for-vmware-cloud-foundation-vum-to-vlcm/issues).
