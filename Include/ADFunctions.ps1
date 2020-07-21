function Get-ADUsernames {
    $ADUserNames = New-Object Collections.Generic.List[String]
    foreach($ADUser in Get-ADUser -Filter * -Properties sAMAccountName -ResultPageSize 2147483647)
    {
        if ($ADUserNames.Contains($ADUser.sAMAccountName) -eq $false) {
            $ADUserNames.Add($ADUser.sAMAccountName)
        }
    }
    return $ADUserNames | Sort-Object
}


function Get-ADUsers {
    param(
        [Parameter(Mandatory=$true)][String] $EmployeeType
    )

    $ADUserNames = New-Object Collections.Generic.List[String]
    foreach($ADUser in Get-ADUser -Filter 'EmployeeType -eq $EmployeeType' -Properties sAMAccountName -ResultPageSize 2147483647)
    {
        if ($ADUserNames.Contains($ADUser.sAMAccountName) -eq $false) {
            $ADUserNames.Add($ADUser.sAMAccountName)
        }
    }
    return $ADUserNames | Sort-Object
}
