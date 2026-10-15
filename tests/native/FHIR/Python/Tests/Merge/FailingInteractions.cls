Include HS.FHIRServer

Class FHIR.Python.Tests.Merge.FailingInteractions Extends FHIR.Python.Interactions
{

Property FailAfter As %Integer;

Property Updates As %Integer;

Property TestToken As HS.FHIRServer.API.OAuth2Token;

Property FailDiscovery As %Boolean;

Method Search(pResourceType As %String, pCompartment As %String, pCompartmentId As %String, pParameters As HS.FHIRServer.API.Data.QueryParameters = "", ByRef pSortKeys = "") As HS.FHIRServer.Util.SearchResult
{
    If ..FailDiscovery {
        $$$ThrowFHIR($$$GeneralError, "Injected native discovery failure", $$$OutcomeIs(500, "error", "exception"))
    }
    Return ##super(pResourceType, pCompartment, pCompartmentId, pParameters, .pSortKeys)
}

Method oauth2TokenHandlerGet() As HS.FHIRServer.API.OAuth2Token
{
    If $IsObject(..TestToken) {
        Return ..TestToken
    }
    Return ##super()
}

Method Update(pResourceObj As %DynamicObject) As %String
{
    Set ..Updates = ..Updates + 1
    If ..FailAfter && (..Updates = ..FailAfter) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "Injected merge write failure"))
    }
    Return ##super(pResourceObj)
}

}
