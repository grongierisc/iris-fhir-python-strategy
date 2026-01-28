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
	set len = handlers."__len__"()
	try {
	    for i=0:1:len-1 {
	        set handler = handlers."__getitem__"(i)
	        do handler."__call__"(pResourceObject, pFHIRVersion)
	    }
	} catch ex {
		if ex.%IsA("%Exception.PythonException") { do ##class(FHIR.Python.Helper).HandlePythonException(ex) }
		throw ex
	}
}

}
