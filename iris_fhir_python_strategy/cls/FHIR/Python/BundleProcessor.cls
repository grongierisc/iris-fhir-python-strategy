Include HS.FHIRServer

Class FHIR.Python.BundleProcessor Extends HS.FHIRServer.Storage.Json.BundleProcessor
{

Parameter BundleValidatorClass = "FHIR.Python.BundleValidator";

ClassMethod IsFHIRPathPatch(pEntry As %DynamicObject) As %Boolean
{
    Return pEntry.%IsA("%DynamicObject") && $IsObject(pEntry.request) && pEntry.request.%IsA("%DynamicObject") && (pEntry.request.method = "PATCH") && $IsObject(pEntry.resource) && pEntry.resource.%IsA("%DynamicObject") && (pEntry.resource.resourceType = "Parameters")
}

ClassMethod ValidationEntry(pEntry As %DynamicObject) As %DynamicObject
{
    Set entry = {}.%FromJSON(pEntry.%ToJSON())
    Set entry.resource = {"resourceType":"Binary","contentType":"application/json-patch+json","data":"W10="}
    Return entry
}

ClassMethod BuildDependencyCallback(ByRef visitContext, pRefObj As %DynamicObject)
{
    Set entryId = visitContext("visiting")
    If ..IsFHIRPathPatch(visitContext("entry",entryId)), pRefObj.reference [ "?" {
        // Parameters are not stored; exclude them from native conditional-reference reposting.
        Set patchContext("schema") = visitContext("schema")
        Set patchContext("visiting") = entryId, patchContext("entry",entryId) = visitContext("entry",entryId)
        Set patchContext("_va","curPropName") = visitContext("_va","curPropName")
        Merge patchContext("ConditionalRef") = visitContext("PatchConditional",entryId)
        Do ##super(.patchContext, pRefObj)
        Merge visitContext("PatchConditional",entryId) = patchContext("ConditionalRef")
        Return
    }
    Do ##super(.visitContext, pRefObj)
}

ClassMethod prepareRequest(pService As HS.FHIRServer.API.Service, pTransRequest As HS.FHIRServer.API.Data.Request, ByRef visitContext, entryObj As %DynamicObject) As HS.FHIRServer.API.Data.Request
{
    If '..IsFHIRPathPatch(entryObj) {
        Return ##super(pService, pTransRequest, .visitContext, entryObj)
    }
    If pTransRequest.Json.type = "transaction" {
        Set entryId = ""
        For {
            Set entryId = $Order(visitContext("PatchConditional",entryId))
            Quit:(entryId = "")
            If visitContext("entry",entryId) = entryObj {
                Set patchContext("schema") = pService.Schema
                Merge patchContext("_va") = visitContext("_va")
                Merge patchContext("ConditionalRef") = visitContext("PatchConditional",entryId)
                Do ..ResolveConditionalReferences(pService, .patchContext)
                Kill visitContext("PatchConditional",entryId)
                Quit
            }
        }
    }
    Set request = ##super(pService, pTransRequest, .visitContext, ..ValidationEntry(entryObj))
    Set request.Json = entryObj.resource
    Set request.RequestFormatCode = $$$FHIRContentCodeJPatch
    Return request
}

}
