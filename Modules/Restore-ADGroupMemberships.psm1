function Restore-ADGroupMemberships {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)][string]$OrgNameInput,
        [Parameter(Mandatory=$true)][string]$JsonPath
    )

    if (-not (Test-Path $JsonPath)) { return }
    $Domain = Get-ADDomain
    $RootDN = "OU=$OrgNameInput,$($Domain.DistinguishedName)"

    # 100% reliable array extraction to dodge PS5.1 pipeline bugs
    [array]$RawData = Get-Content $JsonPath -Raw | ConvertFrom-Json
    $UserData = @()
    foreach ($item in $RawData) {
        if ($item.Type -ne "Template") { $UserData += $item }
    }

    Write-Host "`n--- Processing Security Memberships ---" -ForegroundColor Magenta

    # ==========================================
    # PHASE 1: GLOBAL BASELINES
    # ==========================================
    Write-Host " [i] Phase 1: Global Baselines..." -ForegroundColor White
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
                # FIXED: Swapped -Identity for -Filter
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

    # ==========================================
    # PHASE 2: TIERED ADMIN ROLES
    # ==========================================
    Write-Host "`n [i] Phase 2: Tiered Admin Roles..." -ForegroundColor White
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
            # FIXED: Swapped -Identity for -Filter
            $userRefresh = Get-ADUser -Filter "SamAccountName -eq '$SAM'" -Properties MemberOf

            if ($userRefresh -and $userRefresh.MemberOf -notcontains $roleGroupObj.DistinguishedName) {
                if ($PSCmdlet.ShouldProcess($SAM, "Add to Admin Role")) {
                    Add-ADGroupMember -Identity $RoleName -Members $SAM -ErrorAction Stop
                    Write-Host "   [>] Nested $SAM into $RoleName" -ForegroundColor Gray
                }
            }

            $NativeGroups = if ($U.Tier -eq "0") { @("Enterprise Admins", "Domain Admins", "Schema Admins") }
                            elseif ($U.Tier -eq "1") { @("Server Operators") } else { @() }

            foreach ($GroupName in $NativeGroups) {
                $nativeGroupObj = Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue
                if ($nativeGroupObj -and ($userRefresh.MemberOf -notcontains $nativeGroupObj.DistinguishedName)) {
                    if ($PSCmdlet.ShouldProcess($SAM, "Promote to Native Group")) {
                        Add-ADGroupMember -Identity $GroupName -Members $SAM -ErrorAction Stop
                        Write-Host "   [+] Promoted $SAM to native: $GroupName" -ForegroundColor Yellow
                    }
                }
            }
        } catch { Write-Host "  [!] Failed Admin Logic for ${SAM}: $($_.Exception.Message)" -ForegroundColor Red }
    }

    # ==========================================
    # PHASE 3: DEPARTMENTAL ROLES
    # ==========================================
    Write-Host "`n [i] Phase 3: Departmental Roles..." -ForegroundColor White
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
                    # FIXED: Swapped -Identity for -Filter
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

    # ==========================================
    # PHASE 4: CUSTOM EXCEPTION GROUPS
    # ==========================================
    Write-Host "`n [i] Phase 4: Custom Exceptions..." -ForegroundColor White
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
                    # FIXED: Swapped -Identity for -Filter
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
