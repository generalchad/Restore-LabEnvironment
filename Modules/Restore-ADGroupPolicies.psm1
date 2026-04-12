#Requires -Modules ActiveDirectory, GroupPolicy

<#
.SYNOPSIS
    Parses a JSON configuration file to provision, configure, and link Group Policy Objects.
.DESCRIPTION
    Automates the generation of GPOs, assigns Registry Preferences, configures MS16-072 compliant
    Security Filtering via Set-GPPermission, and manages WMI filter linking by modifying AD attributes natively.
#>
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
    $DomainName = $Domain.DNSRoot
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
                            New-GPLink -Name $GReq.DisplayName -Target $Target -Enforced $Enforced -ErrorAction Stop | Out-Null
                            Write-Host "  [>] Linked to: $Target (Enforced: $Enforced)" -ForegroundColor Cyan
                        }
                    } else {
                        Set-GPLink -Name $GReq.DisplayName -Target $Target -Enforced $Enforced -ErrorAction SilentlyContinue | Out-Null
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
                    $WmiBase = "CN=SOM,CN=WMIPolicy,CN=System,$DomainDN"

                    $WmiObj = Get-ADObject -Filter "msWMI-Name -eq '$($GReq.WmiFilterName)'" -SearchBase $WmiBase -ErrorAction SilentlyContinue

                    if ($WmiObj) {
                        $GpoADPath = "CN={$($GPO.Id.ToString())},CN=Policies,CN=System,$DomainDN"

                        $FilterLinkStr = "[$DomainName;$($WmiObj.Name);0]"

                        Set-ADObject -Identity $GpoADPath -Replace @{gPCWQLFilter = $FilterLinkStr} -ErrorAction Stop

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
