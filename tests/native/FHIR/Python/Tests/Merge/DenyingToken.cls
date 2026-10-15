Include HS.FHIRServer

Class FHIR.Python.Tests.Merge.DenyingToken Extends HS.FHIRServer.Util.OAuth2Token
{

Property DeniedPermission As %String [ InitialExpression = "u" ];

Property DeniedType As %String;

Method VerifyResourceContent(pResourceJson As %DynamicObject, pRequiredPermission As %String, pAllowSharedResource As %Boolean = 0)
{
    If (pRequiredPermission = ..DeniedPermission) &&
        ((..DeniedType = "") || (pResourceJson.resourceType = ..DeniedType)) {
        $$$ThrowFHIR($$$GeneralError, "Test authorization denied", $$$OutcomeIs(403, "error", "forbidden"))
    }
    Do ##super(pResourceJson, pRequiredPermission, pAllowSharedResource)
}

}
