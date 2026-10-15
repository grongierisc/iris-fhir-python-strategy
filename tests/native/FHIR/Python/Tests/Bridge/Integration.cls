Include (HS.FHIRServer, %outUnitTest)

Class FHIR.Python.Tests.Bridge.Integration Extends FHIR.Python.Tests.Patch.BundleIntegration
{

Property Hooks As %SYS.Python;

Method OnBeforeAllTests() As %Status
{
    Set sc = ##super()
    Quit:$$$ISERR(sc) sc
    Do ##class(FHIR.Python.Helper).SetPythonPath("/irisdev/app/tests/native")
    Set ..Hooks = ##class(%SYS.Python).Import("bridge_hooks")
    Return $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
    Do ..Hooks."install"()
    Return ##super(testname)
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Try {
        Do ..Hooks."configure"("observe")
        Set sc = ##super(testname)
    } Catch ex {
        Do ..Hooks."restore"()
        Throw ex
    }
    Do ..Hooks."restore"()
    Return sc
}

Method MergeInput(preview As %Boolean = 1) As %DynamicObject
{
    Set source = ..Create("-source", "source"), target = ..Create("-target", "target")
    Set input = {"resourceType":"Parameters","parameter":[
        {"name":"source-patient","valueReference":{"reference":("Patient/"_source)}},
        {"name":"target-patient","valueReference":{"reference":("Patient/"_target)}},
        {"name":"preview","valueBoolean":true}
    ]}
    Do input.parameter.%Get(2).%Set("valueBoolean", preview, "boolean")
    Return input
}

Method TestNativeMergeDispatchAndHooks()
{
    Set input = ..MergeInput()
    Set response = ..Request("POST", "Patient/$merge", input)
    Do $$$AssertEquals(+response.Status, 200)
    Do $$$AssertEquals(response.Json.parameter.%Get(0).name, "input")
    Do $$$AssertEquals(..Hooks."count"("before", "operation"), 1)
    Do $$$AssertEquals(..Hooks."count"("after", "operation"), 1)
    Do $$$AssertEquals(..Hooks."count"("create", "Parameters"), 0)
    Do $$$AssertTrue(..Hooks."context_clear"())
}

Method TestPythonMergeOverrideAndMetadata()
{
    Do ..Hooks."configure"("override")
    Set response = ..Request("POST", "Patient/$merge", {"resourceType":"Parameters"})
    Do $$$AssertEquals(+response.Status, 200)
    Do $$$AssertEquals(response.Json.parameter.%Get(0).name, "python")
    Do ..AssertMergeMetadata("http://example.com/OperationDefinition/merge")
}

Method TestWildcardMergeMetadata()
{
    Do ..Hooks."configure"("wildcard")
    Do ..AssertMergeMetadata("http://example.com/OperationDefinition/merge")
    Do $$$AssertEquals(+..Request("POST", "Patient/$merge", {"resourceType":"Parameters"}).Status, 200)
}

Method TestInstanceMergeDoesNotDuplicateMetadata()
{
    Do ..Hooks."configure"("instance")
    Do ..AssertMergeMetadata("http://example.com/OperationDefinition/merge")
    Set input = ..MergeInput()
    Do $$$AssertEquals(+..Request("POST", "Patient/$merge", input).Status, 200)
    Do $$$AssertEquals(+..Request("POST", "Patient/"_..Prefix_"-target/$merge", {"resourceType":"Parameters"}).Status, 200)
}

Method TestDefinitionPublicationIdempotent()
{
    Set endpoint = "/fhir/python-test/r4"
    Set service = ##class(HS.FHIRServer.Service).EnsureInstance(endpoint)
    Set before = service.interactions.Read("OperationDefinition", "Patient-merge-r4").meta.versionId
    Do ##class(FHIR.Python.Setup).PublishDefinition(endpoint)
    Do ##class(FHIR.Python.Setup).PublishDefinition(endpoint)
    Do $$$AssertEquals(service.interactions.Read("OperationDefinition", "Patient-merge-r4").meta.versionId, before)
    Set rejected = 0
    Try {
        Do ##class(FHIR.Python.Setup).PublishDefinition("/fhir/python-test/not-installed")
    } Catch ex {
        Set rejected = 1
    }
    Do $$$AssertTrue(rejected)
}

Method AssertMergeMetadata(definition As %String)
{
    Set metadata = ..Service.strategy.GetMetadataResource(), count = 0
    Set resources = metadata.rest.%Get(0).resource.%GetIterator()
    While resources.%GetNext(.index, .resource) {
        If (resource.type '= "Patient") || '$IsObject(resource.operation) Continue
        Set operations = resource.operation.%GetIterator()
        While operations.%GetNext(.index, .operation) {
            If operation.name = "merge" {
                Set count = count + 1
                Do $$$AssertEquals(operation.definition, definition)
            }
        }
    }
    Do $$$AssertEquals(count, 1)
    Do $$$AssertEquals(metadata.publisher, "Python bridge test")
}

Method TestNativeMergeMetadata()
{
    Do ..AssertMergeMetadata(##class(FHIR.Python.InteractionsStrategy).DefinitionURL("4"))
}

Method TestOriginalBundleAndResourceValidation()
{
    Set id = ..Create()
    Set bundle = {"resourceType":"Bundle","type":"transaction","entry":[
        {"request":{"method":"PATCH","url":("Patient/"_id)},"resource":(..Patch())}
    ]}
    Set response = ..Request("POST", "", bundle)
    Do $$$AssertEquals(+response.Status, 200)
    Do $$$AssertEquals(..Hooks."count"("bundle", "Parameters"), 1)
    Do $$$AssertEquals(..Hooks."count"("resource", "Parameters"), 1)
    Do $$$AssertEquals(..Hooks."count"("resource", "Patient"), 2)
    Do $$$AssertTrue(..Hooks."context_clear"())
}

Method TestNativeSchemaCannotBeBypassed()
{
    Set id = ..Create()
    Set patch = {"resourceType":"Parameters","parameter":[{"name":"operation","part":[
        {"name":"type","valueCode":"add"},{"name":"path","valueString":"Patient"},
        {"name":"name","valueString":"active"},{"name":"value","valueString":"not boolean"}
    ]}]}
    Set bundle = {"resourceType":"Bundle","type":"transaction","entry":[
        {"request":{"method":"PATCH","url":("Patient/"_id)},"resource":(patch)}
    ]}
    Do $$$AssertEquals(+..Request("POST", "", bundle).Status, 400)
    Do $$$AssertEquals(..Request("GET", "Patient/"_id).Json.meta.versionId, "1")
    Do $$$AssertTrue(..Hooks."context_clear"())
}

Method TestPythonPatchRejectionRollsBack()
{
    Set id = ..Create()
    Do ..Hooks."configure"("reject-patient")
    Set bundle = {"resourceType":"Bundle","type":"transaction","entry":[
        {"request":{"method":"PATCH","url":("Patient/"_id)},"resource":(..Patch())}
    ]}
    Do $$$AssertEquals(+..Request("POST", "", bundle).Status, 400)
    Do ..Hooks."configure"("observe")
    Do $$$AssertEquals(..Request("GET", "Patient/"_id).Json.meta.versionId, "1")
}

Method TestPythonBundleRejection()
{
    Set id = ..Create()
    Do ..Hooks."configure"("reject-bundle")
    Set bundle = {"resourceType":"Bundle","type":"transaction","entry":[
        {"request":{"method":"PATCH","url":("Patient/"_id)},"resource":(..Patch())}
    ]}
    Do $$$AssertEquals(+..Request("POST", "", bundle).Status, 400)
    Do ..Hooks."configure"("observe")
    Do $$$AssertEquals(..Request("GET", "Patient/"_id).Json.meta.versionId, "1")
}

Method TestConsentDeniesMerge()
{
    Set input = ..MergeInput()
    Do ..Hooks."configure"("deny")
    Do $$$AssertEquals(+..Request("POST", "Patient/$merge", input).Status, 404)
}

Method TestReadMaskNotPersisted()
{
    Set input = ..MergeInput(0)
    Do ..Hooks."configure"("mask")
    Do $$$AssertEquals(+..Request("POST", "Patient/$merge", input).Status, 200)
    Do ..Hooks."configure"("observe")
    Set target = ..Request("GET", "Patient/"_..Prefix_"-target").Json
    Do $$$AssertEquals(target.identifier.%Size(), 2)
}

Method TestMergeThenBundlePatch()
{
    Set input = ..MergeInput(0)
    Do $$$AssertEquals(+..Request("POST", "Patient/$merge", input).Status, 200)
    Set bundle = {"resourceType":"Bundle","type":"transaction","entry":[
        {"request":{"method":"PATCH","url":("Patient/"_..Prefix_"-target")},"resource":(..Patch())}
    ]}
    Do $$$AssertEquals(+..Request("POST", "", bundle).Status, 200)
    Set target = ..Request("GET", "Patient/"_..Prefix_"-target").Json
    Do $$$AssertEquals(target.active, 1)
    Do $$$AssertEquals(target.meta.versionId, "3")
    Do $$$AssertEquals(+..Request("GET", "Patient/"_..Prefix_"-source/$everything").Status, 400)
}

Method TestAfterHandlerErrorClearsContext()
{
    Do ..Hooks."configure"("after-error")
    Try {
        Do ..Request("GET", "metadata")
        Do $$$AssertFailure("Expected after-request handler error")
    } Catch ex {
        Do $$$AssertTrue(..Hooks."context_clear"())
    }
}

Method TestMergeConfigValidation()
{
    Do $$$AssertEquals(##class(FHIR.Python.InteractionsStrategy).GetMergeWriteLimit({}), 1000)
    For value = 2, 3.5, "1000" {
        Set rejected = 0
        Try {
            Do ##class(FHIR.Python.InteractionsStrategy).GetMergeWriteLimit({"max_merge_writes":(value)})
        } Catch ex {
            Set rejected = 1
        }
        Do $$$AssertTrue(rejected)
    }
}

Method TestPythonJSONTypesPreserved()
{
    Set json = ##class(%SYS.Python).Import("json")
    Set original = {"active":true,"empty":null,"text":"001","number":1,"object":{},"array":[]}
    Set body = json.loads(original.%ToJSON()), copy = {}
    Do ##class(FHIR.Python.Helper).UpdateDynamicObject(copy, body)
    Do $$$AssertEquals(copy.%GetTypeOf("active"), "boolean")
    Do $$$AssertEquals(copy.%GetTypeOf("empty"), "null")
    Do $$$AssertEquals(copy.%GetTypeOf("text"), "string")
    Do $$$AssertEquals(copy.%GetTypeOf("number"), "number")
    Do $$$AssertEquals(copy.%GetTypeOf("object"), "object")
    Do $$$AssertEquals(copy.%GetTypeOf("array"), "array")
}

}
