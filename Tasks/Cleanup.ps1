param (
    [Parameter(Mandatory=$true)][string]$FacilityFile,
    [Parameter(Mandatory=$true)][string]$ConfigFile,
    [Parameter(Mandatory=$true)][string]$LogDirectory
)

$JobNameNoSpaces = "IdentityCleanup"


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
if ((Test-Path $ConfigFilePath) -eq $false) {
    Write-Log "Config file not found. exiting." >> $LogFile
    Write-Log "Finished full sync script with errors." >> $LogFile
    set-location $OldLocation
    exit
}

## #########################################################
## # Finished
## #########################################################

Write-Log "Finished $JobNameNoSpaces script." >> $LogFile
set-location $OldLocation
exit