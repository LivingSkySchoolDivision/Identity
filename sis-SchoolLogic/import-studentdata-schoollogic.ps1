param (
    [Parameter(Mandatory=$true)][string]$SISExportFile,
    [string]$ConfigFile
 )

##############################################
# No configurable settings beyond this point #
##############################################

. ./../Include/UtilityFunctions.ps1
. ./../Include/CSVFunctions.ps1
. ./../Include/ADFunctions.ps1

Write-Log "Starting SIS import script..."
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
    $ActiveEmployeeType = $configXml.Settings.Students.ActiveEmployeeType
    $DeprovisionedEmployeeType = $configXml.Settings.Students.DeprovisionedEmployeeType
    
    ## Load the student records from the file.
    ## If the file doesn't exist or is empty, don't continue any further.
    $SourceUsers = @(Get-SourceUsers -CSVFile $SISExportFile)

    if ($SourceUsers.Count -lt 1)
    {
        Write-Log "No students from source system. Exiting"
        exit
    } else {
        Write-Log "$($SourceUsers.Count) students found in import file."
    }

    # We need a list of just student numbers later
    $KnownSourceUserIds = @()
    foreach($SourceUser in $SourceUsers) 
    {
        $KnownSourceUserIds += [int]$SourceUser.UserId 
    }
   
    Write-Log "Getting all users from AD..."
    # Get a list of users from AD
    $AllStudents = Get-ADUser -Filter {(EmployeeType -eq $ActiveEmployeeType) -OR (EmployeeType -eq $DeprovisionedEmployeeType)} -ResultSetSize 2147483647 -Properties EmailAddress, employeeId, sAMAccountName

    # Now put those users in a hashtable
    Write-Log "Putting AD users in a hashtable for easier consumption..."
    $AllADUsersHT = @{}
    foreach($ADUser in $AllStudents) 
    {
        if ($ADUser.employeeId.length -gt 0) 
        {
            if($AllADUsersHT.ContainsKey($ADUser.employeeId) -eq $false) 
            {
                $AllADUsersHT.Add("$($ADUser.employeeId)", $ADUser)
            }
        }
    }

    # Loop through the CSV, finding matching users in the AD list
    # If the values for username or email address differ, put them in a list to be updated in the next step

    Write-Log "Comparing..."
    $UsersThatNeedUpdates = @()
    foreach($CSVUser in $SourceUsers) 
    {
        # Find this user in the AD list
        if ($AllADUsersHT.ContainsKey($CSVUser.UserId))
        {
            $ADUser = $AllADUsersHT[$CSVUser.UserId]

            if (($CSVUser.Email.ToLower() -ne $ADUser.EmailAddress.ToLower()) -OR ($CSVUser.UserName.ToLower() -ne $ADUser.sAMAccountName.ToLower()))
            {
                $UsersThatNeedUpdates += @{ UserID = $ADUser.employeeId; OldEmail=$CSVUser.Email; OldUserName=$CSVUser.UserName ; EmailAddress=$ADUser.EmailAddress; AccountName=$ADUser.sAMAccountName }
            }
        }
    }

    Write-Log "Updating SchoolLogic..."
    
    # Set up the SQL connection
    $SqlConnection = new-object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = $ConnectionString
    
    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
    $SqlAdapter.SelectCommand = $SqlCommand

    # Run the SQL query
    $SqlConnection.open()


    $KnownUserIDsSingle = $KnownSourceUserIds -Join ","

    # Wipe any email and usernames that ARENT in our CSV
    if ($KnownUserIDsSingle.length -gt 1)
    {
        $SqlCommand = New-Object System.Data.SqlClient.SqlCommand
        $SqlCommand.CommandText = "UPDATE Student SET cUserName='', mEmail='' WHERE  mEmail<>'' AND cUserName<>'' AND cStudentNumber NOT IN ($KnownUserIDsSingle);"
        $SqlCommand.Connection = $SqlConnection 
        $Sqlcommand.ExecuteNonQuery()   
    }
    
    foreach($User in $UsersThatNeedUpdates) 
    {
        if ($User.UserId.length -gt 1)
        {
            Write-Log "$($User.UserId): Email from ""$($User.OldEmail)"" to ""$($User.EmailAddress)"", Username from ""$($User.OldUserName)"" to ""$($User.AccountName)"""
        
            $SqlCommand = New-Object System.Data.SqlClient.SqlCommand
            $SqlCommand.CommandText = "UPDATE Student SET cUserName=@NEWUSERNAME, mEmail=@NEWEMAIL WHERE cStudentNumber=@STUDNUM;"
            $SqlCommand.Parameters.AddWithValue("@NEWUSERNAME",$User.AccountName) | Out-Null
            $SqlCommand.Parameters.AddWithValue("@NEWEMAIL",$User.EmailAddress) | Out-Null
            $SqlCommand.Parameters.AddWithValue("@STUDNUM",$User.UserId) | Out-Null
            $SqlCommand.Connection = $SqlConnection
            $Sqlcommand.ExecuteNonQuery()
        }
    }

    $SqlConnection.close()        
}
catch { 
    Write-Log $_
}
Write-Log "Finished SIS import script."