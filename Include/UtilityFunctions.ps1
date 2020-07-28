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

function New-Username 
{
    param(
        [Parameter(Mandatory=$true)][String] $FirstName,
        [Parameter(Mandatory=$true)][String] $LastName,
        [Parameter(Mandatory=$true)][String] $UserId,
        [Parameter(Mandatory=$true)] $ExistingUsernames
    )

    $newUsername = Remove-NonAlphaCharacters -InputString "$($FirstName.ToLower()).$($LastName.ToLower())"

    # If it's longer than 19 characters

    if ($newUsername.length -gt 19) 
    {        
        $newUsername = Remove-NonAlphaCharacters -InputString "$($FirstName.Substring(0,1).ToLower()).$($LastName.ToLower())"
    }

    # If it's still longer than 19 characters
    if ($newUsername.length -gt 19) 
    {        
        $newUsername = Remove-NonAlphaCharacters -InputString "$($FirstName.Substring(0,1).ToLower()).$($LastName.Substring(0,17).ToLower())"
    }

    # If it exists already, start adding numbers    
    if ($ExistingUsernames -Contains $newUsername) 
    {
        $tempUsername = $newUsername
        $counter = 0
        while($ExistingUsernames -Contains $tempUsername)
        {
            $counter++
            $tempUsername = Remove-NonAlphaCharacters -InputString "$newUsername$counter"
        }    
        $newUsername = $tempUsername    
    }
   
    return $newUsername
}