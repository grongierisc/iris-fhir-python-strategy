Class FHIR.Python.Interactions Extends (HS.FHIRServer.Storage.Json.Interactions, FHIR.Python.Helper)
{

Parameter OAuth2TokenHandlerClass As %String = "FHIR.Python.OAuth2Token";

Method %OnNew(pStrategy As HS.FHIRServer.Storage.Json.InteractionsStrategy) As %Status
{
	// %OnNew is called when the object is created.
	// The pStrategy parameter is the strategy object that created this object.
	// The default implementation does nothing
	// Frist set the python path from an env var
	set ..PythonPath = $system.Util.GetEnviron("INTERACTION_PATH")
	// Then set the python class name from the env var
	set ..PythonClassname = $system.Util.GetEnviron("INTERACTION_CLASS")
	// Then set the python module name from the env var
	set ..PythonModule = $system.Util.GetEnviron("INTERACTION_MODULE")

	if (..PythonPath = "") || (..PythonClassname = "") || (..PythonModule = "") {
		//quit ##super(pStrategy)
		set ..PythonPath = "/irisdev/app/src/python/"
		set ..PythonClassname = "CustomInteraction"
		set ..PythonModule = "custom"
	}


	// Then set the python class
	do ..SetPythonPath(..PythonPath)
	set ..PythonClass = ##class(FHIR.Python.Interactions).GetPythonInstance(..PythonModule, ..PythonClassname)

	quit ##super(pStrategy)
}

Method OnBeforeRequest(
	pFHIRService As HS.FHIRServer.API.Service,
	pFHIRRequest As HS.FHIRServer.API.Data.Request,
	pTimeout As %Integer)
{
	// OnBeforeRequest is called before each request is processed.
	if $ISOBJECT(..PythonClass) {
		set body = ##class(%SYS.Python).None()
		if pFHIRRequest.Json '= "" {
			set jsonLib = ##class(%SYS.Python).Import("json")
			set body = jsonLib.loads(pFHIRRequest.Json.%ToJSON())
		}
		do ..PythonClass."on_before_request"(pFHIRService, pFHIRRequest, body, pTimeout)
	}
}

Method OnAfterRequest(
	pFHIRService As HS.FHIRServer.API.Service,
	pFHIRRequest As HS.FHIRServer.API.Data.Request,
	pFHIRResponse As HS.FHIRServer.API.Data.Response)
{
	// OnAfterRequest is called after each request is processed.
	if $ISOBJECT(..PythonClass) {
		set body = ##class(%SYS.Python).None()
		if pFHIRResponse.Json '= "" {
			set jsonLib = ##class(%SYS.Python).Import("json")
			set body = jsonLib.loads(pFHIRResponse.Json.%ToJSON())
		}
		do ..PythonClass."on_after_request"(pFHIRService, pFHIRRequest, pFHIRResponse, body)
	}
}

Method PostProcessRead(pResourceObject As %DynamicObject) As %Boolean
{
	// PostProcessRead is called after a resource is read from the database.
	// Return 1 to indicate that the resource should be included in the response.
	// Return 0 to indicate that the resource should be excluded from the response.
	if $ISOBJECT(..PythonClass) {
		if pResourceObject '= "" {
			set jsonLib = ##class(%SYS.Python).Import("json")
			set body = jsonLib.loads(pResourceObject.%ToJSON())
		}
		return ..PythonClass."post_process_read"(body)
	}
	quit 1
}

Method PostProcessSearch(
	pRS As HS.FHIRServer.Util.SearchResult,
	pResourceType As %String) As %Status
{
	// PostProcessSearch is called after a search is performed.
	// Return $$$OK to indicate that the search was successful.
	// Return an error code to indicate that the search failed.
	if $ISOBJECT(..PythonClass) {
		return ..PythonClass."post_process_search"(pRS, pResourceType)
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
