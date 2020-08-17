## #########################################################
## # This script is designed to be run as a scheduled task.
## #
## # It should be run as a user that has permission to 
## # add/update/remove users in AD, in the OUs that this
## # system is set up to manage.
## #
## # DO NOT SET THIS SCRIPT UP TO RUN AS A DOMAIN ADMIN.
## # Create a service account, MSA, or gMSA, and delegate
## # AD permissions to it for the OUs that it will manage.
## #
## # You should run this script with the "working directory"
## # set to the directory this script is in.
## #########################################################

$ConfigFilePath = "../config.xml"
$InFilePath = "../In/students.csv"
$LogFilePath = "../Logs/"
$JobNameNoSpaces = "Cleanup"

# Include this library file, because we want to use Write-Log
. ./../Include/UtilityFunctions.ps1

## #########################################################
## # Set script location so the relative paths all work
## #########################################################

$OldLocation = get-location
set-location $PSScriptRoot

## #########################################################
## # Set up a filename for the logs
## #########################################################
function Get-FullTimeStamp 
{
    $now=get-Date
    $yr=("{0:0000}" -f $now.Year).ToString()
    $mo=("{0:00}" -f $now.Month).ToString()
    $dy=("{0:00}" -f $now.Day).ToString()
    $hr=("{0:00}" -f $now.Hour).ToString()
    $mi=("{0:00}" -f $now.Minute).ToString()
    $timestamp=$yr + "-" + $mo + "-" + $dy + "-" + $hr + $mi
    return $timestamp
}

$LogFile = Join-Path $LogFilePath ((Get-FullTimeStamp) + "-$JobNameNoSpaces.log")
if ((Test-Path $LogFilePath) -eq $false) {
    Write-Log "Creating log file directory at $LogFilePath"
    New-Item -Path $LogFilePath -ItemType Directory
}

Write-Host "Logging to $LogFile"
Write-Log "Starting $JobNameNoSpaces script..." >> $LogFile
## #########################################################
## # Checks to make sure necesary files exist
## #########################################################

# Make sure config file exists
if ((Test-Path $ConfigFilePath) -eq $false) {
    Write-Log "Config file not found. exiting." >> $LogFile
    Write-Log "Finished full sync script with errors." >> $LogFile
    set-location $OldLocation
    exit
}

## #########################################################
## # Run cleanup script
## #########################################################

Write-Log "Calling account cleanup script..." >> $LogFile
try {
    powershell -NoProfile -File ../Tasks-Students/Ident-Cleanup.ps1 -ConfigFile $ConfigFilePath >> $LogFile
} 
catch {
    Write-Log "Exception running account cleanup script."
    Write-Log $_
}

Write-Log "Finished $JobNameNoSpaces script." >> $LogFile
set-location $OldLocation
exit