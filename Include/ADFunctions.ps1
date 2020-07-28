
function Get-ADUsernames {
    $ADUserNames = @()
    foreach($ADUser in Get-ADUser -Filter * -Properties sAMAccountName -ResultPageSize 2147483647 -Server "wad1-lskysd.lskysd.ca")
    {
        if ($ADUserNames.Contains($ADUser.sAMAccountName) -eq $false) {
            $ADUserNames += $ADUser.sAMAccountName.ToLower()
        }
    }
    return $ADUserNames | Sort-Object
}

function Get-ADUsers {
    param(
        [Parameter(Mandatory=$true)][String] $EmployeeType
    )
    return Get-ADUser -Filter 'EmployeeType -eq $EmployeeType' -Properties sAMAccountName, EmployeeID, employeeType -ResultPageSize 2147483647 -Server "wad1-lskysd.lskysd.ca"
}

function Get-SyncableEmployeeIDs {
    param(
        [Parameter(Mandatory=$true)][String] $EmployeeType
    )


    $employeeIDs = New-Object Collections.Generic.List[String]

    foreach ($ADUser in Get-ADUser -Filter 'EmployeeType -eq $EmployeeType' -Properties sAMAccountName, EmployeeID, employeeType -ResultPageSize 2147483647 -Server "wad1-lskysd.lskysd.ca") 
    {      
        if ($employeeIDs.Contains($ADUser.EmployeeID) -eq $false) {
            $employeeIDs.Add($ADUser.EmployeeID)
        }  
    }    

    return $employeeIDs
}
