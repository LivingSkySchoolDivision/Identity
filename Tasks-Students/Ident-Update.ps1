param (
    [Parameter(Mandatory=$true)][string]$SISExportFile,
    [Parameter(Mandatory=$true)][string]$FacilityFile,
    [string]$ConfigFile
 )
<#
    .SYNOPSIS
        Updates users and makes sure users are assigned to appropriate groups based on their schools.

    .DESCRIPTION
        Updates users and makes sure users are assigned to appropriate groups based on their schools.

    .PARAMETER SISExportFile
        A CSV export from the source SIS system.

    .PARAMETER ConfigFile
        Configuration file. Defaults to ""../config.xml".
#>

## ##################################################
## # Configuration can be done in config.xml.       #
## # No user configurable stuff beyond this point   #
## ##################################################

## Bring in functions from external files
. ./../Include/UtilityFunctions.ps1
. ./../Include/ADFunctions.ps1
. ./../Include/CSVFunctions.ps1

Write-Log "Start update script (This script may take 20+ minutes to complete)..."
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
    ## Ensure that they are in the correct groups, based on any additional schools
    ## Ensure their "Office" includes the names of all of their schools

    $TotalUsers = $($SourceUsers.Count)
    $UserCounter = 0

    Write-Log "Processing users..."
    foreach($SourceUser in $SourceUsers)
    {
        # Parse the user's name
        $FirstName = $SourceUser.PreferredFirstName
        $LastName = $SourceUser.PreferredLastName
        $Grade = $SourceUser.GradeLevel
        $StudentID = $SourceUser.PupilNo
        $LearningID = $SourceUser.SaskLearningID

        # Check for missing preferred names
        if ($FirstName.Length -lt 1) {
            $FirstName = $SourceUser.LegalFirstName
        }
        if ($LastName.Length -lt 1) {
            $LastName = $SourceUser.LegalLastName
        }

        # Find an account for this user in AD
        $EmpID = $StudentID

        ## #####################################################################
        ## # Get facility information for the facilities that this user
        ## # is supposed to be in.
        ## #####################################################################

        $BaseFacility = $null

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
            ## #####################################################################
            ## # We need to do things in a few seperate loops, because several
            ## # lines below could break the reference returned by Get-ADUser
            ## # This will not be very efficient.
            ## #####################################################################
            


            ## #####################################################################
            ## # Check if the user's display name needs to be updated       
            ## #####################################################################
            foreach($ADUser in Get-ADUser -Filter {(EmployeeId -eq $EmpID) -and ((EmployeeType -eq $ActiveEmployeeType) -or (EmployeeType -eq $DeprovisionedEmployeeType))} -Properties cn,displayName,Department,Company,Office)
            {
                ## #####################################################################
                ## # Check if this user's first or last name has changed.
                ## #
                ## # If so, we'll need to update the new name, and make a new username
                ## # and email address for the user.
                ## #####################################################################

                $DisplayName = "$FirstName $LastName"

                # If the display name is different than expected, make a new username and
                # make a new email address
                if ($DisplayName.ToLower() -ne $ADUser.displayName.ToLower())
                {
                    $OldUsername = $ADUser.samaccountname

                    # If old username exists in the big list of usernames, remove it
                    $newAllUsernames = @()
                    foreach($existingusername in $AllUsernames) {
                        if ($OldUsername -ne $existingusername) {
                            $newAllUsernames += $existingusername
                        }
                    }
                    $AllUsernames = $newAllUsernames

                    $NewUsername = New-Username -FirstName $FirstName -LastName $LastName -UserId $SourceUser.PupilNo -ExistingUsernames $AllUsernames
                    $NewEmail = "$($NewUsername)@$($EmailDomain)"

                    # Insert the new username into the list
                    $AllUsernames += $NewUsername

                    # Apply the new samaccountname, displayname, firstname, lastname, userprincipalname, and mail
                    Write-Log "Updating names, usernames, and email address user $OldUsername to $NewUsername"
                    set-aduser $ADUser -SamAccountName $NewUsername -UserPrincipalName $NewEmail -DisplayName $DisplayName -GivenName $FirstName -Surname $LastName -EmailAddress $NewEmail

                    # TODO: Probably need to add/remove things from the "proxyAddress" field to handle default email aliases here
                    #       This field is not a simple string though, and may contain things we don't want to touch.
                }
            }

            
            ## #####################################################################
            ## # Check if the user's CN needs to be renamed        
            ## #####################################################################
            foreach($ADUser in Get-ADUser -Filter {(EmployeeId -eq $EmpID) -and ((EmployeeType -eq $ActiveEmployeeType) -or (EmployeeType -eq $DeprovisionedEmployeeType))} -Properties cn,displayName,Department,Company,Office)
            {
                ## #####################################################################
                ## # Check if this user's first or last name has changed.
                ## #
                ## # If so, we'll need to update the new name, and make a new username
                ## # and email address for the user.
                ## #####################################################################

                $ExpectedCN = "$($FirstName.ToLower()) $($LastName.ToLower()) $StudentID"

                if ($ExpectedCN -ne $ADUser.cn)
                {
                    Write-Log "Updating CN for user '$($ADUser.cn)' to '$ExpectedCN'"
                    $ADUser | rename-adobject -NewName $ExpectedCN                     
                }
            }
            
            ## #####################################################################
            ## # Check if values need to be updated for the user
            ## #####################################################################
            foreach($ADUser in Get-ADUser -Filter {(EmployeeId -eq $EmpID) -and ((EmployeeType -eq $ActiveEmployeeType) -or (EmployeeType -eq $DeprovisionedEmployeeType))} -Properties displayName,Department,Company,Office,employeeNumber)
            {
                 ## #####################################################################
                ## # Learning ID (Stored as EmployeeNumber)
                ## #####################################################################
                if ($LearningID -ne $ADUser.employeeNumber) {
                    Write-Log "Updating learning ID (employee number) for $($ADUser.userprincipalname) from $($ADUser.employeeNumber) to $LearningID"
                    set-aduser -Identity $ADUser -EmployeeNumber $LearningID
                }

                ## #####################################################################
                ## # Grade (stored as Department)
                ## #####################################################################
                $GradeValue = "Grade $Grade"
                if ($GradeValue -ne $ADUser.Department) {
                    Write-Log "Updating grade for $($ADUser.userprincipalname) from $($ADUser.Department) to $GradeValue"
                    set-aduser -Identity $ADUser -Department $GradeValue
                }

                ## #####################################################################
                ## # Check if this user is in the correct groups for any
                ## # additional facilities they may belong to.
                ## # Also check to make sure that this facility is listed in their "Department".
                ## #####################################################################

                $userActualGroups = @()
                foreach($adgroup in (get-adprincipalgroupmembership -Identity $ADUser)) 
                {
                    $userActualGroups += $adgroup.name
                }

                ## #####################################################################
                ## # Ensure this user is in the necesary groups for the primary facility
                ## #####################################################################
                foreach($grp in $(Convert-GroupList -GroupString $($BaseFacility.Groups)))
                {
                    if ($userActualGroups -inotcontains $grp)
                    {
                        Write-Log "Adding $($ADUser.userprincipalname) to group: $grp"
                        Add-ADGroupMember -Identity $grp -Members $ADUser -Confirm:$false
                    }
                }

            }

        } # If facility isn't null

        $UserCounter++
        if ($UserCounter % 50 -eq 0) {
            Write-Log "$UserCounter/$TotalUsers"
        }

    }


    ## Send teams webhook notification

    ## Send email notification
}
catch {
    Write-Log "ERROR: $_"
}
Write-Log "Finished update script."