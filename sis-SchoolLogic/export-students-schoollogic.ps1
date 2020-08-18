param (
    [Parameter(Mandatory=$true)][string]$OutFile,
    [string]$ConfigFile
 )

##############################################
# Script configuration                       #
##############################################

# SQL Query to run
# The output CSV file will use column names from your SQL query.
# Rename them using "as" - example: "SELECT cFirstName as FirstName FROM Students"
$SqlQuery = "SELECT
                Student.cStudentNumber AS UserId,
                Student.cFirstName AS FirstName,
                Student.cLaStName AS LastName,
                cMiddlename AS MiddleName,
                Student.iSchoolID AS BaseFacilityId,
                SS.iSchoolID AS AdditionalFacilityId,
                Student.mEmail AS Email,
                FORMAT(Student.dBirthdate, 'yyyy-MM-dd') AS DateOfBirth,
                RTRIM(LTRIM(cUserName)) AS UserName,
                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(RTRIM(LTRIM(g.cName)),'0K','K'),'01','1'),'02','2'),'03','3'),'04','4'),'05','5'),'06','6'),'07','7'),'08','8'),'09','9') AS Grade,
                Homeroom.cName as HomeRoom
            FROM Student
                LEFT OUTER JOIN Homeroom ON Student.iHomeroomID = Homeroom.iHomeroomID
                LEFT OUTER JOIN Grades g ON Student.iGradesID = g.iGradesID
                LEFT OUTER JOIN StudentStatus SS ON Student.iStudentID = SS.iStudentID
            WHERE
                (SS.dInDate <=  { fn CURDATE() }) AND
                ((SS.dOutDate < '1901-01-01') OR (SS.dOutDate >=  { fn CURDATE() }))
            ORDER BY
                Student.iSchoolID;"

# CSV Delimeter
# Some systems expect this to be a tab "`t" or a pipe "|".
$Delimeter = ','

# Should all columns be quoted, or just those that contains characters to escape?
# Note: This has no effect on systems with PowerShell versions <7.0 (all fields will be quoted otherwise)
$QuoteAllColumns = $false

##############################################
# No configurable settings beyond this point #
##############################################

. ./../Include/UtilityFunctions.ps1
Write-Log "Starting SIS exportscript..."
try {
    # Find the config file
    $AdjustedConfigFilePath = $ConfigFile
    if ($AdjustedConfigFilePath.Length -le 0) {
        $AdjustedConfigFilePath = join-path -Path $(Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent) -ChildPath "config.xml"
    }

    # Retreive the connection string from config.xml
    if ((test-path -Path $AdjustedConfigFilePath) -eq $false) {
        Throw "Config file not found. Specify using -ConfigFilePath. Defaults to config.xml in the directory above where this script is run from."
    }
    $configXML = [xml](Get-Content $AdjustedConfigFilePath)
    $ConnectionString = $configXML.Settings.ConnectionStrings.SchoolLogic

    # Set up the SQL connection
    $SqlConnection = new-object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = $ConnectionString
    $SqlCommand = New-Object System.Data.SqlClient.SqlCommand
    $SqlCommand.CommandText = $SqlQuery
    $SqlCommand.Connection = $SqlConnection
    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
    $SqlAdapter.SelectCommand = $SqlCommand
    $SqlDataSet = New-Object System.Data.DataSet

    # Run the SQL query
    $SqlConnection.open()
    $SqlAdapter.Fill($SqlDataSet)
    $SqlConnection.close()

    # Output to a CSV file
    foreach($DSTable in $SqlDataSet.Tables) {
        if (($PSVersionTable.PSVersion.Major -ge 7) -and ($QuoteAllColumns -eq $false)) {
            $DSTable | export-csv $OutFile -notypeinformation -Delimiter $Delimeter -UseQuotes AsNeeded
        } else {
            $DSTable | export-csv $OutFile -notypeinformation -Delimiter $Delimeter
        }
    }
    
}
catch { 
    Write-Log $_
}
Write-Log "Finished SIS export script."