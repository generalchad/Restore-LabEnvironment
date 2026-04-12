# Active Directory Lab Automation Framework

## Overview

The Active Directory Lab Automation Framework is a modular, JSON-driven PowerShell solution designed to rapidly provision, standardize, and restore Active Directory environments. Built around the principles of Infrastructure-as-Code (IaC), this framework ensures idempotent execution, allowing administrators and security researchers to reliably rebuild organizational units, users, role-based access controls, and security baselines.

## Features

* **JSON-Driven Configuration:** All structural and object data is decoupled from the execution logic, allowing environments to be version-controlled and modified without altering the underlying PowerShell modules.
* **Idempotent Execution:** The framework safely checks for the existence of objects before creation, preventing duplication errors and allowing the script to be run multiple times safely.
* **Cascading Error Handling:** Utilizes strict variable enforcement and terminating errors within isolated modules to prevent partial or corrupted deployments.
* **Persistent Transcript Logging:** Every execution automatically generates a timestamped log file detailing success states, warnings, and handled exceptions.
* **Dynamic Path Translation:** Converts intuitive slash-based paths (e.g., `Servers/Infrastructure`) into proper Active Directory Distinguished Names dynamically.

## Prerequisites

To execute this framework, the host system must meet the following requirements:

1. **Operating System:** Windows Server 2016+ or Windows 10/11 (with RSAT installed).
2. **PowerShell:** Version 5.1 or later.
3. **Dependencies:** The `ActiveDirectory` and `GroupPolicy` PowerShell modules must be available.
4. **Permissions:** The execution context must be elevated (Run as Administrator) and the executing user must hold Domain Admin privileges within the target Active Directory forest.

## Repository Structure

Ensure the repository is structured exactly as follows before execution:

```text
Restore-AD/
├── Restore-LabEnvironment.ps1
├── Config/
│   ├── ADStructure.json
│   ├── ADUserData.json
│   └── ADGroupPolicies.json
├── Logs/
│   └── (Log files will auto-generate here)
└── Modules/
    ├── Restore-LabUtils.psm1
    ├── Restore-ADStructure.psm1
    ├── Restore-ADUsers.psm1
    ├── Restore-ADGroupMemberships.psm1
    └── Restore-ADGroupPolicies.psm1
```

## Configuration Guide

Before executing the deployment, customize the environment by editing the files within the `Config\` directory.

* **ADStructure.json:** Defines the Organizational Unit (OU) hierarchy. Use `ParentOU` to nest OUs. Leave `ParentOU` blank to place the OU at the deployment root.
* **ADUserData.json:** Defines user objects and their attributes. Map users to specific OUs, define their administrative tier, and assign them to roles. Non-standard attributes will be written directly to the AD object.
* **ADGroupPolicies.json:** Defines security baselines and registry preferences. Assigns policies to target OUs and supports Security Filtering via MS16-072 compliant permission mapping.

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

Execute `Restore-LabEnvironment.ps1`. You must provide the `-OrgName` parameter, which establishes the root OU for the deployment (e.g., passing `EzCorp` will create and target `OU=_EzCorp,DC=domain,DC=com`).

```powershell
.\Restore-LabEnvironment.ps1 -OrgName "EzCorp"
```

**Optional Parameters:**

* `-DisableProtection`: Appending this switch removes the "Protect from accidental deletion" flag on all created OUs, which is useful for temporary environments that need to be torn down quickly.
* `-WhatIf`: Simulates the execution to validate the JSON configuration without making actual changes to Active Directory.

### Step 4: Review Logs

Upon completion, the orchestrator will output the location of the transcript log. Navigate to the `Logs\` directory to review the timestamped text file for a detailed audit of the deployment process.

## Roadmap

Future capabilities planned for integration into the framework include:

* **WMI Filter Automation:** Support for defining, generating, and linking WMI Filters directly via the `GPMgmt.GPM` COM interface to enforce hardware and OS-specific policy targeting.
* **Automated Workstation Joining:** Subroutines to automatically domain-join specified virtual machines and move them to their correct staging OUs.
* **LAPS Integration:** Automated deployment of the Local Administrator Password Solution schema and corresponding group policies.
