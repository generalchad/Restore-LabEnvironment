function Get-LabDN {
    param(
        [string]$SlashPath,
        [Parameter(Mandatory=$true)][string]$RootDN
    )
    if ([string]::IsNullOrWhiteSpace($SlashPath) -or $SlashPath.Trim() -eq "/") { return $RootDN }
    $Parts = $SlashPath.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() }
    [array]::Reverse($Parts)
    $OUPath = ($Parts | ForEach-Object { if ($_ -match "^(?i)OU=") { $_ } else { "OU=$($_)" } }) -join ","
    return "$OUPath,$RootDN"
}

function Assert-OUPath {
    param([string]$SlashPath, [string]$RootDN)
    if ([string]::IsNullOrWhiteSpace($SlashPath)) { return }

    $Parts = $SlashPath.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() }
    $CurrentPath = ""

    foreach ($P in $Parts) {
        $CurrentPath = if ($CurrentPath) { "$CurrentPath/$P" } else { $P }
        $TargetDN = Get-LabDN -SlashPath $CurrentPath -RootDN $RootDN

        $ouExists = $true
        try { $null = Get-ADOrganizationalUnit -Identity $TargetDN -ErrorAction Stop } catch { $ouExists = $false }

        if (-not $ouExists) {
            $ParentSlash = $CurrentPath -replace "/$P$", "" # Strip current node to get parent
            $ParentDN = Get-LabDN -SlashPath $ParentSlash -RootDN $RootDN
            New-ADOrganizationalUnit -Name $P -Path $ParentDN -ErrorAction Stop
            Write-Host "  [+] Auto-Created Missing OU: $P" -ForegroundColor Yellow
        }
    }
}

function Wait-ForADObject {
    param($Filter, $Type, $Retries = 5)
    for ($i = 1; $i -le $Retries; $i++) {
        $obj = if ($Type -eq "User") { Get-ADUser -Filter $Filter -Properties MemberOf } else { Get-ADGroup -Filter $Filter }
        if ($obj) { return $obj }
        Write-Host "    [w] Waiting for AD indexing (Attempt $i/$Retries)..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 1
    }
    return $null
}

Export-ModuleMember -Function Get-LabDN, Assert-OUPath, Wait-ForADObject
