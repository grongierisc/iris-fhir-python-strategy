Class FHIR.Python.Interactions Extends (HS.FHIRServer.Storage.JsonAdvSQL.Interactions, FHIR.Python.Helper)
{

// Commented for using the default values that support Smart on FHIR

// Parameter OAuth2TokenHandlerClass As %String = "FHIR.Python.OAuth2Token";

Parameter ResourceValidatorClass = "FHIR.Python.ResourceValidator";

Parameter OperationHandlerClass As %String = "FHIR.Python.OperationHandler";

Parameter BatchHandlerClass As %String = "FHIR.Python.BundleProcessor";

Method %OnNew(pStrategy As HS.FHIRServer.Storage.JsonAdvSQL.InteractionsStrategy) As %Status
{

	// %OnNew is called when the object is created.
	// Load the Python decorator registry
	do ..GetCustomizationSettings(.tPythonPath, .tPythonModule)
	set ..PythonPath = tPythonPath
	set ..PythonModule = tPythonModule

	// Set Python path and import the module (which registers decorators)
	do ..SetPythonPath(..PythonPath)
	if ..TryImportModule(..PythonModule, .tModuleObj) {
		set ..PythonModule = tModuleObj
	} else {
		set ..PythonModule = ""
	}
	
	// Get the fhir decorator registry
	set fhirDecorators = ##class(%SYS.Python).Import("fhir_decorators")
	set ..PythonClass = fhirDecorators.fhir
	
	// Set interactions reference for helper functions
	if $ISOBJECT(..PythonModule) {
		set pyBuiltins = ##class(%SYS.Python).Import("builtins")
		if pyBuiltins.hasattr(..PythonModule, "get_request_context") {
			set context = ..PythonModule."get_request_context"()
			set context.interactions = $this
		} elseif pyBuiltins.hasattr(..PythonModule, "context") {
			set context = ..PythonModule.context
			set context.interactions = $this
		}
	}

	quit ##super(pStrategy)
}

Method OnBeforeRequest(
	pFHIRService As HS.FHIRServer.API.Service,
	pFHIRRequest As HS.FHIRServer.API.Data.Request,
	pTimeout As %Integer)
{
	// OnBeforeRequest is called before each request is processed.
	// Call all registered before_request handlers
	if $ISOBJECT(..PythonClass) {
		set requestMethod = pFHIRRequest.RequestMethod
		set resourceType = pFHIRRequest.Type
		set interaction = pFHIRRequest.Interaction
		set hasHandlers = 0
		set handlers = ..PythonClass."get_on_before_request_handlers"()
		if handlers."__len__"() > 0 {
			set hasHandlers = 1
		}
		
		set specificHandlers = ##class(%SYS.Python).None()

		if (requestMethod = "POST") && (resourceType '= "") {
			set specificHandlers = ..PythonClass."get_on_before_create_handlers"(resourceType)
		} elseif (requestMethod = "PUT") && (resourceType '= "") {
			set specificHandlers = ..PythonClass."get_on_before_update_handlers"(resourceType)
		} elseif (requestMethod = "DELETE") && (resourceType '= "") {
			set specificHandlers = ..PythonClass."get_on_before_delete_handlers"(resourceType)
		} elseif (interaction = "read") && (resourceType '= "") {
			set specificHandlers = ..PythonClass."get_on_before_read_handlers"(resourceType)
		} elseif (interaction = "search-type") && (resourceType '= "") {
			set specificHandlers = ..PythonClass."get_on_before_search_handlers"(resourceType)
		}

		if (specificHandlers '= ##class(%SYS.Python).None()) && (specificHandlers."__len__"() > 0) {
			set hasHandlers = 1
		}

		if 'hasHandlers {
			do ##super(pFHIRService, pFHIRRequest, pTimeout)
			quit
		}

		set body = ##class(%SYS.Python).None()
		if pFHIRRequest.Json '= "" {
			set jsonLib = ##class(%SYS.Python).Import("json")
			set body = jsonLib.loads(pFHIRRequest.Json.%ToJSON())
		}
		
		do ..RunHandlers(handlers, pFHIRService, pFHIRRequest, body, pTimeout)
		
		if (specificHandlers '= ##class(%SYS.Python).None()) {
			do ..RunHandlers(specificHandlers, pFHIRService, pFHIRRequest, body, pTimeout)
		}
        
        // Update pFHIRRequest.Json if body exists and was modified
        if (pFHIRRequest.Json '= "") && (body '= ##class(%SYS.Python).None()) {
            do ..UpdateDynamicObject(pFHIRRequest.Json, body)
        }

	} else {
		do ##super(pFHIRService, pFHIRRequest, pTimeout)
	}
}

Method OnAfterRequest(
	pFHIRService As HS.FHIRServer.API.Service,
	pFHIRRequest As HS.FHIRServer.API.Data.Request,
	pFHIRResponse As HS.FHIRServer.API.Data.Response)
{
	// OnAfterRequest is called after each request is processed.
	// Call all registered after_request handlers
	if $ISOBJECT(..PythonClass) {
		set requestMethod = pFHIRRequest.RequestMethod
		set resourceType = pFHIRRequest.Type
		set hasHandlers = 0

		set handlers = ..PythonClass."get_on_after_request_handlers"()
		if handlers."__len__"() > 0 {
			set hasHandlers = 1
		}

		set specificHandlers = ##class(%SYS.Python).None()
		if (requestMethod = "POST") && (resourceType '= "") {
			set specificHandlers = ..PythonClass."get_on_after_create_handlers"(resourceType)
		} elseif (requestMethod = "PUT") && (resourceType '= "") {
			set specificHandlers = ..PythonClass."get_on_after_update_handlers"(resourceType)
		} elseif (requestMethod = "DELETE") && (resourceType '= "") {
			set specificHandlers = ..PythonClass."get_on_after_delete_handlers"(resourceType)
		}

		if (specificHandlers '= ##class(%SYS.Python).None()) && (specificHandlers."__len__"() > 0) {
			set hasHandlers = 1
		}
		
		if 'hasHandlers {
			do ##super(pFHIRService, pFHIRRequest, pFHIRResponse)
			quit
		}
		
		set body = ##class(%SYS.Python).None()
		if pFHIRResponse.Json '= "" {
			set jsonLib = ##class(%SYS.Python).Import("json")
			set body = jsonLib.loads(pFHIRResponse.Json.%ToJSON())
		}
		
		if (specificHandlers '= ##class(%SYS.Python).None()) {
			do ..RunHandlers(specificHandlers, pFHIRService, pFHIRRequest, pFHIRResponse, body)
		}

		do ..RunHandlers(handlers, pFHIRService, pFHIRRequest, pFHIRResponse, body)

        // Update pFHIRResponse.Json if body exists and was modified
        if (pFHIRResponse.Json '= "") && (body '= ##class(%SYS.Python).None()) {
            do ..UpdateDynamicObject(pFHIRResponse.Json, body)
        }
        
        do ##super(pFHIRService, pFHIRRequest, pFHIRResponse)

	} else {
		do ##super(pFHIRService, pFHIRRequest, pFHIRResponse)
	}
}

Method PostProcessRead(pResourceObject As %DynamicObject) As %Boolean
{
	// PostProcessRead is called after a resource is read from the database.
	// Call all registered post_process_read handlers
	if $ISOBJECT(..PythonClass) {
		if pResourceObject = "" {
			return ##super(pResourceObject)
		}
		set jsonLib = ##class(%SYS.Python).Import("json")
		set body = jsonLib.loads(pResourceObject.%ToJSON())
		set resourceType = body."get"("resourceType")
		
		// Get all post_process_read handlers for this resource type
		set handlers = ..PythonClass."get_on_after_read_handlers"(resourceType)
		if '..RunBooleanHandlers(handlers, body) {
			return 0
		}
		
		// Get all consent handlers for this resource type
		set handlers = ..PythonClass."get_consent_handlers"(resourceType)
		if '..RunBooleanHandlers(handlers, body) {
			return 0
		}
        
        // Update pResourceObject with potential modifications from Python
        do ..UpdateDynamicObject(pResourceObject, body)
        
	} else {
		return ##super(pResourceObject)
	}
	quit 1
}

Method PostProcessSearch(
	pRS As HS.FHIRServer.Util.SearchResult,
	pResourceType As %String) As %Status
{
	// PostProcessSearch is called after a search is performed.
	// Call all registered post_process_search handlers
		if $ISOBJECT(..PythonClass) {
			// Get all post_process_search handlers for this resource type
			set handlers = ..PythonClass."get_on_after_search_handlers"(pResourceType)
			if handlers."__len__"() = 0 {
				do ##super(pRS, pResourceType)
				quit $$$OK
			}
			do ..RunHandlers(handlers, pRS, pResourceType)
			do ##super(pRS, pResourceType)
		} else {
			do ##super(pRS, pResourceType)
			quit $$$OK
		}
		quit $$$OK
}

Method Read(
	pResourceType As %String,
	pResourceId As %String,
	pVersionId As %String = "") As %DynamicObject
{
	return ##super(pResourceType, pResourceId, pVersionId)
}

Method Add(
	pResourceObj As %DynamicObject,
	pResourceIdToAssign As %String = "",
	pHttpMethod = "POST") As %String
{
	return ##super(pResourceObj, pResourceIdToAssign, pHttpMethod)
}

/// Returns VersionId for the "deleted" version
Method Delete(
	pResourceType As %String,
	pResourceId As %String) As %String
{
	return ##super(pResourceType, pResourceId)
}

Method Update(pResourceObj As %DynamicObject) As %String
{
	return ##super(pResourceObj)
}

}
