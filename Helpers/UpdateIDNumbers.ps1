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
        #write-host "Old:" $Row."Legacy ID" "New:" $Row."Pupil #"
        $LegacyID = $Row."Legacy ID"
        $NewID = $Row."Pupil #"
        $User = Get-ADUser -Filter "(employeeid -eq $LegacyID) -and (employeetype -eq 'Student')" -Properties cn,postOfficeBox,givenName,sn
        
        if ($null -ne $User) {
         write-host $User
         $NewCN = $User.givenName + " " + $User.sn + " (" + $NewID + ")"
         $User | Set-AdUser -POBox $LegacyID -EmployeeID $NewID        
         $User | Rename-ADObject -NewName $NewCN         
        }
    }
 }
 