function Restore-ADStructure {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$OrgNameInput,

        [string]$JsonPath = ".\ADStructure.json",

        [Parameter(Mandatory=$false)]
        [switch]$DisableProtection
    )

    process {
        # 1. Prerequisites & Initialization
        try { Import-Module ActiveDirectory -ErrorAction Stop }
        catch { Write-Error "RSAT ActiveDirectory module missing."; return }

        $ProtectionValue = -not $DisableProtection
        $DomainDN = (Get-ADDomain).DistinguishedName
        $OrgName = "_" + $OrgNameInput.Trim().TrimStart('_').ToUpper()
        $RootPath = "OU=$OrgName,$DomainDN"

        # 2. Helper Function (Preserved from your current version)
        function New-OUHelper {
            param($Name, $Path, $IsProtected)
            $FullDN = "OU=$Name,$Path"
            if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$FullDN'" -ErrorAction SilentlyContinue)) {
                if ($PSCmdlet.ShouldProcess($FullDN, "Create Organizational Unit")) {
                    New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $IsProtected
                    Write-Host "Created: $Name" -ForegroundColor Green
                }
            } else {
                Write-Verbose "Exists: $Name (Skipping)"
            }
        }

        # 3. Create Root OU
        New-OUHelper -Name $OrgName -Path $DomainDN -IsProtected $ProtectionValue

        # 4. Load & Sort JSON Structure
        if (-not (Test-Path $JsonPath)) { Write-Error "JSON not found."; return }

        # We sort by the number of '/' in ParentOU to ensure parents are created before children
        $OUDefinitions = Get-Content -Raw -Path $JsonPath | ConvertFrom-Json |
                         Sort-Object { ($_.ParentOU -split '/').Count }

        foreach ($OU in $OUDefinitions) {
            $ParentPath = $RootPath
            if (-not [string]::IsNullOrWhiteSpace($OU.ParentOU)) {
                $PathParts = $OU.ParentOU -split '/'
                [array]::Reverse($PathParts)
                $FormattedParent = ($PathParts | ForEach-Object { "OU=$_" }) -join ","
                $ParentPath = "$FormattedParent,$RootPath"
            }

            New-OUHelper -Name $OU.Name -Path $ParentPath -IsProtected $ProtectionValue
        }

        Write-Host "AD Structure for $OrgName completed." -ForegroundColor Cyan
    }
}

Export-ModuleMember -Function Restore-ADStructure
