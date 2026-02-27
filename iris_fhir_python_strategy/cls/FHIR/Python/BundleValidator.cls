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
	
	// convert pResourceObject to Python object
	set jsonLib = ##class(%SYS.Python).Import("json")
	set resourceJson = pResourceObject.%ToJSON()
	set resourcePyObj = jsonLib.loads(resourceJson)

	set handlers = registry."get_on_validate_bundle_handlers"()
	if handlers."__len__"() = 0 {
		do ##super(pResourceObject, pFHIRVersion)
		quit
	}
	do ..RunValidationHandlers(handlers, resourcePyObj, pFHIRVersion)
}

}
