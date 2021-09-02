param (
    [Parameter(Mandatory=$true)][string]$FacilityFile,
    [Parameter(Mandatory=$true)][string]$ConfigFile,
    [Parameter(Mandatory=$true)][string]$LogDirectory,
    [Parameter(Mandatory=$true)][string]$InputFile
)

$JobNameNoSpaces = "IdentityFullSync"

## #########################################################
## # Set script location so the relative paths all work
## #########################################################

$OldLocation = get-location
set-location $PSScriptRoot

## #########################################################
## # Functions
## #########################################################

function Write-Log
{
    param(
        [Parameter(Mandatory=$true)] $Message
    )

    Write-Output "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss K")> $Message"
}

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

$LogFile = Join-Path $LogDirectory ((Get-FullTimeStamp) + "-$JobNameNoSpaces.log")
if ((Test-Path $LogDirectory) -eq $false) {
    Write-Log "Creating log file directory at $LogDirectory"
    New-Item -Path $LogDirectory -ItemType Directory
}

Write-Host "Logging to $LogFile"
Write-Log "Starting $JobNameNoSpaces script..." >> $LogFile
## #########################################################
## # Checks to make sure necesary files exist
## #########################################################

# Make sure config file exists
if ((Test-Path $ConfigFile) -eq $false) {
    Write-Log "Config file not found. exiting." >> $LogFile
    Write-Log "Finished full sync script with errors." >> $LogFile
    set-location $OldLocation
    exit
}

# Make sure facilities file exists
if ((Test-Path $FacilityFile) -eq $false) {
    Write-Log "Facilities file not found. exiting." >> $LogFile
    Write-Log "Finished full sync script with errors." >> $LogFile
    set-location $OldLocation
    exit
}

# If student file exists, delete it
if ((Test-Path $InputFile) -eq $true) {
    Write-Log "Student file found ($InputFile) - deleting." >> $LogFile
    remove-item $InputFile
}

## #########################################################
## # Export from SIS
## #########################################################

Write-Log "Calling SIS export script..." >> $LogFile
try {
    powershell -NoProfile -File ../sis-SchoolLogic/export-students-schoollogic.ps1 -ConfigFile $ConfigFile -OutFile $InputFile >> $LogFile
} 
catch {
    Write-Log "Exception running move/update script."
    Write-Log $_
}

## #########################################################
## # Make sure we have an "in" file to actually process
## # before continuing...
## #########################################################

if ((Test-Path $InputFile) -eq $false) {
    Write-Log "Student file found ($InputFile) - cannot proceed." >> $LogFile
    Write-Log "Finished full sync script with errors." >> $LogFile
    set-location $OldLocation
    exit
}

## #########################################################
## # Provision new accounts
## #########################################################

Write-Log "Calling Provision script..." >> $LogFile
try {
    powershell -NoProfile -File ../Tasks-Students/Ident-Provision.ps1 -ConfigFile $ConfigFile -SISExportFile $InputFile -FacilityFile $FacilityFile >> $LogFile
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
    powershell -NoProfile -File ../Tasks-Students/Ident-DeProvision.ps1 -ConfigFile $ConfigFile -SISExportFile $InputFile -FacilityFile $FacilityFile >> $LogFile
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
    powershell -NoProfile -File ../Tasks-Students/Ident-Move.ps1 -ConfigFile $ConfigFile -SISExportFile $InputFile -FacilityFile $FacilityFile >> $LogFile
} 
catch {
    Write-Log "Exception running move script."
    Write-Log $_
}

## #########################################################
## # Update account groups and properties
## #########################################################

Write-Log "Calling Update script..." >> $LogFile
try {
    powershell -NoProfile -File ../Tasks-Students/Ident-Update.ps1 -ConfigFile $ConfigFile -SISExportFile $InputFile -FacilityFile $FacilityFile >> $LogFile
} 
catch {
    Write-Log "Exception running update script."
    Write-Log $_
}


## #########################################################
## # Reimport changes into SIS
## #########################################################

Write-Log "Calling SIS change import script..." >> $LogFile
try {
    powershell -NoProfile -File ../sis-SchoolLogic/import-studentdata-schoollogic.ps1 -ConfigFile $ConfigFile -SISExportFile $InputFile >> $LogFile
} 
catch {
    Write-Log "Exception running SIS change import script."
    Write-Log $_
}


## #########################################################
## # Finished
## #########################################################

Write-Log "Finished $JobNameNoSpaces script." >> $LogFile
set-location $OldLocation
exit