#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Parses a JSON configuration file to provision Active Directory Users.
.DESCRIPTION
    Dynamically maps standard JSON properties to native New-ADUser parameters, and funnels
    unrecognized properties into the -OtherAttributes hashtable for extended schema support.
#>
function Restore-ADUsers {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)][string]$OrgNameInput,
        [Parameter(Mandatory=$true)][string]$JsonPath
    )

    $Domain = Get-ADDomain
    $RootDN = "OU=$OrgNameInput,$($Domain.DistinguishedName)"
    $Pass = ConvertTo-SecureString "Welcome1" -AsPlainText -Force
    [array]$UserData = Get-Content $JsonPath -Raw | ConvertFrom-Json

    $SystemLogic = @('Type', 'Tier', 'Groups', 'TargetOU')
    $AttrMap = @{
        'Email'     = 'EmailAddress'
        'Phone'     = 'OfficePhone'
        'Telephone' = 'OfficePhone'
        'Mobile'    = 'MobilePhone'
        'Street'    = 'StreetAddress'
        'Zip'       = 'PostalCode'
    }

    $ValidNativeParams = (Get-Command New-ADUser).Parameters.Keys

    Write-Host "`n--- Restoring AD Users with Extended Attributes ---" -ForegroundColor Cyan

    foreach ($U in $UserData) {
        if ($U.Type -eq "Template") { continue }

        $SAM = $U.SamAccountName
        Write-Host " [i] Processing User: $SAM" -ForegroundColor White

        try {
            $TargetDN = Get-LabDN -SlashPath $U.TargetOU -RootDN $RootDN
            Assert-OUPath -SlashPath $U.TargetOU -RootDN $RootDN

            $UserParams = @{
                SamAccountName    = $SAM
                Path              = $TargetDN
                AccountPassword   = $Pass
                Enabled           = $true
                UserPrincipalName = "$SAM@$($Domain.DNSRoot)"
                ErrorAction       = "Stop"
            }

            $OtherAttributes = @{}

            $U.psobject.Properties | ForEach-Object {
                $Key = $_.Name
                $Val = $_.Value

                if ($SystemLogic -contains $Key -or [string]::IsNullOrWhiteSpace($Val)) { return }

                $ParamName = if ($AttrMap.ContainsKey($Key)) { $AttrMap[$Key] } else { $Key }

                if ($ValidNativeParams -contains $ParamName) {
                    $UserParams[$ParamName] = $Val
                } else {
                    $OtherAttributes[$ParamName] = $Val
                }
            }

            if (-not $UserParams.ContainsKey('Name')) {
                $UserParams['Name'] = if ($U.GivenName -and $U.Surname) { "$($U.GivenName) $($U.Surname)" } else { $SAM }
            }

            if ($OtherAttributes.Count -gt 0) {
                $UserParams['OtherAttributes'] = $OtherAttributes
            }

            if (-not (Get-ADUser -Filter "SamAccountName -eq '$SAM'" -ErrorAction SilentlyContinue)) {
                if ($PSCmdlet.ShouldProcess($SAM, "Create User")) {
                    New-ADUser @UserParams
                    Write-Host "  [+] Created: $SAM in $($U.TargetOU)" -ForegroundColor Green

                    if ($OtherAttributes.Count -gt 0) {
                        Write-Host "      -> Extended Schema Attributes written: $($OtherAttributes.Keys -join ', ')" -ForegroundColor DarkGray
                    }
                }
            } else {
                Write-Host "  [~] User $SAM already exists." -ForegroundColor DarkGray
            }

        } catch {
            Write-Host " [X] CRITICAL FATAL for ${SAM}: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
Export-ModuleMember -Function Restore-ADUsers
