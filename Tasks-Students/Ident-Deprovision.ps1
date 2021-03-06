param (
    [Parameter(Mandatory=$true)][string]$SISExportFile,
    [Parameter(Mandatory=$true)][string]$FacilityFile,
    [string]$ConfigFile
 )
<#
    .SYNOPSIS
        Compares a list of users with users in an AD system, and deprovision.
    
    .DESCRIPTION
        This script removes users from AD/Azure who no longer exist in the Student Information System.
    
    .PARAMETER SISExportFile
        A CSV export from the source SIS system.
    
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

function Deprovision-User 
{
    param(
        [Parameter(Mandatory=$true)] $Identity,
        [Parameter(Mandatory=$true)][String] $EmployeeType,
        [Parameter(Mandatory=$true)][String] $DeprovisionOU
    )

    Write-Log "Deprovisioning: $EmployeeId ($($ADUser))"

    try {
        $DepTime = Get-Date  
        set-aduser $Identity -Description "Deprovisioned: $DepTime" -Enabled $true -Office "$DeprovisionedEmployeeType" -Replace @{'employeeType'="$DeprovisionedEmployeeType";'title'="$DeprovisionedEmployeeType"}

        # Remove all group memberships
        foreach($Group in Get-ADPrincipalGroupMembership -Identity $Identity)
        {
            # Don't remove from "domain users", because it won't let you do this anyway (its the user's "default group").
            if ($Group.Name -ne "Domain Users")
            {
                Remove-ADGroupMember -Identity $Group -Members $Identity -Confirm:$false
            }
        }

        # Move user to deprovision OU
        move-ADObject -identity $Identity -TargetPath $DeprovisionOU 
    }
    catch {
        Write-Log "Failed to deprovision $Identity (exception follows)"
        Write-Log $_
    }
}


Write-Log "Start deprovision script..."
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
    $ActiveEmployeeType = $configXml.Settings.Students.ActiveEmployeeType
    $DeprovisionedEmployeeType = $configXml.Settings.Students.DeprovisionedEmployeeType
    $DeprovisionedADOU = $configXml.Settings.Students.DeprovisionedADOU
    $NotificationWebHookURL = $configXML.Settings.Notifications.WebHookURL

    ## Load the list of schools from the ../db folder

    $Facilities = @(Get-Facilities -CSVFile $FacilityFile)
    if ($Facilities.Count -lt 1)
    {
        Write-Log "No facilities found. Exiting."
        exit
    } else {
        Write-Log "$($Facilities.Count) facilities found in import file."
    }

    ## Load the student records from the file.
    ## If the file doesn't exist or is empty, don't continue any further.

    $SourceUsers = @(Remove-DuplicateRecords -UserList (
        Remove-UsersFromUnknownFacilities -UserList (
            Get-SourceUsers -CSVFile $SISExportFile
            ) -FacilityList $Facilities
        ))

    if ($SourceUsers.Count -lt 1)
    {
        Write-Log "No students from source system. Exiting"
        exit
    } else {
        Write-Log "$($SourceUsers.Count) students found in import file."
    }

    ## Make a List<string> of UserIDs from the source CSV so we can loop through it to find stuff more efficiently.

    $sourceUserIds = New-Object Collections.Generic.List[String]
    foreach($SourceUser in $SourceUsers)
    {
        if ($sourceUserIds.Contains($SourceUser.UserId) -eq $false)
        {
            $sourceUserIds.Add($SourceUser.UserId)
        }
    }

    ## Get a list of all users currently in AD
    ## Only users with employeeID set AND employeeType set to the specified one from the config file.

    $ExistingActiveEmployeeIds = Get-SyncableEmployeeIDs -EmployeeType $ActiveEmployeeType

    ## ############################################################
    ## Find users to delete
    ## ############################################################

    $EmployeeIDsToDeprovision = @()
    foreach($ExistingEmployeeId in $ExistingActiveEmployeeIds)
    {
        if ($ExistingEmployeeId.Length -gt 0)
        {
            if ($sourceUserIds.Contains($ExistingEmployeeId) -eq $false)
            {
                $EmployeeIDsToDeprovision += $ExistingEmployeeId
            }
        }
    }

    Write-Log "Found $($EmployeeIDsToDeprovision.Count) users to deprovision"

    ## ############################################################
    ## Deprovision users
    ## ############################################################

    foreach($EmployeeId in $EmployeeIDsToDeprovision) {
        # Find the user's DN based on their employeeID   
        foreach($ADUser in Get-AdUser -Filter {(EmployeeId -eq $EmployeeId) -and (EmployeeType -eq $ActiveEmployeeType)})
        {
            Deprovision-User $ADUser -EmployeeType $DeprovisionedEmployeeType -DeprovisionOU $DeprovisionedADOU              
        }
    }
 
    ## Send teams webhook notification

    ## Send email notification
}
catch {
    Write-Log "ERROR: $_"
}
Write-Log "Finished deprovisioning."
