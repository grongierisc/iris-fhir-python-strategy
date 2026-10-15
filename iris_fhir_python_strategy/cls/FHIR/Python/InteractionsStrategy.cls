Include HS.FHIRServer

Class FHIR.Python.InteractionsStrategy Extends (HS.FHIRServer.Storage.JsonAdvSQL.InteractionsStrategy, FHIR.Python.Helper)
{

Parameter StrategyKey = "FHIR.Python.InteractionsStrategy";

Parameter InteractionsClass = "FHIR.Python.Interactions";

ClassMethod GetStrategyConfigInfo() As %DynamicObject
{
    set config = ##super()
    set config."max_merge_writes" = {
        "type":"number",
        "default":1000,
        "display_name":"Maximum synchronous merge writes",
        "description":"Includes both Patients, dependent resources and merge Provenance."
    }
    return config
}

Method OnBeforeSaveStrategyConfigData(configData As %DynamicObject)
{
    do ..GetMergeWriteLimit(configData)
    do ##super(configData)
}

ClassMethod GetMergeWriteLimit(configData As %DynamicObject) As %Integer
{
    if configData.%IsDefined("max_merge_writes") {
        if (configData.%GetTypeOf("max_merge_writes") '= "number") ||
           (configData."max_merge_writes" < 3) ||
           ((configData."max_merge_writes" # 1) '= 0) {
            $$$ThrowFHIR($$$GeneralError, "max_merge_writes must be an integer of at least 3", $$$OutcomeInvalid(400))
        }
        return configData."max_merge_writes"
    }
    return 1000
}

ClassMethod DefinitionURL(version As %String) As %String
{
    if $Extract(version) = "4" {
        return "https://github.com/grongierisc/iris-fhir-strategy-merge-operator/OperationDefinition/Patient-merge-r4"
    }
    return "http://hl7.org/fhir/OperationDefinition/Patient-merge"
}

Method GetMetadataResource() As %DynamicObject
{
    set tMyCapabilityStatement = ##super()
    set rests = tMyCapabilityStatement.rest.%GetIterator()
    while rests.%GetNext(.index, .rest) {
        set resources = rest.resource.%GetIterator()
        while resources.%GetNext(.index, .resource) {
            if (resource.type '= "Patient") || '$IsObject(resource.operation) continue
            set operations = resource.operation.%GetIterator()
            while operations.%GetNext(.index, .operation) {
                if (operation.name = "merge") && (operation.definition = ..DefinitionURL("5")) {
                    set operation.definition = ..DefinitionURL(tMyCapabilityStatement.fhirVersion)
                }
            }
        }
    }
	// Load the Python decorator registry
	do ..GetCustomizationSettings(.tPythonPath, .tPythonModule)
	set ..PythonPath = tPythonPath
	set ..PythonModule = tPythonModule

	// Set Python path and import module
	do ..SetPythonPath(..PythonPath)
	if ..TryImportModule(..PythonModule, .tModuleObj) {
		set ..PythonModule = tModuleObj
	} else {
		zw "Failed to import Python module: "_tPythonModule
        return tMyCapabilityStatement
	}
	
	// Get the fhir decorator registry
	set fhirDecorators = ##class(%SYS.Python).Import("iris_fhir_python_strategy")
	set ..PythonClass = fhirDecorators.fhir

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
