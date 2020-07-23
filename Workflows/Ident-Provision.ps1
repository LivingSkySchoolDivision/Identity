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
$ActiveEmployeeType = $configXml.Settings.General.ActiveEmployeeType
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

write-host "Found" $UsersToReProvision.Count "deprovisioned users to reactivate."
write-host "Adjusted to" $UsersToProvision.Count "users to create"

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
## Reprovision existing deprovisioned users
## ############################################################

foreach($User in $UsersToReProvision) {
    
}

## ############################################################
## Deprovision users
## ############################################################

foreach($EmployeeId in $EmployeeIDsToDeprovision) {
    
}

## ############################################################
## Provision new users
## ############################################################

write-host "Getting all existing sAMAccountNames from AD..."
#$AllUsernames = Get-ADUsernames


foreach($NewUser in $UsersToProvision) {
    $NewUsername = New-Username -FirstName $NewUser.FirstName -LastName $NewUser.LastName -UserId $NewUser.UserId -ExistingUsernames $AllUsernames
    write-host "New username:" $NewUsername
}


## Send teams webhook notification

## Send email notification