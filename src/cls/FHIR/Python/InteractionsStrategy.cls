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
	set importlib = ##class(%SYS.Python).Import("importlib")
	do importlib."import_module"(..PythonModule)
	
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
	        set iterator = handlers."__iter__"()
	        set handler = ""
	        Try {
		        for {
			        set handler = iterator."__next__"()
			        quit:handler=""
			        set capability = handler."__call__"(capability)
		        }
	        }
	        Catch ex {
		        if (ex.Code '= 246) { // StopIteration
			        //throw ex
		        }
	        }
	        set tMyCapabilityStatement = {}.%FromJSON(jsonLib.dumps(capability))
        }
	}

    return tMyCapabilityStatement
}

}
