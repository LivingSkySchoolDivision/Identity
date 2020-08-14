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
$FacilityFilePath = "../db/facilities.csv"
$LogFilePath = "../Logs/"
$JobNameNoSpaces = "QuickSync"

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
Write-Log "Starting full sync script..." >> $LogFile
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

# Make sure facilities file exists
if ((Test-Path $FacilityFilePath) -eq $false) {
    Write-Log "Facilities file not found. exiting." >> $LogFile
    Write-Log "Finished full sync script with errors." >> $LogFile
    set-location $OldLocation
    exit
}

# If student file exists, delete it
if ((Test-Path $InFilePath) -eq $true) {
    Write-Log "Student file found ($InFilePath) - deleting." >> $LogFile
    remove-item $InFilePath
}

## #########################################################
## # Export from SIS
## #########################################################

Write-Log "Calling SIS export script..." >> $LogFile
try {
    powershell -NoProfile -File ../sis-export/export-students-schoollogic.ps1 -ConfigFile $ConfigFilePath -OutFile $InFilePath >> $LogFile
} 
catch {
    Write-Log "Exception running move/update script."
    Write-Log $_
}

## #########################################################
## # Make sure we have an "in" file to actually process
## # before continuing...
## #########################################################

if ((Test-Path $InFilePath) -eq $false) {
    Write-Log "Student file found ($InFilePath) - cannot proceed." >> $LogFile
    Write-Log "Finished full sync script with errors." >> $LogFile
    set-location $OldLocation
    exit
}

## #########################################################
## # Provision new accounts
## #########################################################

Write-Log "Calling Provision script..." >> $LogFile
try {
    powershell -NoProfile -File ../Tasks-Students/Ident-Provision.ps1 -ConfigFile $ConfigFilePath -SISExportFile $InFilePath -FacilityFile $FacilityFilePath >> $LogFile
} 
catch {
    Write-Log "Exception running move/update script."
    Write-Log $_
}

## #########################################################
## # Deprovision accounts no longer needed
## #########################################################

Write-Log "Calling Deprovision script..." >> $LogFile
try {
    powershell -NoProfile -File ../Tasks-Students/Ident-DeProvision.ps1 -ConfigFile $ConfigFilePath -SISExportFile $InFilePath -FacilityFile $FacilityFilePath >> $LogFile
} 
catch {
    Write-Log "Exception running move/update script."
    Write-Log $_
}

## #########################################################
## # Move accounts (and reprovision)
## #########################################################

Write-Log "Calling Move script..." >> $LogFile
try {
    powershell -NoProfile -File ../Tasks-Students/Ident-Move.ps1 -ConfigFile $ConfigFilePath -SISExportFile $InFilePath -FacilityFile $FacilityFilePath >> $LogFile
} 
catch {
    Write-Log "Exception running move script."
    Write-Log $_
}


## #########################################################
## # Clean up
## #########################################################

Write-Log "Cleaning up..." >> $LogFile

# Delete the student file
if ((Test-Path $InFilePath) -eq $true) {
    Write-Log "Deleting $InFilePath"
    remove-item $InFilePath
}
Write-Log "Finished full sync script." >> $LogFile
set-location $OldLocation
exit