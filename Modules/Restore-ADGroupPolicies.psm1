#Requires -Modules ActiveDirectory, GroupPolicy

function Restore-ADGroupPolicies {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$OrgNameInput,

        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_})]
        [string]$JsonPath
    )

    $Domain = Get-ADDomain
    $DomainDN = $Domain.DistinguishedName
    $DomainName = $Domain.Forest
    $RootPath = "OU=$OrgNameInput,$DomainDN"

    [array]$GPOData = Get-Content -Path $JsonPath -Raw | ConvertFrom-Json

    foreach ($GReq in $GPOData) {
        $GPO = $null
        $TargetObj = $null

        Write-Host "`n[*] Processing GPO: $($GReq.DisplayName)" -ForegroundColor Yellow

        try {
            $GPO = Get-GPO -Name $GReq.DisplayName -ErrorAction SilentlyContinue

            if (-not $GPO) {
                if ($PSCmdlet.ShouldProcess($GReq.DisplayName, "Create GPO")) {
                    $GPOComment = if ([string]::IsNullOrWhiteSpace($GReq.Comment)) { "Automated Lab" } else { $GReq.Comment }
                    $GPO = New-GPO -Name $GReq.DisplayName -Comment $GPOComment -ErrorAction Stop
                    Write-Host "  [+] Created successfully" -ForegroundColor Green
                }
            } else {
                Write-Host "  [-] Already exists" -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "  [X] Creation Failed: $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        if ($GPO -and $null -ne $GReq.TargetOU) {
            try {
                $Target = Get-LabDN -SlashPath $GReq.TargetOU -RootDN $RootPath
                $TargetObj = Get-ADObject -Identity $Target -Properties gPLink -ErrorAction SilentlyContinue

                if ($TargetObj) {
                    $Links = $TargetObj.gPLink
                    $Enforced = if ($GReq.Enforced) { "Yes" } else { "No" }

                    if ($Links -notmatch $GPO.Id.Guid) {
                        if ($PSCmdlet.ShouldProcess($Target, "Link GPO $($GReq.DisplayName)")) {
                            New-GPLink -Name $GReq.DisplayName -Target $Target -Enforcement $Enforced -ErrorAction Stop | Out-Null
                            Write-Host "  [>] Linked to: $Target (Enforced: $Enforced)" -ForegroundColor Cyan
                        }
                    } else {
                        # Ensure enforcement state is correct even if already linked
                        Set-GPLink -Name $GReq.DisplayName -Target $Target -Enforcement $Enforced -ErrorAction SilentlyContinue | Out-Null
                        Write-Host "  [-] Already linked to target (Enforced: $Enforced)" -ForegroundColor DarkGray
                    }
                } else {
                    Write-Host "  [X] Target path not found in AD: $Target" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "  [X] Linking Failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        if ($GPO -and $GReq.Settings) {
            foreach ($S in $GReq.Settings) {
                try {
                    if ($PSCmdlet.ShouldProcess("$($S.Key)\$($S.ValueName)", "Set Registry Preference")) {
                        Set-GPRegistryValue -Name $GReq.DisplayName -Key $S.Key -ValueName $S.ValueName -Type $S.Type -Value $S.Value -ErrorAction Stop | Out-Null
                        Write-Host "  [+] Configured Registry: $($S.ValueName)" -ForegroundColor Green
                    }
                } catch {
                    Write-Host "  [X] RegKey Failed ($($S.ValueName)): $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }

        if ($GPO -and $GReq.SecurityFilters) {
            try {
                if ($GReq.RemoveAuthUsersApply) {
                    # MS16-072 dictates Authenticated Users MUST have 'Read' to evaluate the GPO, even if they don't apply it.
                    Set-GPPermission -Name $GReq.DisplayName -PermissionLevel GpoRead -TargetName "Authenticated Users" -TargetType Group -ErrorAction Stop | Out-Null
                    Write-Host "  [+] Authenticated Users restricted to 'Read' only" -ForegroundColor Green
                }

                foreach ($SecGroup in $GReq.SecurityFilters) {
                    if ($PSCmdlet.ShouldProcess($SecGroup, "Add GPO Apply Permission")) {
                        Set-GPPermission -Name $GReq.DisplayName -PermissionLevel GpoApply -TargetName $SecGroup -TargetType Group -ErrorAction Stop | Out-Null
                        Write-Host "  [+] Security Filter applied for: $SecGroup" -ForegroundColor Green
                    }
                }
            } catch {
                Write-Host "  [X] Security Filtering Failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        if ($GPO -and $GReq.WmiFilterName) {
            try {
                if ($PSCmdlet.ShouldProcess($GReq.WmiFilterName, "Link WMI Filter")) {
                    # Native PowerShell lacks a WMI Link cmdlet. We must use the GPMgmt COM Object.
                    $GPM = New-Object -ComObject GPMgmt.GPM
                    $Constants = $GPM.GetConstants()
                    $GPMDomain = $GPM.GetDomain($DomainName, "", $Constants.UseAnyDC)

                    # Search for the specified WMI Filter
                    $Search = $GPM.CreateSearchCriteria()
                    $Search.Add($Constants.SearchPropertyWMIFilterName, $Constants.SearchOpEquals, $GReq.WmiFilterName)
                    $WMIFilters = $GPMDomain.SearchWMIFilters($Search)

                    if ($WMIFilters.Count -gt 0) {
                        $TargetFilter = $WMIFilters.Item(1)
                        $GPM_GPO = $GPMDomain.GetGPO($GPO.Id.Guid)
                        $GPM_GPO.SetWMIFilter($TargetFilter)
                        Write-Host "  [+] WMI Filter Linked: $($GReq.WmiFilterName)" -ForegroundColor Green
                    } else {
                        Write-Host "  [X] WMI Filter not found in domain: $($GReq.WmiFilterName)" -ForegroundColor Yellow
                    }
                }
            } catch {
                Write-Host "  [X] WMI Filter Link Failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}
Export-ModuleMember -Function Restore-ADGroupPolicies
