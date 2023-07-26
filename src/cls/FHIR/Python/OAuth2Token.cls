Include HS.FHIRServer

Class FHIR.Python.OAuth2Token Extends (HS.FHIRServer.API.OAuth2Token, FHIR.Python.Helper)
{

Method TokenStringGet() As %String [ CodeMode = expression ]
{
..PythonClass."token_string"
}

Method OAuthClientGet() As %String [ CodeMode = expression ]
{
..PythonClass."oauth_client"
}

Method BaseURLGet() As %String [ CodeMode = expression ]
{
..PythonClass."base_url"
}

Method UsernameGet() As %String [ CodeMode = expression ]
{
..PythonClass."username"
}

Method TokenObjectGet() As %String [ CodeMode = expression ]
{
..PythonClass."token_object"
}

Method ScopesListGet() As %String
{
	set tScopesList = $lb()
	for i=1:1:..PythonClass."scopes_list".Count() {
		set tScopesList = tScopesList_$lb(..PythonClass."scopes_list".GetAt(i))
	}
	return tScopesList
}

Method VerifySearchResultsGet() As %Boolean [ CodeMode = expression ]
{
..PythonClass."verify_search_results"
}

Method %OnNew(pSchema As HS.FHIRServer.Schema) As %Status
{
	// %OnNew is called when the object is created.
	// The pStrategy parameter is the strategy object that created this object.
	// The default implementation does nothing
	// Frist set the python path from an env var
	set ..PythonPath = $system.Util.GetEnviron("OAUTH_PATH")
	// Then set the python class name from the env var
	set ..PythonClassname = $system.Util.GetEnviron("OAUTH_CLASS")
	// Then set the python module name from the env var
	set ..PythonModule = $system.Util.GetEnviron("OAUTH_MODULE")

	if (..PythonPath = "") || (..PythonClassname = "") || (..PythonModule = "") {
		set ..PythonPath = "/irisdev/app/src/python/"
		set ..PythonClassname = "CustomOAuthInteraction"
		set ..PythonModule = "custom"
	}


	// Then set the python class
	do ..SetPythonPath(..PythonPath)
	set ..PythonClass = ##class(FHIR.Python.Interactions).GetPythonInstance(..PythonModule, ..PythonClassname)

	quit $$$OK
}

/// @API<br>
/// Set or re-set the properties of the current token handler instance, based on the input parameters.<br>
/// @Input pTokenString The access token string.<br>
/// @Input pOAuthClient The OAuth 2.0 Client Name, as defined in the Management Portal at System Administration > Security > OAuth 2.0 > Client.
/// @Input pBaseURL The base URL, including scheme, host, port and path of the end point for the current FHIR interaction.
/// @Input pUserame The effective username for the current FHIR interaction.
Method SetInstance(
	pTokenString As %String = "",
	pOAuthClient As %String = "",
	pBaseURL As %String = "",
	pUsername As %String = "")
{
	if $ISOBJECT(..PythonClass) {
		Try {
			do ..PythonClass."set_instance"(pTokenString, pOAuthClient, pBaseURL, pUsername)
		}
		Catch ex {
			$$$FSLog($system.Status.GetOneStatusText(ex.AsStatus()))
			throw ##class(%Exception.SystemException).%New("Token is invalid")
		}
		
	}
}

/// @API.Overrideable<br>
/// Call introspection for the current access token, and return a JSON token object and return a status.<br>
/// Properties of this class are expected to be implemented and available during execution of any
/// overriden version of this method. ..OAuthClient and ..TokenString are essential to introspection
/// calls, and are expected to be available along with all other instance properties.
/// @Output pJWTObj : JSON object returned by introspection call.<br>
/// @Return         : %Status return value.
Method GetIntrospection(Output pJWTObj) As %Status [ Private ]
{
	if $ISOBJECT(..PythonClass) {
		set tJWTObjDict = ..PythonClass."get_introspection"()
		set jsonLib = ##class(%SYS.Python).Import("json")
		set tJWTObjString = jsonLib.dumps(tJWTObjDict)
		set pJWTObj = {}.%FromJSON(tJWTObjString)
	}
	quit $$$OK
}

/// @API<br>
/// Derive user information from the current OAuth 2.0 token, and return that
/// data if desired.<br>
/// Input:<br>
/// - pBAUsername: Existing basic authentication username (e.g., $username value).
/// - pBARoles   : Existing basic authentication user roles (e.g., $roles value).
/// Output:<br>
/// - pUserInfo(): Array of user information, subscripted by item name (e.g. pUserInfo("Username") = "_SYSTEM").
Method GetUserInfo(
	pBAUsername As %String,
	pBARoles As %String,
	Output pUserInfo)
{
	if $ISOBJECT(..PythonClass) {
		set builtins = ##class(%SYS.Python).Builtins()
		set tInfoDict = ..PythonClass."get_user_info"(pBAUsername, pBARoles)
		for i=0:1:builtins.len(tInfoDict)-1 {
			set tKey = builtins.list(tInfoDict.keys())."__getitem__"(i)
			set tValue = tInfoDict."__getitem__"(tKey)
			set pUserInfo(tKey) = tValue
		}
	}
	quit $$$OK
}

/// Verify that the access token allows the current interaction request based on the resource type,
/// resource id and required privilege. If not allowed, this method will Throw. Otherwise, it will
/// simply Return.
Method VerifyResourceIdRequest(
	pResourceType As %String,
	pResourceId As %String,
	pRequiredPrivilege As %String)
{
	if $ISOBJECT(..PythonClass) {
		do ..PythonClass."verify_resource_id_request"(pResourceType, pResourceId, pRequiredPrivilege)
	}
}

/// Verify that the access token allows the current interaction on the specified resource, based on
/// the content and required privilege. If not allowed, this method will Throw. Otherwise, it will
/// simply Return.
Method VerifyResourceContent(
	pResourceJson As %DynamicObject,
	pRequiredPrivilege As %String,
	pAllowSharedResource As %Boolean = 0)
{
	if $ISOBJECT(..PythonClass) {
		do ..PythonClass."verify_resource_content"(pResourceJson, pRequiredPrivilege, pAllowSharedResource)
	}
}

/// Verify that the access token allows the history-instance request based on the contents of
/// the interaction response and required privilege. If not allowed, this method will Throw.
/// Otherwise, it will simply Return.
Method VerifyHistoryInstanceResponse(
	pResourceType As %String,
	pResourceJson As %DynamicObject,
	pRequiredPrivilege As %String)
{
	if $ISOBJECT(..PythonClass) {
		do ..PythonClass."verify_history_instance_response"(pResourceType, pResourceJson, pRequiredPrivilege)
	}
}

/// Verify that the access token allows the delete request based on the specified resource type
/// and resource id. If not allowed, this method will Throw. Otherwise, it will simply Return.
Method VerifyDeleteRequest(
	pResourceType As %String,
	pResourceId As %String,
	pRequiredPrivilege As %String)
{
	if $ISOBJECT(..PythonClass) {
		do ..PythonClass."verify_delete_request"(pResourceType, pResourceId, pRequiredPrivilege)
	}
}

/// Verify that the access token allows the search request based on some or all of resource type,
/// resource id, compartment type, search parameters and required privilege. If not allowed, this
/// method will Throw. Otherwise, it will simply Return.
Method VerifySearchRequest(
	pResourceType As %String,
	pCompartmentResourceType As %String,
	pCompartmentResourceId As %String,
	pParameters As HS.FHIRServer.API.Data.QueryParameters,
	pRequiredPrivilege As %String)
{
	if $ISOBJECT(..PythonClass) {
		do ..PythonClass."verify_search_request"(pResourceType, pCompartmentResourceType, pCompartmentResourceId, pParameters, pRequiredPrivilege)
	}
}

/// Verify that the access token allows the system-level request. If not allowed, this method will
/// Throw. Otherwise, it will simply Return.
Method VerifySystemLevelRequest()
{
	if $ISOBJECT(..PythonClass) {
		do ..PythonClass."verify_system_level_request"()
	}
}

}
