param (
    [string]$ConfigFile
 )
<#
    .SYNOPSIS
        Disables and deletes stale deprovisioned accounts

    .DESCRIPTION
        Disables and deletes stale deprovisioned accounts
        
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

Write-Log "Start cleanup script..."
Write-Log " Import file path: $SISExportFile"
Write-Log " Facility file path: $FacilityFile"
Write-Log " Config file path: $ConfigFile"

try {
    ## Load config file
    if ((test-path -Path $ConfigFile) -eq $false) {
        Throw "Config file not found. Specify using -ConfigFile. Defaults to config.xml in the directory above where this script is run from."
    }
    $configXML = [xml](Get-Content $ConfigFile)

    $DeprovisionedEmployeeType = $configXml.Settings.Students.DeprovisionedEmployeeType
    $NotificationWebHookURL = $configXML.Settings.Notifications.WebHookURL
    $DisableCutoffDays = [int]$configXml.Settings.Students.DaysDeprovisionedUntilDisable
    $PurgeCutoffDays = [int]$configXml.Settings.Students.DaysDisabledBeforePurge

    # Find any currently disabled accounts that have been untouched for the given amount of days
    # and DELETE the accounts
    Write-Log "Stale disabled former student accounts:"
    $PurgeCutoffDay = (get-date).adddays([int]$PurgeCutoffDays * -1)
    Write-Log "Purge Cutoff day: $PurgeCutoffDay"

    foreach($User in Get-ADUser -filter {Enabled -eq $false -AND employeeType -eq $DeprovisionedEmployeeType -AND whenChanged -lt $PurgeCutoffDay} -Properties whenChanged)
    {
        Write-Log "PURGE: $($User.DistinguishedName)"
        Remove-ADUser -Identity $User
    }

    # Find any currently enabled accounts that have been untouched for the given amount of days
    # and DISABLE them
    Write-Log "Finding stale deprovisioned accounts..."
    $DisableCutOffDate = (get-date).adddays([int]$DisableCutoffDays * -1)
    Write-Log "Disable cutoff day: $DisableCutOffDate"
    foreach($User in Get-ADUser -filter {Enabled -eq $True -and employeeType -eq $DeprovisionedEmployeeType -AND whenChanged -lt $DisableCutOffDate } -Property whenChanged)
    {
        Write-Log "DISABLE: $($User.DistinguishedName)"
        Disable-ADAccount -Identity $User.DistinguishedName
    }
 
    ## Send teams webhook notification

    ## Send email notification
}
catch {
    Write-Log "ERROR: $_"
}
Write-Log "Finished cleaning up."
