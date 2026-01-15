Include HS.FHIRServer

Class FHIR.Python.Validation Extends FHIR.Python.Helper [ Abstract ]
{

Parameter SkipIfNoProfileKEY = 1;

Parameter TerminologyServerKEY = "https://tx.fhir.org/r4";

Parameter PatientProfileKEY = "http://hl7.org/fhir/StructureDefinition/Patient";

Parameter IGPackagesKEY = "hl7.fhir.fr.core@2.1.0";

Parameter UnknownCodeSystemModeKEY = "WARNING";

ClassMethod GetIGPackages() As %List
{
	// Get IG packages from environment or parameter
	Set igPackages = $system.Util.GetEnviron("IG_PACKAGES")
	If igPackages = "" {
		Set igPackages = ..#IGPackagesKEY
	}
	
	// Convert comma-separated string to list
	Set packageList = $ListFromString(igPackages, ",")
	Quit packageList
}

ClassMethod Validate(theResource As %DynamicObject)
{
	#dim skipIfNoProfile As %String = ..#SkipIfNoProfileKEY
	#dim errorStatus As %Status = $$$OK

	#dim noProfile As %Boolean = ('theResource.%IsDefined("meta") || 'theResource.meta.%IsDefined("profile") || (theResource.meta.profile.%Size() = 0))
	
	// skipIfNoProfile: only validate if profile is specified
	if +skipIfNoProfile && noProfile
	{
		quit
	}

	#dim terminologyServer As %String = $system.Util.GetEnviron("TERMINOLOGY_SERVER")
	If terminologyServer = "" {
		Set terminologyServer = ..#TerminologyServerKEY
	}
	
	#dim unknownCodeSystemMode As %String = $system.Util.GetEnviron("UNKNOWN_CODE_SYSTEM_MODE")
	If unknownCodeSystemMode = "" {
		Set unknownCodeSystemMode = ..#UnknownCodeSystemModeKEY
	}
	
	#dim patientProfile As %String = ..#PatientProfileKEY
	#dim profileToValidateAgainst As %String = ""
	
	// Build profile list to validate against
	Set profileList = ""
	if noProfile 
			&& (theResource.resourceType = "Patient") 
			&& (patientProfile '= "")
	{
		set profileToValidateAgainst = patientProfile
	}
	else
	{
		// Get all profiles from meta.profile
		If theResource.%IsDefined("meta") && theResource.meta.%IsDefined("profile") {
			Set iter = theResource.meta.profile.%GetIterator()
			While iter.%GetNext(.key, .profile) {
				If profileToValidateAgainst '= "" {
					Set profileToValidateAgainst = profileToValidateAgainst _ "," _ profile
				}
				Else {
					Set profileToValidateAgainst = profile
				}
			}
		}
	}
	
	// Initialize Python validator
	Set pythonPath = "/irisdev/app/src/FHIRSERVER/python/"
	Do ..SetPythonPath(pythonPath)

	set msg = ""
	set sc = $$BeginCapture^%SYS.Capture(.msg)

	// Get Python validator module
	Set validatorModule = ##class(%SYS.Python).Import("FhirInteraction._fhir_validator")
	
	// Get IG packages as Python list
	Set igPackages = ..GetIGPackages()
	Set pyPackages = ##class(%SYS.Python).Builtins().list()
	Set ptr = 0
	While $ListNext(igPackages, ptr, package) {
		If package '= "" {
			Do pyPackages.append(package)
		}
	}
	
	// Convert resource to JSON string
	Set jsonLib = ##class(%SYS.Python).Import("json")
	Set resourceJson = theResource.%ToJSON()
	
	// Call Python validator
	#dim operationOutcome As %DynamicObject = ""
	try
	{
		$$$FSLog("Calling Python FHIR validator...")
		// Validate using Python validator
		Set pyResult = validatorModule."validate_resource"(
			resourceJson,
			profileToValidateAgainst,
			pyPackages,
			terminologyServer,
			unknownCodeSystemMode
		)
		// Convert Python result to IRIS object
		Set operationOutcome = {}.%FromJSON(jsonLib.dumps(pyResult))
	}
	catch ex
	{
		set sc = ex.AsStatus()
		$$$FHIRAddError(errorStatus, sc)
	}
	set sc = $$EndCapture^%SYS.Capture(msg,.msgArray)

	$$$ThrowOnError(errorStatus)

	If '$IsObject(operationOutcome) {
		Quit
	}

	// assemble error status in case of any severity=error issues
	#dim iter As %Iterator.Object = operationOutcome.issue.%GetIterator()
	#dim issue As %DynamicObject
	while iter.%GetNext(.key, .issue) 
	{
		if (issue.severity = "error")
		{
			#dim expressionPath As %String = ""
			If issue.%IsDefined("expression") && (issue.expression.%Size() > 0) {
				Set expressionPath = issue.expression.%Get(0)
			}
			#dim oneError As %Status = $$$ERROR($$$GeneralError, issue.details.text, $$$OutcomeWithPath(400, "error", issue.code, expressionPath))
			$$$FHIRAddError(errorStatus, oneError)
		}
	}

	$$$ThrowOnError(errorStatus)
}

}
