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
        # Find an account for this user in AD
        $EmpID = $SourceUser.UserId

        ## #####################################################################
        ## # Get facility information for the facilities that this user
        ## # is supposed to be in.
        ## #####################################################################

        $BaseFacility = $null
        $AdditionalFacility = $null

        # Find this user's base facility
        foreach($Facility in $Facilities)
        {
            if ($Facility.FacilityId -eq $SourceUser.BaseFacilityId)
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
            ## #####################################################################
            ## # We need to do things in a few seperate loops, because several
            ## # lines below could break the reference returned by Get-ADUser
            ## # This will not be very efficient.
            ## #####################################################################
            
            ## #####################################################################
            ## # Check if the user needs to be moved        
            ## #####################################################################
            foreach($ADUser in Get-ADUser -Filter {(EmployeeId -eq $EmpID) -and ((EmployeeType -eq $ActiveEmployeeType) -or (EmployeeType -eq $DeprovisionedEmployeeType))} -Properties displayName,Department,Company,Office,Description,EmployeeType,title)
            {
                ## #####################################################################
                ## # Ensure the user is in the correct OU for their base facility.
                ## #
                ## # If a move is required, remove from old facility groups, and
                ## # add to new facility groups.
                ## #
                ## # We basically can't do anything after this, because the object
                ## # reference for $ADUser will no longer be valid once the object 
                ## # is moved.
                ## #####################################################################
                $ParentContainer = $ADUser.DistinguishedName -replace '^.+?,(CN|OU.+)','$1'

                # Check if this user is in the expected container
                if ($ParentContainer.ToLower() -ne $BaseFacility.ADOU.ToLower()) {
                    Write-Log "Moving $ADUser from $ParentContainer to $($BaseFacility.ADOU)"

                    # Remove the user from any previous groups
                    # Get the security groups from the "previous" school, based on what OU he's in
                    $PreviousFacility = $null
                    foreach($Facility in $Facilities)
                    {
                        if ($null -ne $Facility.ADOU) {
                            if ($Facility.ADOU.ToLower() -eq $ParentContainer.ToLower())
                            {
                                $PreviousFacility = $Facility
                            }
                        }
                    }
                    if ($null -ne $PreviousFacility) {
                        foreach($grp in (Convert-GroupList -GroupString $($PreviousFacility.Groups)))
                        {
                            Write-Log "Removing $($ADUser.userprincipalname) from group: $grp"
                            remove-ADGroupMember -Identity $grp -Members $ADUser -Confirm:$false
                        }
                    }

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

                    # If this user is being reprovisioned, reset some values
                    if ($ADUser.EmployeeType -eq $DeprovisionedEmployeeType) 
                    {
                        set-aduser $ADUser -Replace @{'employeeType'="$ActiveEmployeeType";'title'="$ActiveEmployeeType"} -Clear description                   
                    }

                    # Set new Company value
                    set-ADUser -Identity $ADUser -Company $($BaseFacility.Name) -Office $($BaseFacility.Name) -Enabled $AccountEnable

                    # Actually move the object
                    move-ADObject -identity $ADUser -TargetPath $BaseFacility.ADOU

                    # Add user to new groups based on new facility
                    foreach($grp in (Convert-GroupList -GroupString $($BaseFacility.Groups)))
                    {
                        Write-Log "Adding $($ADUser.userprincipalname) to group: $grp"
                        Add-ADGroupMember -Identity $grp -Members $ADUser -Confirm:$false
                    }
                }  

                if ($null -eq $ADUser) {
                    Write-Log "ADUser object is now null. Skipping until next run."
                    continue
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
Write-Log "Finished move script."