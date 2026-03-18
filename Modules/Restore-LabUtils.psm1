function Get-LabDN {
    param(
        [string]$SlashPath,
        [Parameter(Mandatory=$true)][string]$RootDN
    )

    # Handle Root or Empty paths
    if ([string]::IsNullOrWhiteSpace($SlashPath) -or $SlashPath -eq "/") {
        return $RootDN
    }

    # Split and filter out any empty elements (caused by leading/trailing/double slashes)
    $Parts = $SlashPath.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)

    # Reverse the order: "Users/Finance" -> "Finance", "Users"
    [array]::Reverse($Parts)

    # Rebuild as OU=Finance,OU=Users
    $OUPath = ($Parts | ForEach-Object { "OU=$($_)" }) -join ","

    return "$OUPath,$RootDN"
}

Export-ModuleMember -Function Get-LabDN
