Include (%occStatus, HS.FHIRServer)

Class FHIR.Python.Tests.Patch.BundleIntegration Extends %UnitTest.TestCase
{

Property Service As HS.FHIRServer.Service;

Property Prefix As %String;

Property CreatedPaths As %DynamicArray;

Method OnBeforeAllTests() As %Status
{
    Set id = ..Manager.UserParam
    If id = "" {
        Return $$$ERROR($$$GeneralError, "Pass the isolated test service ID as RunTest's third argument")
    }
    Set instance = ##class(HS.FHIRServer.ServiceInstance).GetById(id)
    If (instance.cspUrl '= "") || (instance.parentRepo.strategyClass '= "FHIR.Python.InteractionsStrategy") {
        Return $$$ERROR($$$GeneralError, "Integration tests require an isolated, non-HTTP BundlePatch repository")
    }
    Set ..Service = ##class(HS.FHIRServer.Service).%New(id)
    Do ..Service.Configure(instance)
    Return $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set ..Prefix = "bp-"_$ZConvert($Translate($System.Util.CreateGUID(),"{}"),"L")
    Set ..CreatedPaths = []
    Return $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    For index = 0:1:..CreatedPaths.%Size()-1 {
        Set response = ..Request("DELETE", ..CreatedPaths.%Get(index))
        If (+response.Status '= 204) && (+response.Status '= 404) {
            Return $$$ERROR($$$GeneralError, "Unable to delete test resource: "_response.Status)
        }
    }
    Return $$$OK
}

Method Request(pMethod As %String, pPath As %String, pJson = "", pQuery As %String = "", pIfMatch As %String = "") As HS.FHIRServer.API.Data.Response
{
    Set request = ##class(HS.FHIRServer.API.Data.Request).%New()
    Set request.RequestMethod = pMethod, request.RequestPath = "/"_pPath
    Set request.RequestFormatCode = $$$FHIRContentCodeJSON, request.ResponseFormatCode = $$$FHIRContentCodeJSON
    Set request.Json = pJson, request.QueryString = pQuery, request.IfMatch = pIfMatch
    Set request.Prefer = "return=representation"
    Set request.BaseURL = "http://example.test/fhir", request.LocalBaseURL = request.BaseURL
    Do ..Service.DispatchRequest(request, .response)
    Return response
}

Method Create(pSuffix As %String = "", pIdentifier As %String = "") As %String
{
    Set id = ..Prefix_pSuffix
    Do ..CreatedPaths.%Push("Patient/"_id)
    Set resource = {"resourceType":"Patient","id":(id),"active":false}
    If pIdentifier '= "" {
        Set resource.identifier = [{"system":"urn:bundlepatch:test","value":(pIdentifier)}]
    }
    Set response = ..Request("PUT", "Patient/"_id, resource)
    Do $$$AssertEquals(+response.Status, 201)
    Return id
}

Method Patch(pPath As %String = "Patient.active", pValue As %Boolean = 1) As %DynamicObject
{
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"replace"},{"name":"path","valueString":(pPath)},{"name":"value","valueBoolean":true}]}]}
    Do patch.parameter.%Get(0).part.%Get(2).%Set("valueBoolean", pValue, "boolean")
    Return patch
}

Method TestTransactionSuccessAndOrder()
{
    Set id = ..Create(), secondId = ..Prefix_"-put"
    Do ..CreatedPaths.%Push("Patient/"_secondId)
    Set bundle = {"resourceType":"Bundle","type":"transaction","entry":[
        {"request":{"method":"PATCH","url":("Patient/"_id)},"resource":(..Patch())},
        {"request":{"method":"PUT","url":("Patient/"_secondId)},"resource":{"resourceType":"Patient","id":(secondId),"active":true}}
    ]}
    Set response = ..Request("POST", "", bundle)
    Do $$$AssertEquals(+response.Status, 200)
    Do $$$AssertEquals(response.Json.type, "transaction-response")
    Do $$$AssertEquals(response.Json.entry.%Size(), 2)
    Do $$$AssertEquals(+response.Json.entry.%Get(0).response.status, 200)
    Do $$$AssertEquals(+response.Json.entry.%Get(1).response.status, 201)
    Do $$$AssertEquals(response.Json.entry.%Get(0).resource.active, 1)
    Do $$$AssertTrue(response.Json.entry.%Get(0).response.etag '= "")
    Set read = ..Request("GET", "Patient/"_id)
    Do $$$AssertEquals(read.Json.active, 1)
    Do $$$AssertEquals(read.Json.meta.versionId, 2)
    Set history = ..Request("GET", "Patient/"_id_"/_history")
    Do $$$AssertEquals(+history.Status, 200)
    Do $$$AssertEquals(history.Json.entry.%Size(), 2)
}

Method TestTransactionRollback()
{
    Set id = ..Create(), secondId = ..Prefix_"-rollback"
    Do ..CreatedPaths.%Push("Patient/"_secondId)
    Set bundle = {"resourceType":"Bundle","type":"transaction","entry":[
        {"request":{"method":"PUT","url":("Patient/"_secondId)},"resource":{"resourceType":"Patient","id":(secondId)}},
        {"request":{"method":"PATCH","url":("Patient/"_id)},"resource":(..Patch())},
        {"request":{"method":"PATCH","url":("Patient/"_id)},"resource":(..Patch("Patient.birthDate"))}
    ]}
    Set response = ..Request("POST", "", bundle)
    Do $$$AssertEquals(+response.Status, 400)
    Do $$$AssertEquals(response.Json.resourceType, "OperationOutcome")
    Set read = ..Request("GET", "Patient/"_id)
    Do $$$AssertEquals(read.Json.active, 0)
    Do $$$AssertEquals(read.Json.meta.versionId, 1)
    Set read = ..Request("GET", "Patient/"_secondId)
    Do $$$AssertEquals(+read.Status, 404)
}

Method TestBatchIsolation()
{
    Set id = ..Create(), other = ..Create("-other")
    Set failedPatch = ..Patch()
    Do failedPatch.parameter.%Push(..Patch("Patient.birthDate").parameter.%Get(0))
    Set bundle = {"resourceType":"Bundle","type":"batch","entry":[
        {"request":{"method":"PATCH","url":("Patient/"_other)},"resource":(failedPatch)},
        {"request":{"method":"PATCH","url":("Patient/"_id)},"resource":(..Patch())}
    ]}
    Set response = ..Request("POST", "", bundle)
    Do $$$AssertEquals(+response.Status, 200)
    Do $$$AssertEquals(response.Json.type, "batch-response")
    Do $$$AssertEquals(+response.Json.entry.%Get(0).response.status, 400)
    Do $$$AssertEquals(response.Json.entry.%Get(0).response.outcome.resourceType, "OperationOutcome")
    Do $$$AssertEquals(+response.Json.entry.%Get(1).response.status, 200)
    Set read = ..Request("GET", "Patient/"_other)
    Do $$$AssertEquals(read.Json.active, 0)
    Do $$$AssertEquals(read.Json.meta.versionId, 1)
    Set read = ..Request("GET", "Patient/"_id)
    Do $$$AssertEquals(read.Json.active, 1)
}

Method TestIfMatch()
{
    Set id = ..Create()
    Set bundle = {"resourceType":"Bundle","type":"batch","entry":[
        {"request":{"method":"PATCH","url":("Patient/"_id),"ifMatch":"W/\"99\""},"resource":(..Patch())},
        {"request":{"method":"PATCH","url":("Patient/"_id),"ifMatch":"W/\"1\""},"resource":(..Patch())}
    ]}
    Set response = ..Request("POST", "", bundle)
    Do $$$AssertEquals(+response.Status, 200)
    Do $$$AssertEquals(+response.Json.entry.%Get(0).response.status, 412)
    Do $$$AssertEquals(+response.Json.entry.%Get(1).response.status, 200)
    Set read = ..Request("GET", "Patient/"_id)
    Do $$$AssertEquals(read.Json.meta.versionId, 2)
}

Method TestConditionalMatching()
{
    Set id = ..Create("", ..Prefix), ambiguous = ..Prefix_"-ambiguous"
    Set other = ..Create("-one", ambiguous), third = ..Create("-two", ambiguous)
    Set bundle = {"resourceType":"Bundle","type":"batch","entry":[
        {"request":{"method":"PATCH","url":("Patient?identifier=urn:bundlepatch:test|"_..Prefix)},"resource":(..Patch())},
        {"request":{"method":"PATCH","url":("Patient?identifier=urn:bundlepatch:test|"_..Prefix_"-missing")},"resource":(..Patch())},
        {"request":{"method":"PATCH","url":("Patient?identifier=urn:bundlepatch:test|"_ambiguous)},"resource":(..Patch())}
    ]}
    Set response = ..Request("POST", "", bundle)
    Do $$$AssertEquals(+response.Status, 200)
    Do $$$AssertEquals(+response.Json.entry.%Get(0).response.status, 200)
    Do $$$AssertEquals(+response.Json.entry.%Get(1).response.status, 404)
    Do $$$AssertEquals(+response.Json.entry.%Get(2).response.status, 412)
    Set read = ..Request("GET", "Patient/"_id)
    Do $$$AssertEquals(read.Json.active, 1)
}

Method TestBinaryAndDirectJSONPatch()
{
    Set id = ..Create()
    Set bundle = {"resourceType":"Bundle","type":"transaction","entry":[
        {"request":{"method":"PATCH","url":("Patient/"_id)},"resource":{"resourceType":"Binary","contentType":"application/json-patch+json","data":"W3sib3AiOiJyZXBsYWNlIiwicGF0aCI6Ii9hY3RpdmUiLCJ2YWx1ZSI6dHJ1ZX1d"}}
    ]}
    Set response = ..Request("POST", "", bundle)
    Do $$$AssertEquals(+response.Status, 200)
    Do $$$AssertEquals(response.Json.entry.%Get(0).resource.active, 1)
    Set request = ##class(HS.FHIRServer.API.Data.Request).%New()
    Set request.RequestMethod = "PATCH", request.RequestPath = "/Patient/"_id
    Set request.RequestFormatCode = $$$FHIRContentCodeJPatch, request.ResponseFormatCode = $$$FHIRContentCodeJSON
    Set request.Json = [{"op":"replace","path":"/active","value":false}]
    Do ..Service.DispatchRequest(request, .response)
    Do $$$AssertEquals(+response.Status, 200)
    Set read = ..Request("GET", "Patient/"_id)
    Do $$$AssertEquals(read.Json.active, 0)
}

Method TestMixedReferences()
{
    Set id = ..Prefix, fullUrl = "urn:uuid:"_$Extract(..Prefix,4,*)
    Do ..CreatedPaths.%Push("Observation/"_id)
    Set response = ..Request("PUT", "Observation/"_id, {"resourceType":"Observation","id":(id),"status":"final","code":{"text":"Bundle reference test"}})
    Do $$$AssertEquals(+response.Status, 201)
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"add"},{"name":"path","valueString":"Observation"},{"name":"name","valueString":"subject"},{"name":"value","valueReference":{"reference":(fullUrl)}}]}]}
    Set bundle = {"resourceType":"Bundle","type":"transaction","entry":[
        {"request":{"method":"PATCH","url":("Observation/"_id)},"resource":(patch)},
        {"fullUrl":(fullUrl),"request":{"method":"POST","url":"Patient"},"resource":{"resourceType":"Patient","active":true}}
    ]}
    Set response = ..Request("POST", "", bundle)
    If +response.Status '= 200 {
        Do $$$LogMessage(response.Json.%ToJSON())
    }
    Do $$$AssertEquals(+response.Status, 200)
    Do $$$AssertEquals(+response.Json.entry.%Get(0).response.status, 200)
    Do $$$AssertEquals(+response.Json.entry.%Get(1).response.status, 201)
    Set patientId = response.Json.entry.%Get(1).resource.id
    Do ..CreatedPaths.%Push("Patient/"_patientId)
    Set read = ..Request("GET", "Observation/"_id)
    Do $$$AssertEquals(read.Json.subject.reference, "Patient/"_patientId)
}

Method TestMalformedPathReturnsOutcome()
{
    Set id = ..Create()
    Set bundle = {"resourceType":"Bundle","type":"batch","entry":[
        {"request":{"method":"PATCH","url":("Patient/"_id)},"resource":(..Patch("Patient.["))}
    ]}
    Set response = ..Request("POST", "", bundle)
    Do $$$AssertEquals(+response.Status, 200)
    Do $$$AssertEquals(+response.Json.entry.%Get(0).response.status, 400)
    Do $$$AssertEquals(response.Json.entry.%Get(0).response.outcome.resourceType, "OperationOutcome")
    Set read = ..Request("GET", "Patient/"_id)
    Do $$$AssertEquals(read.Json.meta.versionId, 1)
}

Method TestConditionalReference()
{
    Set patientId = ..Create("", ..Prefix), id = ..Prefix_"-obs"
    Do ..CreatedPaths.%Push("Observation/"_id)
    Set response = ..Request("PUT", "Observation/"_id, {"resourceType":"Observation","id":(id),"status":"final","code":{"text":"Conditional reference test"}})
    Do $$$AssertEquals(+response.Status, 201)
    Set reference = "Patient?identifier=urn:bundlepatch:test|"_..Prefix
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"add"},{"name":"path","valueString":"Observation"},{"name":"name","valueString":"subject"},{"name":"value","valueReference":{"reference":(reference)}}]}]}
    Set bundle = {"resourceType":"Bundle","type":"transaction","entry":[{"request":{"method":"PATCH","url":("Observation/"_id)},"resource":(patch)}]}
    Set response = ..Request("POST", "", bundle)
    Do $$$AssertEquals(+response.Status, 200)
    Set read = ..Request("GET", "Observation/"_id)
    Do $$$AssertEquals(read.Json.subject.reference, "Patient/"_patientId)
    Do $$$AssertEquals(read.Json.meta.versionId, 2)
    Set rolledId = ..Prefix_"-rolled"
    Do ..CreatedPaths.%Push("Patient/"_rolledId)
    Set patch.parameter.%Get(0).part.%Get(0).valueCode = "replace"
    Do patch.parameter.%Get(0).part.%Remove(2)
    Set patch.parameter.%Get(0).part.%Get(2).valueReference.reference = reference_"-missing"
    Set bundle = {"resourceType":"Bundle","type":"transaction","entry":[
        {"request":{"method":"PUT","url":("Patient/"_rolledId)},"resource":{"resourceType":"Patient","id":(rolledId)}},
        {"request":{"method":"PATCH","url":("Observation/"_id)},"resource":(patch)}
    ]}
    Set response = ..Request("POST", "", bundle)
    Do $$$AssertEquals(+response.Status, 400)
    Set read = ..Request("GET", "Patient/"_rolledId)
    Do $$$AssertEquals(+read.Status, 404)
    Set read = ..Request("GET", "Observation/"_id)
    Do $$$AssertEquals(read.Json.meta.versionId, 2)
}

}
