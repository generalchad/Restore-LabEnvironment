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

    $DomainDN = (Get-ADDomain).DistinguishedName
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
            continue # Skip linking and registry if we don't have a valid GPO object
        }

        if ($GPO -and $null -ne $GReq.TargetOU) {
            try {
                # Assuming Get-LabDN correctly returns the Domain root DN if TargetOU is empty ""
                $Target = Get-LabDN -SlashPath $GReq.TargetOU -RootDN $RootPath

                # Use Get-ADObject so it works on Domain Roots AND OUs
                $TargetObj = Get-ADObject -Identity $Target -Properties gPLink -ErrorAction SilentlyContinue

                if ($TargetObj) {
                    $Links = $TargetObj.gPLink
                    if ($Links -notmatch $GPO.Id.Guid) {
                        if ($PSCmdlet.ShouldProcess($Target, "Link GPO $($GReq.DisplayName)")) {
                            New-GPLink -Name $GReq.DisplayName -Target $Target -ErrorAction Stop | Out-Null
                            Write-Host "  [>] Linked to: $Target" -ForegroundColor Cyan
                        }
                    } else {
                        Write-Host "  [-] Already linked to target" -ForegroundColor DarkGray
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
                        Set-GPRegistryValue -Name $GReq.DisplayName `
                                            -Key $S.Key `
                                            -ValueName $S.ValueName `
                                            -Type $S.Type `
                                            -Value $S.Value `
                                            -ErrorAction Stop | Out-Null
                        Write-Host "  [+] Configured Registry: $($S.ValueName)" -ForegroundColor Green
                    }
                } catch {
                    Write-Host "  [X] RegKey Failed ($($S.ValueName)): $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }
}
Export-ModuleMember -Function Restore-ADGroupPolicies
