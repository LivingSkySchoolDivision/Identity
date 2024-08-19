param (
    [Parameter(Mandatory=$true)][string]$SISExportFile,
    [Parameter(Mandatory=$true)][string]$FacilityFile,
    [Parameter(Mandatory=$true)][string]$ConfigFile
 )
<#
    .SYNOPSIS
        Moves users and makes sure users are assigned to appropriate groups based on their schools.

    .DESCRIPTION
        Moves users and makes sure users are assigned to appropriate groups based on their schools.

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


Write-Log "Start move script..."
Write-Log " Import file path: $SISExportFile"
Write-Log " Facility file path: $FacilityFile"
Write-Log " Config file path: $ConfigFile"

try {
    ## Load config file
    if ((test-path -Path $ConfigFile) -eq $false) {
        Throw "Config file not found. Specify using -ConfigFile. Defaults to config.xml in the directory above where this script is run from."
    }
    $configXML = [xml](Get-Content $ConfigFile)

    $ActiveEmployeeType = $configXml.Settings.Students.ActiveEmployeeType
    $DeprovisionedEmployeeType = $configXml.Settings.Students.DeprovisionedEmployeeType
    $DeprovisionedADOU = $configXml.Settings.Students.DeprovisionedADOU
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
    $SourceUsers = @(Remove-UsersFromUnknownFacilities -UserList (
            Get-SourceUsers -CSVFile $SISExportFile
            ) -FacilityList $Facilities)

    if ($SourceUsers.Count -lt 1)
    {
        Write-Log "No students from source system. Exiting"
        exit
    } else {
        Write-Log "$($SourceUsers.Count) students found in import file."
    }

    # We'll need a list of existing AD usernames if we need to do any renames
    Write-Log "Caching all AD usernames..."
    $AllUsernames = Get-ADUsernames

    # For each active student (in the import file)
    ## If an account exists, continue. If an account does not, skip this user
    ## Ensure that they are in the correct OU, based on their base school

    # Make a list of all AD users (active students) and their OUs
    # Compare those OUs to what we expect them to be

    Write-Log "Caching AD users..."
    $AllStudents = Get-ADUser -Filter {(EmployeeType -eq $ActiveEmployeeType)} -ResultSetSize 2147483647 -Properties employeeId, DistinguishedName
    $ADUsersWithParentOUs = @{}
    foreach($ADUser in $AllStudents) 
    {
        if ($ADUser.employeeId.length -gt 0) 
        {
            if($ADUsersWithParentOUs.ContainsKey($ADUser.employeeId) -eq $false) 
            {
                $ParentContainer = $ADUser.DistinguishedName -replace '^.+?,(CN|OU.+)','$1'
                $ADUsersWithParentOUs.Add("$($ADUser.employeeId)", $ParentContainer)
            }
        }
    }

    $TotalUsers = $($SourceUsers.Count)

    Write-Log "Processing users..."
    foreach($SourceUser in $SourceUsers)
    {
        # Parse the user's name
        $FirstName = $SourceUser.PreferredFirstName
        $LastName = $SourceUser.PreferredLastName
        $Grade = $SourceUser.GradeLevel
        $StudentID = $SourceUser.PupilNo

        # Check for missing preferred names
        if ($FirstName.Length -lt 1) {
            $FirstName = $SourceUser.LegalFirstName
        }
        if ($LastName.Length -lt 1) {
            $LastName = $SourceUser.LegalLastName
        }


        ## #####################################################################
        ## # Get facility information for the facilities that this user
        ## # is supposed to be in.
        ## #####################################################################

        $BaseFacility = $null
        $AdditionalFacility = $null

        # Find this user's base facility
        foreach($Facility in $Facilities)
        {
            if ($Facility.FacilityDAN -eq $SourceUser.BaseSchoolDAN)
            {
                $BaseFacility = $Facility
            }
        }

        ## #####################################################################
        ## # Only continue if the facility (from the source SIS file) is legit
        ## # (skipping schools that we don't want to make user accounts for)
        ## #####################################################################

        if ($null -ne $BaseFacility)
        {                     
            # Should the user account be enabled by default at the new site?
            $AccountEnable = $false
            if (
                ($BaseFacility.DefaultAccountEnabled.ToLower() -eq "true") -or 
                ($BaseFacility.DefaultAccountEnabled.ToLower() -eq "yes")  -or 
                ($BaseFacility.DefaultAccountEnabled.ToLower() -eq "y")  -or 
                ($BaseFacility.DefaultAccountEnabled.ToLower() -eq "t") 
            )
            {
                $AccountEnable = $true
            }

            ## #####################################################################
            ## # Check if the user needs to be moved        
            ## #####################################################################
            
            if ($ADUsersWithParentOUs.ContainsKey($SourceUser.PupilNo))
            {
                $CurrentOU = [string]($ADUsersWithParentOUs[$SourceUser.PupilNo])
                $ExpectedOU = [string]$BaseFacility.ADOU

                if ($CurrentOU.ToLower() -ne $ExpectedOU.ToLower())
                {
                    Write-Log "Moving $FirstName $LastName $StudentID from $CurrentOU to $ExpectedOU..."

                    # Find the ADUser object
                    $EmpID = $SourceUser.PupilNo
                    foreach($ADUser in Get-ADUser -Filter { (employeeId -eq $EmpID) -AND (employeeType -eq $ActiveEmployeeType)})
                    {
                        Write-Log " > Stripping existing groups..."
                        # Strip all existing groups
                        foreach($grp in (get-adprincipalgroupmembership -Identity $ADUser))
                        {
                            try 
                            {
                                if ($grp.Name -ne "Domain Users")
                                {
                                    Remove-ADGroupMember -Identity $grp -Members $ADUser -Confirm:$false
                                }
                            }
                            catch {}
                        }

                        # Update it's new values
                        Write-Log " > Updating properties..."
                        $OfficeValue = $($BaseFacility.Name)
                        if ($null -ne $AdditionalFacility) 
                        {
                            $OfficeValue += ", $($AdditionalFacility.Name)"
                        }

                        set-ADUser -Identity $ADUser -Department "Grade $($SourceUser.Grade)" -Company $($BaseFacility.Name) -Office $OfficeValue -Enabled $AccountEnable

                        # Add user to new groups based on new facility
                        Write-Log " > Adding new groups..."
                        foreach($grp in (Convert-GroupList -GroupString $($BaseFacility.Groups)))
                        {
                            try 
                            {
                                Add-ADGroupMember -Identity $grp -Members $ADUser -Confirm:$false                            
                            }
                            catch {}
                        }
                        
                        # Actually move the object
                        Write-Log " > Moving object..."
                        move-ADObject -identity $ADUser -TargetPath $($BaseFacility.ADOU)
                    }
                }
            }       

        } # If facility isn't null
    }

    ## #####################################################################
    ## # As a clean-up, make sure that all AD objects with the employeetype
    ## # matching our deprovisioned employeetype are in the correct OU
    ## #####################################################################
    Write-Log "Housekeeping existing deprovisioned users..."
    foreach($ADUser in Get-AdUser -Filter {(EmployeeType -eq $DeprovisionedEmployeeType)})
    {
        $ParentContainer = $ADUser.DistinguishedName -replace '^.+?,(CN|OU.+)','$1'
        if ($ParentContainer -ne $DeprovisionedADOU) 
        {
            Write-Log "Deprovisioned user $($ADUser.userprincipalname) is not in correct OU. Moving."
            move-ADObject -identity $ADUser -TargetPath $DeprovisionedADOU         
        }
    } 

    ## Send teams webhook notification

    ## Send email notification
}
catch {
    Write-Log "ERROR: $_"
}
Write-Log "Finished move script."