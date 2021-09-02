param (
    [Parameter(Mandatory=$true)][string]$FacilityFile,
    [Parameter(Mandatory=$true)][string]$ConfigFile,
    [Parameter(Mandatory=$true)][string]$LogFilePath,
    [Parameter(Mandatory=$true)][string]$InputFile
)

$JobNameNoSpaces = "IdentityFullSync"

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

## #########################################################
## # Normalize input paths
## #########################################################

$OldLocation = Get-Location
$NormalizedConfigFile = $(Resolve-Path $ConfigFile)
$NormalizedFacilityFile = $(Resolve-Path $FacilityFile)
$NormalizedLogFilePath = $(Resolve-Path $LogFilePath)
$NormalizedInputFile = $(Resolve-Path $InputFile)
Set-Location $PSScriptRoot
$NormalizedScriptRoot = Resolve-Path "../Tasks-Students"
Set-Location $OldLocation

Write-Log "Working Directory is: $OldLocation"
Write-Log "Using config file: $NormalizedConfigFile"
Write-Log "Using facility file: $NormalizedFacilityFile"
Write-Log "Using log file path: $NormalizedLogFilePath"
Write-Log "Using input file: $NormalizedInputFile"
Write-Log "Using script root: $NormalizedScriptRoot"

## #########################################################
## # Set up a filename for the logs
## #########################################################

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
if ((Test-Path $NormalizedConfigFile) -eq $false) {
    Write-Log "Config file not found. exiting." >> $LogFile
    Write-Log "Finished full sync script with errors." >> $LogFile
    set-location $OldLocation
    exit
}

# Make sure facilities file exists
if ((Test-Path $NormalizedFacilityFile) -eq $false) {
    Write-Log "Facilities file not found. exiting." >> $LogFile
    Write-Log "Finished full sync script with errors." >> $LogFile
    set-location $OldLocation
    exit
}

## #########################################################
## # Make sure we have an "in" file to actually process
## # before continuing...
## #########################################################

if ((Test-Path $NormalizedInputFile) -eq $false) {
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
    $ScriptPath = Join-Path -Path $NormalizedScriptRoot -ChildPath "Ident-Provision.ps1"
    powershell -NoProfile -File $ScriptPath -ConfigFile $NormalizedConfigFile -SISExportFile $NormalizedInputFile -FacilityFile $NormalizedFacilityFile >> $LogFile
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
    $ScriptPath = Join-Path -Path $NormalizedScriptRoot -ChildPath "Ident-DeProvision.ps1 "
    powershell -NoProfile -File $ScriptPath -ConfigFile $NormalizedConfigFile -SISExportFile $NormalizedInputFile -FacilityFile $NormalizedFacilityFile >> $LogFile
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
    $ScriptPath = Join-Path -Path $NormalizedScriptRoot -ChildPath "Ident-Move.ps1"
    powershell -NoProfile -File $ScriptPath -ConfigFile $NormalizedConfigFile -SISExportFile $NormalizedInputFile -FacilityFile $NormalizedFacilityFile >> $LogFile
} 
catch {
    Write-Log "Exception running move script."
    Write-Log $_
}

## #########################################################
## # Update script
## #########################################################

Write-Log "Calling Update script..." >> $LogFile
try {
    $ScriptPath = Join-Path -Path $NormalizedScriptRoot -ChildPath "Ident-Update.ps1"
    powershell -NoProfile -File $ScriptPath -ConfigFile $NormalizedConfigFile -SISExportFile $NormalizedInputFile -FacilityFile $NormalizedFacilityFile >> $LogFile
} 
catch {
    Write-Log "Exception running Update script."
    Write-Log $_
}

## #########################################################
## # Finished
## #########################################################

Write-Log "Finished $JobNameNoSpaces script." >> $LogFile
set-location $OldLocation
exit