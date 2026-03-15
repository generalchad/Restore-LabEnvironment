function Restore-ADGroupMemberships {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)][string]$OrgNameInput,
        [Parameter(Mandatory=$true)][string]$JsonPath
    )

    if (-not (Test-Path $JsonPath)) { return }
    $Domain = Get-ADDomain
    $RootDN = "OU=$OrgNameInput,$($Domain.DistinguishedName)"
    $UserData = Get-Content -Raw $JsonPath | ConvertFrom-Json

    Write-Host "`n--- Processing Security Memberships ---" -ForegroundColor Magenta

    foreach ($U in $UserData) {
        $SAM = [string]$U.SamAccountName
        $Type = [string]$U.Type

        # 1. Tiered Admin Logic (Privileged Group Nesting)
        if ($Type -eq "Admin") {
            $Tier = [string]$U.Tier
            $TargetSecurityGroups = @()

            # Assign to native high-level groups based on Tier
            if ($Tier -eq "0") {
                $TargetSecurityGroups = @("Enterprise Admins", "Domain Admins", "Schema Admins")
            }
            elseif ($Tier -eq "1") {
                $TargetSecurityGroups = @("Server Operators")
            }

            foreach ($GroupName in $TargetSecurityGroups) {
                if ($PSCmdlet.ShouldProcess("$($SAM) to $($GroupName)", "Add Privileged Membership")) {
                    try {
                        Add-ADGroupMember -Identity $GroupName -Members $SAM -ErrorAction Stop
                        Write-Host " [+] $($SAM) promoted to: $($GroupName)" -ForegroundColor Yellow
                    } catch {
                        # Silently skip if user is already a member
                    }
                }
            }
        }

        # 2. Departmental / Role Group Logic
        if ($U.Department) {
            $Dept = [string]$U.Department
            $RoleGroupName = "GRP-$($Dept)"
            $BaseGroupsOU = "OU=Roles,OU=Groups,$RootDN"

            # Ensure the Departmental Role Group exists in the Groups OU
            if (-not (Get-ADGroup -Filter "Name -eq '$RoleGroupName'" -ErrorAction SilentlyContinue)) {
                if ($PSCmdlet.ShouldProcess($RoleGroupName, "Create Departmental Group")) {
                    New-ADGroup -Name $RoleGroupName -GroupCategory Security -GroupScope Global -Path $BaseGroupsOU
                    Write-Host " [+] Created Departmental Group: $($RoleGroupName)" -ForegroundColor Cyan
                }
            }

            # Add User to Departmental Group
            if ($PSCmdlet.ShouldProcess("$($SAM) to $($RoleGroupName)", "Add Role Membership")) {
                Add-ADGroupMember -Identity $RoleGroupName -Members $SAM -ErrorAction SilentlyContinue
                Write-Host "  [>] $($SAM) nested into: $($RoleGroupName)" -ForegroundColor Gray
            }
        }
    }
}

Export-ModuleMember -Function Restore-ADGroupMemberships
