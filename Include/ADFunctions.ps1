import-module ActiveDirectory

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

function Deprovision-User 
{
    param(
        [Parameter(Mandatory=$true)] $Identity,
        [Parameter(Mandatory=$true)][String] $EmployeeType,
        [Parameter(Mandatory=$true)][String] $DeprovisionOU
    )

    Write-Log "Deprovisioning: $EmployeeId ($($ADUser))"

    $DepTime = Get-Date  
    set-aduser $Identity -Description "Deprovisioned: $DepTime" -Enabled $true -Department "$DeprovisionedEmployeeType" -Office "$DeprovisionedEmployeeType" -Replace @{'employeeType'="$DeprovisionedEmployeeType";'title'="$DeprovisionedEmployeeType"}

    # Remove all group memberships
    foreach($Group in Get-ADPrincipalGroupMembership -Identity $Identity)
    {
        # Don't remove from "domain users", because it won't let you do this anyway (its the user's "default group").
        if ($Group.Name -ne "Domain Users")
        {
            Remove-ADGroupMember -Identity $Group -Members $Identity -Confirm:$false
        }
    }

    # Move user to deprovision OU
    move-ADObject -identity $Identity -TargetPath $DeprovisionOU 
}