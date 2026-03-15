function Restore-ADUsers {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$OrgNameInput, [string]$JsonPath)

    if (-not (Test-Path $JsonPath)) { return }
    $Domain = Get-ADDomain
    $RootDN = "OU=$OrgNameInput,$($Domain.DistinguishedName)"
    $Pass = ConvertTo-SecureString "Welcome1" -AsPlainText -Force

    Get-Content $JsonPath | ConvertFrom-Json | ForEach-Object {
        $U = $_
        if ($U.Type -eq "Admin") {
            $AccPath = "OU=T$($U.Tier)_Accounts,OU=Tier $($U.Tier),OU=_Admin,$RootDN"
            $GrpPath = "OU=T$($U.Tier)_Groups,OU=Tier $($U.Tier),OU=_Admin,$RootDN"
            $GrpName = "GRP-SEC-ADMIN-Tier-$($U.Tier)-Admins"
        } else {
            $Base = "OU=$($U.Type),OU=Users,$RootDN"

            # FIXED: Replaced ternary with standard If/Else
            if ($U.Department) {
                $AccPath = "OU=$($U.Department),$Base"
            } else {
                $AccPath = $Base
            }

            $GrpPath = "OU=Roles,OU=Groups,$RootDN"
            $GrpName = "Role-General-$($U.Type)"
        }

        # Create Group
        if (-not (Get-ADGroup -Filter "Name -eq '$GrpName'" -ErrorAction SilentlyContinue)) {
            if ($PSCmdlet.ShouldProcess($GrpName, "Create Security Group")) {
                New-ADGroup -Name $GrpName -GroupCategory Security -GroupScope Global -Path $GrpPath
                Write-Host " [+] Group Created: $GrpName" -ForegroundColor Cyan
            }
        }

        # Create User
        if (-not (Get-ADUser -Filter "SamAccountName -eq '$($U.SamAccountName)'" -ErrorAction SilentlyContinue)) {
            if ($PSCmdlet.ShouldProcess($U.SamAccountName)) {
                $UserParams = @{
                    Name              = $U.SamAccountName
                    SamAccountName    = $U.SamAccountName
                    Path              = $AccPath
                    UserPrincipalName = "$($U.SamAccountName)@$($Domain.DNSRoot)"
                    DisplayName       = "$($U.FirstName) $($U.LastName)"
                    AccountPassword   = $Pass
                    Enabled           = $true
                }
                New-ADUser @UserParams
                Add-ADGroupMember -Identity $GrpName -Members $U.SamAccountName
                Write-Host " [+] User Created: $($U.SamAccountName)" -ForegroundColor Green
            }
        }
    }
}
Export-ModuleMember -Function Restore-ADUsers
