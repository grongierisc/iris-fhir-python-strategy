Class FHIR.Python.InteractionsStrategy Extends (HS.FHIRServer.Storage.Json.InteractionsStrategy, FHIR.Python.Helper)
{

Parameter StrategyKey = "FHIR.Python.InteractionsStrategy";

Parameter InteractionsClass = "FHIR.Python.Interactions";

Method GetMetadataResource() As %DynamicObject
{
	set ..PythonPath = $system.Util.GetEnviron("STRATEGY_PATH")
	// Then set the python class name from the env var
	set ..PythonClassname = $system.Util.GetEnviron("STRATEGY_CLASS")
	// Then set the python module name from the env var
	set ..PythonModule = $system.Util.GetEnviron("STRATEGY_MODULE")

	if (..PythonPath = "") || (..PythonClassname = "") || (..PythonModule = "") {
		#; quit ##super()
		set ..PythonPath = "/irisdev/app/src/python/"
		set ..PythonClassname = "CustomStrategy"
		set ..PythonModule = "custom"
	}

	// Then set the python class
	do ..SetPythonPath(..PythonPath)
	set ..PythonClass = ..GetPythonInstance(..PythonModule, ..PythonClassname)

    set tMyCapabilityStatement = ##super()

	// OnBeforeRequest is called before each request is processed.
	if $ISOBJECT(..PythonClass) {
        // cast the tMyCapabilityStatement to a dict
        set jsonLib = ##class(%SYS.Python).Import("json")
        set capability = jsonLib.loads(tMyCapabilityStatement.%ToJSON())
        // call the python class
        set capability = ..PythonClass."on_get_capability_statement"(capability)
        // cast the dict back to a tMyCapabilityStatement
        set tMyCapabilityStatement = {}.%FromJSON(jsonLib.dumps(capability))
	}

    return tMyCapabilityStatement
}

}
