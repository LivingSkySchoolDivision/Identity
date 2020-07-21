param (
    [Parameter(Mandatory=$true)][string]$SISExportFile,
    [string]$ConfigFile
 )
<#
    .SYNOPSIS
        Deprovisions user accounts that no longer exist in the system
    
    .DESCRIPTION
        This script removes users from AD/Azure who no longer exist in the Student Information System.
    
    .PARAMETER SISExportFile
        A CSV export from the source SIS system.
    
    .PARAMETER ConfigFile
        Configuration file. Defaults to ""../config.xml".
#>

