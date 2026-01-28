Include HS.FHIRServer

Class FHIR.Python.OAuth2Token Extends (HS.FHIRServer.Util.OAuth2Token, FHIR.Python.Helper)
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
	// Load decorator registry
	do ..GetCustomizationSettings(.tPythonPath, .tPythonModule)
	set ..PythonPath = tPythonPath
	set ..PythonModule = tPythonModule

	// Load decorator module and registry
	do ..SetPythonPath(..PythonPath)
	set sys = ##class(%SYS.Python).Import("sys")
	do sys.path.insert(0, ..PythonPath)
	
	set importlib = ##class(%SYS.Python).Import("importlib")
	do importlib."import_module"(..PythonModule)
	
	set decoratorsModule = ##class(%SYS.Python).Import("fhir_decorators")
	set ..PythonClass = decoratorsModule.fhir

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
			// Call all registered OAuth set_instance handlers
			set handlers = ..PythonClass."get_oauth_set_instance_handlers"()
			if handlers."__len__"() = 0 {
				do ##super(pTokenString, pOAuthClient, pBaseURL, pUsername)
				quit
			}
			set len = handlers."__len__"()
			for i=0:1:len-1 {
				set handler = handlers."__getitem__"(i)
				do handler."__call__"(pTokenString, pOAuthClient, pBaseURL, pUsername)
			}
		} Catch ex {
			// If any exception occurs, fall back to superclass implementation
			do ##super(pTokenString, pOAuthClient, pBaseURL, pUsername)
		}
	} else {
		do ##super(pTokenString, pOAuthClient, pBaseURL, pUsername)
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
		set handlers = ..PythonClass."get_oauth_get_introspection_handlers"()
		if handlers."__len__"() > 0 {
			set handler = handlers."__getitem__"(0)
			set tJWTObjDict = handler."__call__"()
			set jsonLib = ##class(%SYS.Python).Import("json")
			set tJWTObjString = jsonLib.dumps(tJWTObjDict)
			set pJWTObj = {}.%FromJSON(tJWTObjString)
			quit $$$OK
		}
	}
	quit ##super(.pJWTObj)
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
		set handlers = ..PythonClass."get_oauth_get_user_info_handlers"()
		if handlers."__len__"() > 0 {
			set builtins = ##class(%SYS.Python).Builtins()
			set handler = handlers."__getitem__"(0)
			set tInfoDict = handler."__call__"(pBAUsername, pBARoles)
			for i=0:1:builtins.len(tInfoDict)-1 {
				set tKey = builtins.list(tInfoDict.keys())."__getitem__"(i)
				set tValue = tInfoDict."__getitem__"(tKey)
				set pUserInfo(tKey) = tValue
			}
			quit
		}
	}
	do ##super(pBAUsername, pBARoles, .pUserInfo)
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
		set handlers = ..PythonClass."get_oauth_verify_resource_id_handlers"(pResourceType)
		if handlers."__len__"() = 0 {
			do ##super(pResourceType, pResourceId, pRequiredPrivilege)
			quit
		}
		set len = handlers."__len__"()
		for i=0:1:len-1 {
			set handler = handlers."__getitem__"(i)
			do handler."__call__"(pResourceType, pResourceId, pRequiredPrivilege)
		}
	} else {
		do ##super(pResourceType, pResourceId, pRequiredPrivilege)
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
		set resourceType = pResourceJson.resourceType
		set handlers = ..PythonClass."get_oauth_verify_resource_content_handlers"(resourceType)
		if handlers."__len__"() = 0 {
			do ##super(pResourceJson, pRequiredPrivilege, pAllowSharedResource)
			quit
		}
		set len = handlers."__len__"()
		for i=0:1:len-1 {
			set handler = handlers."__getitem__"(i)
			do handler."__call__"(pResourceJson, pRequiredPrivilege, pAllowSharedResource)
		}
	} else {
		do ##super(pResourceJson, pRequiredPrivilege, pAllowSharedResource)
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
		set handlers = ..PythonClass."get_oauth_verify_history_handlers"(pResourceType)
		if handlers."__len__"() = 0 {
			do ##super(pResourceType, pResourceJson, pRequiredPrivilege)
			quit
		}
		set len = handlers."__len__"()
		for i=0:1:len-1 {
			set handler = handlers."__getitem__"(i)
			do handler."__call__"(pResourceType, pResourceJson, pRequiredPrivilege)
		}
	} else {
		do ##super(pResourceType, pResourceJson, pRequiredPrivilege)
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
		set handlers = ..PythonClass."get_oauth_verify_delete_handlers"(pResourceType)
		if handlers."__len__"() = 0 {
			#; do ##super(pResourceType, pResourceId, pRequiredPrivilege)
			quit
		}
		set len = handlers."__len__"()
		for i=0:1:len-1 {
			set handler = handlers."__getitem__"(i)
			do handler."__call__"(pResourceType, pResourceId, pRequiredPrivilege)
		}
	} else {
		#; do ##super(pResourceType, pResourceId, pRequiredPrivilege)
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
		set handlers = ..PythonClass."get_oauth_verify_search_handlers"(pResourceType)
		if handlers."__len__"() = 0 {
			do ##super(pResourceType, pCompartmentResourceType, pCompartmentResourceId, pParameters, pRequiredPrivilege)
			quit
		}
		set len = handlers."__len__"()
		for i=0:1:len-1 {
			set handler = handlers."__getitem__"(i)
			do handler."__call__"(pResourceType, pCompartmentResourceType, pCompartmentResourceId, pParameters, pRequiredPrivilege)
		}
	} else {
		do ##super(pResourceType, pCompartmentResourceType, pCompartmentResourceId, pParameters, pRequiredPrivilege)
	}
}

/// Verify that the access token allows the system-level request. If not allowed, this method will
/// Throw. Otherwise, it will simply Return.
Method VerifySystemLevelRequest()
{
	if $ISOBJECT(..PythonClass) {
		set handlers = ..PythonClass."get_oauth_verify_system_level_handlers"()
		if handlers."__len__"() = 0 {
			do ##super()
			quit
		}
		set len = handlers."__len__"()
		for i=0:1:len-1 {
			set handler = handlers."__getitem__"(i)
			do handler."__call__"()
		}
	} else {
		do ##super()
	}
}

}
