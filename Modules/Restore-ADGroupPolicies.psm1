function Restore-ADGroupPolicies {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$OrgNameInput,

        [string]$JsonPath = ".\ADGroupPolicies.json"
    )

    process {
        if (-not (Test-Path $JsonPath)) { Write-Error "GPO JSON file not found."; return }
        try { Import-Module GroupPolicy -ErrorAction Stop } catch { Write-Error "GroupPolicy module missing."; return }

        $DomainDN = (Get-ADDomain).DistinguishedName
        $OrgName = "_" + $OrgNameInput.Trim().TrimStart('_').ToUpper()
        $RootPath = "OU=$OrgName,$DomainDN"

        $GPODefinitions = Get-Content -Raw -Path $JsonPath | ConvertFrom-Json

        foreach ($GPOReq in $GPODefinitions) {
            # 1. Create or Get the GPO
            $ExistingGPO = Get-GPO -Name $GPOReq.DisplayName -ErrorAction SilentlyContinue
            if (-not $ExistingGPO) {
                if ($PSCmdlet.ShouldProcess($GPOReq.DisplayName, "Create new GPO")) {
                    $GPO = New-GPO -Name $GPOReq.DisplayName -Comment $GPOReq.Comment
                    Write-Host "Created GPO: $($GPOReq.DisplayName)" -ForegroundColor Green
                }
            } else { $GPO = $ExistingGPO }

            # 2. Link the GPO (FIXED)
            if ([string]::IsNullOrWhiteSpace($GPOReq.TargetOU)) {
                $TargetLinkPath = $RootPath
            } else {
                $TargetLinkPath = "OU=$($GPOReq.TargetOU),$RootPath"
            }

            if ($GPO -and (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$TargetLinkPath'" -ErrorAction SilentlyContinue)) {
                if ($PSCmdlet.ShouldProcess($TargetLinkPath, "Link GPO to Target")) {
                    # XML Report check prevents Red-Text errors if link already exists
                    $CurrentLinks = Get-GPOReport -Name $GPOReq.DisplayName -ReportType Xml | Select-Xml -XPath "//LinksTo"
                    if ($CurrentLinks -notmatch [regex]::Escape($TargetLinkPath)) {
                        New-GPLink -Name $GPOReq.DisplayName -Target $TargetLinkPath
                        Write-Host "Linked $($GPOReq.DisplayName) to $TargetLinkPath" -ForegroundColor Cyan
                    }
                }
            }

            # 3. Apply Registry Settings
            if ($GPO -and $GPOReq.Settings) {
                foreach ($Setting in $GPOReq.Settings) {
                    if ($PSCmdlet.ShouldProcess("$($Setting.ValueName)", "Apply Registry Setting")) {
                        Set-GPRegistryValue -Name $GPOReq.DisplayName `
                                            -Key $Setting.Key `
                                            -ValueName $Setting.ValueName `
                                            -Type $Setting.Type `
                                            -Value $Setting.Value
                    }
                }
            }
        }
        Write-Host "GPO Restoration completed for $OrgName." -ForegroundColor Cyan
    }
}

Export-ModuleMember -Function Restore-ADGroupPolicies
