param (
    [Parameter(Mandatory=$true)][string]$SISExportFile,
    [string]$ConfigFile
 )
<#
    .SYNOPSIS
        Moves users and makes sure users are assigned to appropriate groups based on their schools.
    
    .DESCRIPTION
        Moves users and makes sure users are assigned to appropriate groups based on their schools.
    
    .PARAMETER SISExportFile
        A CSV export from the source SIS system.
    
    .PARAMETER ConfigFile
        Configuration file. Defaults to ""../config.xml".
#>

