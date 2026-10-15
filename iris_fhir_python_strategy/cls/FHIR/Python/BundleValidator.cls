Class FHIR.Python.BundleValidator Extends (HS.FHIRServer.Util.BundleValidator, FHIR.Python.Helper)
{

ClassMethod ValidateBundle(
	pResourceObject As %DynamicObject,
	pFHIRVersion As %String)
{
    set nativeBundle = pResourceObject
    set hasFHIRPathPatch = 0
    if $IsObject(pResourceObject.entry), pResourceObject.entry.%IsA("%DynamicArray") {
        for index = 0:1:pResourceObject.entry.%Size()-1 {
            set entry = pResourceObject.entry.%Get(index)
            if $IsObject(entry), ##class(FHIR.Python.BundleProcessor).IsFHIRPathPatch(entry) {
                if 'hasFHIRPathPatch {
                    set nativeBundle = {}.%FromJSON(pResourceObject.%ToJSON())
                    set hasFHIRPathPatch = 1
                }
                do nativeBundle.entry.%Set(index, ##class(FHIR.Python.BundleProcessor).ValidationEntry(entry))
            }
        }
    }
    if hasFHIRPathPatch {
        do ##super(nativeBundle, pFHIRVersion)
    }
	// Call decorator handlers for additional bundle validation
	do ..GetCustomizationSettings(.customPath, .customModule)

	do ..SetPythonPath(customPath)

	if ..TryImportModule(customModule, .module) {
	} else {
		zw "Failed to import Python module: "_customModule
        if 'hasFHIRPathPatch do ##super(pResourceObject, pFHIRVersion)
        quit
	}

	set decoratorsModule = ##class(%SYS.Python).Import("iris_fhir_python_strategy")
	set registry = decoratorsModule.fhir

	// convert pResourceObject to Python object
	set jsonLib = ##class(%SYS.Python).Import("json")
	set resourceJson = pResourceObject.%ToJSON()
	set resourcePyObj = jsonLib.loads(resourceJson)

	set handlers = registry."get_on_validate_bundle_handlers"()
	if handlers."__len__"() = 0 {
        if 'hasFHIRPathPatch do ##super(pResourceObject, pFHIRVersion)
		quit
	}
	do ..RunValidationHandlers(handlers, resourcePyObj, pFHIRVersion)
}

}
