#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Parses JSON configuration files to enforce the exact Desired State of Security and Distribution groups.
.DESCRIPTION
    Compiles a master dictionary of desired group memberships based on Global Baselines, Admin Tiers,
    Departments, and Custom Exceptions. Compares this dictionary against Active Directory to perform
    idempotent synchronization, adding missing members and aggressively pruning unauthorized drift
    for managed user accounts.
#>
function Restore-ADGroupMemberships {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)][string]$OrgNameInput,
        [Parameter(Mandatory=$true)][string]$JsonPath,
        [string]$BaselineJson
    )

    if (-not (Test-Path $JsonPath)) { return }
    $Domain = Get-ADDomain
    $RootDN = "OU=$OrgNameInput,$($Domain.DistinguishedName)"

    [array]$RawData = Get-Content $JsonPath -Raw | ConvertFrom-Json
    $UserData = $RawData | Where-Object { $_.Type -ne "Template" }
    $ManagedSAMs = $UserData.SamAccountName

    Write-Host "`n--- Compiling Desired State Dictionary ---" -ForegroundColor Magenta

    $DesiredState = @{}

    function Add-ToDesiredState ($GrpName, $Category, $Path, $UserSAM) {
        if (-not $DesiredState.ContainsKey($GrpName)) {
            $DesiredState[$GrpName] = @{
                Category = $Category
                Path = $Path
                Members = @()
            }
        }
        if ($null -ne $UserSAM -and $UserSAM -notin $DesiredState[$GrpName].Members) {
            $DesiredState[$GrpName].Members += $UserSAM
        }
    }

    [array]$BaselineGroups = if ($BaselineJson -and (Test-Path $BaselineJson)) { Get-Content $BaselineJson -Raw | ConvertFrom-Json } else { @() }
    foreach ($BG in $BaselineGroups) {
        Add-ToDesiredState -GrpName $BG.Name -Category $BG.Category -Path $BG.Path -UserSAM $null
        foreach ($U in $UserData) {
            Add-ToDesiredState -GrpName $BG.Name -Category $BG.Category -Path $BG.Path -UserSAM $U.SamAccountName
        }
    }

    foreach ($U in ($UserData | Where-Object { $_.Type -eq "Admin" })) {
        $RoleName = "GRP-SEC-ADMIN-Tier-$($U.Tier)-Admins"
        $RolePath = "_Admin/Tier $($U.Tier)/T$($U.Tier)_Groups"
        Add-ToDesiredState -GrpName $RoleName -Category "Security" -Path $RolePath -UserSAM $U.SamAccountName
    }

    foreach ($U in ($UserData | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Department) })) {
        $RoleName = "GRP-ROLE-$($U.Department)"
        $RolePath = "Groups/Roles"
        Add-ToDesiredState -GrpName $RoleName -Category "Security" -Path $RolePath -UserSAM $U.SamAccountName
    }

    foreach ($U in ($UserData | Where-Object { $_.Groups })) {
        foreach ($GrpObj in $U.Groups) {
            Add-ToDesiredState -GrpName $GrpObj.Name -Category "Security" -Path $GrpObj.TargetOU -UserSAM $U.SamAccountName
        }
    }

    Write-Host " [i] Compiled $($DesiredState.Keys.Count) Groups for Synchronization." -ForegroundColor White
    Write-Host "`n--- Executing Synchronization ---" -ForegroundColor Magenta

    foreach ($GroupName in $DesiredState.Keys) {
        $GroupInfo = $DesiredState[$GroupName]
        $TargetDN = Get-LabDN -SlashPath $GroupInfo.Path -RootDN $RootDN

        $groupObj = Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue
        if (-not $groupObj) {
            Assert-OUPath -SlashPath $GroupInfo.Path -RootDN $RootDN
            if ($PSCmdlet.ShouldProcess($GroupName, "Create Group")) {
                New-ADGroup -Name $GroupName -GroupCategory $GroupInfo.Category -GroupScope Global -Path $TargetDN -ErrorAction Stop
                Write-Host "  [+] Created Group: $GroupName" -ForegroundColor Cyan
                $groupObj = Wait-ForADObject -Filter "Name -eq '$GroupName'" -Type "Group"
            }
        }

        if ($groupObj) {
            $CurrentMembers = Get-ADGroupMember -Identity $GroupName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SamAccountName
            if ($null -eq $CurrentMembers) { $CurrentMembers = @() }

            $DesiredMembers = $GroupInfo.Members

            $ToAdd = $DesiredMembers | Where-Object { $_ -notin $CurrentMembers }
            $ToRemove = $CurrentMembers | Where-Object { $_ -notin $DesiredMembers -and $_ -in $ManagedSAMs }

            if ($ToAdd) {
                if ($PSCmdlet.ShouldProcess($GroupName, "Add Members: $($ToAdd -join ', ')")) {
                    Add-ADGroupMember -Identity $GroupName -Members $ToAdd -ErrorAction Stop
                    Write-Host "   [>] Synced (Added) to ${GroupName}: $($ToAdd -join ', ')" -ForegroundColor DarkGreen
                }
            }

            if ($ToRemove) {
                if ($PSCmdlet.ShouldProcess($GroupName, "Remove Members: $($ToRemove -join ', ')")) {
                    Remove-ADGroupMember -Identity $GroupName -Members $ToRemove -Confirm:$false -ErrorAction Stop
                    Write-Host "   [<] Synced (Removed) from ${GroupName}: $($ToRemove -join ', ')" -ForegroundColor DarkYellow
                }
            }

            if (-not $ToAdd -and -not $ToRemove) {
                Write-Host "   [-] $GroupName is in desired state." -ForegroundColor DarkGray
            }
        }
    }
}
Export-ModuleMember -Function Restore-ADGroupMemberships
