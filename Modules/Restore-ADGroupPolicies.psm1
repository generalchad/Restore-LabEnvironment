function Restore-ADGroupPolicies {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$OrgNameInput, [string]$JsonPath)

    if (-not (Test-Path $JsonPath)) { return }
    $RootPath = "OU=$OrgNameInput,$((Get-ADDomain).DistinguishedName)"

    # FIXED: -Raw and [array] casting prevents pipeline unrolling bugs
    [array]$GPOData = Get-Content $JsonPath -Raw | ConvertFrom-Json

    foreach ($GReq in $GPOData) {
        try {
            $GPO = Get-GPO -Name $GReq.DisplayName -ErrorAction SilentlyContinue

            if (-not $GPO) {
                if ($PSCmdlet.ShouldProcess($GReq.DisplayName, "Create GPO")) {
                    $GPOComment = if ($GReq.Comment) { $GReq.Comment } else { "Automated Lab" }

                    $GPO = New-GPO -Name $GReq.DisplayName -Comment $GPOComment
                    Write-Host " [+] GPO Created: $($GReq.DisplayName)" -ForegroundColor Green
                }
            }

            # Linking
            $Target = Get-LabDN -SlashPath $GReq.TargetOU -RootDN $RootPath
            $TargetOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$Target'" -Properties gPLink -ErrorAction SilentlyContinue

            if ($TargetOU) {
                $Links = $TargetOU.gPLink
                if ($GPO -and ($Links -notmatch $GPO.Id.Guid)) {
                    if ($PSCmdlet.ShouldProcess($Target, "Link GPO $($GReq.DisplayName)")) {
                        New-GPLink -Name $GReq.DisplayName -Target $Target | Out-Null
                        Write-Host "  [>] Linked to: $Target" -ForegroundColor Cyan
                    }
                }
            }

            # Registry Preferences
            if ($GPO -and $GReq.Settings) {
                foreach ($S in $GReq.Settings) {
                    if ($PSCmdlet.ShouldProcess("$($S.Key)", "Set Registry Preference")) {
                        Set-GPRegistryValue -Name $GReq.DisplayName -Key $S.Key -ValueName $S.ValueName -Type $S.Type -Value $S.Value | Out-Null
                    }
                }
            }
        } catch {
            Write-Host " [X] Failed processing GPO '$($GReq.DisplayName)': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
Export-ModuleMember -Function Restore-ADGroupPolicies
