function Get-LabDN {
    param(
        [string]$SlashPath,
        [Parameter(Mandatory=$true)][string]$RootDN
    )
    if ([string]::IsNullOrWhiteSpace($SlashPath)) { return $RootDN }

    $Parts = $SlashPath -split '/'
    [array]::Reverse($Parts)
    return (($Parts | ForEach-Object { "OU=$_" }) -join ",") + ",$RootDN"
}

Export-ModuleMember -Function Get-LabDN
