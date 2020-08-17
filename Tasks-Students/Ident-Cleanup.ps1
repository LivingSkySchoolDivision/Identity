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

## Bring in functions from external files

. ./../Include/UtilityFunctions.ps1
. ./../Include/ADFunctions.ps1
. ./../Include/CSVFunctions.ps1

Write-Log "Start cleanup script..."
try {
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
    $DeprovisionedEmployeeType = $configXml.Settings.Students.DeprovisionedEmployeeType
    $NotificationWebHookURL = $configXML.Settings.Notifications.WebHookURL
    $DisableCutoffDays = $configXml.Settings.Students.DaysDeprovisionedUntilDisable
    $PurgeCutoffDays = $configXml.Settings.Students.DaysDisabledBeforePurge

    Write-Log "Finding stale deprovisioned accounts..."
    foreach($User in Get-ADUser -filter {Enabled -eq $True -and employeeType -eq $DeprovisionedEmployeeType } -Property LastLogonTimestamp | Select-Object -Property Name,DistinguishedName,@{ n = "LastLogonDate"; e = { [datetime]::FromFileTime( $_.lastLogonTimestamp ) } })
    {
        # Parse the date
        [datetime]$today = Get-Date
        [datetime]$userLastLogonDate = New-Object DateTime
        if ([DateTime]::TryParse($User.LastLogonDate,
                                      [System.Globalization.CultureInfo]::InvariantCulture,
                                      [System.Globalization.DateTimeStyles]::None,
                                      [ref]$userLastLogonDate))
        {
            $UserDaysSinceLastLogin = New-TimeSpan -Start $userLastLogonDate -End $today
            if ($UserDaysSinceLastLogin.TotalDays -gt $DisableCutoffDays)
            {
                $DepTime = Get-Date  
                Write-Log "DISABLE: $($User.DistinguishedName) ($($UserDaysSinceLastLogin.TotalDays))"
                Disable-ADAccount -Identity $User.DistinguishedName
                Set-ADUser -Identity $User.DistinguishedName -Description "Disabled due to inactivity: $DepTime"
            }
        }
    }

    Write-Log "Stale disabled former student accounts:"
    $PurgeCutoffDay = (get-date).adddays($PurgeCutoffDays * -1)
    foreach($User in Get-ADUser -filter {Enabled -eq $false -AND employeeType -eq $DeprovisionedEmployeeType -AND whenChanged -lt $PurgeCutoffDay} -Properties whenChanged)
    {
        Write-Log "PURGE: $($User.DistinguishedName)"
        Remove-ADUser -Identity $User
    }
    
 
    ## Send teams webhook notification

    ## Send email notification
}
catch {
    Write-Log "ERROR: $_"
}
Write-Log "Finished cleaning up."
