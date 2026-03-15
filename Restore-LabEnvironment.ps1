<#
.SYNOPSIS
    Orchestrator script to rebuild the Active Directory lab environment.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$OrgName,

    [switch]$DisableProtection,

    [string]$StructureJson = ".\Modules\ADStructure.json",
    [string]$UserDataJson  = ".\Modules\ADUserData.json",
    [string]$GpoJson       = ".\Modules\ADGroupPolicies.json"
)

# 1. Import Modules
# Using relative paths to the .psm1 files in their respective folders
try {
    Import-Module ".\Modules\Restore-ADStructure.psm1" -Force
    Import-Module ".\Modules\Restore-ADUsers.psm1" -Force
    Import-Module ".\Modules\Restore-ADGroupPolicies.psm1" -Force
} catch {
    Write-Error "Failed to load modules. Ensure the 'Modules' folder structure is correct."
    return
}

Write-Host "--- Starting Lab Restoration for $OrgName ---" -ForegroundColor Magenta

# 2. Run Structure
Write-Host "`n[STEP 1] Rebuilding OU Structure..." -ForegroundColor White -BackgroundColor DarkBlue
Restore-ADStructure -OrgNameInput $OrgName -JsonPath $StructureJson -DisableProtection:$DisableProtection

# 3. Run Users
Write-Host "`n[STEP 2] Restoring User Accounts and Tiered Groups..." -ForegroundColor White -BackgroundColor DarkBlue
Restore-ADUsers -OrgNameInput $OrgName -JsonPath $UserDataJson

# 4. Run GPOs
Write-Host "`n[STEP 3] Applying Group Policies and Links..." -ForegroundColor White -BackgroundColor DarkBlue
Restore-ADGroupPolicies -OrgNameInput $OrgName -JsonPath $GpoJson

Write-Host "`n--- Lab Restoration Complete ---" -ForegroundColor Magenta
Write-Host "Remember to run 'gpupdate /force' on your Domain Controller." -ForegroundColor Gray
