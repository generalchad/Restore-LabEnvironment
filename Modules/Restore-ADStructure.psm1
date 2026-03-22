function Restore-ADStructure {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$OrgNameInput, [string]$JsonPath, [switch]$DisableProtection)

    $DomainDN = (Get-ADDomain).DistinguishedName
    $RootPath = "OU=$OrgNameInput,$DomainDN"
    $Prot = -not $DisableProtection

    if (-not (Get-ADOrganizationalUnit -Filter {DistinguishedName -eq $RootPath} -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess($RootPath, "Create Root OU")) {
            New-ADOrganizationalUnit -Name $OrgNameInput -Path $DomainDN -ProtectedFromAccidentalDeletion $Prot
            Write-Host "[+] Created Root: $OrgNameInput" -ForegroundColor Green
        }
    }

    if (-not (Test-Path $JsonPath)) { return }

    $OUs = Get-Content $JsonPath | ConvertFrom-Json | Sort-Object {
        if ([string]::IsNullOrWhiteSpace($_.ParentOU)) { 0 } else { ($_.ParentOU -split '/').Count }
    }

    foreach ($OU in $OUs) {
        $Parent = Get-LabDN -SlashPath $OU.ParentOU -RootDN $RootPath
        $Target = "OU=$($OU.Name),$Parent"

        $Depth = if ([string]::IsNullOrWhiteSpace($OU.ParentOU)) { 0 } else { ($OU.ParentOU -split '/').Count }
        $Indent = " " * (($Depth * 2) + 1)

        $ouExists = $true
        try { $null = Get-ADOrganizationalUnit -Identity $Target -ErrorAction Stop } catch { $ouExists = $false }

        if (-not $ouExists) {
            if ($PSCmdlet.ShouldProcess($Target)) {
                New-ADOrganizationalUnit -Name $OU.Name -Path $Parent -ProtectedFromAccidentalDeletion $Prot
                Write-Host "$Indent[+] Created: $($OU.Name)" -ForegroundColor Green
            }
        }
    }
}
Export-ModuleMember -Function Restore-ADStructure
