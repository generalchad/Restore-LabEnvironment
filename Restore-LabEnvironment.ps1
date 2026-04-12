[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$OrgName,

    [switch]$DisableProtection,

    [string]$StructureJson = "$PSScriptRoot\Config\ADStructure.json",
    [string]$UserDataJson  = "$PSScriptRoot\Config\ADUserData.json",
    [string]$GpoJson       = "$PSScriptRoot\Config\ADGroupPolicies.json"
)

Set-StrictMode -Version Latest

function Write-LabLog {
    param([string]$Message, [ValidateSet("INFO", "OK", "SKIP", "FAIL", "HEAD")]$Type = "INFO")
    $Colors = @{ INFO = "Cyan"; OK = "Green"; SKIP = "Yellow"; FAIL = "Red"; HEAD = "Magenta" }
    $Markers = @{ INFO = "[i]"; OK = "[+]"; SKIP = "[!]"; FAIL = "[X]"; HEAD = "---" }

    Write-Host "$($Markers[$Type]) $Message" -ForegroundColor $Colors[$Type]
    Write-Information "$($Markers[$Type]) $Message"
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-LabLog "Admin privileges required. Please run PowerShell as Administrator." "FAIL"; return
}

$RequiredModules = @("ActiveDirectory", "GroupPolicy")
foreach ($Mod in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $Mod)) {
        Write-LabLog "Missing RSAT Feature: $Mod. Please install RSAT via Optional Features or Server Manager." "FAIL"
        return
    }
}

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

$CleanOrg = "_" + $OrgName.Trim().TrimStart('_').ToUpper()
$LogPath = Join-Path $PSScriptRoot "Logs\LabBuild_$($CleanOrg)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

if (-not (Test-Path (Join-Path $PSScriptRoot "Logs"))) {
    New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot "Logs") | Out-Null
}

Write-LabLog "Starting Lab Restoration for $CleanOrg" "HEAD"

$StructureParams = @{ OrgNameInput = $CleanOrg; DisableProtection = $DisableProtection; JsonPath = $StructureJson; ErrorAction = 'Stop' }
$UserParams      = @{ OrgNameInput = $CleanOrg; JsonPath = $UserDataJson; ErrorAction = 'Stop' }
$GpoParams       = @{ OrgNameInput = $CleanOrg; JsonPath = $GpoJson; ErrorAction = 'Stop' }
$MemberParams    = @{ OrgNameInput = $CleanOrg; JsonPath = $UserDataJson; ErrorAction = 'Stop' }

try {
    Start-Transcript -Path $LogPath -Append -Force | Out-Null

    Write-LabLog "Step 1: Restoring AD OU Structure..." "INFO"
    Restore-ADStructure @StructureParams

    Write-LabLog "Step 2: Restoring AD Users..." "INFO"
    Restore-ADUsers @UserParams

    Write-LabLog "Step 3: Restoring Group Policies..." "INFO"
    Restore-ADGroupPolicies @GpoParams

    Write-LabLog "Step 4: Restoring Group Memberships..." "INFO"
    Restore-ADGroupMemberships @MemberParams

    Write-LabLog "Restoration Complete. Log saved to $LogPath" "HEAD"
}
catch {
    Write-LabLog "Critical Failure during restoration: $($_.Exception.Message)" "FAIL"
}
finally {
    Stop-Transcript | Out-Null
}
