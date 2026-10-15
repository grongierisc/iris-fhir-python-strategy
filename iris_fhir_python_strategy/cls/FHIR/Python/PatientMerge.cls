Include HS.FHIRServer

Class FHIR.Python.PatientMerge Extends %RegisteredObject
{

ClassMethod Execute(service As HS.FHIRServer.API.Service, request As HS.FHIRServer.API.Data.Request) As %DynamicObject
{
    Set interactions = service.interactions
    Set bases = service.GetBaseURLs(request)
    If (request.RequestMethod '= "POST") || (request.Type '= "Patient") {
        $$$ThrowFHIR($$$GeneralError, "Use POST Patient/$merge", $$$OutcomeInvalid(400))
    }
    Set input = request.Json
    Do ..Parse(input, .parameters)
    Set validator = $ClassMethod(interactions.#ResourceValidatorClass, "%New", service.Schema)
    Do validator.ValidateExtensionResource(input)
    Set source = ..Resolve(interactions, parameters.source, parameters.sourceIdentifiers, bases)
    Set target = ..Resolve(interactions, parameters.target, parameters.targetIdentifiers, bases)
    If source.id = target.id {
        $$$ThrowFHIR($$$GeneralError, "Source and target must be different Patients", $$$OutcomeIs(422, "error", "business-rule"))
    }
    If ##class(FHIR.Python.ReferenceUpdater).IsMerged(source) ||
        ##class(FHIR.Python.ReferenceUpdater).IsMerged(target) {
        $$$ThrowFHIR($$$GeneralError, "Source or target is already merged; merge chains and replay are not supported", $$$OutcomeIs(422, "error", "business-rule"))
    }
    Set updater = ##class(FHIR.Python.ReferenceUpdater).%New()
    Set updater.Metadata = ##class(HS.FHIRMeta.API).getInstance(interactions.strategy.RepoInstance.packageList)
    Set updater.BaseURLs = bases, updater.Source = source, updater.TargetId = target.id
    Do updater.Process(..Clone(target))
    If updater.Signed {
        $$$ThrowFHIR($$$GeneralError, "Target Patient is signed", $$$OutcomeIs(422, "error", "business-rule"))
    }
    Set sourceOut = ..Clone(source)
    Set targetOut = ..Clone(target)
    If $IsObject(parameters.result) {
        Set targetOut = ..Clone(parameters.result)
        If (targetOut.resourceType '= "Patient") || (targetOut.id '= target.id) {
            $$$ThrowFHIR($$$GeneralError, "result-patient must be a Patient with the target id", $$$OutcomeInvalid(400))
        }
        If ##class(FHIR.Python.ReferenceUpdater).IsMerged(targetOut) {
            $$$ThrowFHIR($$$GeneralError, "result-patient cannot be merged away", $$$OutcomeInvalid(400))
        }
        If '..HasLink(targetOut, source.id, "replaces", bases) {
            $$$ThrowFHIR($$$GeneralError, "result-patient must include a replaces link to the source", $$$OutcomeInvalid(400))
        }
        Do ..RequireIdentifiers(targetOut, parameters.sourceIdentifiers)
        Do ..RequireIdentifiers(targetOut, parameters.targetIdentifiers)
        For reference = parameters.source, parameters.target {
            If $IsObject(reference) && $IsObject(reference.identifier) {
                If '##class(FHIR.Python.ReferenceUpdater).HasIdentifier(targetOut, reference.identifier) {
                    $$$ThrowFHIR($$$GeneralError, "result-patient omits a provided identifier", $$$OutcomeInvalid(400))
                }
            }
        }
        If $IsObject(targetOut.meta) && $IsObject(target.meta) &&
            (targetOut.meta.versionId '= "") && (targetOut.meta.versionId '= target.meta.versionId) {
            $$$ThrowFHIR($$$GeneralError, "result-patient contains a stale version", $$$OutcomeIs(409, "error", "conflict"))
        }
    } Else {
        Do ..CopyIdentifiers(source, targetOut)
    }
    Do updater.Process(sourceOut)
    If updater.Signed {
        $$$ThrowFHIR($$$GeneralError, "Source Patient is signed", $$$OutcomeIs(422, "error", "business-rule"))
    }
    Do updater.Process(targetOut)
    If updater.Signed {
        $$$ThrowFHIR($$$GeneralError, "Target Patient is signed", $$$OutcomeIs(422, "error", "business-rule"))
    }
    Do sourceOut.%Set("active", 0, "boolean")
    Do ..AddLink(sourceOut, target.id, "replaced-by", bases)
    Do ..AddLink(targetOut, source.id, "replaces", bases)
    Set changes = [], writes = 3, limit = ..WriteLimit(interactions)
    Set candidates = ..Discover(service, request, source.id)
    Set iterator = candidates.%GetIterator()
    While iterator.%GetNext(.index, .candidate) {
        If (candidate.resourceType = "Patient") && ((candidate.id = source.id) || (candidate.id = target.id)) {
            Continue
        }
        Set original = interactions.Read(candidate.resourceType, candidate.id)
        Set resource = ..Clone(original)
        If updater.Process(resource) {
            Do ..Authorize(service, original, "r")
            Do ..Authorize(service, original, "u")
            Do ..Authorize(service, resource, "u")
            Do changes.%Push(resource)
            Set writes = writes + 1
            If writes > limit {
                $$$ThrowFHIR($$$GeneralError, "Merge exceeds max_merge_writes; no changes made", $$$OutcomeIs(422, "error", "too-costly"))
            }
        }
    }
    For resource = sourceOut, targetOut {
        Do ..Authorize(service, resource, "r")
        Do ..Authorize(service, resource, "u")
    }
    For resource = source, target {
        Do ..Authorize(service, resource, "u")
    }
    Set provenance = ..Provenance(source, target, changes, request.Username)
    Do ..Authorize(service, provenance, "c")
    Do validator.ValidateExtensionResource(sourceOut)
    Do validator.ValidateExtensionResource(targetOut)
    Do validator.ValidateExtensionResource(provenance)
    Set iterator = changes.%GetIterator()
    While iterator.%GetNext(.index, .resource) {
        Do validator.ValidateExtensionResource(resource)
    }
    If parameters.preview {
        If $IsObject(targetOut.meta) {
            Do targetOut.meta.%Remove("versionId")
            Do targetOut.meta.%Remove("lastUpdated")
        }
        Return ..Response(input, ..Outcome("Preview only Patient merge - no changes made", writes), targetOut)
    }
    Set entry = $TLevel
    TStart
    Try {
        Do interactions.Add(provenance)
        Set iterator = changes.%GetIterator()
        While iterator.%GetNext(.index, .resource) {
            Do interactions.Update(resource)
        }
        Do interactions.Update(targetOut)
        Do interactions.Update(sourceOut)
        Set response = ..Response(input, ..Outcome("Patient merge completed", writes), targetOut)
        TCommit
    } Catch ex {
        TRollback:$TLevel>entry 1
        Throw ex
    }
    Return response
}

ClassMethod Parse(input, Output parameters As %DynamicObject)
{
    If '$IsObject(input) || 'input.%IsA("%DynamicObject") {
        $$$ThrowFHIR($$$GeneralError, "A Parameters request body is required", $$$OutcomeInvalid(400))
    }
    If (input.resourceType '= "Parameters") || (input.%GetTypeOf("parameter") '= "array") {
        $$$ThrowFHIR($$$GeneralError, "Request body must be Parameters with a parameter array", $$$OutcomeInvalid(400))
    }
    Set parameters = {"preview":false,"sourceIdentifiers":[],"targetIdentifiers":[]}
    Set iterator = input.parameter.%GetIterator()
    While iterator.%GetNext(.index, .parameter) {
        If '$IsObject(parameter) || 'parameter.%IsA("%DynamicObject") {
            $$$ThrowFHIR($$$GeneralError, "Each parameter must be an object", $$$OutcomeInvalid(400))
        }
        Set name = parameter.name
        Set field = $Case(name, "source-patient":"valueReference", "target-patient":"valueReference",
            "source-patient-identifier":"valueIdentifier", "target-patient-identifier":"valueIdentifier",
            "result-patient":"resource", "preview":"valueBoolean", :"")
        If field = "" {
            $$$ThrowFHIR($$$GeneralError, "Unknown merge parameter", $$$OutcomeInvalid(400))
        }
        If $Data(seen(name)) && (field '= "valueIdentifier") {
            $$$ThrowFHIR($$$GeneralError, "Duplicate singleton merge parameter", $$$OutcomeInvalid(400))
        }
        Set seen(name) = 1
        Set type = $Select(field = "valueBoolean":"boolean", 1:"object")
        If parameter.%GetTypeOf(field) '= type {
            $$$ThrowFHIR($$$GeneralError, "Merge parameter has the wrong value type", $$$OutcomeInvalid(400))
        }
        Set values = parameter.%GetIterator()
        While values.%GetNext(.property, .value) {
            If ((property = "part") || (property = "resource") || ($Extract(property, 1, 5) = "value")) && (property '= field) {
                $$$ThrowFHIR($$$GeneralError, "Merge parameter must contain exactly one value", $$$OutcomeInvalid(400))
            }
        }
        Set value = parameter.%Get(field)
        If field = "valueIdentifier" {
            Do ..ValidateIdentifier(value)
        }
        If name = "source-patient" {
            Set parameters.source = value
        } ElseIf name = "target-patient" {
            Set parameters.target = value
        } ElseIf name = "source-patient-identifier" {
            Do parameters.sourceIdentifiers.%Push(value)
        } ElseIf name = "target-patient-identifier" {
            Do parameters.targetIdentifiers.%Push(value)
        } ElseIf name = "result-patient" {
            Set parameters.result = value
        } Else {
            Set parameters.preview = value
        }
    }
    For side = "source", "target" {
        Set hasReference = parameters.%IsDefined(side)
        Set hasIdentifiers = parameters.%Get(side _ "Identifiers").%Size() > 0
        If hasReference = hasIdentifiers {
            $$$ThrowFHIR($$$GeneralError, "Provide exactly one selection form for each Patient", $$$OutcomeInvalid(400))
        }
    }
}

ClassMethod ValidateIdentifier(identifier As %DynamicObject)
{
    If (identifier.%GetTypeOf("value") '= "string") || (identifier.value = "") ||
        (identifier.%IsDefined("system") && (identifier.%GetTypeOf("system") '= "string")) {
        $$$ThrowFHIR($$$GeneralError, "Patient identifier requires a nonempty value and optional string system", $$$OutcomeInvalid(400))
    }
}

ClassMethod Resolve(interactions As FHIR.Python.Interactions, reference, identifiers As %DynamicArray, bases As %List) As %DynamicObject
{
    Set id = ""
    If $IsObject(reference) {
        If (reference.type '= "") && ($Piece(reference.type, "/", *) '= "Patient") {
            $$$ThrowFHIR($$$GeneralError, "Patient selector declares a non-Patient type", $$$OutcomeInvalid(400))
        }
        If reference.reference '= "" {
            If '##class(FHIR.Python.ReferenceUpdater).PatientReference(reference.reference, bases, .id, .version, .prefix) || (version '= "") {
                $$$ThrowFHIR($$$GeneralError, "Patient selector must reference a current Patient in this repository", $$$OutcomeInvalid(400))
            }
        }
        If $IsObject(reference.identifier) {
            Do ..ValidateIdentifier(reference.identifier)
            Set identifiers = ..Clone(identifiers)
            Do identifiers.%Push(reference.identifier)
        }
    }
    If identifiers.%Size() {
        Set selected = ""
        Set iterator = identifiers.%GetIterator()
        While iterator.%GetNext(.index, .identifier) {
            Set found = ""
            Set rows = ..IdentifierMatches(interactions, identifier)
            While rows.NextUndeleted() {
                Set patient = interactions.Read("Patient", rows.ResourceId)
                If ##class(FHIR.Python.ReferenceUpdater).HasIdentifier(patient, identifier) {
                    If found '= "" {
                        $$$ThrowFHIR($$$GeneralError, "Patient identifier is ambiguous", $$$OutcomeIs(422, "error", "multiple-matches"))
                    }
                    Set found = patient.id
                }
            }
            $$$ThrowOnError(rows.SearchStatus)
            If found = "" {
                $$$ThrowFHIR($$$GeneralError, "Patient identifier did not resolve", $$$OutcomeIs(422, "error", "not-found"))
            }
            If ((selected '= "") && (selected '= found)) || ((id '= "") && (id '= found)) {
                $$$ThrowFHIR($$$GeneralError, "Patient identifiers resolve inconsistently", $$$OutcomeIs(422, "error", "multiple-matches"))
            }
            Set selected = found
        }
        Set id = selected
    }
    If id = "" {
        $$$ThrowFHIR($$$GeneralError, "Patient selector requires reference or identifier", $$$OutcomeInvalid(400))
    }
    Do interactions.oauth2TokenHandler.VerifyResourceIdRequest("Patient", id, "r")
    Set patient = interactions.FindResourceObject("Patient", id)
    If '$IsObject(patient) {
        $$$ThrowFHIR($$$GeneralError, "Selected Patient does not exist", $$$OutcomeIs(422, "error", "not-found"))
    }
    Do interactions.oauth2TokenHandler.VerifyResourceContent(patient, "r")
    Return patient
}

ClassMethod Discover(service As HS.FHIRServer.API.Service, request As HS.FHIRServer.API.Data.Request, sourceId As %String) As %DynamicArray
{
    Set everything = ##class(HS.FHIRServer.API.Data.Request).%New()
    Set everything.RequestMethod = "GET", everything.Type = "Patient", everything.Id = sourceId
    Set everything.RequestPath = "Patient/" _ sourceId _ "/$everything"
    Set everything.BaseURL = request.BaseURL, everything.LocalBaseURL = request.LocalBaseURL
    Set everything.SessionApplication = request.SessionApplication, everything.Username = request.Username
    Set everything.Parameters = ##class(HS.FHIRServer.API.Data.QueryParameters).%New()
    Set response = ##class(HS.FHIRServer.API.Data.Response).%New()
    Do ##class(HS.FHIRServer.Storage.JsonAdvSQL.BuiltInOperations).FHIRInstanceOpEverything(service, everything, response)
    If response.Status '= 200 {
        $$$ThrowFHIR($$$GeneralError, "Native Patient $everything discovery failed", $$$OutcomeIs(500, "error", "exception"))
    }
    Return ..CandidateKeys(response.Json)
}

ClassMethod CandidateKeys(bundle As %DynamicObject) As %DynamicArray
{
    If '$IsObject(bundle) || (bundle.resourceType '= "Bundle") ||
        (bundle.type '= "searchset") || (bundle.%GetTypeOf("entry") '= "array") {
        $$$ThrowFHIR($$$GeneralError, "Native Patient $everything returned an invalid bundle", $$$OutcomeIs(500, "error", "exception"))
    }
    If $IsObject(bundle.link) {
        Set links = bundle.link.%GetIterator()
        While links.%GetNext(.index, .link) {
            If link.relation = "next" {
                $$$ThrowFHIR($$$GeneralError, "Native Patient $everything returned incomplete results", $$$OutcomeIs(422, "error", "too-costly"))
            }
        }
    }
    Set candidates = [], count = 0, entries = bundle.entry.%GetIterator()
    While entries.%GetNext(.index, .entry) {
        Set resource = entry.resource
        If '$IsObject(resource) {
            $$$ThrowFHIR($$$GeneralError, "Native Patient $everything returned an entry without a resource", $$$OutcomeIs(500, "error", "exception"))
        }
        If resource.resourceType = "OperationOutcome" {
            If resource.%GetTypeOf("issue") '= "array" {
                $$$ThrowFHIR($$$GeneralError, "Native Patient $everything returned an invalid outcome", $$$OutcomeIs(500, "error", "exception"))
            }
            Set issues = resource.issue.%GetIterator()
            While issues.%GetNext(.issueIndex, .issue) {
                If issue.severity '= "information" {
                    $$$ThrowFHIR($$$GeneralError, "Native Patient $everything returned discovery issues", $$$OutcomeIs(422, "error", "not-supported"))
                }
            }
            Continue
        }
        If (resource.%GetTypeOf("resourceType") '= "string") || (resource.resourceType = "") ||
            (resource.%GetTypeOf("id") '= "string") || '##class(FHIR.Python.ReferenceUpdater).ValidId(resource.id) {
            $$$ThrowFHIR($$$GeneralError, "Native Patient $everything returned an invalid resource identity", $$$OutcomeIs(500, "error", "exception"))
        }
        Set count = count + 1
        Set key = resource.resourceType _ "/" _ resource.id
        If '$Data(seen(key)) {
            Set seen(key) = 1
            Do candidates.%Push({"resourceType":(resource.resourceType),"id":(resource.id)})
        }
    }
    If bundle.%IsDefined("total") && (bundle.total > count) {
        $$$ThrowFHIR($$$GeneralError, "Native Patient $everything returned fewer resources than its total", $$$OutcomeIs(422, "error", "too-costly"))
    }
    Return candidates
}

ClassMethod IdentifierMatches(interactions As FHIR.Python.Interactions, identifier As %DynamicObject) As HS.FHIRServer.Util.SearchResult
{
    Do ..ValidateIdentifier(identifier)
    Set token = ..EscapeToken(identifier.value)
    If identifier.system '= "" {
        Set token = ..EscapeToken(identifier.system) _ "|" _ token
    }
    Set query = "identifier=" _ $Replace($ZConvert(token, "O", "URL"), "+", "%20")
    Set parameters = ##class(HS.FHIRServer.API.Data.QueryParameters).CreateFromQueryString(query, interactions.strategy.schema, "Patient")
    $$$ThrowOnError(parameters.status)
    // Selector uniqueness must not omit Patients outside caller search scopes.
    Set lookup = ##class(HS.FHIRServer.Storage.JsonAdvSQL.Interactions).%New(interactions.strategy)
    Set rows = lookup.Search("Patient", "", "", parameters)
    $$$ThrowOnError(rows.SearchStatus)
    Return rows
}

ClassMethod EscapeToken(value As %String) As %String
{
    For delimiter = "\", "$", ",", "|" {
        Set value = $Replace(value, delimiter, "\" _ delimiter)
    }
    Return value
}

ClassMethod Authorize(service As HS.FHIRServer.API.Service, resource As %DynamicObject, permission As %String)
{
    If permission '= "c" {
        Do service.interactions.oauth2TokenHandler.VerifyResourceIdRequest(resource.resourceType, resource.id, permission)
    }
    Do service.interactions.oauth2TokenHandler.VerifyResourceContent(resource, permission)
    If (permission = "r") && 'service.interactions.PostProcessRead(..Clone(resource)) {
        $$$ThrowFHIR($$$GeneralError, "Patient merge requires access to every affected resource", $$$OutcomeIs(403, "error", "forbidden"))
    }
}

ClassMethod WriteLimit(interactions As FHIR.Python.Interactions) As %Integer
{
    Set config = interactions.strategy.RepoInstance.strategyConfigData
    If config '= "" {
        Set config = {}.%FromJSON(config)
    } Else {
        Set config = {}
    }
    Return ##class(FHIR.Python.InteractionsStrategy).GetMergeWriteLimit(config)
}

ClassMethod Clone(object)
{
    Set stream = ##class(%Stream.TmpCharacter).%New()
    Do object.%ToJSON(stream)
    Do stream.Rewind()
    Return ##class(%DynamicAbstractObject).%FromJSON(stream)
}

ClassMethod RequireIdentifiers(patient As %DynamicObject, identifiers As %DynamicArray)
{
    Set iterator = identifiers.%GetIterator()
    While iterator.%GetNext(.index, .identifier) {
        If '##class(FHIR.Python.ReferenceUpdater).HasIdentifier(patient, identifier) {
            $$$ThrowFHIR($$$GeneralError, "result-patient omits a provided identifier", $$$OutcomeInvalid(400))
        }
    }
}

ClassMethod CopyIdentifiers(source As %DynamicObject, target As %DynamicObject)
{
    If '$IsObject(source.identifier) {
        Return
    }
    If '$IsObject(target.identifier) {
        Set target.identifier = []
    }
    Set iterator = source.identifier.%GetIterator()
    While iterator.%GetNext(.index, .identifier) {
        Set found = 0
        Set existing = target.identifier.%GetIterator()
        While existing.%GetNext(.targetIndex, .candidate) {
            If (candidate.system = identifier.system) && (candidate.value = identifier.value) {
                Do ..UnionIdentifier(candidate, identifier)
                Set found = 1
                Quit
            }
        }
        If 'found {
            Do target.identifier.%Push(..Clone(identifier))
        }
    }
}

ClassMethod UnionIdentifier(target As %DynamicObject, source As %DynamicObject)
{
    Set iterator = source.%GetIterator()
    While iterator.%GetNext(.property, .value) {
        If 'target.%IsDefined(property) {
            If $IsObject(value) {
                Set value = ..Clone(value)
            }
            Do target.%Set(property, value, source.%GetTypeOf(property))
        } ElseIf (source.%GetTypeOf(property) = "object") && (target.%GetTypeOf(property) = "object") {
            Do ..UnionIdentifier(target.%Get(property), value)
        } ElseIf (source.%GetTypeOf(property) '= target.%GetTypeOf(property)) ||
            (..Canonical(target.%Get(property)) '= ..Canonical(value)) {
            $$$ThrowFHIR($$$GeneralError, "Matching identifiers have conflicting metadata; provide result-patient", $$$OutcomeIs(422, "error", "business-rule"))
        }
    }
}

ClassMethod Canonical(value) As %String
{
    If '$IsObject(value) {
        Return value
    }
    If value.%IsA("%DynamicArray") {
        Set out = [], iterator = value.%GetIterator()
        While iterator.%GetNext(.key, .child) {
            Do out.%Push(..Canonical(child))
        }
        Return out.%ToJSON()
    }
    Set iterator = value.%GetIterator()
    While iterator.%GetNext(.key, .child) {
        Set keys(key) = child
    }
    Set out = {}, key = ""
    For {
        Set key = $Order(keys(key))
        Quit:key=""
        Do out.%Set(key, ..Canonical(keys(key)))
    }
    Return out.%ToJSON()
}

ClassMethod HasLink(patient As %DynamicObject, id As %String, type As %String, bases As %List) As %Boolean
{
    If '$IsObject(patient.link) {
        Return 0
    }
    Set iterator = patient.link.%GetIterator()
    While iterator.%GetNext(.index, .link) {
        If (link.type = type) && $IsObject(link.other) &&
            ##class(FHIR.Python.ReferenceUpdater).PatientReference(link.other.reference, bases, .linkedId, .version, .prefix) &&
            (linkedId = id) && (version = "") {
            Return 1
        }
    }
    Return 0
}

ClassMethod AddLink(patient As %DynamicObject, id As %String, type As %String, bases As %List)
{
    If ..HasLink(patient, id, type, bases) {
        Return
    }
    If '$IsObject(patient.link) {
        Set patient.link = []
    }
    Do patient.link.%Push({"other":{"reference":("Patient/" _ id)},"type":(type)})
}

ClassMethod Provenance(source As %DynamicObject, target As %DynamicObject, changes As %DynamicArray, user As %String) As %DynamicObject
{
    Set provenance = {
        "resourceType":"Provenance",
        "recorded":($ZDateTime($ZTimestamp, 3, 7)),
        "activity":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v3-DataOperation","code":"UPDATE"}],"text":"Patient merge"},
        "target":[],
        "entity":[{"role":"revision","what":{"reference":("Patient/" _ source.id _ "/_history/" _ source.meta.versionId)}}],
        "agent":[{"who":{"display":(user)}}]
    }
    For patient = source, target {
        Set version = $Select(patient.id = source.id:source.meta.versionId, 1:target.meta.versionId) + 1
        Do provenance.target.%Push({"reference":("Patient/" _ patient.id _ "/_history/" _ version)})
    }
    Set iterator = changes.%GetIterator()
    While iterator.%GetNext(.index, .resource) {
        Do provenance.target.%Push({"reference":(resource.resourceType _ "/" _ resource.id _ "/_history/" _ (resource.meta.versionId + 1))})
    }
    Return provenance
}

ClassMethod Outcome(message As %String, writes As %Integer) As %DynamicObject
{
    Return {"resourceType":"OperationOutcome","issue":[{"severity":"information","code":"informational","details":{"text":(message)},"diagnostics":("Merge resource writes: " _ writes)}]}
}

ClassMethod Response(input, outcome As %DynamicObject, patient = "") As %DynamicObject
{
    Set result = {"resourceType":"Parameters","parameter":[]}
    If $IsObject(input) && input.%IsA("%DynamicObject") && (input.resourceType = "Parameters") {
        Do result.parameter.%Push({"name":"input","resource":(..Clone(input))})
    }
    Do result.parameter.%Push({"name":"outcome","resource":(outcome)})
    If $IsObject(patient) {
        Do result.parameter.%Push({"name":"result","resource":(patient)})
    }
    Return result
}

}
