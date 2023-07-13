Include HS.FHIRServer

Class FHIR.Python.OAuth2Token Extends HS.FHIRServer.API.OAuth2Token
{

/// Minimum number of seconds between introspection calls for the current access token.
Parameter IntrospectionInterval As Integer = 5;

/// If 0, SetInstance() will perform token validation. Otherwise, if 1, the tokens
/// handled by the Interactions instance that uses this class are expected to have
/// already been validated by alternate means.
Parameter AlreadyValidated As %Boolean = 0;

/// The access token string, as extracted from a FHIR REST API request.
Property %TokenString As %String(MAXLEN = 8192) [ Private ];

/// OAuth 2.0 Client name, as defined in System Administration > Security > OAuth 2.0 > Client.
Property %OAuthClient As %String(MAXLEN = 256) [ Private ];

/// FHIR request BaseURL.
Property %BaseURL As %String(MAXLEN = 1024) [ Private ];

/// FHIR request Basic Auth username.
Property %Username As %String(MAXLEN = 256) [ Private ];

/// The access token JWT object, as derived from validating via OAuth 2.0 API calls. 
Property %TokenObject As %Library.DynamicObject [ Private ];

/// $List of access token JWT scopes.
Property %ScopesList As %List [ Private ];

/// Array of clinical scopes present. Array format is:<br>
/// ..%ClinicalScopes(clinicalScopeName, N, "resourceType") = resourceType<br>
/// ..%ClinicalScopes(clinicalScopeName, N, "readWrite") = readWrite<br>
Property %ClinicalScopes As %String [ MultiDimensional, Private ];

/// Array of context values present (e.g., ..%ContextValues("patient") = 123)
Property %ContextValues As %String [ MultiDimensional, Private ];

/// The schema object that governs evaluation of resources and resource definitions.
Property %schema As HS.FHIRServer.Schema [ Private ];

/// Last time, in seconds, that introspection was done for this access token.
Property %LastIntrospectionTime As %Integer [ InitialExpression = 0, Private ];

/// Flag to indicate that search results should be verified against the access token.
Property %VerifySearchResults As %Boolean [ InitialExpression = 0, Private ];

Method TokenStringGet() As %String [ CodeMode = expression ]
{
..%TokenString
}

Method OAuthClientGet() As %String [ CodeMode = expression ]
{
..%OAuthClient
}

Method BaseURLGet() As %String [ CodeMode = expression ]
{
..%BaseURL
}

Method UsernameGet() As %String [ CodeMode = expression ]
{
..%Username
}

Method TokenObjectGet() As %String [ CodeMode = expression ]
{
..%TokenObject
}

Method ScopesListGet() As %String [ CodeMode = expression ]
{
..%ScopesList
}

Method VerifySearchResultsGet() As %Boolean [ CodeMode = expression ]
{
..%VerifySearchResults
}

Method %OnNew(pSchema As HS.FHIRServer.Schema) As %Status
{
	Set ..%schema = pSchema
	Return $$$OK
}

/// @API<br>
/// Set or reset the properties of the current token handler instance, based on the input parameters.<br>
/// @Input pTokenString The access token string.<br>
/// @Input pOAuthClient The OAuth 2.0 Client Name, as defined in the Management Portal at System Administration > Security > OAuth 2.0 > Client.
/// @Input pBaseURL The base URL, including scheme, host, port and path of the end point for the current FHIR interaction.
/// @Input pUsername (DEPRECATED) The Basic Auth username for the current FHIR interaction.
Method SetInstance(
	pTokenString As %String = "",
	pOAuthClient As %String = "",
	pBaseURL As %String = "",
	pUsername As %String = "")
{
	
	If pTokenString '= "" {
		
		Set ..%TokenString = pTokenString
		Set ..%OAuthClient = pOAuthClient
		Set ..%BaseURL = pBaseURL
		Set ..%Username = pUsername
		
		Try {
			Do ..ValidateToken()
			
		} Catch eException {
			Do ..ClearInstance()
			Throw eException
		}
	}
	
	Return
}

Method ClearInstance() [ Private ]
{
	Set ..%TokenString = ""
	Set ..%OAuthClient = ""
	Set ..%BaseURL = ""
	Set ..%Username = ""
	Set ..%TokenObject = ""
	Set ..%ScopesList = ""
	Set ..%LastIntrospectionTime = 0
	Set ..%VerifySearchResults = 0
	Kill ..%ClinicalScopes
	Kill ..%ContextValues
	Quit
}

/// Internal method to wrap up a common group of tasks.
Method CheckExpiredOrInactive() [ Private ]
{
	Set lastIntrospectionTime = ..%LastIntrospectionTime
	
	If ..IsExpiredOrInactive(.lastIntrospectionTime, .httpStatus, .failReasonText) {
		$$$FSLog(failReasonText)
		Do ..ClearInstance()
		$$$ThrowFHIR($$$HttpOnlyResponse(httpStatus))
	}
	
	Set ..%LastIntrospectionTime = lastIntrospectionTime
	
	Quit
}

/// This method does a quick check of expiration, comparing current time with token
/// expiration time. If not expired, then, if it has been longer than ..#IntrospectionInterval
/// seconds since the last time introspection has been done on this token, it queries
/// the introspection endpoint to verify that the token is still active (i.e., not revoked).
Method IsExpiredOrInactive(
	ByRef pLastIntrospectionTime As %Integer,
	Output pHTTPStatus As %String,
	Output pFailReasonText As %String) As %Boolean [ Private ]
{
	Set expiredOrInactive = 0
	
	Set pHTTPStatus = ""
	Set pFailReasonText = ""
	
	If ..IsExpired() {
		Set pHTTPStatus = 401
		Set pFailReasonText = "Access token is expired"
		Set expiredOrInactive = 1
		
	} Else {
		Set pLastIntrospectionTime = ..TimeInSeconds($ztimestamp, 0)
	}
	
	Return expiredOrInactive
}

/// Per RFC 7662, exp is OPTIONAL for Introspection response. Return 0 (not expired) if exp is blank.
Method IsExpired() As %Boolean [ CodeMode = expression, Private ]
{
((..%TokenObject.exp '= "") && (..TimeInSeconds($ztimestamp, 0) > ..%TokenObject.exp))
}

/// This method returns 1 if the last introspection call for this token has
/// been more than ..#IntrospectionInterval seconds, returns 0 if not.
Method IsIntroCached(pLastIntrospectionTime As %Integer) As %Boolean [ CodeMode = expression, Private ]
{
((pLastIntrospectionTime > 0) && (..TimeInSeconds($ztimestamp, 0) <= (pLastIntrospectionTime + ..#IntrospectionInterval)))
}

/// Convert $h value to seconds since start of the Unix epoch,<br>
/// time is $h value.<br>
/// interval is interval to be added in seconds.
ClassMethod TimeInSeconds(
	time As %String,
	interval As %Integer = 0) As %Integer [ CodeMode = expression, Internal ]
{
##class(%OAuth2.Utils).TimeInSeconds(time, interval)
}

/// Uses the instance properties populated by SetInstance() to validate the access
/// token and to derive and expose access token data that will be used for verifying
/// that a given FHIR request is allowed by the token. If ValidateToken() fails then
/// it will Throw. Otherwise, it will simply Return.
Method ValidateToken() [ Private ]
{
	// Must specify an OAuth 2.0 Client name if going to handle a token.
	If (..%TokenString '= "") && (..%OAuthClient = "") {
		$$$FSLog("OAuth access token received on end point that has no OAuth 2.0 Client defined")
		$$$ThrowFHIR($$$HttpOnlyResponse(403))
	}
	
	$$$FSLog("LastIntrospectionTime=" _ ..%LastIntrospectionTime)
	$$$FSLog("AlreadyValidated=" _ ..IsIntroCached(..%LastIntrospectionTime))
	
	If '..IsIntroCached(..%LastIntrospectionTime) {
		// ValidateJWT() verifies that the token is sensical as a JWT and returns an
		// indication that it is signed. As of 2021.1, a JWT returned by ValidateJWT()
		// by default does NOT include scope information.
		Set tReturn = ##class(%SYS.OAuth2.Validation).ValidateJWT(..%OAuthClient, ..%TokenString, "", "", .JWTObj, .securityParams, .tSC)
		
		If $$$ISERR(tSC)  {
			$$$FSLog("ValidateJWT on OAuth access token failed: " _ $system.Status.GetErrorText(tSC))
			$$$ThrowFHIR($$$HttpOnlyResponse(401))
		}
		
		// Verify aud and sub now, using the JWT returned by ValidateJWT().
		Set ..%TokenObject = JWTObj
		
		// Validate the sub.
		If '..ValidateSub() {
			$$$FSLog("Token sub '" _ JWTObj.sub _ "' failed validation")
			$$$ThrowFHIR($$$HttpOnlyResponse(401))
		}

		// Set it to the cached value.
		Set ..%LastIntrospectionTime = ..TimeInSeconds($ztimestamp, 0)
	}

	
	Return
}

/// @API.Overrideable<br>
/// This method presents the token string to the introspection endpoint for the server that
/// granted this token.<br>
/// <br>
/// The server returns a JSON object with information about the token. RFC 7662 "OAuth 2.0
/// Token Introspection" Section 2.2 (https://datatracker.ietf.org/doc/html/rfc7662#section-2.2)
/// describes the expected contents of the returned JSON object. RFC 7662 lists "scope" as
/// OPTIONAL. However, for FHIRServer processing, it is REQUIRED.<br>
/// <br>
/// This method checks the JSON object to verify that the token is active (well-formed and not
/// expired), and returns it as ByRef variable pJWTObj.<br>
/// <br>
/// By the time this method returns, pJWTObj MUST hold the token scopes in the 'scope' property,
/// as a space-delimited string. If the tokens being handled by this class are expected to hold
/// scopes in an alternate property and/or in an alternate format, you may need to override this
/// method to ensure that the scopes are moved and/or reformatted into the 'scope' property. The
/// default implementation of this method handles only one common alternate scenario, where the
/// token object scopes are found in property 'scp', either as a JSON array or a space-delimited
/// string. Other alternate scenarios must be handled via override of this method.<br>
/// <br>
/// If the server that granted the token does not host an introspection endpoint, then you must
/// override this method to derive/obtain a JSON object that holds information about the access
/// token, with the required properties described above.<br>
/// <br>
/// @Output pJWTObj : JSON object that holds information about the token.<br>
/// @Return         : %Status return value.
Method GetIntrospection(Output pJWTObj) As %Status [ Private ]
{
	Set pJWTObj = ""
	
	Set status = ##class(%SYS.OAuth2.AccessToken).GetIntrospection(..%OAuthClient, ..%TokenString, .pJWTObj)
	
	If $$$ISOK(status) {
		If '$IsObject($Get(pJWTObj)) {
			Set status = $$$ERROR($$$HSFHIRErrTokenIntrospectionNoToken)
			
		} ElseIf 'pJWTObj.active {
			Set status = $$$ERROR($$$HSFHIRErrTokenIntrospectionInactive)
			
		} Else {
			// Compensate for use of 'scp' instead of 'scope' for scopes.
			// Some auth server implementations specify 'scp' to be a
			// space-delimited list, and other implementations specify it
			// to be a JSON array of strings.
			If (pJWTObj.scope = "") && (pJWTObj.scp '= "") {
				
				If '$IsObject(pJWTObj.scp) {
					Set pJWTObj.scope = pJWTObj.scp
					
				} ElseIf pJWTObj.scp.%IsA("%Library.DynamicArray") {
					Set reconstructedScope = ""
					Set arrIter = pJWTObj.scp.%GetIterator()
					While arrIter.%GetNext(.arrIdx, .oneScope) {
						If '$IsObject(oneScope) {
							If oneScope '= "" {
								Set reconstructedScope = reconstructedScope _ $Select(reconstructedScope'="":" ", 1:"") _ oneScope
							}
						} Else {
							// If array is not all strings then abort the reconstruct.
							Set reconstructedScope = ""
							Quit
						}
					}
					If reconstructedScope '= "" {
						Set pJWTObj.scope = reconstructedScope
					}
				} 
			}
		}
	}
	
	Return status
}

/// Parses the token JWT object "scope" property and populates %ScopesList and %ClinicalScopes.
Method SetScopes() [ Private ]
{
	Set scopesList = ""
	
	Set scopesString = ..%TokenObject.scope
	
	$$$FSLog("scope string = " _ scopesString)
	
	For i = 1:1:$Length(scopesString," ") {
		Set nextScope = $Piece(scopesString," ",i)
		Continue:nextScope=""
		Set $List(scopesList, *+1) = nextScope
		If $Extract(nextScope, 1, 8) = "patient/" {
			Set clinicalScopeName = "patient"
		} ElseIf $Extract(nextScope, 1, 5) = "user/" {
			Set clinicalScopeName = "user"
		} Else {
			Set clinicalScopeName = ""
		}
		If clinicalScopeName '= "" {
			Set scopeTypeAndRW = $Piece(nextScope, "/", 2)
			Set scopeResourceType = $Piece(scopeTypeAndRW, ".", 1)
			Set scopeReadWrite = $Piece(scopeTypeAndRW, ".", 2)
			Set N = $Get(..%ClinicalScopes(clinicalScopeName)) + 1
			Set ..%ClinicalScopes(clinicalScopeName, N, "resourceType") = scopeResourceType
			Set ..%ClinicalScopes(clinicalScopeName, N, "readWrite") = scopeReadWrite
			Set ..%ClinicalScopes(clinicalScopeName) = N
			$$$FSLog("allowing scope " _ nextScope)
			
		} Else {
			$$$FSLog("dropping scope " _ nextScope)
		}
	}
	
	Set ..%ScopesList = scopesList
	
	Return
}

/// Derives context values (e.g., patient context) from the access token JWT object
/// information. Default functionality is to derive it from scopes that are
/// formatted as "launch/" _ contextName _ "/" _ contextValue, or from a specific
/// JWT property such as "patient".
Method SetContextValues() [ Private ]
{
	Set scopesString = ..%TokenObject.scope
	
	For i = 1:1:$Length(scopesString," ") {
		Set nextScope = $Piece(scopesString," ",i)
		Continue:nextScope=""
		If ($Extract(nextScope, 1, 7) = "launch/") && ($Length(nextScope, "/") = 3) {
			Set p2 = $Piece(nextScope, "/", 2)
			Set p3 = $Piece(nextScope, "/", 3)
			If p2?1A.A {
				If p3 '="" {
					Set ..%ContextValues(p2) = p3
				} ElseIf ..%TokenObject.%Get(p2) '= "" {
					Set ..%ContextValues(p2) = ..%TokenObject.%Get(p2)
				}
			}
		}
	}
	
	For context = "patient", "encounter" {
		If (..%TokenObject.%Get(context) '= "") && ($Get(..%ContextValues(context)) = "") {
			Set ..%ContextValues(context) = ..%TokenObject.%Get(context)
		}
	}
	
	Return
}

/// @API
/// Return the current context values, if any, as a Multidimensional array.
Method GetContextValues(ByRef pContextValues)
{
	Kill pContextValues
	
	Set contextName = ""
	For {
		Set contextName = $Order(..%ContextValues(contextName))
		If contextName = "" Quit
		Set pContextValues(contextName) = ..%ContextValues(contextName)
	}
}

/// Compares the current audience (the BaseURL) against the token aud value(s),
/// if any. For http URL aud values, the comparison is trailing-slash-insensitive
/// and case-sensitive only for the application path.
Method ValidateAudience() As %Boolean [ Private ]
{
	Set JWTAudience = ..%TokenObject.aud
	
	If JWTAudience'="" {
		Set matched = 0
		Set currentAud = $$formatAud(..%BaseURL)
		If '$IsObject(JWTAudience) {
			// Compare single audience from JWT.
			If $$formatAud(JWTAudience)=currentAud {
				Set matched = 1
			}
		} Else {
			// Compare multiple audience from JWT. In this case it is a %DynamicArray.
			For i = 0:1:JWTAudience.%Size()-1 {
				If $$formatAud(JWTAudience.%Get(i))=currentAud {
					Set matched = 1
					Quit
				}
			}
		}
		
	} Else {
		// If no aud in the token, then it does not match the current audience.
		Set matched = 0
	}
	
	Return matched
	
formatAud(aud)
	// Strip trailing slash.
	If $Extract(aud, *)="/" {
		Set aud = $Extract(aud, 1, *-1)
	}
	Set audL = $ZConvert(aud, "L")
	If ($Extract(audL, 1, 7) = "http://") || ($Extract(audL, 1, 8) = "https://") {
		// If aud is an HTTP URL, then make the comparison case-INsensitive
		// against the scheme and server, and case-SENSITIVE against the
		// rest of the URL.
		Set aud = $Piece(audL, "/", 1, 3) _ $Select($Length(aud, "/")>3:"/"_$Piece(aud, "/", 4, *), 1:"")
	} Else {
		Set aud = audL
	}
	Return aud
}

/// Verify that the access token sub is okay.
Method ValidateSub() As %Boolean [ CodeMode = expression, Private ]
{
..%TokenObject.sub '= ""
}

/// @API<br>
/// Derive user information from the current OAuth 2.0 token, and return that
/// data if desired.<br>
/// Input:<br>
/// - pBAUsername: Existing basic authentication username (e.g., $username value).
/// - pBARoles   : Existing basic authentication user roles (e.g., $roles value).
/// Output:<br>
/// - pUserInfo(): Array of user information. Standard return is pUserInfo("Username")
///               and pUserInfo("Roles"). This method may be overridden to derive and
///               return other user info via subscripts in the pUserInfo() array.
Method GetUserInfo(
	pBAUsername As %String,
	pBARoles As %String,
	Output pUserInfo)
{
	Kill pUserInfo
	Set pUserInfo("Username") = ""
	Set pUserInfo("Roles") = ""
	
	If '$IsObject(..%TokenObject) Quit
	
	If ..%TokenObject.sub '= "" {
		Set pUserInfo("Username") = ..%TokenObject.sub
	}
	
	Quit
}

/// Return a Boolean indicating whether the current specified clinical scope
/// allows the specified interaction per resource type plus read/write.
Method HasScope(
	pClinicalScopeName,
	pResourceType,
	pRequiredPrivilege) As %Boolean
{
	Set hasScope = 0
	
	Set n = ""
	For {
		Set n = $Order(..%ClinicalScopes(pClinicalScopeName, n))
		If n="" Quit
		If ((..%ClinicalScopes(pClinicalScopeName, n, "resourceType")="*") || (..%ClinicalScopes(pClinicalScopeName, n, "resourceType")=pResourceType)) 
			&& 
			((..%ClinicalScopes(pClinicalScopeName, n, "readWrite")="*") || (..%ClinicalScopes(pClinicalScopeName, n, "readWrite")=pRequiredPrivilege)) {
			Set hasScope = 1
			Quit
		}
	}
	
	Return hasScope
}

/// Return a Boolean indicating that the specified resource content resides in the
/// specified compartment (compartment type plus resource id).
Method HasCompartment(
	pCompartmentType As %String,
	pCompartmentResourceId As %String,
	pResourceJson As %DynamicObject) As %Boolean
{
	Set hasCompartment = 0
	
	Set compartmentResourceType = $ZConvert($Extract(pCompartmentType), "U") _ $Extract(pCompartmentType, 2, *)
	
	Set compartmentsList = ..GetCompartments(..%schema, pResourceJson)
	
	Set listIndex = 0
	While $ListNext(compartmentsList, listIndex, refVal) {
		Set refType = $Piece(refVal, "/", *-1)
		Set refId = $Piece(refVal, "/", *)
		If (refType = compartmentResourceType) && (refId = pCompartmentResourceId) {
			Set hasCompartment = 1
			Quit
		}
	}
	
	Return hasCompartment
}

ClassMethod GetCompartments(
	pSchema As HS.FHIRServer.Schema,
	pResourceJson As %DynamicObject) As %List [ Final, Internal ]
{
	// GetCompartments segregated here and conditionalized to be able
	// to run on pre- and post- IF-875 code base.
	
	Set compartmentsFound = ""
	
	Try {
		Set isNewParams = pSchema.isNewParams
	} Catch compartmentsEx {
		Set isNewParams = 0
	}
	
	If isNewParams {
		Set compartmentsFound = pSchema.GetCompartmentsForResource(pResourceJson)
	} Else {
		Set compartmentsFound = pSchema.BuildCompartmentList(pResourceJson)
	}
	
	Return compartmentsFound
}

/// Verify that the access token allows the current interaction request based on the resource type,
/// resource id and required privilege. If not allowed, this method will Throw. Otherwise, it will
/// simply Return. Note that despite returning from this call, the corresponding response to the
/// interaction could still fail verification.<br>
/// <br>
/// This method typically used for read, vread or history-instance requests.
Method VerifyResourceIdRequest(
	pResourceType As %String,
	pResourceId As %String,
	pRequiredPrivilege As %String)
{
	If ..%TokenString = "" Return
	
	// CheckExpiredOrInactive will Throw if the current token is expired or inactive.
	Do ..CheckExpiredOrInactive()
	
	// patient context and scopes supersedes user scopes.
	If $Data(..%ClinicalScopes("patient")) {
		
		// No specific check for Patient resource type + resource id here. Reading a
		// Patient resource that is NOT the patient context resource id but IS in
		// the Patient compartment for the patient context resource id is okay.
		// However, we won't know the latter until we actually look at the response.
		
		// No requiredPrivilege access to the requested resource type is definitely a fail.
		If '..HasScope("patient", pResourceType, pRequiredPrivilege) {
			$$$FSLog( ..FSLogScopeMsg( , "patient", pRequiredPrivilege, pResourceType) )
			$$$ThrowFHIR($$$HttpOnlyResponse(403))
		}
		
		Return
		
	} ElseIf $Data(..%ClinicalScopes("user")) {
		
		If '..HasScope("user", pResourceType, pRequiredPrivilege) {
			$$$FSLog( ..FSLogScopeMsg( , "user", pRequiredPrivilege, pResourceType) )
			$$$ThrowFHIR($$$HttpOnlyResponse(403))
		}
	}
	
	Return
}

/// Verify that the access token allows the current interaction on the specified resource, based on
/// the content and required privilege. If not allowed, this method will Throw. Otherwise, it will
/// simply Return.<br>
/// <br>
/// This method typically used for read response, create request, update request, patch request.
Method VerifyResourceContent(
	pResourceJson As %DynamicObject,
	pRequiredPrivilege As %String,
	pAllowSharedResource As %Boolean = 0)
{
	If ..%TokenString = "" Return
	
	// CheckExpiredOrInactive will Throw if the current token is expired or inactive.
	Do ..CheckExpiredOrInactive()
	
	Set resourceType = pResourceJson.resourceType
	Set resourceId = pResourceJson.id
	
	// patient context and scopes supersedes user scopes.
	If $Data(..%ClinicalScopes("patient")) {
		
		// Lack of requiredPrivilege access to the requested resource type is not allowed.
		If '..HasScope("patient", resourceType, pRequiredPrivilege) {
			$$$FSLog( ..FSLogScopeMsg( , "patient", pRequiredPrivilege, resourceType) )
			$$$ThrowFHIR($$$HttpOnlyResponse(403))
		}
		
		// Patient resource that is resource id matching the required context is okay.
		If resourceType = "Patient" {
			If resourceId = ..%ContextValues("patient") {
				Return
			} Else {
				$$$FSLog("Patient resource that does not match patient clinical context is not allowed")
				$$$ThrowFHIR($$$HttpOnlyResponse(403))
			}
		}
		
		If ..%schema.IsSharedResourceType(resourceType) {
			If pAllowSharedResource {
				Return
			} Else {
				$$$FSLog("Request on shared resource when patient clinical context present is not allowed")
				$$$ThrowFHIR($$$HttpOnlyResponse(403))
			}
		}
		
		If '..HasCompartment("patient", ..%ContextValues("patient"), pResourceJson) {
			$$$FSLog("Resource content for request is not in patient clinical scope compartment")
			$$$ThrowFHIR($$$HttpOnlyResponse(403))
		}
		
		Return
		
	} ElseIf $Data(..%ClinicalScopes("user")) {
		
		If '..HasScope("user", resourceType, pRequiredPrivilege) {
			$$$FSLog( ..FSLogScopeMsg( , "user", pRequiredPrivilege, resourceType) )
			$$$ThrowFHIR($$$HttpOnlyResponse(403))
		}
	}
	
	Return
}

/// Verify that the access token allows the history-instance request based on the contents of
/// the interaction response and required privilege. If not allowed, this method will Throw.
/// Otherwise, it will simply Return.
Method VerifyHistoryInstanceResponse(
	pResourceType As %String,
	pResourceJson As %DynamicObject,
	pRequiredPrivilege As %String)
{
	If ..%TokenString = "" Return
	
	// CheckExpiredOrInactive will Throw if the current token is expired or inactive.
	Do ..CheckExpiredOrInactive()
	
	// patient context and scopes supersedes user scopes.
	If $Data(..%ClinicalScopes("patient")) {
		
		If ('$IsObject(pResourceJson)) || ('pResourceJson.%Size()) || (pResourceJson.entry = "") {
			// Nothing found, nothing to unauthorize or forbid.
			Return
		}
		
		// Only check the last (most recent) resource in the Bundle.
		For entryIndex = pResourceJson.entry.%Size()-1:-1:0 {
			Set resourceObj = pResourceJson.entry.%Get(entryIndex).resource
			// It is possible for a history entry to not have a resource.
			If '$IsObject(resourceObj) Continue
			// Could be an OperationOutcomes, skip if it is not the requested resource type.
			If resourceObj.resourceType '= pResourceType Continue
			If '..HasCompartment("patient", ..%ContextValues("patient"), resourceObj) {
				$$$FSLog("history response resource is not in patient clinical scope compartment")
				$$$ThrowFHIR($$$HttpOnlyResponse(403))
			}
		}
		
		Return
		
	} ElseIf $Data(..%ClinicalScopes("user")) {
		
		If '..HasScope("user", pResourceType, pRequiredPrivilege) {
			$$$FSLog( ..FSLogScopeMsg( , "user", pRequiredPrivilege, pResourceType) )
			$$$ThrowFHIR($$$HttpOnlyResponse(403))
		}
	}
	
	Return
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
	Set ..%VerifySearchResults = 0
	
	If ..%TokenString = "" Return
	
	// CheckExpiredOrInactive will Throw if the current token is expired or inactive.
	Do ..CheckExpiredOrInactive()
	
	Set compartmentType = $ZConvert($Extract(pCompartmentResourceType), "L") _ $Extract(pCompartmentResourceType, 2, *)
	
	// verifySearchResultsInclude=1 indicates that post-search verification of
	// the search result set must be done because _include using a reference
	// type with multiple target types was included in the search request.
	Set verifySearchResultsInclude = 0
	
	// patient context and scopes supersedes user scopes.
	If $Data(..%ClinicalScopes("patient")) {
		
		// patient scopes verification:
		// - If the search resource type is not allowed by the scopes, then return 403.
		// - If search by Patient compartment but the resource id is not the patient context,
		//   then return 403.
		// - If chain and/or reverse chain are included, then return 403.
		// - If the search resource type is Patient and a single _id parameter value is present,
		//   or multiple _id parameters but all the same value, then the request is approved.
		// - If the search resource type is not Patient, and a reference search param value is
		//   present that indicates a Patient resource that is NOT the patient context, then
		//   return 403.
		// - If _include or _revinclude are present and do not indicate pulling in resources
		//   that are allowed by the scopes, then return 403.
		// - Otherwise if none of the above applies, then Set ..%VerifySearchResults to 1,
		///  which will trigger a checking of all resources in the eventual search result set.
		
		If '..HasScope("patient", pResourceType, pRequiredPrivilege) {
			$$$FSLog( ..FSLogScopeMsg("Search", "patient", pRequiredPrivilege, pResourceType) )
			$$$ThrowFHIR($$$HttpOnlyResponse(403))
		}
		
		If (pCompartmentResourceType = "Patient") && (pCompartmentResourceId '= ..%ContextValues("patient")) {
			$$$FSLog("Search specified Patient compartment does not match access token patient context")
			$$$ThrowFHIR($$$HttpOnlyResponse(403))
		}
		
		Set PatientByIdParam = ""
		Set PatientSearchParam = ""
		
		For paramIndex = pParameters.Count():-1:1 {
			Set searchQueryParameter = pParameters.GetAt(paramIndex)
			Set paramName = searchQueryParameter.name
			Set paramVal = searchQueryParameter.value
			
			// The only "non search params" evaluated here are _include and _revinclude.
			// Search params are expected to have been vetted by the stack by this point.
			// Therefore, if paramName is not valid for pResourceType, FindSearchParam
			// will Throw, which should be expected.
			If '..%schema.IsNonSearchParam(paramName) {
				Set searchParamObj = ..%schema.FindSearchParam(pResourceType, paramName)
				
			} ElseIf '((paramName = "_include") || (paramName = "_revinclude")) {
				Continue
			}
			
			If paramName = "_id" {
				If pResourceType = "Patient" {
					// Multiple Patient _id parameter values are okay.
					// However, they must all be for the patient context.
					For i = 1:1:$Length(paramVal, ",") {
						Set pvp = $Piece(paramVal, ",", i)
						If pvp '= "" {
							If pvp '= ..%ContextValues("patient") {
								$$$FSLog("Search request specifies Patient _id search parameter value that does not match specified access token patient context")
								$$$ThrowFHIR($$$HttpOnlyResponse(403))
							}
							Set PatientByIdParam = pvp
						}
					}
				}
				
			} ElseIf paramName = "_include" {
				Set clinicalScopeType = "patient"
				Do evaluateInclude
				
			} ElseIf paramName = "_revinclude" {
				If '..HasScope("patient", $Piece(paramVal, ":", 1), pRequiredPrivilege) {
					$$$FSLog( ..FSLogScopeMsg("Search", "patient", pRequiredPrivilege, $Piece(paramVal, ":", 1)) )
					$$$ThrowFHIR($$$HttpOnlyResponse(403))
				}
				
			} ElseIf (searchParamObj.target = $ListBuild("Patient")) ||
					(($ListFind(searchParamObj.target, "Patient")) && ($Extract(paramVal, 1, 8) = "Patient/")) {
				// This assumes that resource version is not specified on the search param value.
				Set patientResourceId = $Select($Extract(paramVal, 1, 8) = "Patient/": $Extract(paramVal, 9, *), 1: paramVal)
				If patientResourceId '= ..%ContextValues("patient") {
					$$$FSLog("Search request patient reference search parameter value does not match specified access token patient context")
					$$$ThrowFHIR($$$HttpOnlyResponse(403))
				}
				Set PatientSearchParam = patientResourceId
				
			} ElseIf searchQueryParameter.nextInChain '= "" {
				// Chain not allowed.
				$$$FSLog("Search request chained parameter not allowed when access token patient context specified")
				$$$ThrowFHIR($$$HttpOnlyResponse(403))
				
			} ElseIf searchQueryParameter.nextInRevChain '= "" {
				// Reverse chain not allowed.
				$$$FSLog("Search request reverse chained parameter not allowed when access token patient context specified")
				$$$ThrowFHIR($$$HttpOnlyResponse(403))
			}
		}
		
		If ((PatientByIdParam = "") && (PatientSearchParam = "")) || (verifySearchResultsInclude) {
			Set ..%VerifySearchResults = 1
		}
		
		$$$FSLog("%VerifySearchResults = " _ ..%VerifySearchResults)
		
		Return
		
	} ElseIf $Data(..%ClinicalScopes("user")) {
		
		// user scopes verification:
		// - search resource type must be allowed by user scope.
		// - If _include or _revinclude are present and do not indicate pulling in resources
		//   that are allowed by the scopes, then return 403.
		
		If '..HasScope("user", pResourceType, pRequiredPrivilege) {
			$$$FSLog( ..FSLogScopeMsg("Search", "user", pRequiredPrivilege, pResourceType) )
			$$$ThrowFHIR($$$HttpOnlyResponse(403))
		}
		
		For paramIndex = pParameters.Count():-1:1 {
			Set searchQueryParameter = pParameters.GetAt(paramIndex)
			Set paramName = searchQueryParameter.name
			Set paramVal = searchQueryParameter.value
			If paramName = "_include" {
				Set clinicalScopeType = "user"
				Do evaluateInclude
				
			} ElseIf paramName = "_revinclude" {
				If '..HasScope("user", $Piece(paramVal, ":", 1), pRequiredPrivilege) {
					$$$FSLog( ..FSLogScopeMsg("Search", "user", pRequiredPrivilege, $Piece(paramVal, ":", 1)) )
					$$$ThrowFHIR($$$HttpOnlyResponse(403))
				}
				
			} ElseIf searchQueryParameter.nextInChain '= "" {
				If '..HasScope("user", searchQueryParameter.modifier, pRequiredPrivilege) {
					$$$FSLog( ..FSLogScopeMsg("Search", "user", pRequiredPrivilege, searchQueryParameter.modifier) )
					$$$ThrowFHIR($$$HttpOnlyResponse(403))
				}
				
			} ElseIf searchQueryParameter.nextInRevChain '= "" {
				If '..HasScope("user", searchQueryParameter.searchParam.resourceType, pRequiredPrivilege) {
					$$$FSLog( ..FSLogScopeMsg("Search", "user", pRequiredPrivilege, searchQueryParameter.searchParam.resourceType) )
					$$$ThrowFHIR($$$HttpOnlyResponse(403))
				}
			}
		}
		
		If verifySearchResultsInclude {
			Set ..%VerifySearchResults = 1
		}
		
		$$$FSLog("%VerifySearchResults = " _ ..%VerifySearchResults)
	}
	
	Return
	
evaluateInclude
	// Piece 2 is the search param name from the current search resource type.
	// target is the target resource type(s) for that search param.
	// Piece 3 is a specific target resource type, for when the search param has multiple targets.
	Set searchParamTarget = ..%schema.FindSearchParam(pResourceType, $Piece(paramVal, ":", 2)).target
	Set specificTargetResourceType = $Piece(paramVal, ":", 3)
	Set listLen = $ListLength(searchParamTarget)
	If (listLen=1) || ((listLen>1) && (specificTargetResourceType '= "")) {
		Set targetResourceType = $Select(listLen=1:$ListGet(searchParamTarget,1), 1:specificTargetResourceType)
		If '..HasScope(clinicalScopeType, targetResourceType, pRequiredPrivilege) {
			$$$FSLog( ..FSLogScopeMsg("Search", clinicalScopeType, pRequiredPrivilege, paramName) )
			$$$ThrowFHIR($$$HttpOnlyResponse(403))
		}
	} Else {
		// If multiple search param targets, then only one needs to qualify.
		// If other non-scoped resource types are obtained during the search
		// process then post-search check per scopes will find unauthorized
		// resource types.
		Set hasOne = 0
		Set listIndex = 0
		While $ListNext(searchParamTarget, listIndex, targetResourceType) {
			If ..HasScope(clinicalScopeType, targetResourceType, pRequiredPrivilege) {
				Set hasOne = 1
				Quit
			}
		}
		If hasOne {
			Set verifySearchResultsInclude = 1
			$$$FSLog( "..%VerifySearchResults = 1 triggered by _include="_paramVal )
		} Else {
			$$$FSLog( ..FSLogScopeMsg("Search", clinicalScopeType, pRequiredPrivilege, paramName) )
			$$$ThrowFHIR($$$HttpOnlyResponse(403))
		}
	}
	Quit
}

/// Verify that the access token allows the system-level request. This is for system-history and
/// system-search. Default functionality is to ignore patient context, and require user/*.read
/// and/or user/*.*<br>
/// If not allowed, this method will Throw. Otherwise, it will simply Return.
Method VerifySystemLevelRequest()
{
	If ..%TokenString = "" Return
	
	// CheckExpiredOrInactive will Throw if the current token is expired or inactive.
	Do ..CheckExpiredOrInactive()
	
	Set hasScope = 0
	
	// Must have user/*.read or user/*.*
	
	// patient scopes are not applicable.
	
	For i = 1:1 {
		Kill userScope
		Merge userScope = ..%ClinicalScopes("user", i)
		If '$Data(userScope) Quit
		If (userScope("resourceType") = "*") && ((userScope("readWrite") = "*") || (userScope("readWrite") = "read")) {
			Set hasScope = 1
			Quit
		}
	}
	
	If 'hasScope {
		$$$FSLog("System-level request access token does not have user/*.read or user/*.* scope")
		$$$ThrowFHIR($$$HttpOnlyResponse(403))
	}
	
	Return
}

Method VerifyEverythingRequest(
	pResourceType As %String,
	pResourceId As %String,
	pResourceJson As %DynamicObject)
{
	If ..%TokenString = "" Return
	
	// CheckExpiredOrInactive will Throw if the current token is expired or inactive.
	Do ..CheckExpiredOrInactive()
	
	Set requiredPrivilege = "read"
	
	// patient context and scopes supersedes user scopes.
	If $Data(..%ClinicalScopes("patient")) {
		
		// Any $everything needs to have read access to all resource types.
		Set ok = 0
		Set N = ""
		For {
			Set N = $Order(..%ClinicalScopes("patient", N))
			If N="" Quit
			If (..%ClinicalScopes("patient", N, "resourceType") = "*") {
				If (..%ClinicalScopes("patient", N, "readWrite") = "*") || (..%ClinicalScopes("patient", N, "readWrite") = requiredPrivilege) {
					Set ok = 1
				}
			}
		}
		If 'ok {
			$$$FSLog("Patient $everything request access token does not have required patient read scope for all resource types")
			$$$ThrowFHIR($$$HttpOnlyResponse(403))
		}
		
		If (pResourceType = "Patient") && (pResourceId '= ..%ContextValues("patient")) {
			$$$FSLog(pResourceType _ " $everything request resource id does not match access token patient context value")
			$$$ThrowFHIR($$$HttpOnlyResponse(403))
		}
		
		If (pResourceType = "Encounter") && ('..HasCompartment("patient", ..%ContextValues("patient"), pResourceJson)) {
			$$$FSLog("Resource content for Encounter $everything request is not in patient clinical scope compartment")
			$$$ThrowFHIR($$$HttpOnlyResponse(403))
		}
		
		Return
		
	} ElseIf $Data(..%ClinicalScopes("user")) {
		
		// Any $everything needs to have read access to all resource types.
		Set ok = 0
		Set N = ""
		For {
			Set N = $Order(..%ClinicalScopes("user", N))
			If N="" Quit
			If (..%ClinicalScopes("user", N, "resourceType") = "*") {
				If (..%ClinicalScopes("user", N, "readWrite") = "*") || (..%ClinicalScopes("user", N, "readWrite") = requiredPrivilege) {
					Set ok = 1
				}
			}
		}
		If 'ok {
			$$$FSLog(pResourceType _ " $everything request access token does not have required user read scope for all resource types")
			$$$ThrowFHIR($$$HttpOnlyResponse(403))
		}
	}
	
	Return
}

/// Verify that the access token scopes authorize the specified privilege
/// on ALL the resource types in the specified list.
Method VerifyTypesList(
	pResourceTypesList As %List,
	pRequiredPrivilege As %String)
{
	If pResourceTypesList = "" Return
	
	If ..%TokenString = "" Return
	
	// CheckExpiredOrInactive will Throw if the current token is expired or inactive.
	Do ..CheckExpiredOrInactive()
	
	For clinicalScopeName = "patient", "user" {
		
		If $Data(..%ClinicalScopes(clinicalScopeName)) {
			
			Set listIndex = 0
			While $ListNext(pResourceTypesList, listIndex, resourceType) {
				If '..HasScope(clinicalScopeName, resourceType, pRequiredPrivilege) {
					$$$FSLog("$everything request access token does not have required " _ clinicalScopeName _ " read scope for all specified resource types")
					$$$ThrowFHIR($$$HttpOnlyResponse(403))
				}
			}
			
			// Check patient or user, not both.
			Quit
		}
	}
	
	Return
}

ClassMethod FSLogScopeMsg(
	pInteraction As %String = "",
	pClinicalScopeType As %String,
	pRequiredPrivilege As %String,
	pResourceType As %String = "") As %String
{
	Set msg = ""
	
	If pInteraction '= "" {
		Set msg = msg _ pInteraction _ " request"
	} Else {
		Set msg = msg _ "Request"
	}
	
	Set msg = msg _ " access token does not have required " _ pClinicalScopeType _ " clinical scope " _ pRequiredPrivilege _ " access to"
	
	If pResourceType '= "" {
		Set msg = msg _ " " _ pResourceType
	}
	
	Set msg = msg _ " resource type"
	
	Return msg
}

}
