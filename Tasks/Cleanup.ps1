param (
    [Parameter(Mandatory=$true)][string]$ConfigFile,
    [Parameter(Mandatory=$true)][string]$LogFilePath
)

$JobNameNoSpaces = "IdentityCleanup"

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
$NormalizedLogFilePath = $(Resolve-Path $LogFilePath)
Set-Location $PSScriptRoot
$NormalizedScriptRoot = Resolve-Path "../Tasks-Students"
Set-Location $OldLocation

Write-Log "Working Directory is: $OldLocation"
Write-Log "Using config file: $NormalizedConfigFile"
Write-Log "Using log file path: $NormalizedLogFilePath"
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

## #########################################################
## # Run cleanup script...
## #########################################################

Write-Log "Calling cleanup script..." >> $LogFile
try {
    $ScriptPath = Join-Path -Path $NormalizedScriptRoot -ChildPath "Ident-Cleanup.ps1"
    powershell -NoProfile -File $ScriptPath -ConfigFile $NormalizedConfigFile >> $LogFile
} 
catch {
    Write-Log "Exception running move/update script."
    Write-Log $_
}

## #########################################################
## # Finished
## #########################################################

Write-Log "Finished $JobNameNoSpaces script." >> $LogFile
set-location $OldLocation
exit