Class FHIR.Python.BundleValidator Extends HS.FHIRServer.Util.BundleValidator
{

ClassMethod ValidateBundle(
	pResourceObject As %DynamicObject,
	pFHIRVersion As %String)
{
	
	// Call decorator handlers for additional bundle validation
	do ##class(FHIR.Python.Helper).GetCustomizationSettings(.customPath, .customModule)
	
	do ##class(FHIR.Python.Helper).SetPythonPath(customPath)
	
	do ##class(FHIR.Python.Helper).TryImportModule(customModule, .module)
	
	set decoratorsModule = ##class(%SYS.Python).Import("fhir_decorators")
	set registry = decoratorsModule.fhir
	
	set handlers = registry."get_validate_bundle_handlers"()
	if handlers."__len__"() = 0 {
		do ##super(pResourceObject, pFHIRVersion)
		quit
	}
	set iterator = handlers."__iter__"()
	set handler = ""
	Try {
		for {
			set handler = iterator."__next__"()
			quit:handler=""
			do handler."__call__"(pResourceObject, pFHIRVersion)
		}
	}
	Catch ex {
		if (ex.Data '[ "StopIteration") { // StopIteration
			if ex.%IsA("%Exception.PythonException") { do ##class(FHIR.Python.Helper).HandlePythonException(ex) }
			throw ex
		}
	}
}

}
