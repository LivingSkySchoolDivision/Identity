param (
    [Parameter(Mandatory=$true)][string]$SISExportFile,
    [Parameter(Mandatory=$true)][string]$FacilityFile,
    [Parameter(Mandatory=$true)][string]$ConfigFilePath
 )
<#
    .SYNOPSIS
        Privisions new user accounts for users who exist in the reference SIS but do not yet have an account.

    .DESCRIPTION
        Privisions new user accounts for users who exist in the reference SIS but do not yet have an account.

    .PARAMETER SISExportFile
        A CSV export from the source SIS system.

    .PARAMETER ConfigFile
        Configuration file. Defaults to ""../config.xml".
#>

## ##################################################
## # Configuration can be done in config.xml.       #
## # No user configurable stuff beyond this point   #
## ##################################################

import-module ActiveDirectory

function Write-Log
{
    param(
        [Parameter(Mandatory=$true)] $Message
    )

    Write-Output "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss K")> $Message"
}
function Get-SourceUsers {
    param(
        [Parameter(Mandatory=$true)][String] $CSVFile
    )

    return import-csv $CSVFile -header("PupilNo","SaskLearningID","LegalFirstName","LegalLastName","LegalMiddleName","PreferredFirstName","PreferredLastName","PreferredMiddleName","PrimaryEmail","AlternateEmail","BaseSchoolName","BaseSchoolDAN","EnrollmentStatus","GradeLevel","YOG","O365Authorisation","AcceptableUsePolicy","LegacyStudentID","GoogleDocsEmail") | Select -skip 1
}
function Get-Facilities {
    param(
        [Parameter(Mandatory=$true)][String] $CSVFile
    )

    return import-csv $CSVFile -header("Name","MSSFacilityName","FacilityDAN","DefaultAccountEnabled","ADOU","Groups") | Select -skip 1
}
function Remove-UsersFromUnknownFacilities {
    param(
        [Parameter(Mandatory=$true)] $FacilityList,
        [Parameter(Mandatory=$true)] $UserList
    )

    ## Make a list<string> of facility ids to make checking easier
    $facilityIds = New-Object Collections.Generic.List[String]
    foreach($Facility in $FacilityList) {
        if ($facilityIds.Contains($Facility.FacilityDAN) -eq $false) {
            $facilityIds.Add($Facility.FacilityDAN)
        }
    }

    $validUsers = @()
    ## Go through each user and only return users with facilities in our list
    foreach($User in $UserList) {
        if ($facilityIds.Contains($User.BaseSchoolDAN)) {
            $validUsers += $User
        }
        # Don't attempt to fall back to the additional school, because if a student
        # has multiple outside enrolments and their base school isn't valid, 
        # they'll be constantly moved back and forth as the file gets processed.
        # This could happen with the increase in distance ed.
        # A student will _need_ a valid base school.
        # To combat this, we could potentially create a fake school in the facilities file
        # and use that somehow.
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
        if ($seenUserIds.Contains($User.PupilNo) -eq $false) {
            $validUsers += $User
            $seenUserIds.Add($User.PupilNo)
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

function New-CN {
    param(
        [Parameter(Mandatory=$true)][String] $FirstName,
        [Parameter(Mandatory=$true)][String] $LastName,
        [Parameter(Mandatory=$true)][String] $StudentNumber
    )

    return "$($FirstName -replace '[^a-zA-Z0-9\.\s-]','') $($LastName -replace '[^a-zA-Z0-9\.\s-]','') $($StudentNumber -replace '[^a-zA-Z0-9\.\s-]','')".ToLower()
}

function Convert-GroupList
{
    param(
        [Parameter(Mandatory=$true)] $GroupString
    )

    $GroupList = @()

    foreach($str in $GroupString -Split ";")
    {
        if ($str.Trim().Length -gt 0)
        {
            $GroupList += $str.Trim()
        }
    }

    return $GroupList
}

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

Write-Log "Start provision script..."
try {
    ## Load config file
    $AdjustedConfigFilePath = $ConfigFilePath
    if ($AdjustedConfigFilePath.Length -le 0)
    {
        $AdjustedConfigFilePath = join-path -Path $(Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent) -ChildPath "config.xml"
    }

    if ((test-path -Path $AdjustedConfigFilePath) -eq $false) {
        Throw "Config file not found. Specify using -ConfigFilePath. Defaults to config.xml in the directory above where this script is run from."
    }
    $configXML = [xml](Get-Content $AdjustedConfigFilePath)
    $EmailDomain = $configXml.Settings.Students.EmailDomain
    $ActiveEmployeeType = $configXml.Settings.Students.ActiveEmployeeType
    $DeprovisionedEmployeeType = $configXml.Settings.Students.DeprovisionedEmployeeType
    $NotificationWebHookURL = $configXML.Settings.Notifications.WebHookURL

    ## Load the list of schools from the ../db folder
    $Facilities = @(Get-Facilities -CSVFile $FacilityFile)
    if ($Facilities.Count -lt 1)
    {
        Write-Log "No facilities found. Exiting."
        exit
    } else {
        Write-Log "$($Facilities.Count) facilities found in import file."
    }

    ## Load the student records from the file.
    ## If the file doesn't exist or is empty, don't continue any further.
    $SourceUsers = @(Remove-DuplicateRecords -UserList (
        Remove-UsersFromUnknownFacilities -UserList (
            Get-SourceUsers -CSVFile $SISExportFile
            ) -FacilityList $Facilities
        ))

    if ($SourceUsers.Count -lt 1)
    {
        Write-Log "No students from source system. Exiting"
        exit
    } else {
        Write-Log "$($SourceUsers.Count) students found in import file."
    }

    ## Get a list of all users currently in AD
    ## Only users with employeeID set AND employeeType set to the specified one from the config file.

    $ExistingActiveEmployeeIds = Get-SyncableEmployeeIDs -EmployeeType $ActiveEmployeeType

    ## ############################################################
    ## Find new users
    ## ############################################################

    $UsersToProvision = @()
    if ($ExistingActiveEmployeeIds.Count -gt 0)
    {
        # Find users in Source (import file) that don't exist in AD
        foreach($SourceUser in $SourceUsers)
        {
            if ($ExistingActiveEmployeeIds.Contains($SourceUser.PupilNo) -eq $false)
            {
                $UsersToProvision += $SourceUser
            }
        }
    }

    Write-Log "Found $($UsersToProvision.Count) users to create"

    ## ############################################################
    ## Find users to re-provision
    ## ############################################################

    $ExistingDeprovisionedEmployeeIDs = Get-SyncableEmployeeIDs -EmployeeType $DeprovisionedEmployeeType

    $UsersToReProvision = @()
    if ($ExistingDeprovisionedEmployeeIDs.Count -gt 0)
    {
        foreach($SourceUser in $UsersToProvision)
        {
            if ($ExistingDeprovisionedEmployeeIDs.Contains($SourceUser.PupilNo) -eq $true)
            {
                $UsersToReProvision += $SourceUser
            }
        }
    }

    # Remove users to deprovision from the new users list
    $actualUsersToProvision = @()
    foreach($User in $UsersToProvision) {
        if ($UsersToReProvision.Contains($User) -eq $false) {
            $actualUsersToProvision += $User
        }
    }

    $UsersToProvision = $actualUsersToProvision

    Write-Log "Found $($UsersToReProvision.Count) deprovisioned users to reactivate."
    Write-Log "Adjusted to $($UsersToProvision.Count) users to create"

    
    ## ############################################################
    ## Stop if there's nothing to do
    ## ############################################################

    if (($UsersToProvision.Count -eq 0) -and ($UsersToReprovision.Count -eq 0)) 
    {
        Write-Log "No work to do - exiting."
        exit
    }

    ## ############################################################
    ## Provision new users
    ## ############################################################

    Write-Log "Getting all existing sAMAccountNames from AD..."
    $AllUsernames = Get-ADUsernames

    $IgnoredUsers = @()
    Write-Log "Processing new users..."
    foreach($NewUser in $UsersToProvision) 
    {
        # Parse the user's name
        $FirstName = $NewUser.PreferredFirstName
        $LastName = $NewUser.PreferredLastName
        $Grade = $NewUser.GradeLevel
        $StudentID = $NewUser.PupilNo
        $LearningID = $NewUser.SaskLearningID

        # Check for missing preferred names
        if ($FirstName.Length -lt 1) {
            $FirstName = $NewUser.LegalFirstName
        }
        if ($LastName.Length -lt 1) {
            $LastName = $NewUser.LegalLastName
        }


        # Find the facility for this user
        $ThisUserFacility = $null

        foreach($Facility in $Facilities)
        {
            if ($Facility.FacilityDAN -eq $NewUser.BaseSchoolDAN)
            {
                $ThisUserFacility = $Facility
            }
        }

        if ($null -ne $ThisUserFacility)
        {
            # Don't provision for facilities that don't have an OU
            if ($ThisUserFacility.ADOU.Length -gt 1)
            {
                # Find the OU for this new user
                $OU = $ThisUserFacility.ADOU

                # Make a display name
                $DisplayName = "$FirstName $LastName"

                # Make a CanonicalName
                $CN = $(New-CN -FirstName $FirstName -LastName $LastName -StudentNumber $StudentID)

                # Generate a username for this user
                $NewUsername = New-Username -FirstName $FirstName -LastName $LastName -UserId $StudentID -ExistingUsernames $AllUsernames

                # Generate an email for this user
                $NewEmail = "$($NewUsername)@$($EmailDomain)"

                # Should the user be enable or disabled by default (based on facility)
                $AccountEnable = $false
                if (
                    ($ThisUserFacility.DefaultAccountEnabled.ToLower() -eq "true") -or 
                    ($ThisUserFacility.DefaultAccountEnabled.ToLower() -eq "yes")  -or 
                    ($ThisUserFacility.DefaultAccountEnabled.ToLower() -eq "y")  -or 
                    ($ThisUserFacility.DefaultAccountEnabled.ToLower() -eq "t") 
                )
                {
                    $AccountEnable = $true
                }

                # Initial password
                $Password = "$($FirstName.Substring(0,1).ToLower())$($LastName.Substring(0,1).ToLower())-$($NewUser.PupilNo)"
                $SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force

                # Create the user
                New-ADUser -SamAccountName $NewUsername -AccountPassword $SecurePassword -UserPrincipalName $NewEmail -Name $CN -Enabled $AccountEnable -DisplayName $DisplayName -GivenName $($FirstName) -Surname $($LastName) -ChangePasswordAtLogon $true -Department "Grade $($Grade)" -EmailAddress $NewEmail -Company $($ThisUserFacility.Name) -Office $($ThisUserFacility.Name) -EmployeeID $($StudentID) -EmployeeNumber $LearningID -OtherAttributes @{'employeeType'="$ActiveEmployeeType";'title'="$ActiveEmployeeType"} -Path $OU

                # Add the user to groups for this facility
                foreach($grp in (Convert-GroupList -GroupString $($ThisUserFacility.Groups)))
                {
                    Add-ADGroupMember -Identity $grp -Members $NewUsername -Confirm:$false
                }

                # Add our new username to the list of existing usernames, in case 
                # we'd end up with a duplicate in this script with similar names
                $AllUsernames += $NewUsername

                Write-Log "New user: CN=$CN,$OU"
            }
        } else {
            $IgnoredUsers += $NewUser
        }
    }


    ## ############################################################
    ## Reprovision previously deprovisioned users
    ## ############################################################
    Write-Log "Processing users to reprovision..."
    foreach($NewUser in $UsersToReProvision) 
    {
        $ThisUserFacility = $null

        foreach($Facility in $Facilities)
        {
            if ($Facility.FacilityDAN -eq $NewUser.BaseSchoolDAN)
            {
                $ThisUserFacility = $Facility
            }
        }

        if ($null -ne $ThisUserFacility)
        {
            # Based on the new facility, should the account be enabled or not?
            $AccountEnable = $false
            if (
                ($ThisUserFacility.DefaultAccountEnabled.ToLower() -eq "true") -or 
                ($ThisUserFacility.DefaultAccountEnabled.ToLower() -eq "yes")  -or 
                ($ThisUserFacility.DefaultAccountEnabled.ToLower() -eq "y")  -or 
                ($ThisUserFacility.DefaultAccountEnabled.ToLower() -eq "t") 
            )
            {
                $AccountEnable = $true
            }

            # Find the user
            $EmpID = $StudentID
            foreach($ADUser in Get-ADUser -Filter {(EmployeeId -eq $EmpID) -and ((EmployeeType -eq $DeprovisionedEmployeeType))} -Properties displayName,Department,Company,Office,Description,EmployeeType,title,CN)
            {
                # Adjust user properties
                set-aduser -Identity $ADUser -Replace @{'employeeType'="$ActiveEmployeeType";'title'="$ActiveEmployeeType"} -Clear description -Company $($ThisUserFacility.Name) -Office $($ThisUserFacility.Name) -Enabled $AccountEnable -Department "Grade $($Grade)"

                # Remove the user from all groups
                foreach($Group in Get-ADPrincipalGroupMembership -Identity $ADUser)
                {
                    # Don't remove from "domain users", because it won't let you do this anyway (its the user's "default group").
                    if ($Group.Name -ne "Domain Users")
                    {
                        try 
                        {
                            Remove-ADGroupMember -Identity $Group -Members $ADUser -Confirm:$false
                        }
                        catch {}
                    }
                }
                
                # Add the user to groups for this facility
                foreach($grp in (Convert-GroupList -GroupString $($ThisUserFacility.Groups)))
                {
                    Add-ADGroupMember -Identity $grp -Members $ADUser -Confirm:$false
                }

                # Actually move the user
                move-ADObject -identity $ADUser -TargetPath $ThisUserFacility.ADOU    
                                
                Write-Log "Reprovisioned user: CN=$($ADUser.CN),$($ThisUserFacility.ADOU)"
            }
        }
    } 


    ## Send teams webhook notification

    ## Send email notification
} 
catch {
    Write-Log "ERROR: $_"
}

Write-Log "Finished provisioning."