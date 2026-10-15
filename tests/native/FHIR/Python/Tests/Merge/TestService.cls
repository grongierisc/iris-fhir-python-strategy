Class FHIR.Python.Tests.Merge.TestService Extends HS.FHIRServer.Service
{

Property FaultInteractions As FHIR.Python.Tests.Merge.FailingInteractions;

Method interactionsGet() As HS.FHIRServer.API.Interactions
{
    If $IsObject(..FaultInteractions) {
        Return ..FaultInteractions
    }
    Return ##super()
}

}
