function Restore-ADGroupMemberships {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)][string]$OrgNameInput,
        [Parameter(Mandatory=$true)][string]$JsonPath
    )

    if (-not (Test-Path $JsonPath)) { return }
    $Domain = Get-ADDomain
    $RootDN = "OU=$OrgNameInput,$($Domain.DistinguishedName)"
    [array]$UserData = Get-Content $JsonPath -Raw | ConvertFrom-Json

    Write-Host "`n--- Processing Security Memberships ---" -ForegroundColor Magenta

    foreach ($U in $UserData) {
        $SAM = [string]$U.SamAccountName

        $userObj = Wait-ForADObject -Filter "SamAccountName -eq '$SAM'" -Type "User"
        if (-not $userObj) { continue }

        # --- 0. GLOBAL BASELINE LOGIC (Applies to everyone) ---
        $BaselineGroups = @(
            @{ Name = "GRP-SEC-EVERYONE-GLOBAL"; Category = "Security";     Path = "Groups/Security" },
            @{ Name = "GRP-DISTRO-ALL-STAFF";    Category = "Distribution"; Path = "Groups/Distribution" }
        )

        foreach ($BG in $BaselineGroups) {
            try {
                $GlobalDN = Get-LabDN -SlashPath $BG.Path -RootDN $RootDN
                Assert-OUPath -SlashPath $BG.Path -RootDN $RootDN

                if (-not (Get-ADGroup -Filter "Name -eq '$($BG.Name)'" -ErrorAction SilentlyContinue)) {
                    if ($PSCmdlet.ShouldProcess($BG.Name, "Create Global Baseline Group")) {
                        New-ADGroup -Name $BG.Name -GroupCategory $BG.Category -GroupScope Global -Path $GlobalDN -ErrorAction Stop
                        Write-Host "  [+] Created Baseline Group: $($BG.Name)" -ForegroundColor Cyan
                    }
                }

                $globalGroupObj = Wait-ForADObject -Filter "Name -eq '$($BG.Name)'" -Type "Group"
                if ($globalGroupObj) {
                    $userRefresh = Get-ADUser -Identity $SAM -Properties MemberOf
                    if ($userRefresh.MemberOf -notcontains $globalGroupObj.DistinguishedName) {
                        Add-ADGroupMember -Identity $BG.Name -Members $SAM -ErrorAction Stop
                        Write-Host "   [>] $SAM added to Baseline: $($BG.Name)" -ForegroundColor DarkGreen
                    }
                }
            } catch {
                Write-Host "  [!] Failed Global Baseline assignment ($($BG.Name)): $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        # --- 1. CUSTOM JSON GROUPS ---
        if ($U.Groups) {
            foreach ($GrpObj in $U.Groups) {
                $GName = $GrpObj.Name
                try {
                    $GrpDN = Get-LabDN -SlashPath $GrpObj.TargetOU -RootDN $RootDN
                    Assert-OUPath -SlashPath $GrpObj.TargetOU -RootDN $RootDN

                    $groupObj = Get-ADGroup -Filter "Name -eq '$GName'" -ErrorAction SilentlyContinue
                    if (-not $groupObj) {
                        if ($PSCmdlet.ShouldProcess($GName, "Create Custom Group")) {
                            New-ADGroup -Name $GName -GroupCategory Security -GroupScope Global -Path $GrpDN -ErrorAction Stop
                            Write-Host "  [+] Created JSON Group: $GName" -ForegroundColor Cyan
                            $groupObj = Wait-ForADObject -Filter "Name -eq '$GName'" -Type "Group"
                        }
                    }

                    if ($groupObj) {
                        $userRefresh = Get-ADUser -Identity $SAM -Properties MemberOf
                        if ($userRefresh.MemberOf -notcontains $groupObj.DistinguishedName) {
                            if ($PSCmdlet.ShouldProcess($SAM, "Add to $GName")) {
                                Add-ADGroupMember -Identity $GName -Members $SAM -ErrorAction Stop
                                Write-Host "    -> Added to $GName" -ForegroundColor DarkGreen
                            }
                        }
                    }
                } catch {
                    Write-Host "  [!] Failed Group [$GName]: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }

        # --- 2. TIERED ADMIN LOGIC ---
        if ($U.Type -eq "Admin") {
            $RoleName = "GRP-SEC-ADMIN-Tier-$($U.Tier)-Admins"
            $RolePath = "_Admin/Tier $($U.Tier)/T$($U.Tier)_Groups"

            try {
                $RoleDN = Get-LabDN -SlashPath $RolePath -RootDN $RootDN
                Assert-OUPath -SlashPath $RolePath -RootDN $RootDN

                if (-not (Get-ADGroup -Filter "Name -eq '$RoleName'" -ErrorAction SilentlyContinue)) {
                    New-ADGroup -Name $RoleName -GroupCategory Security -GroupScope Global -Path $RoleDN -ErrorAction Stop
                    Write-Host "  [+] Created Admin Role: $RoleName" -ForegroundColor Cyan
                }

                $roleGroupObj = Wait-ForADObject -Filter "Name -eq '$RoleName'" -Type "Group"
                $userRefresh = Get-ADUser -Identity $SAM -Properties MemberOf
                if ($userRefresh.MemberOf -notcontains $roleGroupObj.DistinguishedName) {
                    Add-ADGroupMember -Identity $RoleName -Members $SAM -ErrorAction Stop
                    Write-Host "   [>] $SAM nested into: $RoleName" -ForegroundColor Gray
                }

                # Native Groups (Domain Admins, etc.)
                $NativeGroups = if ($U.Tier -eq "0") { @("Enterprise Admins", "Domain Admins", "Schema Admins") }
                                elseif ($U.Tier -eq "1") { @("Server Operators") } else { @() }

                foreach ($GroupName in $NativeGroups) {
                    $nativeGroupObj = Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue
                    if ($nativeGroupObj -and ($userRefresh.MemberOf -notcontains $nativeGroupObj.DistinguishedName)) {
                        Add-ADGroupMember -Identity $GroupName -Members $SAM -ErrorAction Stop
                        Write-Host "  [+] $SAM promoted to native: $GroupName" -ForegroundColor Yellow
                    }
                }
            } catch { Write-Host "  [!] Failed Admin Logic for ${SAM}: $($_.Exception.Message)" -ForegroundColor Red }
        }

        # --- 3. DEPARTMENTAL / ROLE LOGIC ---
        if ($U.Department) {
            $RoleGroupName = "GRP-ROLE-$($U.Department)"
            $RoleSlashPath = "Groups/Roles"

            try {
                $RoleDN = Get-LabDN -SlashPath $RoleSlashPath -RootDN $RootDN
                Assert-OUPath -SlashPath $RoleSlashPath -RootDN $RootDN

                if (-not (Get-ADGroup -Filter "Name -eq '$RoleGroupName'" -ErrorAction SilentlyContinue)) {
                    if ($PSCmdlet.ShouldProcess($RoleGroupName, "Create Role Group")) {
                        New-ADGroup -Name $RoleGroupName -GroupCategory Security -GroupScope Global -Path $RoleDN -ErrorAction Stop
                        Write-Host "  [+] Created Department Group: $RoleGroupName" -ForegroundColor Cyan
                    }
                }

                $roleGroupObj = Wait-ForADObject -Filter "Name -eq '$RoleGroupName'" -Type "Group"
                if ($roleGroupObj) {
                    $userRefresh = Get-ADUser -Identity $SAM -Properties MemberOf
                    if ($userRefresh.MemberOf -notcontains $roleGroupObj.DistinguishedName) {
                        Add-ADGroupMember -Identity $RoleGroupName -Members $SAM -ErrorAction Stop
                        Write-Host "   [>] $SAM nested into: $RoleGroupName" -ForegroundColor Gray
                    }
                }
            } catch {
                Write-Host "  [!] Failed Role Group [$RoleGroupName]: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}
Export-ModuleMember -Function Restore-ADGroupMemberships
