#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Parses a JSON configuration file to provision Security/Distribution groups and handle nesting.
.DESCRIPTION
    Automates the creation of Global Baselines, Tiered Administrative Roles, Department-based Roles,
    and Custom Exceptions. Handles native Active Directory indexing delays via Wait-ForADObject.
#>
function Restore-ADGroupMemberships {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)][string]$OrgNameInput,
        [Parameter(Mandatory=$true)][string]$JsonPath
    )

    if (-not (Test-Path $JsonPath)) { return }
    $Domain = Get-ADDomain
    $RootDN = "OU=$OrgNameInput,$($Domain.DistinguishedName)"

    [array]$RawData = Get-Content $JsonPath -Raw | ConvertFrom-Json
    $UserData = @()
    foreach ($item in $RawData) {
        if ($item.Type -ne "Template") { $UserData += $item }
    }

    Write-Host "`n--- Processing Security Memberships ---" -ForegroundColor Magenta

    Write-Host " [i] Global Baselines..." -ForegroundColor White
    $BaselineGroups = @(
        @{ Name = "GRP-SEC-EVERYONE-GLOBAL"; Category = "Security";     Path = "Groups/Security" },
        @{ Name = "GRP-DISTRO-ALL-STAFF";    Category = "Distribution"; Path = "Groups/Distribution" }
    )

    foreach ($BG in $BaselineGroups) {
        $GlobalDN = Get-LabDN -SlashPath $BG.Path -RootDN $RootDN
        Assert-OUPath -SlashPath $BG.Path -RootDN $RootDN

        if (-not (Get-ADGroup -Filter "Name -eq '$($BG.Name)'" -ErrorAction SilentlyContinue)) {
            if ($PSCmdlet.ShouldProcess($BG.Name, "Create Global Baseline Group")) {
                New-ADGroup -Name $BG.Name -GroupCategory $BG.Category -GroupScope Global -Path $GlobalDN -ErrorAction Stop
                Write-Host "  [+] Created Baseline: $($BG.Name)" -ForegroundColor Cyan
            }
        }

        $globalGroupObj = Wait-ForADObject -Filter "Name -eq '$($BG.Name)'" -Type "Group"
        if ($globalGroupObj) {
            foreach ($U in $UserData) {
                $SAM = $U.SamAccountName
                $userRefresh = Get-ADUser -Filter "SamAccountName -eq '$SAM'" -Properties MemberOf
                if ($userRefresh -and $userRefresh.MemberOf -notcontains $globalGroupObj.DistinguishedName) {
                    if ($PSCmdlet.ShouldProcess($SAM, "Add to Baseline")) {
                        Add-ADGroupMember -Identity $BG.Name -Members $SAM -ErrorAction Stop
                        Write-Host "   [>] Added $SAM to $($BG.Name)" -ForegroundColor DarkGreen
                    }
                }
            }
        }
    }

    Write-Host "`n [i] Tiered Admin Roles..." -ForegroundColor White
    $AdminUsers = $UserData | Where-Object { $_.Type -eq "Admin" }

    foreach ($U in $AdminUsers) {
        $SAM = $U.SamAccountName
        $RoleName = "GRP-SEC-ADMIN-Tier-$($U.Tier)-Admins"
        $RolePath = "_Admin/Tier $($U.Tier)/T$($U.Tier)_Groups"

        try {
            $RoleDN = Get-LabDN -SlashPath $RolePath -RootDN $RootDN
            Assert-OUPath -SlashPath $RolePath -RootDN $RootDN

            if (-not (Get-ADGroup -Filter "Name -eq '$RoleName'" -ErrorAction SilentlyContinue)) {
                if ($PSCmdlet.ShouldProcess($RoleName, "Create Admin Role Group")) {
                    New-ADGroup -Name $RoleName -GroupCategory Security -GroupScope Global -Path $RoleDN -ErrorAction Stop
                    Write-Host "  [+] Created Admin Role: $RoleName" -ForegroundColor Cyan
                }
            }

            $roleGroupObj = Wait-ForADObject -Filter "Name -eq '$RoleName'" -Type "Group"
            $userRefresh = Get-ADUser -Filter "SamAccountName -eq '$SAM'" -Properties MemberOf

            if ($userRefresh -and $userRefresh.MemberOf -notcontains $roleGroupObj.DistinguishedName) {
                if ($PSCmdlet.ShouldProcess($SAM, "Add to Admin Role")) {
                    Add-ADGroupMember -Identity $RoleName -Members $SAM -ErrorAction Stop
                    Write-Host "   [>] Nested $SAM into $RoleName" -ForegroundColor Gray
                }
            }
        } catch { Write-Host "  [!] Failed Admin Logic for ${SAM}: $($_.Exception.Message)" -ForegroundColor Red }
    }

    Write-Host "`n [i] Departmental Roles..." -ForegroundColor White
    $RoleUsers = $UserData | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Department) }
    $GroupedByDept = $RoleUsers | Group-Object Department

    foreach ($DeptGroup in $GroupedByDept) {
        $DeptName = $DeptGroup.Name
        $RoleGroupName = "GRP-ROLE-$DeptName"
        $RoleSlashPath = "Groups/Roles"

        try {
            $RoleDN = Get-LabDN -SlashPath $RoleSlashPath -RootDN $RootDN
            Assert-OUPath -SlashPath $RoleSlashPath -RootDN $RootDN

            if (-not (Get-ADGroup -Filter "Name -eq '$RoleGroupName'" -ErrorAction SilentlyContinue)) {
                if ($PSCmdlet.ShouldProcess($RoleGroupName, "Create Role Group")) {
                    New-ADGroup -Name $RoleGroupName -GroupCategory Security -GroupScope Global -Path $RoleDN -ErrorAction Stop
                    Write-Host "  [+] Created Dept Group: $RoleGroupName" -ForegroundColor Cyan
                }
            }

            $roleGroupObj = Wait-ForADObject -Filter "Name -eq '$RoleGroupName'" -Type "Group"
            if ($roleGroupObj) {
                foreach ($U in $DeptGroup.Group) {
                    $SAM = $U.SamAccountName
                    $userRefresh = Get-ADUser -Filter "SamAccountName -eq '$SAM'" -Properties MemberOf
                    if ($userRefresh -and $userRefresh.MemberOf -notcontains $roleGroupObj.DistinguishedName) {
                        if ($PSCmdlet.ShouldProcess($SAM, "Add to Dept Role")) {
                            Add-ADGroupMember -Identity $RoleGroupName -Members $SAM -ErrorAction Stop
                            Write-Host "   [>] Nested $SAM into $RoleGroupName" -ForegroundColor Gray
                        }
                    }
                }
            }
        } catch {
            Write-Host "  [!] Failed Role Group [$RoleGroupName]: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`n [i] Custom Exceptions (JSON Assigned Native Groups)..." -ForegroundColor White
    $CustomUsers = $UserData | Where-Object { $_.Groups }

    foreach ($U in $CustomUsers) {
        $SAM = $U.SamAccountName
        foreach ($GrpObj in $U.Groups) {
            $GName = $GrpObj.Name
            try {
                $GrpDN = Get-LabDN -SlashPath $GrpObj.TargetOU -RootDN $RootDN
                Assert-OUPath -SlashPath $GrpObj.TargetOU -RootDN $RootDN

                if (-not (Get-ADGroup -Filter "Name -eq '$GName'" -ErrorAction SilentlyContinue)) {
                    if ($PSCmdlet.ShouldProcess($GName, "Create Custom Group")) {
                        New-ADGroup -Name $GName -GroupCategory Security -GroupScope Global -Path $GrpDN -ErrorAction Stop
                        Write-Host "  [+] Created Custom Group: $GName" -ForegroundColor Cyan
                    }
                }

                $groupObj = Wait-ForADObject -Filter "Name -eq '$GName'" -Type "Group"
                if ($groupObj) {
                    $userRefresh = Get-ADUser -Filter "SamAccountName -eq '$SAM'" -Properties MemberOf
                    if ($userRefresh -and $userRefresh.MemberOf -notcontains $groupObj.DistinguishedName) {
                        if ($PSCmdlet.ShouldProcess($SAM, "Add to Custom Group")) {
                            Add-ADGroupMember -Identity $GName -Members $SAM -ErrorAction Stop
                            Write-Host "   [>] Added $SAM to $GName" -ForegroundColor DarkGreen
                        }
                    }
                }
            } catch {
                Write-Host "  [!] Failed Group [$GName]: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
}
Export-ModuleMember -Function Restore-ADGroupMemberships
