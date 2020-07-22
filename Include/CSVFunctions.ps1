
function Get-SourceUsers {
    param(
        [Parameter(Mandatory=$true)][String] $CSVFile
    )

    return import-csv $CSVFile -header('StudentID','LegalFirstName','LegalLastName','FirstName','LastName','MiddleName','BaseSchoolID','SchoolID','MinistryID','Email','DateOfBirth','UserName','Grade','HomeRoom')    
}

function Get-Facilities {
    param(
        [Parameter(Mandatory=$true)][String] $CSVFile
    )

    return import-csv $CSVFile -header('SchoolName','SchoolDAN','SchoolId','DefaultAccountEnabled','ADOU')    
}