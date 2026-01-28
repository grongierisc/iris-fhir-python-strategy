Class FHIR.Python.OperationHandler Extends (HS.FHIRServer.Storage.JsonAdvSQL.BuiltInOperations, FHIR.Python.Helper)
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
        set builtins = ##class(%SYS.Python).Import("builtins")
        set operationsList = builtins.list(operations.items())
        set len = operationsList."__len__"()
    	for i=0:1:len-1 {
            set item = operationsList."__getitem__"(i)
        	
	        set key = item."__getitem__"(0)  // (name, scope, resource_type)
	        set handler = item."__getitem__"(1)
	        
	        set name = key."__getitem__"(0)
	        set name = ""_name
	        set scope = key."__getitem__"(1)
	        set resourceType = key."__getitem__"(2)
	        
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
			set sc = $$BeginCapture^%SYS.Capture(.msg)
		    Try {
                // Call the decorated function
                set pResponse = handler."__call__"(operationName, operationScope, body, pService, pRequest, pResponse)
                
                // Ensure Json property is %DynamicObject if it was set to a Python dict
                set builtins = ##class(%SYS.Python).Import("builtins")
                set val = pResponse.Json
                if builtins.isinstance(val, builtins.dict) || builtins.isinstance(val, builtins.list) {
                    set json = ##class(%SYS.Python).Import("json")
                    set str = json.dumps(val)
                    set pResponse.Json = ##class(%Library.DynamicAbstractObject).%FromJSON(str)
                }
            } Catch ex {
				set sc = $$EndCapture^%SYS.Capture(msg,.msgArray)
				set ex = ##class(FHIR.Python.Helper).RecoverPythonException(ex)
                do ##class(FHIR.Python.Helper).HandlePythonException(ex)
                throw ex
            }
			set sc = $$EndCapture^%SYS.Capture(msg,.msgArray)
			Return $$$OK
		}
	}

	// Fall back to default processing if no Python handler or handler didn't handle it
	Try {
		do ##super(pService, pRequest, pResponse)
	}
	Catch ex {
        #; if ex.Name '= "<HSFHIRErr>OperationNotSupported" {
		#; 	throw ex
		#; }
        throw ex
	}

	Return $$$OK
}

}
