Include (HS.FHIRServer, %outUnitTest)

Class FHIR.Python.Tests.Merge.IntegrationTest Extends %UnitTest.TestCase
{

Parameter Endpoint = "/fhir/python-test/r4";

Property Service As FHIR.Python.Tests.Merge.TestService;

Property Interactions As FHIR.Python.Tests.Merge.FailingInteractions;

Property Request As HS.FHIRServer.API.Data.Request;

Property EntryLevel As %Integer;

Property OriginalConfig As %String;

Property SourceId As %String;

Property TargetId As %String;

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set ..EntryLevel = $TLevel
    Set instance = ##class(HS.FHIRServer.ServiceInstance).FindByUrl(..#Endpoint)
    Set ..Service = ##class(FHIR.Python.Tests.Merge.TestService).CreateInstance(instance.serviceId)
    Set ..Interactions = ##class(FHIR.Python.Tests.Merge.FailingInteractions).%New(..Service.strategy)
    Set ..OriginalConfig = ..Interactions.strategy.RepoInstance.strategyConfigData
    Set ..Service.FaultInteractions = ..Interactions
    Set ..Request = ##class(HS.FHIRServer.API.Data.Request).%New()
    Set ..Request.BaseURL = "http://localhost:53794" _ ..#Endpoint
    Set ..Request.LocalBaseURL = ..Request.BaseURL
    Set ..Request.SessionApplication = ..#Endpoint
    Set ..Request.Parameters = ##class(HS.FHIRServer.API.Data.QueryParameters).%New()
    Set ..Request.RequestMethod = "POST", ..Request.Type = "Patient"
    TStart
    Set source = {"resourceType":"Patient","active":true,"identifier":[{"system":"urn:fhir-merge:test","value":"source"}],"name":[{"family":"Source"}]}
    Set target = {"resourceType":"Patient","active":true,"identifier":[{"system":"urn:fhir-merge:test","value":"target"}],"name":[{"family":"Target"}]}
    Set ..SourceId = ..Interactions.Add(source), ..TargetId = ..Interactions.Add(target)
    Set ..Request.Json = {
        "resourceType":"Parameters",
        "parameter":[
            {"name":"source-patient","valueReference":{"reference":("Patient/" _ ..SourceId)}},
            {"name":"target-patient","valueReference":{"reference":("Patient/" _ ..TargetId)}}
        ]
    }
    Return $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    While $TLevel > ..EntryLevel {
        TRollback 1
    }
    Do ##class(HS.FHIRServer.ServiceAdmin).SetInstanceStrategyConfigData(..Interactions.strategy.InstanceKey, {}.%FromJSON(..OriginalConfig))
    Set ..Service = "", ..Interactions = "", ..Request = ""
    Return $$$OK
}

Method Merge() As HS.FHIRServer.API.Data.Response
{
    Set response = ##class(HS.FHIRServer.API.Data.Response).%New()
    Do ##class(FHIR.Python.OperationHandler).FHIRTypeOpMerge(..Service, ..Request, response)
    If +response.Status '= 200 {
        Do ..LogMessage(response.Json.%ToJSON())
    }
    Return response
}

Method Parameter(response As HS.FHIRServer.API.Data.Response, name As %String) As %DynamicObject
{
    Set iterator = response.Json.parameter.%GetIterator()
    While iterator.%GetNext(.index, .parameter) {
        If parameter.name = name {
            Return parameter.resource
        }
    }
    Do $$$AssertFailure("Expected output parameter: " _ name)
    Return {}
}

Method AddObservation(reference As %String = "") As %String
{
    If reference = "" {
        Set reference = "Patient/" _ ..SourceId
    }
    Set observation = {"resourceType":"Observation","status":"final","code":{"text":"Synthetic"},"subject":{"reference":(reference)}}
    Return ..Interactions.Add(observation)
}

Method TestPreview()
{
    Set id = ..AddObservation()
    Do ..Request.Json.parameter.%Push({"name":"preview","valueBoolean":true})
    Set before = ..Count("Provenance")
    Set response = ..Merge()
    Do $$$AssertEquals(response.Status, 200, "Preview succeeds")
    Do $$$AssertEquals(response.Json.parameter.%Size(), 3, "Response has input, outcome and result")
    Do $$$AssertEquals(..Parameter(response, "input").resourceType, "Parameters", "Inputs are wrapped as Parameters")
    Set patient = ..Parameter(response, "result")
    Do $$$AssertEquals(patient.id, ..TargetId, "Preview returns target")
    Do $$$AssertNotTrue(patient.meta.%IsDefined("versionId"), "Preview removes versionId")
    Do $$$AssertNotTrue(patient.meta.%IsDefined("lastUpdated"), "Preview removes lastUpdated")
    Do $$$AssertEquals(..Interactions.Read("Patient", ..SourceId).active, 1, "Source remains active")
    Do $$$AssertEquals(..Interactions.Read("Patient", ..TargetId).meta.versionId, "1", "Target version unchanged")
    Do $$$AssertEquals(..Interactions.Read("Observation", id).subject.reference, "Patient/" _ ..SourceId, "Reference unchanged")
    Do $$$AssertEquals(..Count("Provenance"), before, "No merge Provenance created")
}

Method TestSuccessfulMerge()
{
    Set id = ..AddObservation()
    Set before = ..Count("Provenance")
    Set response = ..Merge()
    Do $$$AssertEquals(response.Status, 200, "Merge succeeds")
    Set source = ..Interactions.Read("Patient", ..SourceId)
    Set target = ..Interactions.Read("Patient", ..TargetId)
    Do $$$AssertEquals(source.active, 0, "Source becomes inactive")
    Do $$$AssertEquals(source.%GetTypeOf("active"), "boolean", "active retains Boolean type")
    Do $$$AssertTrue(##class(FHIR.Python.PatientMerge).HasLink(source, ..TargetId, "replaced-by", ..Service.GetBaseURLs(..Request)), "Source link")
    Do $$$AssertTrue(##class(FHIR.Python.PatientMerge).HasLink(target, ..SourceId, "replaces", ..Service.GetBaseURLs(..Request)), "Target link")
    Do $$$AssertEquals(target.name.%Get(0).family, "Target", "Target demographics retained")
    Do $$$AssertEquals(target.identifier.%Size(), 2, "Source identifier transferred")
    Do $$$AssertEquals(..Interactions.Read("Observation", id).subject.reference, "Patient/" _ ..TargetId, "Clinical reference moved")
    Do $$$AssertEquals(..Interactions.Read("Observation", id, "1").subject.reference, "Patient/" _ ..SourceId, "History preserved")
    Do $$$AssertEquals(..Count("Provenance"), before + 1, "Merge Provenance created")
    Do $$$AssertEquals(..Merge().Status, 422, "Repeated merge rejected")
}

Method TestIdentifierResolution()
{
    Set ..Request.Json = {
        "resourceType":"Parameters",
        "parameter":[
            {"name":"source-patient-identifier","valueIdentifier":{"system":"urn:fhir-merge:test","value":"source"}},
            {"name":"target-patient-identifier","valueIdentifier":{"system":"urn:fhir-merge:test","value":"target"}}
        ]
    }
    Do $$$AssertEquals(..Merge().Status, 200, "Identifiers resolve exactly one Patient")
}

Method TestAmbiguousIdentifiers()
{
    Do ..Interactions.Add({"resourceType":"Patient","identifier":[{"system":"urn:fhir-merge:test","value":"source"}]})
    Do ..Request.Json.parameter.%Set(0, {"name":"source-patient-identifier","valueIdentifier":{"system":"urn:fhir-merge:test","value":"source"}})
    Do $$$AssertEquals(..Merge().Status, 422, "Ambiguous identifier rejected")
    Do $$$AssertEquals(..Interactions.Read("Patient", ..SourceId).meta.versionId, "1", "No Patient changes")
}

Method TestSelectionValidation()
{
    Set original = ..Request.Json
    Do ..Request.Json.parameter.%Push({"name":"source-patient-identifier","valueIdentifier":{"value":"source"}})
    Do $$$AssertEquals(..Merge().Status, 400, "Both selection forms rejected")
    Set ..Request.Json = {"resourceType":"Parameters","parameter":[]}
    Do $$$AssertEquals(..Merge().Status, 400, "Missing selectors rejected")
    Set ..Request.Json = original
    Do ..Request.Json.parameter.%Pop()
    Set ..Request.Json.parameter.%Get(1).valueReference.reference = "Patient/" _ ..SourceId
    Do $$$AssertEquals(..Merge().Status, 422, "Self-merge rejected")
}

Method TestWrongPreviewType()
{
    Do ..Request.Json.parameter.%Push({"name":"preview","valueBoolean":"true"})
    Do $$$AssertEquals(..Merge().Status, 400, "String preview rejected")
}

Method TestNonObjectBody()
{
    Set ..Request.Json = []
    Do $$$AssertEquals(..Merge().Status, 400, "Array body rejected as input error")
}

Method TestNonPatientReferenceType()
{
    Set ..Request.Json.parameter.%Get(0).valueReference.type = "Practitioner"
    Do $$$AssertEquals(..Merge().Status, 400, "Contradictory Reference type rejected")
}

Method TestMissingAndInconsistentIdentifiers()
{
    Do ..Request.Json.parameter.%Set(0, {"name":"source-patient-identifier","valueIdentifier":{"value":"missing"}})
    Do $$$AssertEquals(..Merge().Status, 422, "Missing identifier rejected")
    Set ..Request.Json.parameter.%Get(0).valueIdentifier.value = "source"
    Do ..Request.Json.parameter.%Push({"name":"source-patient-identifier","valueIdentifier":{"value":"target"}})
    Do $$$AssertEquals(..Merge().Status, 422, "Inconsistent identifiers rejected")
}

Method TestResultPatientRequiresIdentifiers()
{
    Do ..Request.Json.parameter.%Set(0, {"name":"source-patient-identifier","valueIdentifier":{"system":"urn:fhir-merge:test","value":"source"}})
    Set result = ..Interactions.Read("Patient", ..TargetId)
    Do ##class(FHIR.Python.PatientMerge).AddLink(result, ..SourceId, "replaces", ..Service.GetBaseURLs(..Request))
    Do ..Request.Json.parameter.%Push({"name":"result-patient","resource":(result)})
    Do $$$AssertEquals(..Merge().Status, 400, "Explicit result must contain provided source identifier")
}

Method TestIdentifierDeduplicationPreservesMetadata()
{
    Set source = ..Interactions.Read("Patient", ..SourceId)
    Set target = ..Interactions.Read("Patient", ..TargetId)
    Set source.identifier = [{"system":"urn:test:shared","value":"shared","period":{"start":"2020-01-01"}}]
    Set target.identifier = [{"value":"shared","system":"urn:test:shared","period":{"end":"2030-01-01"}}]
    Do ..Interactions.Update(source)
    Do ..Interactions.Update(target)
    Set response = ..Merge()
    Do $$$AssertEquals(response.Status, 200, "Compatible identifier metadata merged")
    Set result = ..Parameter(response, "result")
    Do $$$AssertEquals(result.identifier.%Size(), 1, "Identifier deduplicated")
    Do $$$AssertEquals(result.identifier.%Get(0).period.start, "2020-01-01", "Source metadata preserved")
    Do $$$AssertEquals(result.identifier.%Get(0).period.end, "2030-01-01", "Target metadata preserved")
}

Method TestConflictingIdentifierMetadataRejected()
{
    Set source = ..Interactions.Read("Patient", ..SourceId)
    Set target = ..Interactions.Read("Patient", ..TargetId)
    Set source.identifier = [{"system":"urn:test:shared","value":"shared","use":"official"}]
    Set target.identifier = [{"system":"urn:test:shared","value":"shared","use":"old"}]
    Do ..Interactions.Update(source)
    Do ..Interactions.Update(target)
    Do $$$AssertEquals(..Merge().Status, 422, "Conflicting metadata requires explicit result")
}

Method TestWriteAuthorization()
{
    Set before = ..Count("Provenance")
    Set token = ##class(FHIR.Python.Tests.Merge.DenyingToken).%New(..Service.Schema, ..Interactions, ..Service.ConfigData.SearchFiltering)
    Set ..Interactions.TestToken = token
    Do $$$AssertEquals(..Merge().Status, 403, "Patient write denial honored")
    Do $$$AssertEquals(..Interactions.Read("Patient", ..SourceId).meta.versionId, "1", "Unauthorized merge writes nothing")
    Do $$$AssertEquals(..Count("Provenance"), before, "No unauthorized Provenance")
}

Method TestDependentAuthorization()
{
    Set id = ..AddObservation()
    Set token = ##class(FHIR.Python.Tests.Merge.DenyingToken).%New(..Service.Schema, ..Interactions, ..Service.ConfigData.SearchFiltering)
    Set token.DeniedType = "Observation"
    Set ..Interactions.TestToken = token
    Do $$$AssertEquals(..Merge().Status, 403, "Dependent write denial honored")
    Do $$$AssertEquals(..Interactions.Read("Observation", id).meta.versionId, "1", "Unauthorized dependent unchanged")
}

Method TestConfiguredWriteLimit()
{
    Set id = ..AddObservation()
    Set config = {}.%FromJSON(..Interactions.strategy.RepoInstance.strategyConfigData)
    Do config.%Set("max_merge_writes", 3, "number")
    Do ##class(HS.FHIRServer.ServiceAdmin).SetInstanceStrategyConfigData(..Interactions.strategy.InstanceKey, config)
    Do $$$AssertEquals(..Merge().Status, 422, "Configured cap enforced")
    Do $$$AssertEquals(..Interactions.Read("Observation", id).meta.versionId, "1", "Configured rejection writes nothing")
}

Method TestMergedSourceCanBeChangedAndDeleted()
{
    Do $$$AssertEquals(..Merge().Status, 200, "Merge succeeds")
    Set source = ..Interactions.Read("Patient", ..SourceId)
    Do source.%Remove("link")
    Set source.active = 1
    Do $$$AssertEquals(..Interactions.Update(source), ..SourceId, "Source can be reactivated and alias removed")
    Set updated = ..Interactions.Read("Patient", ..SourceId)
    Do $$$AssertTrue(updated.active, "Reactivation persisted")
    Do $$$AssertNotTrue(updated.%IsDefined("link"), "Alias removal persisted")
    Do ..Interactions.Delete("Patient", ..SourceId)
    Do $$$AssertEquals(..Interactions.FindResourceObject("Patient", ..SourceId), "", "Deleted source is no longer current")
}

Method TestUnknownAndDuplicateParameters()
{
    Do ..Request.Json.parameter.%Push({"name":"bogus","valueBoolean":true})
    Do $$$AssertEquals(..Merge().Status, 400, "Unknown parameter rejected")
    Do ..Request.Json.parameter.%Pop()
    Do ..Request.Json.parameter.%Push({"name":"source-patient","valueReference":{"reference":("Patient/" _ ..SourceId)}})
    Do $$$AssertEquals(..Merge().Status, 400, "Duplicate selector rejected")
}

Method TestMergedSourceWithAliasCanBeDeleted()
{
    Do $$$AssertEquals(..Merge().Status, 200, "Merge succeeds")
    Do ..Interactions.Delete("Patient", ..SourceId)
    Do $$$AssertEquals(..Interactions.FindResourceObject("Patient", ..SourceId), "", "Deleted alias is no longer current")
}

Method TestResultPatient()
{
    Set result = ..Interactions.Read("Patient", ..TargetId)
    Set result.name = [{"family":"Chosen"}]
    Do ##class(FHIR.Python.PatientMerge).AddLink(result, ..SourceId, "replaces", ..Service.GetBaseURLs(..Request))
    Do ..Request.Json.parameter.%Push({"name":"result-patient","resource":(result)})
    Set response = ..Merge()
    Do $$$AssertEquals(response.Status, 200, "Explicit result accepted")
    Do $$$AssertEquals(..Parameter(response, "result").name.%Get(0).family, "Chosen", "Explicit demographics used")
}

Method TestInvalidResultPatient()
{
    Do ..Request.Json.parameter.%Push({"name":"result-patient","resource":{"resourceType":"Patient","id":(..TargetId)}})
    Do $$$AssertEquals(..Merge().Status, 400, "Missing source link rejected")
    Set ..Request.Json.parameter.%Get(2).resource.id = ..SourceId
    Do $$$AssertEquals(..Merge().Status, 400, "Wrong target id rejected")
}

Method TestStructuralReferences()
{
    Set absolute = ..Request.BaseURL _ "/Patient/" _ ..SourceId
    Set observation = {
        "resourceType":"Observation","status":"final","code":{"text":("Patient/" _ ..SourceId)},
        "subject":{"reference":("Patient/" _ ..SourceId)},
        "extension":[
            {"url":"urn:test:absolute","valueReference":{"reference":(absolute)}},
            {"url":"urn:test:ref","valueReference":{"reference":("Patient/" _ ..SourceId)}}
        ],
        "contained":[{"resourceType":"Observation","id":"contained","status":"final","code":{"text":"Contained"},"subject":{"reference":("Patient/" _ ..SourceId)}}],
        "performer":[{"reference":("https://external.invalid/fhir/Patient/" _ ..SourceId)}]
    }
    Set id = ..Interactions.Add(observation)
    Do $$$AssertEquals(..Merge().Status, 200, "Nested reference merge succeeds")
    Set updated = ..Interactions.Read("Observation", id)
    Do $$$AssertEquals(updated.subject.reference, "Patient/" _ ..TargetId, "Compartment reference rewritten")
    Do $$$AssertEquals(updated.extension.%Get(0).valueReference.reference, ..Request.BaseURL _ "/Patient/" _ ..TargetId, "Local absolute reference rewritten inside discovered resource")
    Do $$$AssertEquals(updated.extension.%Get(1).valueReference.reference, "Patient/" _ ..TargetId, "Extension Reference rewritten")
    Do $$$AssertEquals(updated.contained.%Get(0).subject.reference, "Patient/" _ ..TargetId, "Contained Reference rewritten")
    Do $$$AssertEquals(updated.code.text, "Patient/" _ ..SourceId, "Unrelated string unchanged")
    Do $$$AssertEquals(updated.performer.%Get(0).reference, "https://external.invalid/fhir/Patient/" _ ..SourceId, "External reference unchanged")
}

Method TestVersionedReferenceRejected()
{
    Set id = ..Interactions.Add({
        "resourceType":"Observation","status":"final","code":{"text":"Synthetic"},
        "subject":{"reference":("Patient/" _ ..SourceId)},
        "extension":[{"url":"urn:test:versioned","valueReference":{"reference":("Patient/" _ ..SourceId _ "/_history/1")}}]
    })
    Do $$$AssertEquals(..Merge().Status, 422, "Version-specific reference rejected")
    Do $$$AssertEquals(..Interactions.Read("Observation", id).meta.versionId, "1", "No dependent write")
}

Method TestIdentifierOnlyReferenceRejected()
{
    Do ..Interactions.Add({
        "resourceType":"Observation","status":"final","code":{"text":"Synthetic"},
        "subject":{"reference":("Patient/" _ ..SourceId)},
        "extension":[{"url":"urn:test:identifier","valueReference":{"type":"Patient","identifier":{"system":"urn:fhir-merge:test","value":"source"}}}]
    })
    Do $$$AssertEquals(..Merge().Status, 422, "Identifier-only dependent reference rejected")
}

Method TestNativeDiscoveryScope()
{
    Set id = ..Interactions.Add({
        "resourceType":"Observation","status":"final","code":{"text":"Outside source compartment"},
        "subject":{"reference":("Patient/" _ ..TargetId)},
        "extension":[{"url":"urn:test:outside","valueReference":{"reference":("Patient/" _ ..SourceId)}}]
    })
    Do $$$AssertEquals(..Merge().Status, 200, "Native-scope merge succeeds")
    Set observation = ..Interactions.Read("Observation", id)
    Do $$$AssertEquals(observation.meta.versionId, "1", "Out-of-scope resource not updated")
    Do $$$AssertEquals(observation.extension.%Get(0).valueReference.reference, "Patient/" _ ..SourceId, "Out-of-scope reference remains")
}

Method TestUnindexedReferencesRemainOutsideScope()
{
    Set absoluteId = ..AddObservation(..Request.BaseURL _ "/Patient/" _ ..SourceId)
    Set versionedId = ..AddObservation("Patient/" _ ..SourceId _ "/_history/1")
    Set identifierId = ..Interactions.Add({
        "resourceType":"Observation","status":"final","code":{"text":"Identifier-only"},
        "subject":{"type":"Patient","identifier":{"system":"urn:fhir-merge:test","value":"source"}}
    })
    Do $$$AssertEquals(..Merge().Status, 200, "Undiscovered references do not cause rejection")
    For id = absoluteId, versionedId, identifierId {
        Do $$$AssertEquals(..Interactions.Read("Observation", id).meta.versionId, "1", "Undiscovered resource remains unchanged")
    }
}

Method TestFullResourceReread()
{
    Set id = ..Interactions.Add({
        "resourceType":"Observation","status":"final","code":{"text":"Full resource"},
        "subject":{"reference":("Patient/" _ ..SourceId)},
        "performer":[{"reference":("Patient/" _ ..TargetId)}]
    })
    Set everything = ##class(HS.FHIRServer.API.Data.Request).%New()
    Set everything.Type = "Patient", everything.Id = ..SourceId
    Set everything.BaseURL = ..Request.BaseURL, everything.LocalBaseURL = ..Request.LocalBaseURL
    Set everything.Parameters = ##class(HS.FHIRServer.API.Data.QueryParameters).%New()
    Set response = ##class(HS.FHIRServer.API.Data.Response).%New()
    Do ##class(HS.FHIRServer.Storage.JsonAdvSQL.BuiltInOperations).FHIRInstanceOpEverything(..Service, everything, response)
    Set entries = response.Json.entry.%GetIterator(), redacted = 0
    While entries.%GetNext(.index, .entry) {
        If (entry.resource.resourceType = "Observation") && (entry.resource.id = id) {
            Set redacted = (entry.resource.performer.%Get(0).reference = "")
        }
    }
    Do $$$AssertTrue(redacted, "Native bundle redacts other Patient reference")
    Do $$$AssertEquals(..Merge().Status, 200, "Merge rereads full content")
    Set observation = ..Interactions.Read("Observation", id)
    Do $$$AssertEquals(observation.performer.%Get(0).reference, "Patient/" _ ..TargetId, "Unrelated Patient reference survives")
    Do $$$AssertNotTrue(observation.meta.%IsDefined("tag"), "Native SUBSETTED tag is not persisted")
}

Method TestEscapedIdentifierLookup()
{
    Set source = ..Interactions.Read("Patient", ..SourceId)
    Set system = "https://example.invalid/ids,$?scope=one+two&tag=%25", value = "value|,\$ &+%="
    Set source.identifier = [{"system":(system),"value":(value)}]
    Do ..Interactions.Update(source)
    Do ..Interactions.Add({"resourceType":"Patient","identifier":[{"system":"urn:test:other","value":"value"}]})
    Do ..Request.Json.parameter.%Set(0, {"name":"source-patient-identifier","valueIdentifier":(source.identifier.%Get(0))})
    Do $$$AssertEquals(..Merge().Status, 200, "Escaped token and URL punctuation resolve exactly")
}

Method TestIdentifierReferenceToMergedSourceAllowed()
{
    Do $$$AssertEquals(..Merge().Status, 200, "Merge succeeds")
    Set id = ..Interactions.Add({
        "resourceType":"Observation","status":"final","code":{"text":"Identifier reference"},
        "subject":{"type":"Patient","identifier":{"value":"source"}}
    })
    Do $$$AssertEquals(..Interactions.Read("Observation", id).subject.identifier.value, "source", "Identifier-only source reference remains allowed")
}

Method TestDiscoveryFailureWritesNothing()
{
    Set id = ..AddObservation(), before = ..Count("Provenance")
    Set ..Interactions.FailDiscovery = 1
    Do $$$AssertEquals(..Merge().Status, 500, "Native discovery failure is not an empty success")
    Set ..Interactions.FailDiscovery = 0
    Do $$$AssertEquals(..Interactions.Read("Patient", ..SourceId).meta.versionId, "1", "Source unchanged")
    Do $$$AssertEquals(..Interactions.Read("Observation", id).meta.versionId, "1", "Dependent unchanged")
    Do $$$AssertEquals(..Count("Provenance"), before, "No merge Provenance written")
}

Method TestCandidateDeduplication()
{
    Set bundle = {"resourceType":"Bundle","type":"searchset","total":3,"entry":[
        {"resource":{"resourceType":"Patient","id":(..SourceId)}},
        {"resource":{"resourceType":"Patient","id":(..SourceId)}},
        {"resource":{"resourceType":"Patient","id":(..TargetId)}}
    ]}
    Do $$$AssertEquals(##class(FHIR.Python.PatientMerge).CandidateKeys(bundle).%Size(), 2, "Repeated candidates counted once")
}

Method TestIncompleteDiscoveryRejected()
{
    For mode = "next", "total", "outcome" {
        Set bundle = {"resourceType":"Bundle","type":"searchset","entry":[{"resource":{"resourceType":"Patient","id":(..SourceId)}}]}
        If mode = "next" {
            Set bundle.link = [{"relation":"next","url":"http://example.invalid/next"}]
        } ElseIf mode = "total" {
            Set bundle.total = 2
        } Else {
            Do bundle.entry.%Push({"resource":{"resourceType":"OperationOutcome","issue":[{"severity":"warning","code":"too-costly"}]}})
        }
        Set rejected = 0
        Try {
            Do ##class(FHIR.Python.PatientMerge).CandidateKeys(bundle)
        } Catch ex {
            Set rejected = 1
        }
        Do $$$AssertTrue(rejected, "Incomplete " _ mode _ " discovery rejected")
    }
}

Method TestSignedResourceRejected()
{
    Do ..Interactions.Add({
        "resourceType":"Provenance",
        "recorded":"2026-01-01T00:00:00Z",
        "target":[{"reference":("Patient/" _ ..SourceId)}],
        "agent":[{"who":{"display":"Synthetic signer"}}],
        "signature":[{"type":[{"system":"urn:iso-astm:E1762-95:2013","code":"1.2.840.10065.1.12.1.1"}],"when":"2026-01-01T00:00:00Z","who":{"display":"Synthetic signer"},"data":"dGVzdA=="}]
    })
    Do $$$AssertEquals(..Merge().Status, 422, "Signed resource rejected")
}

Method TestInjectedFailureRollsBackEverything()
{
    Set id = ..AddObservation(), before = ..Count("Provenance")
    Set ..Interactions.FailAfter = 2
    Do $$$AssertEquals(..Merge().Status, 500, "Injected failure surfaced")
    Do $$$AssertEquals($TLevel, ..EntryLevel + 1, "Only merge transaction rolled back")
    Do $$$AssertEquals(..Interactions.Read("Patient", ..SourceId).meta.versionId, "1", "Source rolled back")
    Do $$$AssertEquals(..Interactions.Read("Patient", ..TargetId).meta.versionId, "1", "Target rolled back")
    Do $$$AssertEquals(..Interactions.Read("Observation", id).meta.versionId, "1", "Dependent update rolled back")
    Do $$$AssertEquals(..Count("Provenance"), before, "Provenance creation rolled back")
    Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM " _ ..Service.strategy.GetResourceVersionTable("") _ " WHERE ResourceType = 'Observation' AND ResourceId = ?", id)
    Do rows.%Next()
    Do $$$AssertEquals(rows.N, 0, "Failed merge created no history")
}

Method TestReferenceToMergedSourceAllowed()
{
    Do $$$AssertEquals(..Merge().Status, 200, "Merge setup succeeds")
    Set id = ..AddObservation()
    Do $$$AssertEquals(..Interactions.Read("Observation", id).subject.reference, "Patient/" _ ..SourceId, "New source reference remains allowed")
    Set observation = ..Interactions.Read("Observation", id)
    Set observation.code.text = "Updated source reference"
    Do $$$AssertEquals(..Interactions.Update(observation), id, "Existing source reference can be updated")
    Set target = ..Interactions.Read("Patient", ..TargetId)
    Do $$$AssertEquals(..Interactions.Update(target), ..TargetId, "Target lineage link remains permitted")
}

Method TestExactWriteLimit()
{
    For i = 1:1:997 {
        Do ..AddObservation()
    }
    Set response = ..Merge()
    Do $$$AssertEquals(response.Status, 200, "Exactly 1000 resource writes succeeds")
    Do $$$AssertEquals(..Parameter(response, "outcome").issue.%Get(0).diagnostics, "Merge resource writes: 1000", "Exact write count")
}

Method TestOneAboveWriteLimit()
{
    For i = 1:1:998 {
        Do ..AddObservation()
    }
    Do $$$AssertEquals(..Merge().Status, 422, "1001 resource writes rejected")
    Do $$$AssertEquals(..Interactions.Read("Patient", ..SourceId).meta.versionId, "1", "Limit rejection does not write")
}

Method Count(type As %String) As %Integer
{
    Set parameters = ##class(HS.FHIRServer.API.Data.QueryParameters).%New()
    Set rows = ..Interactions.Search(type, "", "", parameters)
    Set count = 0
    While rows.NextUndeleted() {
        Set count = count + 1
    }
    $$$ThrowOnError(rows.SearchStatus)
    Return count
}

}
