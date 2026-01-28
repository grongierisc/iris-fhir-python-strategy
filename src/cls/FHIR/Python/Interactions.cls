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
		set hasHandlers = 0
		set handlers = ..PythonClass."get_before_request_handlers"()
		if handlers."__len__"() > 0 {
			set hasHandlers = 1
		}

		if (requestMethod = "POST") && (resourceType '= "") {
			set createHandlers = ..PythonClass."get_create_handlers"(resourceType)
			if createHandlers."__len__"() > 0 {
				set hasHandlers = 1
			}
		}
		if (requestMethod = "PUT") && (resourceType '= "") {
			set updateHandlers = ..PythonClass."get_update_handlers"(resourceType)
			if updateHandlers."__len__"() > 0 {
				set hasHandlers = 1
			}
		}
		if (requestMethod = "DELETE") && (resourceType '= "") {
			set deleteHandlers = ..PythonClass."get_delete_handlers"(resourceType)
			if deleteHandlers."__len__"() > 0 {
				set hasHandlers = 1
			}
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
		
		if (requestMethod = "POST") && (resourceType '= "") {
			do ..RunHandlers(createHandlers, pFHIRService, pFHIRRequest, body, pTimeout)
		}
		
		if (requestMethod = "PUT") && (resourceType '= "") {
			do ..RunHandlers(updateHandlers, pFHIRService, pFHIRRequest, body, pTimeout)
		}
		
		if (requestMethod = "DELETE") && (resourceType '= "") {
			do ..RunHandlers(deleteHandlers, pFHIRService, pFHIRRequest, body, pTimeout)
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
		set handlers = ..PythonClass."get_after_request_handlers"()
		if handlers."__len__"() = 0 {
			do ##super(pFHIRService, pFHIRRequest, pFHIRResponse)
			quit
		}

		set body = ##class(%SYS.Python).None()
		if pFHIRResponse.Json '= "" {
			set jsonLib = ##class(%SYS.Python).Import("json")
			set body = jsonLib.loads(pFHIRResponse.Json.%ToJSON())
		}
		
		do ..RunHandlers(handlers, pFHIRService, pFHIRRequest, pFHIRResponse, body)

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
		set handlers = ..PythonClass."get_post_process_read_handlers"(resourceType)
		if handlers."__len__"() = 0 {
			return ##super(pResourceObject)
		}
		if '..RunBooleanHandlers(handlers, body) {
			return 0
		}
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
			set handlers = ..PythonClass."get_post_process_search_handlers"(pResourceType)
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
