param (
    [Parameter(Mandatory=$true)][string]$SISExportFile,
    [Parameter(Mandatory=$true)][string]$FacilityFile,
    [string]$ConfigFile
 )
<#
    .SYNOPSIS
        Deprovisions user accounts that no longer exist in the system
    
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

## Bring in functions from external files
. ../Include/UtilityFunctions.ps1
. ../Include/ADFunctions.ps1
. ../Include/CSVFunctions.ps1


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
$DeprovisionedOU = $configXml.Settings.General.DeprovisionedADOU
$DeprovisionedEmployeeType = $configXml.Settings.General.DeprovisionedEmployeeType
$NotificationWebHookURL = $configXML.Settings.Notifications.WebHookURL


## Load the list of schools from the ../db folder

$Facilities = Get-Facilities -CSVFile $FacilityFile
if ($Facilities.Count -lt 1)
{
    write-host "No facilities found. Exiting."
    exit
} else {
    write-host $Facilities.Count "facilities found in import file."
}

## Load the student records from the file.
## If the file doesn't exist or is empty, don't continue any further.

$SourceUsers = Remove-DuplicateRecords -UserList (
    Remove-UsersFromUnknownFacilities -UserList (
        Get-SourceUsers -CSVFile $SISExportFile
        ) -FacilityList $Facilities
    )

if ($SourceUsers.Count -lt 1)
{
    write-host "No students from source system. Exiting"
    exit
} else {
    write-host $SourceUsers.Count "student found in import file."
}

## Make a List<string> of UserIDs from the source CSV so we can loop through it to find stuff more efficiently.

$sourceUserIds = New-Object Collections.Generic.List[String]
foreach($SourceUser in $SourceUsers)
{
    if ($sourceUserIds.Contains($SourceUser.UserId) -eq $false)
    {
        $sourceUserIds.Add($SourceUser.UserId)
    }
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

write-host "Found" $UsersToProvision.Count "users to create"

## ############################################################
## Find users to delete
## ############################################################

$EmployeeIDsToDeprovision = @()
foreach($ExistingEmployeeId in $ExistingActiveEmployeeIds)
{
    if ($sourceUserIds.Contains($ExistingEmployeeId) -eq $false)
    {
        $EmployeeIDsToDeprovision += $ExistingEmployeeId
    }
}

write-host "Found" $EmployeeIDsToDeprovision.Count "users to deprovision"


## ############################################################
## Deprovision users
## ############################################################

foreach($EmployeeId in $EmployeeIDsToDeprovision) {
    # Find the user's DN
    


    # Set users employeeType

    # Disable the account

    # Add a comment to the user

    # Move user to deprovision OU

    write-host "Deprovision: "
}

## Send teams webhook notification

## Send email notification
