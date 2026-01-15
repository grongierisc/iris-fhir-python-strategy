Class FHIR.Python.OperationHandler Extends (HS.FHIRServer.Storage.BuiltInOperations, FHIR.Python.Helper)
{

ClassMethod HelperGetPython() As %Status
{
	// Load the Python decorator registry
	do ..GetCustomizationSettings(.tPythonPath, .tPythonModule)

	// Set Python path and import module
	do ..SetPythonPath(tPythonPath)
	set importlib = ##class(%SYS.Python).Import("importlib")
	do importlib."import_module"(tPythonModule)
	
	// Get the fhir decorator registry
	set fhirDecorators = ##class(%SYS.Python).Import("fhir_decorators")
	Quit fhirDecorators.fhir
}

ClassMethod AddSupportedOperations(pMap As %DynamicObject)
{
    // This method is called by BuiltInOperations to add supported operations
    do ##super(pMap)

    set tPythonClass = ..HelperGetPython()
    if $ISOBJECT(tPythonClass) {
        set jsonLib = ##class(%SYS.Python).Import("json")
        set operations = tPythonClass."get_operations"()
        
        // Iterate through all registered operations
        set iterator = operations."%Items"()
        while iterator."%Next"() {
	        set item = iterator."%GetCurrent"()
	        set key = item."%Get"(0)  // (name, scope, resource_type)
	        set handler = item."%Get"(1)
	        
	        set name = key."%Get"(0)
	        set scope = key."%Get"(1)
	        set resourceType = key."%Get"(2)
	        
	        // Add to pMap based on scope
	        if scope = "System" {
		        if 'pMap."%IsDefined"("system") {
			        do pMap."%Set"("system", [])
		        }
		        set systemOps = pMap."%Get"("system")
		        do systemOps."%Push"({"name": (name), "definition": ("http://example.com/OperationDefinition/"_name)})
	        }
	        elseif (scope = "Type") || (scope = "Instance") {
		        if 'pMap."%IsDefined"("resource") {
			        do pMap."%Set"("resource", {})
		        }
		        set resourceOps = pMap."%Get"("resource")
		        if (resourceType '= "*") && (resourceType '= "") {
			        if 'resourceOps."%IsDefined"(resourceType) {
				        do resourceOps."%Set"(resourceType, [])
			        }
			        set typeOps = resourceOps."%Get"(resourceType)
			        do typeOps."%Push"({"name": (name), "definition": ("http://example.com/OperationDefinition/"_name)})
		        }
	        }
        }
    }
}

/// @API
/// This is the entry point, called from the FHIR Service instance. The default processing
/// will further dispatch the request to a ClassMethod in this class to process the requested
/// $Operation (see class documentation for details)
/// <br> Note, This method may be overridden if the programmer would rather not use the provided
/// dispatch mechanism.
ClassMethod ProcessOperation(
	pService As HS.FHIRServer.API.Service,
	pRequest As HS.FHIRServer.API.Data.Request,
	pResponse As HS.FHIRServer.API.Data.Response)
{
	set tPythonClass = ..HelperGetPython()
	
	if $ISOBJECT(tPythonClass) {
		set body = ##class(%SYS.Python).None()
		if pRequest.Json '= "" {
			set jsonLib = ##class(%SYS.Python).Import("json")
			set body = jsonLib.loads(pRequest.Json.%ToJSON())
		}
		
		Set operationName = pRequest.OperationName
		Set operationScope = pRequest.OperationScope
		Set resourceType = pRequest.Type
		
		// Get the specific handler for this operation
		set handler = tPythonClass."get_operation_handler"(operationName, operationScope, resourceType)
		
		if $ISOBJECT(handler) {
			// Call the decorated function
			set pResponse = handler."__call__"(operationName, operationScope, body, pService, pRequest, pResponse)
		}
	}

	// Fall back to default processing if no Python handler or handler didn't handle it
	Try {
		do ##super(pService, pRequest, pResponse)
	}
	Catch ex {
		if ex.Name '= "<HSFHIRErr>OperationNotSupported" {
			throw ex
		}
	}

	Return $$$OK
}

}
