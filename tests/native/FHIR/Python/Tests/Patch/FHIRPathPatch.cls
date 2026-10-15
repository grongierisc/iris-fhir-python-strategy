Include %occStatus

Class FHIR.Python.Tests.Patch.FHIRPathPatch Extends %UnitTest.TestCase
{

Property Schema As HS.FHIRServer.Schema;

Property Interactions As FHIR.Python.Tests.Patch.PatchInteractions;

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set ..Schema = ##class(HS.FHIRServer.Schema).LoadSchema($ListBuild("hl7.fhir.r4.core@4.0.1"))
    Set ..Interactions = ##class(FHIR.Python.Tests.Patch.PatchInteractions).%New()
    Return $$$OK
}

Method Apply(pResource As %DynamicObject, pParameters As %DynamicObject) As %Boolean
{
    Return ##class(FHIR.Python.FHIRPathPatch).Apply(pParameters, pResource, ..Schema, ..Interactions)
}

Method TestReplaceFilteredDuplicate()
{
    Set resource = {"resourceType":"Patient","name":[{"use":"usual","given":["Same","Same"]},{"use":"official","given":["Same","Same"]}]}
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"replace"},{"name":"path","valueString":"Patient.name.where(use = 'official').given[1]"},{"name":"value","valueString":"Changed"}]}]}
    Do $$$AssertTrue(..Apply(resource, patch))
    Do $$$AssertEquals(resource.name.%Get(0).given.%Get(1), "Same")
    Do $$$AssertEquals(resource.name.%Get(1).given.%Get(0), "Same")
    Do $$$AssertEquals(resource.name.%Get(1).given.%Get(1), "Changed")
}

Method TestAllOperationsSequentially()
{
    Set resource = {"resourceType":"Patient","name":[{"given":["A","C"]}]}
    Set patch = {"resourceType":"Parameters","parameter":[
        {"name":"operation","part":[{"name":"type","valueCode":"add"},{"name":"path","valueString":"Patient"},{"name":"name","valueString":"active"},{"name":"value","valueBoolean":false}]},
        {"name":"operation","part":[{"name":"type","valueCode":"insert"},{"name":"path","valueString":"Patient.name.given"},{"name":"index","valueInteger":1},{"name":"value","valueString":"B"}]},
        {"name":"operation","part":[{"name":"type","valueCode":"move"},{"name":"path","valueString":"Patient.name.given"},{"name":"source","valueInteger":2},{"name":"destination","valueInteger":0}]},
        {"name":"operation","part":[{"name":"type","valueCode":"replace"},{"name":"path","valueString":"Patient.name.given[1]"},{"name":"value","valueString":"Z"}]},
        {"name":"operation","part":[{"name":"type","valueCode":"delete"},{"name":"path","valueString":"Patient.name.given[2]"}]}
    ]}
    Do $$$AssertTrue(..Apply(resource, patch))
    Do $$$AssertEquals(resource.%GetTypeOf("active"), "boolean")
    Do $$$AssertEquals(resource.active, 0)
    Do $$$AssertEquals(resource.name.%Get(0).given.%ToJSON(), "[""C"",""Z""]")
}

Method TestAnonymousAndChoiceValues()
{
    Set resource = {"resourceType":"Observation","status":"final","code":{"text":"test"}}
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"add"},{"name":"path","valueString":"Observation"},{"name":"name","valueString":"value"},{"name":"value","valueQuantity":{"value":0,"unit":"mg"}}]}]}
    Do $$$AssertTrue(..Apply(resource, patch))
    Do $$$AssertEquals(resource.valueQuantity.value, 0)
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"replace"},{"name":"path","valueString":"Observation.value"},{"name":"value","valueString":"negative"}]}]}
    Do $$$AssertTrue(..Apply(resource, patch))
    Do $$$AssertTrue('resource.%IsDefined("valueQuantity"))
    Do $$$AssertEquals(resource.valueString, "negative")
    Set resource = {"resourceType":"Patient"}
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"add"},{"name":"path","valueString":"Patient"},{"name":"name","valueString":"name"},{"name":"value","part":[{"name":"family","valueString":"Smith"},{"name":"given","valueString":"Ann"},{"name":"given","valueString":"Marie"}]}]}]}
    Do $$$AssertTrue(..Apply(resource, patch))
    Do $$$AssertEquals(resource.name.%Get(0).family, "Smith")
    Do $$$AssertEquals(resource.name.%Get(0).given.%Size(), 2)
}

Method TestDeleteAbsentIsNoOp()
{
    Set resource = {"resourceType":"Patient"}
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"delete"},{"name":"path","valueString":"Patient.birthDate"}]}]}
    Do $$$AssertTrue('..Apply(resource, patch))
}

Method AssertInvalid(pResource As %DynamicObject, pPatch As %DynamicObject)
{
    Set caught = 0
    Try {
        Do ..Apply(pResource, pPatch)
    } Catch ex {
        Set caught = 1
        Do $$$AssertTrue(ex.%IsA("%Exception.StatusException"), ex.DisplayString())
    }
    Do $$$AssertTrue(caught, "Invalid patch must throw a FHIR exception")
}

Method TestInvalidPathsAndParts()
{
    Set resource = {"resourceType":"Patient","name":[{"given":["A","B"]}]}
    Do ..AssertInvalid(resource, {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"replace"},{"name":"path","valueString":"Patient.name.given"},{"name":"value","valueString":"X"}]}]})
    Do ..AssertInvalid(resource, {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"replace"},{"name":"path","valueString":"Patient.name.given.count()"},{"name":"value","valueInteger":1}]}]})
    Do ..AssertInvalid(resource, {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"insert"},{"name":"path","valueString":"Patient.name.given"},{"name":"index","valueInteger":-1},{"name":"value","valueString":"X"}]}]})
    Do ..AssertInvalid(resource, {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"add"},{"name":"path","valueString":"Patient"},{"name":"name","valueString":"active"},{"name":"value","valueString":"true"}]}]})
    Do ..AssertInvalid(resource, {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"delete"},{"name":"type","valueCode":"delete"},{"name":"path","valueString":"Patient"}]}]})
}

Method TestNativeJSONPatchUnchanged()
{
    Set resource = {"resourceType":"Patient","active":false}
    Do $$$AssertTrue(..Interactions.JSONPatch([{"op":"replace","path":"/active","value":true}], resource))
    Do $$$AssertEquals(resource.active, 1)
}

Method TestEmptyArrayAndMoveNoOp()
{
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"insert"},{"name":"path","valueString":"Patient.name.given"},{"name":"index","valueInteger":0},{"name":"value","valueString":"A"}]}]}
    Set resource = {"resourceType":"Patient","name":[{"given":[]}]}
    Do $$$AssertTrue(..Apply(resource, patch))
    Do $$$AssertEquals(resource.name.%Get(0).given.%ToJSON(), "[""A""]")
    Set resource = {"resourceType":"Patient","name":[{}]}
    Do $$$AssertTrue(..Apply(resource, patch))
    Do $$$AssertEquals(resource.name.%Get(0).given.%ToJSON(), "[""A""]")
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"move"},{"name":"path","valueString":"Patient.name.given"},{"name":"source","valueInteger":0},{"name":"destination","valueInteger":0}]}]}
    Do $$$AssertTrue('..Apply(resource, patch))
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"insert"},{"name":"path","valueString":"Patient.name.given.where($this = 'missing')"},{"name":"index","valueInteger":0},{"name":"value","valueString":"B"}]}]}
    Do ..AssertInvalid(resource, patch)
}

Method TestPrimitiveMetadataAlignment()
{
    Set resource = {"resourceType":"Patient","name":[{"given":["A","B","C"],"_given":[{"id":"a"},null,{"id":"c"}]}]}
    Set patch = {"resourceType":"Parameters","parameter":[
        {"name":"operation","part":[{"name":"type","valueCode":"insert"},{"name":"path","valueString":"Patient.name.given"},{"name":"index","valueInteger":1},{"name":"value","valueString":"X","_valueString":{"id":"x"}}]},
        {"name":"operation","part":[{"name":"type","valueCode":"move"},{"name":"path","valueString":"Patient.name.given"},{"name":"source","valueInteger":3},{"name":"destination","valueInteger":0}]},
        {"name":"operation","part":[{"name":"type","valueCode":"replace"},{"name":"path","valueString":"Patient.name.given[1]"},{"name":"value","valueString":"Z"}]},
        {"name":"operation","part":[{"name":"type","valueCode":"delete"},{"name":"path","valueString":"Patient.name.given[3]"}]}
    ]}
    Do $$$AssertTrue(..Apply(resource, patch))
    Do $$$AssertEquals(resource.name.%Get(0).given.%ToJSON(), "[""C"",""Z"",""X""]")
    Do $$$AssertEquals(resource.name.%Get(0).%Get("_given").%ToJSON(), "[{""id"":""c""},null,{""id"":""x""}]")
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"move"},{"name":"path","valueString":"Patient.name.given"},{"name":"source","valueInteger":0},{"name":"destination","valueInteger":2}]}]}
    Do $$$AssertTrue(..Apply(resource, patch))
    Do $$$AssertEquals(resource.name.%Get(0).%Get("_given").%ToJSON(), "[null,{""id"":""x""},{""id"":""c""}]")
}

Method TestChoiceMetadataAndDuplicateAdd()
{
    Set resource = {"resourceType":"Observation","status":"final","code":{"text":"test"},"valueString":"old","_valueString":{"id":"old"}}
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"add"},{"name":"path","valueString":"Observation"},{"name":"name","valueString":"value"},{"name":"value","valueBoolean":true}]}]}
    Do ..AssertInvalid(resource, patch)
    Set patch.parameter.%Get(0).part.%Get(0).valueCode = "replace"
    Set patch.parameter.%Get(0).part.%Get(1).valueString = "Observation.value"
    Do patch.parameter.%Get(0).part.%Remove(2)
    Do $$$AssertTrue(..Apply(resource, patch))
    Do $$$AssertTrue('resource.%IsDefined("valueString"))
    Do $$$AssertTrue('resource.%IsDefined("_valueString"))
    Do $$$AssertEquals(resource.valueBoolean, 1)
}

Method TestMalformedPayloads()
{
    Set resource = {"resourceType":"Patient","active":false}
    Do ..AssertInvalid(resource, {"resourceType":"Parameters","parameter":[[]]})
    Do ..AssertInvalid(resource, {"resourceType":"Parameters","parameter":[{"name":"operation","valueString":"invalid","part":[]}]})
    Do ..AssertInvalid(resource, {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"replace","valueString":"invalid"},{"name":"path","valueString":"Patient.active"},{"name":"value","valueBoolean":true}]}]})
    Do ..AssertInvalid(resource, {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"replace"},{"name":"path","valueString":"Patient.active"},{"name":"value","valueBoolean":"true"}]}]})
    Do ..AssertInvalid(resource, {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"replace"},{"name":"path","valueString":"Patient.active"},{"name":"value","part":7}]}]})
    Do ..AssertInvalid(resource, {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"replace"},{"name":"path","valueString":"Patient.["},{"name":"value","valueBoolean":true}]}]})
}

Method TestPrimitiveExtensionNavigation()
{
    Set resource = {"resourceType":"Patient","name":[{"given":["Same","Same"],"_given":[null,{"extension":[{"url":"urn:bundlepatch:test","valueString":"old"}]}]}]}
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"replace"},{"name":"path","valueString":"Patient.name.given.extension.where(url = 'urn:bundlepatch:test').value"},{"name":"value","valueString":"new"}]}]}
    Do $$$AssertTrue(..Apply(resource, patch))
    Do $$$AssertEquals(resource.name.%Get(0).%Get("_given").%Get(1).extension.%Get(0).valueString, "new")
    Do $$$AssertEquals(resource.name.%Get(0).given.%ToJSON(), "[""Same"",""Same""]")
}

Method TestProtectedMetadataAndNativeRestrictions()
{
    Set resource = {"resourceType":"Patient","id":"p1","meta":{"versionId":"1","lastUpdated":"2026-01-01T00:00:00Z"}}
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"replace"},{"name":"path","valueString":"Patient.meta.versionId"},{"name":"value","valueId":"99"}]}]}
    Do $$$AssertTrue('..Apply(resource, patch))
    Do $$$AssertEquals(resource.meta.versionId, "1")
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"replace"},{"name":"path","valueString":"Patient.id"},{"name":"value","valueId":"p2"}]}]}
    Do ..AssertInvalid(resource, patch)
    Set resource.text = {"status":"generated","div":"<div xmlns=\"http://www.w3.org/1999/xhtml\">test</div>"}
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"add"},{"name":"path","valueString":"Patient"},{"name":"name","valueString":"active"},{"name":"value","valueBoolean":true}]}]}
    Do ..AssertInvalid(resource, patch)
    Do ..AssertInvalid(resource, {"resourceType":"Parameters","parameter":[]})
}

Method TestTypeFilterAndMetadataPadding()
{
    Set resource = {"resourceType":"Observation","status":"final","code":{"text":"test"},"valueQuantity":{"value":1}}
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"replace"},{"name":"path","valueString":"Observation.value.ofType(Quantity).value"},{"name":"value","valueDecimal":2.5}]}]}
    Do $$$AssertTrue(..Apply(resource, patch))
    Do $$$AssertEquals(resource.valueQuantity.value, 2.5)
    Set resource = {"resourceType":"Patient","name":[{"given":["A","B"],"_given":[{"id":"a"}]}]}
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"add"},{"name":"path","valueString":"Patient.name"},{"name":"name","valueString":"given"},{"name":"value","valueString":"C","_valueString":{"id":"c"}}]}]}
    Do $$$AssertTrue(..Apply(resource, patch))
    Do $$$AssertEquals(resource.name.%Get(0).%Get("_given").%ToJSON(), "[{""id"":""a""},null,{""id"":""c""}]")
    Set resource = {"resourceType":"Patient","name":[{"given":["A"],"_given":[{"id":"a"},{"id":"b"}]}]}
    Do ..AssertInvalid(resource, patch)
}

Method TestResourceValueInHeterogeneousList()
{
    Set resource = {"resourceType":"Patient","contained":[{"resourceType":"Patient","id":"child"}]}
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[{"name":"type","valueCode":"insert"},{"name":"path","valueString":"Patient.contained"},{"name":"index","valueInteger":1},{"name":"value","resource":{"resourceType":"Observation","id":"obs","status":"final","code":{"text":"contained"}}}]}]}
    Do $$$AssertTrue(..Apply(resource, patch))
    Do $$$AssertEquals(resource.contained.%Get(0).resourceType, "Patient")
    Do $$$AssertEquals(resource.contained.%Get(1).resourceType, "Observation")
}

Method TestBundleValidationAndPreparation()
{
    Set bundle = {"resourceType":"Bundle","type":"batch","entry":[{"request":{"method":"PATCH","url":"Patient/p1","ifMatch":"W/\"1\""},"resource":{"resourceType":"Parameters","parameter":[]}}]}
    Do ##class(FHIR.Python.BundleValidator).ValidateBundle(bundle, "4.0.1")
    Do $$$AssertEquals(bundle.entry.%Get(0).resource.resourceType, "Parameters")
    Set request = ##class(HS.FHIRServer.API.Data.Request).%New()
    Set request.Json = bundle, request.Prefer = "return=representation"
    Set recursive = ##class(FHIR.Python.BundleProcessor).prepareRequest("", request, .context, bundle.entry.%Get(0))
    Do $$$AssertEquals(recursive.Json.resourceType, "Parameters")
    Do $$$AssertEquals(recursive.IfMatch, "W/""1""")
    Do $$$AssertEquals(recursive.Prefer, "return=representation")
    Do $$$AssertEquals(recursive.RequestPath, "Patient/p1")
    Do $$$AssertEquals(recursive.AdditionalInfo.GetAt("IsInTransaction"), 0)
}

}
