function Restore-ADUsers {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$OrgNameInput,

        [string]$JsonPath = ".\ADUserData.json"
    )

    process {
        if (-not (Test-Path $JsonPath)) { Write-Error "JSON file not found."; return }
        try {
            $DomainDN = (Get-ADDomain).DistinguishedName
            $DomainFQDN = (Get-ADDomain).DNSRoot
        } catch { Write-Error "AD Connection failed."; return }

        $OrgName = "_" + $OrgNameInput.Trim().TrimStart('_').ToUpper()
        $RootPath = "OU=$OrgName,$DomainDN"
        $SecurePass = ConvertTo-SecureString "Welcome1" -AsPlainText -Force

        $UserData = Get-Content -Raw -Path $JsonPath | ConvertFrom-Json

        foreach ($User in $UserData) {
            # 1. Pathing & Group Logic
            if ($User.Type -eq "Admin") {
                $AccountPath = "OU=T$($User.Tier)_Accounts,OU=Tier $($User.Tier),OU=_Admin,$RootPath"
                $GroupPath   = "OU=T$($User.Tier)_Groups,OU=Tier $($User.Tier),OU=_Admin,$RootPath"
                $GroupName   = "GRP-SEC-ADMIN-Tier-$($User.Tier)-Admins"
            } else {
                $BaseUserPath = "OU=$($User.Type),OU=Users,$RootPath"
                $GroupPath    = "OU=Roles,OU=Groups,$RootPath"
                $GroupName    = "Role-General-$($User.Type)"
                $AccountPath = if (-not [string]::IsNullOrWhiteSpace($User.Department)) { "OU=$($User.Department),$BaseUserPath" } else { $BaseUserPath }
            }

            # 2. Ensure Security Group exists
            if (-not (Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue)) {
                if ($PSCmdlet.ShouldProcess($GroupName, "Create Security Group")) {
                    New-ADGroup -Name $GroupName -GroupCategory Security -GroupScope Global -Path $GroupPath
                }
            }

            # 3. Create User
            if (-not (Get-ADUser -Filter "SamAccountName -eq '$($User.SamAccountName)'" -ErrorAction SilentlyContinue)) {
                $UserParams = @{
                    Name = $User.SamAccountName; SamAccountName = $User.SamAccountName
                    UserPrincipalName = "$($User.SamAccountName)@$DomainFQDN"
                    DisplayName = "$($User.FirstName) $($User.LastName)"; Path = $AccountPath
                    AccountPassword = $SecurePass; Enabled = $true; ChangePasswordAtLogon = $false
                }
                if ($PSCmdlet.ShouldProcess($User.SamAccountName, "Create User")) {
                    New-ADUser @UserParams
                    Add-ADGroupMember -Identity $GroupName -Members $User.SamAccountName
                }
            }

            # 4. Tier 0 Nesting (FIX FOR LOGIN ISSUE)
            if ($User.Tier -eq 0) {
                $BuiltInAdmin = "Domain Admins"
                if ($PSCmdlet.ShouldProcess($GroupName, "Nest $GroupName into $BuiltInAdmin")) {
                    # Check if already a member to avoid non-terminating errors
                    $IsMember = Get-ADGroupMember -Identity $BuiltInAdmin | Where-Object { $_.name -eq $GroupName }
                    if (-not $IsMember) {
                        Add-ADGroupMember -Identity $BuiltInAdmin -Members $GroupName
                        Write-Host "Nested $GroupName into $BuiltInAdmin." -ForegroundColor Yellow
                    }
                }
            }
        }
        Write-Host "AD User Restoration Completed." -ForegroundColor Cyan
    }
}

Export-ModuleMember -Function Restore-ADUsers
