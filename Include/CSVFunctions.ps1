
function Get-SourceUsers {
    param(
        [Parameter(Mandatory=$true)][String] $CSVFile
    )

    return import-csv $CSVFile -header("StudentID","LegalFirstName","LegalLastName","LegalMiddleName","PreferredFirstName","PreferredLastName","PreferredMiddleName","PrimaryEmail","AlternateEmail","BaseSchoolName","BaseSchoolDAN","EnrollmentStatus","GradeLevel","YOG","O365Authorisation","AcceptableUsePolicy","LegacyStudentID","GoogleDocsEmail") | Select -skip 1
}

function Get-Facilities {
    param(
        [Parameter(Mandatory=$true)][String] $CSVFile
    )

    return import-csv $CSVFile -header("Name","MSSFacilityName","FacilityDAN","FacilityId","DefaultAccountEnabled","ADOU","Groups") | Select -skip 1
}

function Get-CSVData {
    param(
        [Parameter(Mandatory=$true)][String] $CSVFile
    )

    return import-csv $CSVFile
}