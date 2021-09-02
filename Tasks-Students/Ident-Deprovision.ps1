param (
    [Parameter(Mandatory=$true)][string]$SISExportFile,
    [Parameter(Mandatory=$true)][string]$FacilityFile,
    [Parameter(Mandatory=$true)][string]$ConfigFile
 )
<#
    .SYNOPSIS
        Compares a list of users with users in an AD system, and deprovision.
    
    .DESCRIPTION
        This script removes users from AD/Azure who no longer exist in the Student Information System.
    
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

    try {
        $DepTime = Get-Date  
        set-aduser $Identity -Description "Deprovisioned: $DepTime" -Enabled $true -Office "$DeprovisionedEmployeeType" -Replace @{'employeeType'="$DeprovisionedEmployeeType";'title'="$DeprovisionedEmployeeType"}

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
    catch {
        Write-Log "Failed to deprovision $Identity (exception follows)"
        Write-Log $_
    }
}


Write-Log "Start deprovision script..."
try {
    ## Load config file
    if ((test-path -Path $ConfigFile) -eq $false) {
        Throw "Config file not found. Specify using -ConfigFile. Defaults to config.xml in the directory above where this script is run from."
    }
    $configXML = [xml](Get-Content $ConfigFile)

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

    ## Make a List<string> of UserIDs from the source CSV so we can loop through it to find stuff more efficiently.

    $sourceUserIds = New-Object Collections.Generic.List[String]
    foreach($SourceUser in $SourceUsers)
    {
        if ($sourceUserIds.Contains($SourceUser.PupilNo) -eq $false)
        {
            $sourceUserIds.Add($SourceUser.PupilNo)
        }
    }

    ## Get a list of all users currently in AD
    ## Only users with employeeID set AND employeeType set to the specified one from the config file.

    $ExistingActiveEmployeeIds = Get-SyncableEmployeeIDs -EmployeeType $ActiveEmployeeType

    ## ############################################################
    ## Find users to delete
    ## ############################################################

    $EmployeeIDsToDeprovision = @()
    foreach($ExistingEmployeeId in $ExistingActiveEmployeeIds)
    {
        if ($ExistingEmployeeId.Length -gt 0)
        {
            if ($sourceUserIds.Contains($ExistingEmployeeId) -eq $false)
            {
                $EmployeeIDsToDeprovision += $ExistingEmployeeId
            }
        }
    }

    Write-Log "Found $($EmployeeIDsToDeprovision.Count) users to deprovision"

    ## ############################################################
    ## Deprovision users
    ## ############################################################

    foreach($EmployeeId in $EmployeeIDsToDeprovision) {
        # Find the user's DN based on their employeeID   
        foreach($ADUser in Get-AdUser -Filter {(EmployeeId -eq $EmployeeId) -and (EmployeeType -eq $ActiveEmployeeType)})
        {
            Deprovision-User $ADUser -EmployeeType $DeprovisionedEmployeeType -DeprovisionOU $DeprovisionedADOU              
        }
    }
 
    ## Send teams webhook notification

    ## Send email notification
}
catch {
    Write-Log "ERROR: $_"
}
Write-Log "Finished deprovisioning."
