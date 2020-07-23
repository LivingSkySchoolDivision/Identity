function Remove-UsersFromUnknownFacilities {
    param(
        [Parameter(Mandatory=$true)] $FacilityList,
        [Parameter(Mandatory=$true)] $UserList
    )

    ## Make a list<string> of facility ids to make checking easier
    $facilityIds = New-Object Collections.Generic.List[String]
    foreach($Facility in $FacilityList) {
        if ($facilityIds.Contains($Facility.FacilityId) -eq $false) {
            $facilityIds.Add($Facility.FacilityId)
        }
    }

    $validUsers = @()
    ## Go through each user and only return users with facilities in our list
    foreach($User in $UserList) {
        if ($facilityIds.Contains($User.BaseFacilityId)) {
            $validUsers += $User
        }
    }

    return $validUsers
}

function Remove-DuplicateRecords {
    param(
        [Parameter(Mandatory=$true)] $UserList
    )

    $seenUserIds = New-Object Collections.Generic.List[String]
    $validUsers = @()

    foreach($User in $UserList) {
        if ($seenUserIds.Contains($User.UserId) -eq $false) {
            $validUsers += $User
            $seenUserIds.Add($User.UserId)
        }
    }

    return $validUsers
}

function Remove-NonAlphaCharacters {
    param(
        [Parameter(Mandatory=$true)][String] $InputString
    )

    return $InputString -replace '[^a-zA-Z0-9\.]',''
}

function New-Username {
    param(
        [Parameter(Mandatory=$true)][String] $FirstName,
        [Parameter(Mandatory=$true)][String] $LastName,
        [Parameter(Mandatory=$true)][String] $UserId,
        [Parameter] $ExistingUsernames
    )

    $newUsername = Remove-NonAlphaCharacters -InputString "$($FirstName.ToLower()).$($LastName.ToLower())"

    
    return $newUsername
}