param (
    [Parameter(Mandatory=$true)][string]$ConfigFile,
    [Parameter(Mandatory=$true)][string]$OutputFilename
 )

## ##################################################
## # Configuration can be done in config.xml.       #
## # No user configurable stuff beyond this point   #
## ##################################################

import-module ActiveDirectory

function Write-Log
{
    param(
        [Parameter(Mandatory=$true)] $Message
    )

    Write-Output "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss K")> $Message"
}

Write-Log "Start student email export (by learning id) script..."
try {
    ## Load config file
    if ((test-path -Path $ConfigFile) -eq $false) {
        Throw "Config file not found. Specify using -ConfigFile. Defaults to config.xml in the directory above where this script is run from."
    }
    $configXML = [xml](Get-Content $ConfigFile)
    $ActiveEmployeeType = $configXml.Settings.Students.ActiveEmployeeType
    $DeprovisionedEmployeeType = $configXml.Settings.Students.DeprovisionedEmployeeType
    $NotificationWebHookURL = $configXML.Settings.Notifications.WebHookURL

    # Detect the output file, and if it exists, delete it
    if ((Test-Path $OutputFilename) -eq $true) {
        Remove-Item $OutputFilename
    }

    Write-Log "Exporting student data..."

    $ExportFileRows = @()

    $AllUsers = Get-ADUser -filter {(employeeType -eq $ActiveEmployeeType) -or (employeeType -eq $DeprovisionedEmployeeType)} -ResultPageSize 2147483647 -properties mail,employeeNumber | where { $_.employeeNumber.length -gt 1}
    foreach($User in $AllUsers)
    {
       "$($User.employeeNumber),$($User.mail)" | Out-File $OutputFilename -Append
    }

    
}
catch {
    Write-Log "ERROR: $_"
}
Write-Log "Finished exporting data."
