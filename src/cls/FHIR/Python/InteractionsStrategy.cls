Class FHIR.Python.InteractionsStrategy Extends (HS.FHIRServer.Storage.JsonAdvSQL.InteractionsStrategy, FHIR.Python.Helper)
{

Parameter StrategyKey = "FHIR.Python.InteractionsStrategy";

Parameter InteractionsClass = "FHIR.Python.Interactions";

Method GetMetadataResource() As %DynamicObject
{
	// Load the Python decorator registry
	do ..GetCustomizationSettings(.tPythonPath, .tPythonModule)
	set ..PythonPath = tPythonPath
	set ..PythonModule = tPythonModule

	// Set Python path and import module
	do ..SetPythonPath(..PythonPath)
	do ..TryImportModule(..PythonModule, .tModuleObj, 0)
	
	// Get the fhir decorator registry
	set fhirDecorators = ##class(%SYS.Python).Import("fhir_decorators")
	set ..PythonClass = fhirDecorators.fhir

    set tMyCapabilityStatement = ##super()

	// Call all registered capability statement handlers
	if $ISOBJECT(..PythonClass) {
        set jsonLib = ##class(%SYS.Python).Import("json")
        set capability = jsonLib.loads(tMyCapabilityStatement.%ToJSON())
        
        // Get all capability statement handlers
        set handlers = ..PythonClass."get_capability_statement_handlers"()
        if handlers."__len__"() > 0 {
	        set len = handlers."__len__"()
	        for i=0:1:len-1 {
		        set handler = handlers."__getitem__"(i)
		        set capability = handler."__call__"(capability)
	        }

	        set tMyCapabilityStatement = {}.%FromJSON(jsonLib.dumps(capability))
        }
	}

    return tMyCapabilityStatement
}

}
