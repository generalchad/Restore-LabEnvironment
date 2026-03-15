[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$OrgName,

    [switch]$DisableProtection,

    [string]$StructureJson = "$PSScriptRoot\Modules\ADStructure.json",
    [string]$UserDataJson  = "$PSScriptRoot\Modules\ADUserData.json",
    [string]$GpoJson       = "$PSScriptRoot\Modules\ADGroupPolicies.json"
)

function Write-LabLog {
    param([string]$Message, [ValidateSet("INFO", "OK", "SKIP", "FAIL", "HEAD")]$Type = "INFO")
    $Colors = @{ INFO = "Cyan"; OK = "Green"; SKIP = "Yellow"; FAIL = "Red"; HEAD = "Magenta" }
    $Markers = @{ INFO = "[i]"; OK = "[+]"; SKIP = "[!]"; FAIL = "[X]"; HEAD = "---" }
    Write-Host "$($Markers[$Type]) $Message" -ForegroundColor $Colors[$Type]
}

# 1. Admin & RSAT Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-LabLog "Admin privileges required." "FAIL"; return
}

# (RSAT Check Logic Omitted for Brevity - Keep your existing block here)

# 2. Module Loading
try {
    Import-Module ActiveDirectory, GroupPolicy -ErrorAction Stop
    # Added Memberships to the array
    $CustomModules = @("Restore-LabUtils", "Restore-ADStructure", "Restore-ADUsers", "Restore-ADGroupPolicies", "Restore-ADGroupMemberships")
    foreach ($M in $CustomModules) {
        $P = Join-Path $PSScriptRoot "Modules\$M.psm1"
        if (Test-Path $P) { Import-Module $P -Force } else { throw "Missing $P" }
    }
} catch { Write-LabLog "Load Error: $($_.Exception.Message)" "FAIL"; return }

# 3. Execution
$CleanOrg = "_" + $OrgName.Trim().TrimStart('_').ToUpper()
Write-LabLog "Starting Lab Restoration for $CleanOrg" "HEAD"

# Core Parameters
$StructureParams = @{ OrgNameInput = $CleanOrg; DisableProtection = $DisableProtection; JsonPath = $StructureJson }
$UserParams      = @{ OrgNameInput = $CleanOrg; JsonPath = $UserDataJson }
$GpoParams       = @{ OrgNameInput = $CleanOrg; JsonPath = $GpoJson }
$MemberParams    = @{ OrgNameInput = $CleanOrg; JsonPath = $UserDataJson } # Uses User JSON for mapping

Restore-ADStructure     @StructureParams
Restore-ADUsers         @UserParams
Restore-ADGroupPolicies @GpoParams
Restore-ADGroupMemberships @MemberParams # Final Pass

Write-LabLog "Restoration Complete." "HEAD"
