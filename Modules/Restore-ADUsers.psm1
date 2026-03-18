function Restore-ADUsers {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$OrgNameInput,
        [Parameter(Mandatory=$true)]
        [string]$JsonPath
    )

    if (-not (Test-Path $JsonPath)) {
        Write-Error "JSON file not found at $JsonPath"
        return
    }

    $Domain = Get-ADDomain
    $RootDN = "OU=$OrgNameInput,$($Domain.DistinguishedName)"

    # NOTE: Added a special character (!) just in case your AD complexity policy was rejecting the password
    $Pass = ConvertTo-SecureString "Welcome1!" -AsPlainText -Force

    $UserData = Get-Content $JsonPath | ConvertFrom-Json

    foreach ($U in $UserData) {
        # Build Literal Paths based on the JSON mappings
        $FullAccPath = "$($U.OUPath),$RootDN"
        $FullGrpPath = "$($U.GroupPath),$RootDN"

        # --- RECURSIVE OU VERIFICATION ---
        foreach ($Path in @($FullAccPath, $FullGrpPath)) {
            $OUs = $Path -split ","

            for ($i = $OUs.Count - 1; $i -ge 0; $i--) {
                if ($OUs[$i] -match "^DC=") { continue }

                $CurrentOU = ($OUs[$i..($OUs.Count-1)]) -join ","

                # FIXED: Safely check exact Identity without terminating errors or unreliable DN filters
                $ouExists = $true
                try {
                    $null = Get-ADOrganizationalUnit -Identity $CurrentOU -ErrorAction Stop
                } catch {
                    $ouExists = $false
                }

                if (-not $ouExists) {
                    # FIXED: Regex ensures we only strip the leading "OU=" (case-insensitive)
                    $OUName = $OUs[$i] -replace "^OU=|^ou=", ""
                    $ParentPath = ($OUs[($i+1)..($OUs.Count-1)]) -join ","

                    if ($PSCmdlet.ShouldProcess($CurrentOU, "Create Missing OU")) {
                        try {
                            New-ADOrganizationalUnit -Name $OUName -Path $ParentPath -ErrorAction Stop
                            Write-Host " [+] Created Missing OU: $OUName" -ForegroundColor Yellow
                        } catch {
                            Write-Host " [X] FATAL: Failed to create OU '$OUName' under '$ParentPath': $($_.Exception.Message)" -ForegroundColor Red
                            # FIXED: Abort creating children if the parent fails to prevent cascading "Directory Not Found"
                            break
                        }
                    }
                }
            }
        }

        # --- CREATE GROUP ---
        if (-not (Get-ADGroup -Filter "Name -eq '$($U.Group)'" -ErrorAction SilentlyContinue)) {
            if ($PSCmdlet.ShouldProcess($U.Group, "Create Security Group")) {
                try {
                    New-ADGroup -Name $U.Group -GroupCategory Security -GroupScope Global -Path $FullGrpPath -ErrorAction Stop
                    Write-Host " [+] Group Created: $($U.Group)" -ForegroundColor Cyan
                } catch {
                    # FIXED: Injected $FullGrpPath so you know exactly which path failed
                    Write-Host " [X] Failed to create Group '$($U.Group)' in Path '$FullGrpPath': $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }

        # --- CREATE USER ---
        if (-not (Get-ADUser -Filter "SamAccountName -eq '$($U.SamAccountName)'" -ErrorAction SilentlyContinue)) {
            if ($PSCmdlet.ShouldProcess($U.SamAccountName)) {
                try {
                    $UserParams = @{
                        Name              = $U.SamAccountName
                        SamAccountName    = $U.SamAccountName
                        Path              = $FullAccPath
                        UserPrincipalName = "$($U.SamAccountName)@$($Domain.DNSRoot)"
                        DisplayName       = "$($U.FirstName) $($U.LastName)"
                        AccountPassword   = $Pass
                        Enabled           = $true
                    }
                    New-ADUser @UserParams -ErrorAction Stop
                    Add-ADGroupMember -Identity $U.Group -Members $U.SamAccountName -ErrorAction Stop
                    Write-Host " [+] User Created and Joined Group: $($U.SamAccountName)" -ForegroundColor Green
                } catch {
                    # FIXED: Injected $FullAccPath so you know exactly which path failed
                    Write-Host " [X] Failed to create User '$($U.SamAccountName)' in Path '$FullAccPath': $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }
}
Export-ModuleMember -Function Restore-ADUsers
