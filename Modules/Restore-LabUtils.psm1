#Requires -Modules ActiveDirectory

function Get-LabDN {
    [CmdletBinding()]
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$SlashPath,
        [Parameter(Mandatory=$true)][string]$RootDN
    )

    if ([string]::IsNullOrWhiteSpace($SlashPath)) { return }

    $Parts = $SlashPath.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() }

    $CurrentParentDN = $RootDN

    foreach ($P in $Parts) {
        $TargetDN = "OU=$P,$CurrentParentDN"

        # FIXED: Use Filter instead of Identity to prevent Transcript error spam
        $ouExists = [bool](Get-ADObject -Filter "DistinguishedName -eq '$TargetDN'")

        if (-not $ouExists) {
            try {
                New-ADOrganizationalUnit -Name $P -Path $CurrentParentDN -ErrorAction Stop
                Write-Host "  [+] Auto-Created Missing OU: $P" -ForegroundColor Yellow
            } catch {
                Write-Host "  [X] Failed to create OU '$P': $($_.Exception.Message)" -ForegroundColor Red
                throw $_
            }
        }

        $CurrentParentDN = $TargetDN
    }
}

function Wait-ForADObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Filter,
        [Parameter(Mandatory=$true)][ValidateSet("User","Group","Computer")]$Type,
        [int]$Retries = 5
    )

    for ($i = 1; $i -le $Retries; $i++) {
        $obj = switch ($Type) {
            "User"     { Get-ADUser -Filter $Filter -Properties MemberOf -ErrorAction SilentlyContinue }
            "Group"    { Get-ADGroup -Filter $Filter -ErrorAction SilentlyContinue }
            "Computer" { Get-ADComputer -Filter $Filter -ErrorAction SilentlyContinue }
        }

        if ($obj) { return $obj }

        Write-Host "    [w] Waiting for AD indexing ($Type) (Attempt $i/$Retries)..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 2
    }
    return $null
}

Export-ModuleMember -Function Get-LabDN, Assert-OUPath, Wait-ForADObject
