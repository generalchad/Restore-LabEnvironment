#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Parses a JSON configuration file to provision Group Policy WMI Filters natively in Active Directory.
.DESCRIPTION
    Creates WMI Filters by building native msWMI-Som objects within the System/WMIPolicy container.
    This bypasses the limitations of the GPMC COM API and ensures idempotent, reliable execution.
#>
function Restore-ADWmiFilters {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_})]
        [string]$JsonPath
    )

    $DomainDN = (Get-ADDomain).DistinguishedName
    $WmiContainer = "CN=SOM,CN=WMIPolicy,CN=System,$DomainDN"

    # Ensure the WMIPolicy and SOM containers exist (created automatically in standard AD, but safest to verify)
    $BaseExists = [bool](Get-ADObject -Filter "DistinguishedName -eq '$WmiContainer'")
    if (-not $BaseExists) {
        Write-Host " [X] Critical: Default WMIPolicy container missing in AD. Run domain preparation." -ForegroundColor Red
        return
    }

    [array]$WmiData = Get-Content -Path $JsonPath -Raw | ConvertFrom-Json

    Write-Host "`n--- Restoring WMI Filters ---" -ForegroundColor Cyan

    foreach ($Req in $WmiData) {
        Write-Host " [i] Processing WMI Filter: $($Req.Name)" -ForegroundColor White

        try {
            $ExistingFilter = Get-ADObject -Filter "msWMI-Name -eq '$($Req.Name)'" -SearchBase $WmiContainer -ErrorAction SilentlyContinue

            if (-not $ExistingFilter) {
                if ($PSCmdlet.ShouldProcess($Req.Name, "Create WMI Filter")) {

                    # Generate a new GUID and format it with curly braces for AD
                    $GuidStr = [guid]::NewGuid().ToString('B').ToUpper()

                    # The msWMI-Parm2 attribute expects a strict, semicolon-delimited string payload
                    $WqlPayload = "1;1;1033;1;1;0;WQL;root\CIMv2;$($Req.Query);"

                    $OtherAttributes = @{
                        'msWMI-Name'  = $Req.Name
                        'msWMI-Parm1' = if ($Req.Description) { $Req.Description } else { "Automated Lab WMI Filter" }
                        'msWMI-Parm2' = $WqlPayload
                        'msWMI-ID'    = $GuidStr
                    }

                    New-ADObject -Name $GuidStr -Type "msWMI-Som" -Path $WmiContainer -OtherAttributes $OtherAttributes -ErrorAction Stop
                    Write-Host "  [+] Created WMI Filter: $($Req.Name)" -ForegroundColor Green
                }
            } else {
                Write-Host "  [-] Already exists" -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "  [X] Failed to create WMI Filter '$($Req.Name)': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
Export-ModuleMember -Function Restore-ADWmiFilters
