param (
    [Parameter(Mandatory=$true)][string]$ImportFile
 )

 . ./../Include/CSVFunctions.ps1
import-module ActiveDirectory 

 <# 
    Load rows from import CSV file


 #>

 $ImportFileRows = Get-CSVData -CSVFile $ImportFile

 foreach($Row in $ImportfileRows) {
    if ($Row."Legacy ID" -ne "") 
    {        
        write-host "Old:" $Row."Legacy ID" "New:" $Row."Pupil #"
        $ID = $Row."Legacy ID"
        $User = Get-ADUser -Filter "employeeid -eq $ID"
        write-host $User
    }
    
 }
 