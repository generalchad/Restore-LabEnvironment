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

    # Track the running ParentDN as we build down the tree
    $CurrentParentDN = $RootDN

    foreach ($P in $Parts) {
        $TargetDN = "OU=$P,$CurrentParentDN"
        $ouExists = $true

        try {
            # Get-ADObject is generally faster than Get-ADOrganizationalUnit for existence checks
            $null = Get-ADObject -Identity $TargetDN -ErrorAction Stop
        } catch {
            $ouExists = $false
        }

        if (-not $ouExists) {
            try {
                New-ADOrganizationalUnit -Name $P -Path $CurrentParentDN -ErrorAction Stop
                Write-Host "  [+] Auto-Created Missing OU: $P" -ForegroundColor Yellow
            } catch {
                Write-Host "  [X] Failed to create OU '$P': $($_.Exception.Message)" -ForegroundColor Red
                throw $_ # Rethrow to stop downstream creation if parent fails
            }
        }

        # The target we just checked/created becomes the parent for the next loop iteration
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
