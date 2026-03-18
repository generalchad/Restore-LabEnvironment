[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$OrgName,

    [switch]$DisableProtection,

    [string]$StructureJson = "$PSScriptRoot\Config\ADStructure.json",
    [string]$UserDataJson  = "$PSScriptRoot\Config\ADUserData.json",
    [string]$GpoJson       = "$PSScriptRoot\Config\ADGroupPolicies.json"
)

function Write-LabLog {
    param([string]$Message, [ValidateSet("INFO", "OK", "SKIP", "FAIL", "HEAD")]$Type = "INFO")
    $Colors = @{ INFO = "Cyan"; OK = "Green"; SKIP = "Yellow"; FAIL = "Red"; HEAD = "Magenta" }
    $Markers = @{ INFO = "[i]"; OK = "[+]"; SKIP = "[!]"; FAIL = "[X]"; HEAD = "---" }
    Write-Host "$($Markers[$Type]) $Message" -ForegroundColor $Colors[$Type]
}

# 1. Admin & RSAT Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-LabLog "Admin privileges required. Please run PowerShell as Administrator." "FAIL"; return
}

# RSAT Check Logic
$RequiredModules = @("ActiveDirectory", "GroupPolicy")
foreach ($Mod in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $Mod)) {
        Write-LabLog "Missing RSAT Feature: $Mod. Please install RSAT via Optional Features or Server Manager." "FAIL"
        return
    }
}

# 2. Module Loading
try {
    Write-LabLog "Loading Lab Modules..." "INFO"
    Import-Module ActiveDirectory, GroupPolicy -ErrorAction Stop

    $CustomModules = @("Restore-LabUtils", "Restore-ADStructure", "Restore-ADUsers", "Restore-ADGroupPolicies", "Restore-ADGroupMemberships")
    foreach ($M in $CustomModules) {
        $P = Join-Path $PSScriptRoot "Modules\$M.psm1"
        if (Test-Path $P) {
            Import-Module $P -Force
            Write-LabLog "Loaded $M" "OK"
        } else {
            throw "Missing module file at $P"
        }
    }
} catch {
    Write-LabLog "Load Error: $($_.Exception.Message)" "FAIL"
    return
}

# 3. Execution
$CleanOrg = "_" + $OrgName.Trim().TrimStart('_').ToUpper()
Write-LabLog "Starting Lab Restoration for $CleanOrg" "HEAD"

# Splatting Parameters
$StructureParams = @{ OrgNameInput = $CleanOrg; DisableProtection = $DisableProtection; JsonPath = $StructureJson }
$UserParams      = @{ OrgNameInput = $CleanOrg; JsonPath = $UserDataJson }
$GpoParams       = @{ OrgNameInput = $CleanOrg; JsonPath = $GpoJson }
$MemberParams    = @{ OrgNameInput = $CleanOrg; JsonPath = $UserDataJson }

try {
    # Perform restoration steps sequentially
    Write-LabLog "Step 1: Restoring AD OU Structure..." "INFO"
    Restore-ADStructure @StructureParams

    Write-LabLog "Step 2: Restoring AD Users..." "INFO"
    Restore-ADUsers @UserParams

    Write-LabLog "Step 3: Restoring Group Policies..." "INFO"
    Restore-ADGroupPolicies @GpoParams

    Write-LabLog "Step 4: Restoring Group Memberships..." "INFO"
    Restore-ADGroupMemberships @MemberParams

    Write-LabLog "Restoration Complete." "HEAD"
}
catch {
    Write-LabLog "Critical Failure during restoration: $($_.Exception.Message)" "FAIL"
}
