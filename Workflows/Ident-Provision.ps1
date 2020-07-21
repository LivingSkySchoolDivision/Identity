param (
    [Parameter(Mandatory=$true)][string]$SISExportFile,
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
. ../Include/ADFunctions.ps1

## Load config file 
$AdjustedConfigFilePath = $ConfigFilePath
if ($AdjustedConfigFilePath.Length -le 0) {
    $AdjustedConfigFilePath = join-path -Path $(Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent) -ChildPath "config.xml"
}

if ((test-path -Path $AdjustedConfigFilePath) -eq $false) {
    Throw "Config file not found. Specify using -ConfigFilePath. Defaults to config.xml in the directory above where this script is run from."
}
$configXML = [xml](Get-Content $AdjustedConfigFilePath)
$EmployeeType = $configXml.Settings.General.EmployeeType
$SISConnectionString = $configXML.Settings.ConnectionStrings.SchoolLogic
$NotificationWebHookURL = $configXML.Settings.Notifications.WebHookURL

## Load the student records from the file.
## If the file doesn't exist or is empty, don't continue any further.

## Get a list of all users currently in AD
## Only users with employeeID set AND 

# $AllUsernames = Get-ADUsernames

$AllStudents = Get-ADUsers -EmployeeType $EmployeeType
$AllStudentCount = $AllStudents.Count

write-host "Students:" $AllStudentCount


## Get a list of all usernames in the entire system.
## This should include ALL users, not just those that match the EmployeeType, because
## we need to be able to generate usernames that don't collide with other users.

## Load the list of schools from the ../db folder



## For each student record
##  - If a corresponding AD user with the same EmployeeID exists, ignore them
##  - If a user with the same EmployeeID (and EmployeeType) does not exist, create it in the appropriate OU

## Send teams webhook notification

## Send email notification