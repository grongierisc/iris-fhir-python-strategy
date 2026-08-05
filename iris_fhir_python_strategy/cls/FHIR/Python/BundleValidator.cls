Class FHIR.Python.BundleValidator Extends (HS.FHIRServer.Util.BundleValidator, FHIR.Python.Helper)
{

ClassMethod ValidateBundle(
	pResourceObject As %DynamicObject,
	pFHIRVersion As %String)
{
	// Call decorator handlers for additional bundle validation
	do ..GetCustomizationSettings(.customPath, .customModule)
	
	do ..SetPythonPath(customPath)
	
	if ..TryImportModule(customModule, .module) {
	} else {
		zw "Failed to import Python module: "_customModule
		return ##super(pResourceObject, pFHIRVersion)
	}
	
	set decoratorsModule = ##class(%SYS.Python).Import("iris_fhir_python_strategy")
	set registry = decoratorsModule.fhir
	
	set jsonLib = ##class(%SYS.Python).Import("json")
	try {
		// Avoid using set resourcePyObj = jsonLib.loads(pResourceObject.%ToJSON()) because %ToJSON() produces a large string
		// and passes it directly as an argument in the same expression — both sit on the string stack simultaneously.
		// The string itself may be under the 3.6MB <MAXSTRING> limit, but the combined stack usage during the call overflows.
		set jsonStr = pResourceObject.%ToJSON()
		set resourcePyObj = jsonLib.loads(jsonStr)
		do ##class(%SYS.System).WriteToConsoleLog("BundleValidator: JSON serialized via %ToJSON string (< MAXSTRING)", 0, "FHIR.Python")
	} catch ex {
		do ##class(%SYS.System).WriteToConsoleLog("BundleValidator: catch ex="_ex.DisplayString(), 0, "FHIR.Python")
		if (ex.Name '= "<MAXSTRING>") && (ex.Name '= "<STRINGSTACK>") throw ex
		do ##class(%SYS.System).WriteToConsoleLog("BundleValidator: JSON too large for string, falling back to stream (> MAXSTRING)", 0, "FHIR.Python")
		try {
			set io = ##class(%SYS.Python).Import("io")
			set jsonStream = ##class(%Stream.TmpCharacter).%New()
			do pResourceObject.%ToJSON(jsonStream)
			do jsonStream.Rewind()
			set pyStream = io.StringIO()
			while 'jsonStream.AtEnd { do pyStream.write(jsonStream.Read(32000)) }
			do pyStream.seek(0)
			set resourcePyObj = jsonLib.load(pyStream)
		} catch exStream {
			do ##class(%SYS.System).WriteToConsoleLog("BundleValidator: stream fallback failed - "_exStream.DisplayString(), 2, "FHIR.Python")
			throw exStream
		}
	}

	set handlers = registry."get_on_validate_bundle_handlers"()
	if handlers."__len__"() = 0 {
		do ##super(pResourceObject, pFHIRVersion)
		quit
	}
	do ..RunValidationHandlers(handlers, resourcePyObj, pFHIRVersion)
}

}
