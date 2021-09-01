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
    $DeprovisionedEmployeeType = $configXml.Settings.Students.DeprovisionedEmployeeType
    $NotificationWebHookURL = $configXML.Settings.Notifications.WebHookURL
    $DisableCutoffDays = [int]$configXml.Settings.Students.DaysDeprovisionedUntilDisable
    $PurgeCutoffDays = [int]$configXml.Settings.Students.DaysDisabledBeforePurge

    Write-Log "Finding stale deprovisioned accounts..."
    foreach($User in Get-ADUser -filter {Enabled -eq $True -and employeeType -eq $DeprovisionedEmployeeType } -Property LastLogonTimestamp | Select-Object -Property Name,DistinguishedName,@{ n = "LastLogonDate"; e = { [datetime]::FromFileTime( $_.lastLogonTimestamp ) } })
    {
        # Parse the date
        [datetime]$today = Get-Date
        [datetime]$userLastLogonDate = New-Object DateTime
        if ([DateTime]::TryParse($User.LastLogonDate,
                                      [System.Globalization.CultureInfo]::InvariantCulture,
                                      [System.Globalization.DateTimeStyles]::None,
                                      [ref]$userLastLogonDate))
        {
            $UserDaysSinceLastLogin = New-TimeSpan -Start $userLastLogonDate -End $today
            if ($UserDaysSinceLastLogin.TotalDays -gt $DisableCutoffDays)
            {
                $DepTime = Get-Date  
                Write-Log "DISABLE: $($User.DistinguishedName) ($($UserDaysSinceLastLogin.TotalDays))"
                Disable-ADAccount -Identity $User.DistinguishedName
                Set-ADUser -Identity $User.DistinguishedName -Description "Disabled due to inactivity: $DepTime"
            }
        }
    }

    Write-Log "Stale disabled former student accounts:"
    $PurgeCutoffDay = (get-date).adddays([int]$PurgeCutoffDays * -1)
    Write-Log "Purge Cutoff day: $PurgeCutoffDay"
    foreach($User in Get-ADUser -filter {Enabled -eq $false -AND employeeType -eq $DeprovisionedEmployeeType -AND whenChanged -lt $PurgeCutoffDay} -Properties whenChanged)
    {
        Write-Log "PURGE: $($User.DistinguishedName)"
        Remove-ADUser -Identity $User
    }
    
 
    ## Send teams webhook notification

    ## Send email notification
}
catch {
    Write-Log "ERROR: $_"
}
Write-Log "Finished cleaning up."
