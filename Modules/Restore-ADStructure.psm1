function Restore-ADStructure {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$OrgNameInput, [string]$JsonPath, [switch]$DisableProtection)

    $DomainDN = (Get-ADDomain).DistinguishedName
    $RootPath = "OU=$OrgNameInput,$DomainDN"
    $Prot = -not $DisableProtection

    # Ensure Root OU
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$RootPath'" -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess($RootPath, "Create Root OU")) {
            New-ADOrganizationalUnit -Name $OrgNameInput -Path $DomainDN -ProtectedFromAccidentalDeletion $Prot
            Write-Host "[+] Created Root: $OrgNameInput" -ForegroundColor Green
        }
    }

    if (-not (Test-Path $JsonPath)) { return }
    # Sort by depth (number of slashes) to ensure parents are created before children
    $OUs = Get-Content $JsonPath | ConvertFrom-Json | Sort-Object { ($_.ParentOU -split '/').Count }

    foreach ($OU in $OUs) {
        $Parent = Get-LabDN -SlashPath $OU.ParentOU -RootDN $RootPath
        $Target = "OU=$($OU.Name),$Parent"

        if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$Target'" -ErrorAction SilentlyContinue)) {
            if ($PSCmdlet.ShouldProcess($Target)) {
                New-ADOrganizationalUnit -Name $OU.Name -Path $Parent -ProtectedFromAccidentalDeletion $Prot
                Write-Host " [+] Created: $($OU.Name)" -ForegroundColor Green
            }
        }
    }
}
Export-ModuleMember -Function Restore-ADStructure
