Class cls.FHIR.Python.OperationHandler Extends (HS.FHIRServer.Storage.BuiltInOperations, FHIR.Python.Helper)
{

ClassMethod HelperGetPython() As %Status
{
	// %OnNew is called when the object is created.
	// The pStrategy parameter is the strategy object that created this object.
	// The default implementation does nothing
	// Frist set the python path from an env var
	set tPythonPath = $system.Util.GetEnviron("OPERATION_PATH")
	// Then set the python class name from the env var
	set tPythonClassname = $system.Util.GetEnviron("OPERATION_CLASS")
	// Then set the python module name from the env var
	set tPythonModule = $system.Util.GetEnviron("OPERATION_MODULE")

	if (tPythonPath = "") || (tPythonClassname = "") || (tPythonModule = "") {
		//quit ##super(pStrategy)
		set tPythonPath = "/irisdev/app/src/python/"
		set tPythonClassname = "CustomOperationHandler"
		set tPythonModule = "custom"
	}

    // If tPythonPath is not set and tPythonClassname is not set, then we can't do anything
    if (tPythonPath = "") || (tPythonClassname = "") || (tPythonModule = "") {
        quit ""
    }
    else {
        // Then set the python path
        do ..SetPythonPath(tPythonPath)
        Quit ..GetPythonInstance(tPythonModule, tPythonClassname)
    }
}

ClassMethod AddSupportedOperations(pMap As %DynamicObject)
{
    // This method is called the BuiltInOperations class to add the supported operations
    do ##super(pMap)

    set tPythonClass = ..HelperGetPython()
    // Add the custom python operation
    if $ISOBJECT(tPythonClass) {
        set body = ##class(%SYS.Python).None()
        set jsonLib = ##class(%SYS.Python).Import("json")
        if pMap '= "" {
            set body = jsonLib.loads(pMap.%ToJSON())
        }
        set tJson = tPythonClass."add_supported_operations"(body)
        if tJson '= "" {
            set pMap = ##class(%DynamicObject).%FromJSON(jsonLib.dumps(tJson))
        }
    }
}

/// @API
/// This is the entry point, called from the FHIR Service instance. The default processing
/// will further dispatch the request to a ClassMethod in this class to process the requested
/// $Operation (see class documentation for details)
/// <br> Note, This method may be overridden if the programmer would rather not use the provided
/// dispatch mechanism.
ClassMethod ProcessOperation(pService As HS.FHIRServer.API.Service, pRequest As HS.FHIRServer.API.Data.Request, pResponse As HS.FHIRServer.API.Data.Response)
{

    set tPythonClass = ..HelperGetPython()
    // Add the custom python operation
    // If the python class is not set, then we can't do anything
    // If the python class is set, then we can call the python method
    
    if $ISOBJECT(tPythonClass) {
        set body = ##class(%SYS.Python).None()
        if pRequest.Json '= "" {
            set jsonLib = ##class(%SYS.Python).Import("json")
            set body = jsonLib.loads(pRequest.Json.%ToJSON())
        }
        
        Set operationName = pRequest.OperationName
        Set operationScope = pRequest.OperationScope
        set pResponse = tPythonClass."process_operation"(operationName, operationScope, body, pService, pRequest, pResponse)

        k tPythonClass
    }

    // Do the default processing
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
