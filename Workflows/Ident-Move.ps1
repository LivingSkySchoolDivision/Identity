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
$SourceUsers = Remove-UsersFromUnknownFacilities -UserList (
        Get-SourceUsers -CSVFile $SISExportFile
        ) -FacilityList $Facilities

if ($SourceUsers.Count -lt 1)
{
    write-host "No students from source system. Exiting"
    exit
} else {
    write-host $SourceUsers.Count "students found in import file."
}

# For each active student (in the import file)
## If an account exists, continue. If an account does not, skip this user
## Ensure that they are in the correct OU, based on their base school
## Ensure that they are in the correct groups, based on any additional schools
## Ensure their "Office" includes the names of all of their schools

foreach($SourceUser in $SourceUsers) {
    # Find an account for this user in AD
    
    foreach($ADUser in Get-AdUser -Filter {(EmployeeId -eq $SourceUser.UserId) -and (EmployeeType -eq $ActiveEmployeeType)})
    {
        write-host "$($SourceUser.UserId):$($ADUser.sAMAccountName)"
    } 
}