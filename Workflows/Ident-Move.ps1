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
$EmailDomain = $configXml.Settings.General.EmailDomain
$ActiveEmployeeType = $configXml.Settings.General.ActiveEmployeeType
$DeprovisionedEmployeeType = $configXml.Settings.General.DeprovisionedEmployeeType
$NotificationWebHookURL = $configXML.Settings.Notifications.WebHookURL

## Load the list of schools from the ../db folder
$Facilities = @(Get-Facilities -CSVFile $FacilityFile)
if ($Facilities.Count -lt 1)
{
    write-host "No facilities found. Exiting."
    exit
} else {
    write-host $Facilities.Count "facilities found in import file."
}

## Load the student records from the file.
## If the file doesn't exist or is empty, don't continue any further.
$SourceUsers = @(Remove-UsersFromUnknownFacilities -UserList (
        Get-SourceUsers -CSVFile $SISExportFile
        ) -FacilityList $Facilities)

if ($SourceUsers.Count -lt 1)
{
    write-host "No students from source system. Exiting"
    exit
} else {
    write-host $SourceUsers.Count "students found in import file."
}

# We'll need a list of existing AD usernames if we need to do any renames
$AllUsernames = Get-ADUsernames

# For each active student (in the import file)
## If an account exists, continue. If an account does not, skip this user
## Ensure that they are in the correct OU, based on their base school
## Ensure that they are in the correct groups, based on any additional schools
## Ensure their "Office" includes the names of all of their schools

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
        ## #####################################################################
        
        ## #####################################################################
        ## # Check if the user needs to be moved        
        ## #####################################################################
        foreach($ADUser in Get-ADUser -Filter {(EmployeeId -eq $EmpID) -and ((EmployeeType -eq $ActiveEmployeeType) -or (EmployeeType -eq $DeprovisionedEmployeeType))} -Properties displayName,Department,Company,Office)
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
                write-host "Moving $ADUser from $ParentContainer to $($BaseFacility.ADOU)"

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
                        write-host "Removing $($ADUser.userprincipalname) from group: $grp"
                        remove-ADGroupMember -Identity $grp -Members $ADUser -Confirm:$false
                    }
                }

                # Set new Company value
                set-ADUser -Identity $ADUser -Company $($BaseFacility.Name) -Office $($BaseFacility.Name)

                # Actually move the object
                move-ADObject -identity $ADUser -TargetPath $BaseFacility.ADOU

                # Add user to new groups based on new facility
                foreach($grp in (Convert-GroupList -GroupString $($BaseFacility.Groups)))
                {
                    write-host "Adding $($ADUser.userprincipalname) to group: $grp"
                    Add-ADGroupMember -Identity $grp -Members $ADUser -Confirm:$false
                }
            }  

            if ($null -eq $ADUser) {
                write-host "ADUser object is now null. Skipping until next run."
                continue
            }
        }

        ## #####################################################################
        ## # Check if the user needs to be renamed        
        ## #####################################################################
        foreach($ADUser in Get-ADUser -Filter {(EmployeeId -eq $EmpID) -and ((EmployeeType -eq $ActiveEmployeeType) -or (EmployeeType -eq $DeprovisionedEmployeeType))} -Properties displayName,Department,Company,Office)
        {
            ## #####################################################################
            ## # Check if this user's first or last name has changed.
            ## #
            ## # If so, we'll need to update the new name, and make a new username
            ## # and email address for the user.
            ## #####################################################################

            $DisplayName = "$($SourceUser.FirstName) $($SourceUser.LastName)"

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
                    } else {
                        write-host "Removed $OldUsername from known username list"
                    }
                }
                $AllUsernames = $newAllUsernames

                $NewUsername = New-Username -FirstName $SourceUser.FirstName -LastName $SourceUser.LastName -UserId $SourceUser.UserId -ExistingUsernames $AllUsernames
                $NewEmail = "$($NewUsername)@$($EmailDomain)"
                $NewCN = "$($SourceUser.FirstName.ToLower()) $($SourceUser.LastName.ToLower()) $($SourceUser.UserId)"

                # Insert the new username into the list
                $AllUsernames += $NewUsername

                # Apply the new samaccountname, displayname, firstname, lastname, userprincipalname, and mail
                write-host "Renaming user $OldUsername to $NewUsername"
                $ADUser = rename-adobject -Identity $ADUser -NewName $NewCN -PassThru
                set-aduser $ADUser -SamAccountName $NewUsername -UserPrincipalName $NewEmail -DisplayName $DisplayName -GivenName $($SourceUser.FirstName) -Surname $($SourceUser.LastName) -EmailAddress $NewEmail

                # TODO: Probably need to add/remove things from the "proxyAddress" field to handle default email aliases here
                #       This field is not a simple string though, and may contain things we don't want to touch.
            }
        }

        ## #####################################################################
        ## # Check if values need to be updated for the user
        ## #####################################################################
        foreach($ADUser in Get-ADUser -Filter {(EmployeeId -eq $EmpID) -and ((EmployeeType -eq $ActiveEmployeeType) -or (EmployeeType -eq $DeprovisionedEmployeeType))} -Properties displayName,Department,Company,Office)
        {
            ## #####################################################################
            ## # Grade (stored as Department)
            ## #####################################################################
            $GradeValue = "Grade $($SourceUser.Grade)"
            if ($GradeValue -ne $ADUser.Department) {
                write-host "Updating grade for $($ADUser.userprincipalname) from $($ADUser.Department) to $GradeValue"
                set-aduser -Identity $ADUser -Department $GradeValue
            }

            ## #####################################################################
            ## # Check if this user is in the correct groups for any
            ## # additional facilities they may belong to.
            ## # Also check to make sure that this facility is listed in their "Department".
            ## #####################################################################
            if ($null -ne $AdditionalFacility)
            {                
                if ($AdditionalFacility.FacilityDAN -ne $BaseFacility.FacilityDAN) 
                {
                    # Store a list of facilities in the "Office" or "PhysicalDeliveryOfficeLocationName" field.
                    if ($ADUser.Office -inotmatch $AdditionalFacility.Name) 
                    {
                        $NewOffice = "$($ADUser.Office), $($AdditionalFacility.Name)"
                        write-host "Setting $($ADUser)'s Office to: $NewOffice"
                        set-aduser -Identity $ADUser -Office $NewOffice
                    }

                    # Add to groups for additional facility
                    foreach($grp in (Convert-GroupList -GroupString $($AdditionalFacility.Groups)))
                    {
                        write-host "Adding $($ADUser.userprincipalname) to group: $grp"
                        Add-ADGroupMember -Identity $grp -Members $ADUser -Confirm:$false
                    }

                }
            }

        }

    } # If facility isn't null

}