Include HS.FHIRServer

Class FHIR.Python.Setup Extends %RegisteredObject
{

ClassMethod PublishDefinition(endpoint As %String, assetsPath As %String = "/irisdev/app/iris_fhir_python_strategy/fhir")
{
    If '##class(HS.FHIRServer.ServiceInstance).ExistsByUrl(endpoint) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "FHIR endpoint does not exist: " _ endpoint))
    }
    Set instance = ##class(HS.FHIRServer.ServiceInstance).FindByUrl(endpoint)
    If (instance.strategyClass '= "FHIR.Python.InteractionsStrategy") || 'instance.isEnabled {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "Endpoint must be enabled and use FHIR.Python.InteractionsStrategy"))
    }
    Set service = ##class(HS.FHIRServer.Service).EnsureInstance(endpoint)
    Set metadata = service.strategy.GetMetadataResource()
    Set version = $Extract(metadata.fhirVersion)
    If (version '= "4") && (version '= "5") {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "No Patient merge definition for FHIR version " _ metadata.fhirVersion))
    }
    Set file = ##class(%Stream.FileCharacter).%New()
    $$$ThrowOnError(file.LinkToFile(assetsPath _ "/R" _ version _ "/Patient-merge.OperationDefinition.json"))
    Set definition = {}.%FromJSON(file)
    Set existing = service.interactions.FindResourceObject("OperationDefinition", definition.id)
    If $IsObject(existing) {
        Do existing.%Remove("meta")
        If ##class(FHIR.Python.PatientMerge).Canonical(existing) = ##class(FHIR.Python.PatientMerge).Canonical(definition) {
            Do service.interactions.SetMetadata(metadata)
            Return
        }
    }
    Set request = ##class(HS.FHIRServer.API.Data.Request).%New()
    Set request.SessionApplication = endpoint
    Set request.BaseURL = "http://localhost:52773" _ endpoint, request.LocalBaseURL = request.BaseURL
    Set request.RequestMethod = "PUT", request.Type = "OperationDefinition", request.Id = definition.id
    Set request.RequestPath = "/OperationDefinition/" _ definition.id, request.Interaction = "update"
    Set request.Parameters = ##class(HS.FHIRServer.API.Data.QueryParameters).%New()
    Set request.Json = definition
    Do service.DispatchRequest(request, .response)
    If (+response.Status '= 200) && (+response.Status '= 201) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "OperationDefinition publication failed: " _ response.Json.%ToJSON()))
    }
    Do service.interactions.SetMetadata(service.strategy.GetMetadataResource())
}

}
