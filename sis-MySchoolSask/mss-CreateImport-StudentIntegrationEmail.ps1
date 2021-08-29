param (
    [string]$ConfigFile
 )

 $OutputFileName = "test.csv"
 $Delimeter = ","

## ##################################################
## # Configuration can be done in config.xml.       #
## # No user configurable stuff beyond this point   #
## ##################################################

## Bring in functions from external files

. ./../Include/UtilityFunctions.ps1
. ./../Include/ADFunctions.ps1
. ./../Include/CSVFunctions.ps1

Write-Log "Generating MSS import file from AD..."
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
    $ActiveEmployeeType = $configXML.Settings.Students.ActiveEmployeeType
    $DeprovisionedEmployeeType = $configXml.Settings.Students.DeprovisionedEmployeeType
    $NotificationWebHookURL = $configXML.Settings.Notifications.WebHookURL


    $RawUsers = Get-ADUser -filter { ((employeeType -eq $ActiveEmployeeType) -or (employeeType -eq $DeprovisionedEmployeeType)) } -Properties employeeNumber,employeeID,mail

    Write-Log "> Processing..."

    $CSVUsers = @()
    foreach($User in $RawUsers) {
        if ($User.employeeID.Length -gt 1)
        {
            $CSVUsers += [PSCustomObject]@{
                "Pupil ID" = $User.employeeID
                "Integration Email" = $User.mail
            }

        }
    }

    write-host $CSVUsers.count

    if (($PSVersionTable.PSVersion.Major -ge 7) -and ($QuoteAllColumns -eq $false)) {
        $CSVUsers | Sort-Object | export-csv $OutputFileName -notypeinformation -Delimiter $Delimeter -UseQuotes AsNeeded
    } else {        
        $CSVUsers | Sort-Object | export-csv $OutputFileName -notypeinformation -Delimiter $Delimeter
    }
    
 
    ## Send teams webhook notification

    ## Send email notification
}
catch {
    Write-Log "ERROR: $_"
}
Write-Log "Finished generating MSS import file."
