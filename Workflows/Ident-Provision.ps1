param (
    [Parameter(Mandatory=$true)][string]$SISExportFile,
    [Parameter(Mandatory=$true)][string]$FacilityFile,
    [string]$ConfigFile
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
        if ($ExistingActiveEmployeeIds.Contains($SourceUser.UserId) -eq $false)
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
        if ($ExistingDeprovisionedEmployeeIDs.Contains($SourceUser.UserId) -eq $true)
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

# Reprovisioning will be handled by the "Move" script

## ############################################################
## Provision new users
## ############################################################

Write-Log "Getting all existing sAMAccountNames from AD..."
$AllUsernames = Get-ADUsernames

$IgnoredUsers = @()
Write-Log "Processing new users..."
foreach($NewUser in $UsersToProvision) {

    # Find the facility for this user
    $ThisUserFacility = $null

    foreach($Facility in $Facilities)
    {
        if ($Facility.FacilityId -eq $NewUser.BaseFacilityId)
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
            $DisplayName = "$($NewUser.FirstName) $($NewUser.LastName)"

            # Make a CanonicalName
            $CN = "$($NewUser.FirstName.ToLower()) $($NewUser.LastName.ToLower()) $($NewUser.UserId)"

            # Generate a username for this user
            $NewUsername = New-Username -FirstName $NewUser.FirstName -LastName $NewUser.LastName -UserId $NewUser.UserId -ExistingUsernames $AllUsernames

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
            $Password = "$($NewUser.FirstName.Substring(0,1).ToLower())$($NewUser.LastName.Substring(0,1).ToLower())-$($NewUser.UserId)"
            $SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force

            # Create the user
            New-ADUser -SamAccountName $NewUsername -AccountPassword $SecurePassword -UserPrincipalName $NewEmail -Name $CN -Enabled $AccountEnable -DisplayName $DisplayName -GivenName $($NewUser.FirstName) -Surname $($NewUser.LastName) -ChangePasswordAtLogon $true -Department "Grade $($NewUser.Grade)" -EmailAddress $NewEmail -Company $($ThisUserFacility.Name) -Office $($ThisUserFacility.Name) -EmployeeID $($NewUser.UserId) -OtherAttributes @{'employeeType'="$ActiveEmployeeType";'title'="$ActiveEmployeeType"} -Path $OU

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



## Send teams webhook notification

## Send email notification

Write-Log "Done."