param (
    [string]$ConfigFile
 )
<#
    .SYNOPSIS
        Disables and deletes stale deprovisioned accounts

    .DESCRIPTION
        Disables and deletes stale deprovisioned accounts
        
    .PARAMETER ConfigFile
        Configuration file. Defaults to ""../config.xml".
#>

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

Write-Log "Start cleanup script..."
Write-Log " Config file path: $ConfigFile"

try {
    ## Load config file
    if ((test-path -Path $ConfigFile) -eq $false) {
        Throw "Config file not found. Specify using -ConfigFile. Defaults to config.xml in the directory above where this script is run from."
    }
    $configXML = [xml](Get-Content $ConfigFile)

    $DeprovisionedEmployeeType = $configXml.Settings.Students.DeprovisionedEmployeeType
    $NotificationWebHookURL = $configXML.Settings.Notifications.WebHookURL
    $DisableCutoffDays = [int]$configXml.Settings.Students.DaysDeprovisionedUntilDisable
    $PurgeCutoffDays = [int]$configXml.Settings.Students.DaysDisabledBeforePurge

    # Find any currently disabled accounts that have been untouched for the given amount of days
    # and DELETE the accounts
    Write-Log "Stale disabled former student accounts:"
    $PurgeCutoffDay = (get-date).adddays([int]$PurgeCutoffDays * -1)
    Write-Log "Purge Cutoff day: $PurgeCutoffDay"

    foreach($User in Get-ADUser -filter {Enabled -eq $false -AND employeeType -eq $DeprovisionedEmployeeType -AND whenChanged -lt $PurgeCutoffDay} -Properties whenChanged)
    {
        Write-Log "PURGE: $($User.DistinguishedName)"
        Remove-ADUser -Identity $User
    }

    # Find any currently enabled accounts that have been untouched for the given amount of days
    # and DISABLE them
    Write-Log "Finding stale deprovisioned accounts..."
    $DisableCutOffDate = (get-date).adddays([int]$DisableCutoffDays * -1)
    Write-Log "Disable cutoff day: $DisableCutOffDate"
    foreach($User in Get-ADUser -filter {Enabled -eq $True -and employeeType -eq $DeprovisionedEmployeeType -AND whenChanged -lt $DisableCutOffDate } -Property whenChanged)
    {
        Write-Log "DISABLE: $($User.DistinguishedName)"
        Disable-ADAccount -Identity $User.DistinguishedName
    }
 
    ## Send teams webhook notification

    ## Send email notification
}
catch {
    Write-Log "ERROR: $_"
}
Write-Log "Finished cleaning up."
