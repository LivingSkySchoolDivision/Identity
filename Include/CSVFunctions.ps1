
function Get-SourceUsers {
    param(
        [Parameter(Mandatory=$true)][String] $CSVFile
    )

    return import-csv $CSVFile -header('UserId','FirstName','LastName','MiddleName','BaseFacilityId','AdditionalFacilityId','Email','DateOfBirth','UserName','Grade','HomeRoom') | Select -skip 1
}

function Get-Facilities {
    param(
        [Parameter(Mandatory=$true)][String] $CSVFile
    )

    return import-csv $CSVFile -header('Name','FacilityDAN','FacilityId','DefaultAccountEnabled','ADOU','Groups') | Select -skip 1
}

function Get-CSVData {
    param(
        [Parameter(Mandatory=$true)][String] $CSVFile
    )

    return import-csv $CSVFile
}