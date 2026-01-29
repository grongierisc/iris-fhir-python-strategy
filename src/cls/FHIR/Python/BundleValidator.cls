Class FHIR.Python.BundleValidator Extends (HS.FHIRServer.Util.BundleValidator, FHIR.Python.Helper)
{

ClassMethod ValidateBundle(
	pResourceObject As %DynamicObject,
	pFHIRVersion As %String)
{
	
	// Call decorator handlers for additional bundle validation
	do ..GetCustomizationSettings(.customPath, .customModule)
	
	do ..SetPythonPath(customPath)
	
	do ..TryImportModule(customModule, .module)
	
	set decoratorsModule = ##class(%SYS.Python).Import("fhir_decorators")
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
	do ..RunHandlers(handlers, resourcePyObj, pFHIRVersion)
}

}
