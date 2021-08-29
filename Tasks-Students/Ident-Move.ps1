param (
    [Parameter(Mandatory=$true)][string]$SISExportFile,
    [Parameter(Mandatory=$true)][string]$FacilityFile,
    [string]$ConfigFile
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

## Bring in functions from external files
. ./../Include/UtilityFunctions.ps1
. ./../Include/ADFunctions.ps1
. ./../Include/CSVFunctions.ps1

Write-Log "Start move script..."
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
        ## #####################################################################
        ## # Get facility information for the facilities that this user
        ## # is supposed to be in.
        ## #####################################################################

        $BaseFacility = $null
        $AdditionalFacility = $null

        # Find this user's base facility
        foreach($Facility in $Facilities)
        {
            if ($Facility.FacilityId -eq $SourceUser.BaseSchoolDAN)
            {
                $BaseFacility = $Facility
            }
        }

        # Find this user's additional facility
        foreach($Facility in $Facilities)
        {
            if ($Facility.FacilityId -eq $SourceUser.AdditionalFacilityId)
            {
                $AdditionalFacility = $Facility
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
            
            if ($ADUsersWithParentOUs.ContainsKey($SourceUser.StudentID))
            {
                $CurrentOU = [string]($ADUsersWithParentOUs[$SourceUser.StudentID])
                $ExpectedOU = [string]$BaseFacility.ADOU

                if ($CurrentOU.ToLower() -ne $ExpectedOU.ToLower())
                {
                    Write-Log "Moving $($SourceUser.PreferredFirstName) $($SourceUser.LastName) ($($SourceUser.StudentID)) from $CurrentOU to $ExpectedOU..."

                    # Find the ADUser object
                    $EmpID = $SourceUser.StudentID
                    foreach($ADUser in Get-ADUser -Filter { (employeeId -eq $EmpID) -AND (employeeType -eq $ActiveEmployeeType)})
                    {
                        Write-Log " > Stripping existing groups..."
                        # Strip all existing groups
                        foreach($grp in (get-adprincipalgroupmembership -Identity $ADUser))
                        {
                            try 
                            {
                                if ($Group.Name -ne "Domain Users")
                                {
                                    Remove-ADGroupMember -Identity $Group -Members $ADUser -Confirm:$false
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
            Write-Log "Deprivisioned user $($ADUser.userprincipalname) is not in correct OU. Moving."
            Deprovision-User $ADUser -EmployeeType $DeprovisionedEmployeeType -DeprovisionOU $DeprovisionedADOU           
        }
    } 

    ## Send teams webhook notification

    ## Send email notification
}
catch {
    Write-Log "ERROR: $_"
}
Write-Log "Finished move script."