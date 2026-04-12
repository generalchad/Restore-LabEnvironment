# Active Directory Lab Automation Framework

## Overview

The Active Directory Lab Automation Framework is a modular, JSON-driven PowerShell solution designed to rapidly provision, standardize, and restore Active Directory environments. Built around the principles of Infrastructure-as-Code (IaC), this framework ensures idempotent execution, allowing administrators and security researchers to reliably rebuild organizational units, users, role-based access controls, and security baselines.

## Features

* **JSON-Driven Configuration:** All structural and object data is decoupled from the execution logic, allowing environments to be version-controlled and modified without altering the underlying PowerShell modules.
* **Desired State Synchronization:** The group membership engine compares current Active Directory state against the JSON configuration, aggressively pruning unauthorized drift while provisioning missing access.
* **Idempotent Execution:** The framework safely checks for the existence of objects before creation, preventing duplication errors and allowing the script to be run multiple times safely.
* **Cascading Error Handling:** Utilizes strict variable enforcement and terminating errors within isolated modules to prevent partial or corrupted deployments.
* **Persistent Transcript Logging:** Every execution automatically generates a timestamped log file detailing success states, warnings, and handled exceptions without console spam.
* **Dynamic Path Translation:** Converts intuitive slash-based paths (e.g., `Servers/Infrastructure`) into proper Active Directory Distinguished Names dynamically.

## Prerequisites

To execute this framework, the host system must meet the following requirements:

1. **Operating System:** Windows Server 2016+ or Windows 10/11 (with RSAT installed) is highly recommended.
2. **PowerShell:** Version 5.1 or later.
3. **Dependencies:** The `ActiveDirectory` and `GroupPolicy` PowerShell modules must be available.
4. **Permissions:** The execution context must be elevated (Run as Administrator) and the executing user must hold Domain Admin privileges within the target Active Directory forest.

### Legacy Environment Configuration (Windows Server 2008 R2 / 2012 R2)

If you must execute this framework against earlier Active Directory Domain Services (ADDS) environments, you must fulfill the following manual prerequisites prior to execution.:

1. **Install WMF 5.1:** Update the management host to Windows Management Framework 5.1. The default PowerShell versions (2.0 and 4.0) included with these operating systems lack the `ConvertFrom-Json` capabilities and advanced splatting required by the orchestrator.
2. **Active Directory Web Services (ADWS):** For Windows Server 2008, you must manually install the "Active Directory Management Gateway Service" to allow the PowerShell AD module to communicate with the legacy database. Expect slower query execution times.

**GPO Compatibility Warning:** Older Group Policy Management Consoles lack the modern ADMX templates required to parse contemporary registry preferences (e.g., Windows 10/11 settings). Additionally, environments unpatched against MS16-072 may fail to apply GPOs correctly when utilizing the `RemoveAuthUsersApply` parameter in `ADGroupPolicies.json`.

## Repository Structure

Ensure the repository is structured exactly as follows before execution:

```text
Restore-AD/
├── Restore-LabEnvironment.ps1
├── Config/
│   ├── ADBaselines.json
│   ├── ADGroupPolicies.json
│   ├── ADStructure.json
│   ├── ADUserData.json
│   └── ADWmiFilters.json
├── Logs/
│   └── (Log files will auto-generate here)
└── Modules/
    ├── Restore-LabUtils.psm1
    ├── Restore-ADStructure.psm1
    ├── Restore-ADUsers.psm1
    ├── Restore-ADGroupMemberships.psm1
    ├── Restore-ADGroupPolicies.psm1
    └── Restore-ADWmiFilters.psm1
```

## Configuration Guide

Before executing the deployment, customize the environment by editing the files within the `Config\` directory.

* **ADStructure.json:** Defines the Organizational Unit (OU) hierarchy. Use `ParentOU` to nest OUs. Leave `ParentOU` blank to place the OU at the deployment root.
* **ADBaselines.json:** Defines global Security and Distribution groups. Every managed user provisioned by the framework is automatically synchronized to these groups.
* **ADUserData.json:** Defines user objects and their attributes. Map users to specific OUs, define their administrative tier, and assign them to explicit native or custom roles.
* **ADGroupPolicies.json:** Defines security baselines and registry preferences. Assigns policies to target OUs and supports Security Filtering via MS16-072 compliant permission mapping.
* **ADWmiFilters.json:** Defines reusable WMI filters (Name, Description, Query) that are created natively in AD and can be linked to GPOs.

### OU Structure Configuration

Each OU object in `ADStructure.json` uses the following schema:

```json
{
    "Name": "Laptops",
    "ParentOU": "Workstations"
}
```

**Guidance:**

* `Name` is the OU name to create.
* `ParentOU` is a slash-delimited relative path from the org root OU.
* Use an empty `ParentOU` (`""`) to create a top-level OU under the org root.

### Baseline Group Configuration

Each baseline group object in `ADBaselines.json` uses the following schema:

```json
{
    "Name": "GRP-SEC-EVERYONE-GLOBAL",
    "Category": "Security",
    "Path": "Groups/Security"
}
```

**Guidance:**

* `Category` must be either "Security" or "Distribution".
* All users defined in `ADUserData.json` will be synchronized to these groups automatically.

### User Data Configuration

Each user object in `ADUserData.json` supports a core set of required fields plus optional identity and organizational metadata.

Minimum practical schema:

```json
{
    "SamAccountName": "jdoe",
    "GivenName": "John",
    "Surname": "Doe",
    "DisplayName": "John Doe",
    "TargetOU": "Users/Employees"
}
```

Optional fields include `Type`, `Tier`, `Description`, `Title`, `Department`, `Company`, contact attributes, address attributes, home/profile paths, and employee identifiers. Non-standard attributes will be mapped directly to the Active Directory object's extended properties.

To define explicit group assignments (including built-in groups like Domain Admins), use `Groups` as an array:

```json
{
    "SamAccountName": "jdoe",
    "TargetOU": "Users/Employees",
    "Groups": [
        { "Name": "Domain Admins", "TargetOU": "Users" },
        { "Name": "GRP-SEC-CustomRole", "TargetOU": "Groups/Security" }
    ]
}
```

**Template behavior:** The built-in `TEMPLATE_USER_DO_NOT_DELETE` record is intentionally skipped by the restore process and serves as a field reference.

### Group Policy Configuration

Each GPO object in `ADGroupPolicies.json` uses this schema pattern:

```json
{
    "DisplayName": "GPO-SEC-WKS-Baseline",
    "TargetOU": "Workstations",
    "Comment": "General workstation security baseline.",
    "Enforced": false,
    "WmiFilterName": "WMI-Filter-ClientOS",
    "RemoveAuthUsersApply": false,
    "SecurityFilters": ["Domain Computers"],
    "Settings": [
        {
            "Key": "HKLM\\Software\\Policies\\Contoso",
            "ValueName": "ExampleSetting",
            "Type": "DWord",
            "Value": 1
        }
    ]
}
```

**Guidance:**

* `DisplayName` is required and must be unique in the domain.
* `TargetOU` can be empty (`""`) to link at the org root OU.
* `Enforced` controls link enforcement for the target OU.
* `WmiFilterName` must match a filter `Name` from `ADWmiFilters.json`.
* `Settings` defines Registry Preference entries applied to the GPO.
* `SecurityFilters` and `RemoveAuthUsersApply` are optional and control GPO security filtering (MS16-072 compliant).

### WMI Filter Configuration

Each WMI filter object in `ADWmiFilters.json` uses the following schema:

```json
{
    "Name": "WMI-Filter-ClientOS",
    "Description": "Targets Windows Client Operating Systems.",
    "Query": "SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1"
}
```

To bind a filter to a GPO, set `WmiFilterName` in `ADGroupPolicies.json` to a matching filter `Name`.

## Deployment Walkthrough

### Step 1: Prepare the Environment

1. Log into a domain-joined machine or Domain Controller using an account with Domain Admin privileges.
2. Open an elevated PowerShell prompt (Run as Administrator).
3. Ensure the execution policy allows script execution:

   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   ```

### Step 2: Navigate to the Framework Directory

Change your working directory to the location of the orchestrator script.

```powershell
cd C:\Path\To\Restore-AD
```

### Step 3: Execute the Orchestrator

Execute `Restore-LabEnvironment.ps1`. You must provide the `-OrgName` parameter, which establishes the root OU for the deployment.

```powershell
.\Restore-LabEnvironment.ps1 -OrgName "BrownCorp"
```

**Optional Parameters:**

* `-DisableProtection`: Appending this switch removes the "Protect from accidental deletion" flag on all created OUs, which is useful for temporary environments that need to be torn down quickly.
* `-WhatIf`: Simulates the execution to validate the JSON configuration without making actual changes to Active Directory.

### Step 4: Review Logs

Upon completion, the orchestrator will output the location of the transcript log. Navigate to the `Logs\` directory to review the timestamped text file for a detailed audit of the deployment process.

## Roadmap

Future capabilities planned for integration into the framework include:

* **Automated Workstation Joining:** Subroutines to automatically domain-join specified virtual machines and move them to their correct staging OUs.
* **LAPS Integration:** Automated deployment of the Local Administrator Password Solution schema and corresponding group policies.
