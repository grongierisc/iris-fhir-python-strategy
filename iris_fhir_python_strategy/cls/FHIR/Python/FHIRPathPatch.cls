Include (HS.FHIRServer, HS.FHIRMeta)

Class FHIR.Python.FHIRPathPatch
{

ClassMethod Invalid(pMessage As %String)
{
    $$$ThrowFHIR($$$GeneralError, pMessage, $$$OutcomeInvalid(400))
}

ClassMethod Apply(pParameters As %DynamicObject, pResource As %DynamicObject, pSchema As HS.FHIRServer.Schema, pInteractions As FHIR.Python.Interactions) As %Boolean
{
    If '$IsObject(pParameters) || 'pParameters.%IsA("%DynamicObject") || (pParameters.resourceType '= "Parameters") {
        Do ..Invalid("FHIR Patch must be a Parameters resource")
    }
    If '$IsObject(pParameters.parameter) || 'pParameters.parameter.%IsA("%DynamicArray") {
        Do ..Invalid("FHIR Patch Parameters.parameter must be an array")
    }
    Set validator = $ClassMethod(pInteractions.#ResourceValidatorClass, "%New", pSchema)
    Do validator.ValidateExtensionResource(pParameters, 1)
    Do pInteractions.JSONPatch([], pResource)
    Set resolver = ##class(FHIR.Python.PathResolver).%New(pSchema)
    Set changed = 0
    For ordinal = 0:1:pParameters.parameter.%Size()-1 {
        Set operation = pParameters.parameter.%Get(ordinal)
        Kill parts
        Do ..ReadParts(operation, .parts)
        Set kind = parts("type").valueCode, path = parts("path").valueString
        Do resolver.Locate(pResource, path, .locations)
        If locations = 1, ..ProtectedMetadata(locations(1,"pointer")) {
            Continue
        }
        Set operations = []
        If kind = "delete" {
            If locations > 1 {
                Do ..Invalid("delete path must select at most one element")
            }
            If locations = 1 {
                Do ..RequireLocation(.locations)
                Do operations.%Push({"op":"remove","path":(locations(1,"pointer"))})
                Do ..LocationMetadata(operations, .locations, pSchema, "delete")
            }
        } ElseIf kind = "add" {
            Do ..RequireSingle(.locations)
            Set parent = locations(1), parentType = locations(1,"t")
            If '$IsObject(parent) || 'parent.%IsA("%DynamicObject") {
                Do ..Invalid("add path must select an object")
            }
            Set name = parts("name").valueString
            Set expected = $$$GetPropertyFHIRType(pSchema, parentType, name)
            If expected = "" {
                Do ..Invalid("Unknown add element: "_parentType_"."_name)
            }
            Set value = ..Value(parts("value"), pSchema, expected)
            Set field = ..Field(pSchema, parentType, name, value.type)
            Set pointer = locations(1,"pointer")_"/"_##class(FHIR.Python.PathResolver).Escape(field)
            If ..ProtectedMetadata(pointer) {
                Continue
            }
            If $$$IsPropertyArray(pSchema, parentType, name) {
                If parent.%IsDefined(field) {
                    Set array = parent.%Get(field)
                    If '$IsObject(array) || 'array.%IsA("%DynamicArray") {
                        Do ..Invalid("Repeating element must be an array: "_field)
                    }
                    Set pointer = pointer_"/-"
                } Else {
                    Set array = []
                    Do array.%Push(value.value, value.jsonType)
                    Set value.value = array, value.jsonType = ""
                }
            } Else {
                Do ..RequireAbsent(parent, pSchema, parentType, name)
            }
            Do operations.%Push(..JSONOperation("add", pointer, value))
            If $Get(@pSchema.PtiGbl@(value.type),"o") '= "o" {
                Do ..Metadata(operations, parent, field, locations(1,"pointer"), "add", -1, -1, value, $$$IsPropertyArray(pSchema, parentType, name))
            }
        } ElseIf kind = "replace" {
            Do ..RequireSingle(.locations)
            Do ..RequireLocation(.locations)
            Set expected = $$$GetPropertyFHIRType(pSchema, locations(1,"ownerType"), locations(1,"schemaField"))
            Set value = ..Value(parts("value"), pSchema, expected)
            Set field = ..Field(pSchema, locations(1,"ownerType"), locations(1,"schemaField"), value.type)
            If field '= locations(1,"field") {
                Do operations.%Push({"op":"remove","path":(locations(1,"pointer"))})
                Do ..LocationMetadata(operations, .locations, pSchema, "delete")
                Set pointer = $Piece(locations(1,"pointer"),"/",1,*-1)_"/"_field
                Do operations.%Push(..JSONOperation("add", pointer, value))
                If $Get(@pSchema.PtiGbl@(value.type),"o") '= "o" {
                    Do ..Metadata(operations, locations(1,"owner"), field, ..OwnerPointer(.locations), "add", -1, -1, value)
                }
            } Else {
                Do operations.%Push(..JSONOperation("replace", locations(1,"pointer"), value))
                Do ..LocationMetadata(operations, .locations, pSchema, "replace", value)
            }
        } ElseIf (kind = "insert") || (kind = "move") {
            If locations = 0 {
                If kind = "move" {
                    Do ..Invalid("move requires a non-empty repeating element")
                }
                Set index = parts("index").valueInteger
                Do ..CheckIndex(index, 0, 1)
                Do resolver.EmptyArray(pResource, path, .target)
                Set value = ..Value(parts("value"), pSchema, target.type), array = []
                Do array.%Push(value.value, value.jsonType)
                Set arrayValue = {"value":(array),"jsonType":""}
                Do operations.%Push(..JSONOperation("add", target.pointer, arrayValue))
                If $Get(@pSchema.PtiGbl@(value.type),"o") '= "o" {
                    Do ..Metadata(operations, target.owner, target.field, target.ownerPointer, "insert", 0, -1, value, 1)
                }
            } Else {
                Set array = locations(1,"parent")
                If '$IsObject(array) || 'array.%IsA("%DynamicArray") || (locations '= array.%Size()) {
                    Do ..Invalid(kind_" path must select the whole repeating element")
                }
                For index = 1:1:locations {
                    If (locations(index,"parent") '= array) || (locations(index,"key") '= index-1) {
                        Do ..Invalid(kind_" path must select one whole repeating element")
                    }
                }
                Set pointer = $Piece(locations(1,"pointer"),"/",1,*-1)
                If kind = "insert" {
                    Set index = parts("index").valueInteger
                    Do ..CheckIndex(index, array.%Size(), 1)
                    Set expected = $$$GetPropertyFHIRType(pSchema, locations(1,"ownerType"), locations(1,"schemaField"))
                    Set value = ..Value(parts("value"), pSchema, expected)
                    Do operations.%Push(..JSONOperation("add", pointer_"/"_index, value))
                    Do ..LocationMetadata(operations, .locations, pSchema, "insert", value, index)
                } Else {
                    Set source = parts("source").valueInteger, destination = parts("destination").valueInteger
                    Do ..CheckIndex(source, array.%Size())
                    Do ..CheckIndex(destination, array.%Size())
                    If source '= destination {
                        Do operations.%Push({"op":"move","from":(pointer_"/"_source),"path":(pointer_"/"_destination)})
                        Do ..LocationMetadata(operations, .locations, pSchema, "move", "", source, destination)
                    }
                }
            }
        }
        If operations.%Size() {
            Set changed = pInteractions.JSONPatch(operations, pResource) || changed
        }
    }
    // Native PATCH dispatch invokes the target's Python validator before persisting changes.
    Do validator.ValidateNativeResource(pResource, 1)
    Return changed
}

ClassMethod ProtectedMetadata(pPointer As %String) As %Boolean
{
    Return (pPointer = "/meta/versionId") || (pPointer = "/meta/lastUpdated")
}

ClassMethod ReadParts(pOperation, Output pParts)
{
    If '$IsObject(pOperation) || 'pOperation.%IsA("%DynamicObject") || (pOperation.name '= "operation") {
        Do ..Invalid("Each patch parameter must be named operation")
    }
    If '$IsObject(pOperation.part) || 'pOperation.part.%IsA("%DynamicArray") {
        Do ..Invalid("operation.part must be an array")
    }
    Do ..CheckContent(pOperation, "part")
    For index = 0:1:pOperation.part.%Size()-1 {
        Set part = pOperation.part.%Get(index)
        If '$IsObject(part) || 'part.%IsA("%DynamicObject") || (part.%GetTypeOf("name") '= "string") {
            Do ..Invalid("Each operation part must be an object")
        }
        Set name = part.name
        If (name = "") || $Data(pParts(name)) {
            Do ..Invalid("Missing or duplicate operation part: "_name)
        }
        Set pParts(name) = part
    }
    For name = "type", "path" {
        If '$Data(pParts(name)) {
            Do ..Invalid("Missing operation part: "_name)
        }
    }
    Set kind = pParts("type").valueCode
    Set required = $Case(kind,"add":"name,value","insert":"index,value","delete":"","replace":"value","move":"source,destination",:"?")
    If required = "?" {
        Do ..Invalid("Unknown FHIR Patch operation: "_kind)
    }
    If (pParts("type").%GetTypeOf("valueCode") '= "string") || (pParts("path").%GetTypeOf("valueString") '= "string") || (pParts("path").valueString = "") {
        Do ..Invalid("type.valueCode and path.valueString are required")
    }
    For index = 1:1:$Length(required,",") {
        Set name = $Piece(required,",",index)
        If (name '= ""), '$Data(pParts(name)) {
            Do ..Invalid("Missing operation part: "_name)
        }
    }
    Set name = ""
    For {
        Set name = $Order(pParts(name))
        Quit:(name = "")
        If (name '= "type") && (name '= "path") && ((","_required_",") '[ (","_name_",")) {
            Do ..Invalid("Unexpected operation part: "_name)
        }
        If name = "name", (pParts(name).%GetTypeOf("valueString") '= "string") || (pParts(name).valueString = "") {
            Do ..Invalid("name.valueString is required")
        }
        If (name = "index") || (name = "source") || (name = "destination") {
            If pParts(name).%GetTypeOf("valueInteger") '= "number" {
                Do ..Invalid(name_".valueInteger is required")
            }
        }
        If name '= "value" {
            Set key = $Case(name,"type":"valueCode","path":"valueString","name":"valueString",:"valueInteger")
            Do ..CheckContent(pParts(name), key)
        }
    }
}

ClassMethod CheckContent(pPart As %DynamicObject, pAllowed As %String)
{
    Set iterator = pPart.%GetIterator()
    While iterator.%GetNext(.key) {
        If ((key = "part") || (key = "resource") || ($Extract(key,1,5) = "value") || ($Extract(key,1,6) = "_value")), (key '= pAllowed), (key '= "_"_pAllowed) {
            Do ..Invalid("Unexpected parameter content: "_key)
        }
    }
}

ClassMethod RequireAbsent(pOwner As %DynamicObject, pSchema As HS.FHIRServer.Schema, pType As %String, pName As %String)
{
    Set types = $ListBuild("")
    If $$$GetPropertyFHIRType(pSchema, pType, pName) = "x-multi" {
        Set types = $$$GetPropertyFHIRTypeList(pSchema, pType, pName)
    }
    For index = 1:1:$ListLength(types) {
        Set type = $List(types,index), field = pName
        If type '= "" {
            Set field = ..Field(pSchema, pType, pName, type)
        }
        If pOwner.%IsDefined(field) || pOwner.%IsDefined("_"_field) {
            Do ..Invalid("add cannot overwrite an existing element: "_pName)
        }
    }
}

ClassMethod RequireSingle(ByRef pLocations)
{
    If pLocations '= 1 {
        Do ..Invalid("Patch path must select exactly one element")
    }
}

ClassMethod RequireLocation(ByRef pLocations)
{
    If '$Data(pLocations(1,"parent")) || (pLocations(1,"pointer") = "") {
        Do ..Invalid("Cannot delete or replace the resource root")
    }
}

ClassMethod CheckIndex(pIndex, pSize As %Integer, pAllowEnd As %Boolean = 0)
{
    If (pIndex < 0) || (pIndex \ 1 '= pIndex) || (pIndex >= (pSize+pAllowEnd)) {
        Do ..Invalid("Patch index out of range: "_pIndex)
    }
}

ClassMethod Field(pSchema As HS.FHIRServer.Schema, pType As %String, pName As %String, pValueType As %String) As %String
{
    If $$$GetPropertyFHIRType(pSchema, pType, pName) = "x-multi" {
        If '$ListFind($$$GetPropertyFHIRTypeList(pSchema, pType, pName), pValueType) {
            Do ..Invalid("Invalid choice datatype: "_pValueType)
        }
        Return pName_$ZConvert($Extract(pValueType),"U")_$Extract(pValueType,2,*)
    }
    Return pName
}

ClassMethod Value(pPart As %DynamicObject, pSchema As HS.FHIRServer.Schema, pExpected As %String) As %DynamicObject
{
    If '$IsObject(pPart) || 'pPart.%IsA("%DynamicObject") {
        Do ..Invalid("value must be a parameter object")
    }
    Set result = {}, count = 0, iterator = pPart.%GetIterator()
    While iterator.%GetNext(.key, .value) {
        If $Extract(key,1,5) = "value" {
            Set count = count+1, type = $Extract(key,6,*)
            If 'pSchema.IsFHIRType(type) {
                Set type = $ZConvert($Extract(type),"L")_$Extract(type,2,*)
            }
            If 'pSchema.IsFHIRType(type) {
                Do ..Invalid("Unknown value datatype: "_key)
            }
            Set result.type = type, result.jsonType = pPart.%GetTypeOf(key)
            Set jsonType = $Case($Get(@pSchema.PtiGbl@(type),"o"),"s":"string","n":"number","b":"boolean","o":"object",:"?")
            If result.jsonType '= jsonType {
                Do ..Invalid("Invalid JSON type for "_key_": expected "_jsonType)
            }
            If pPart.%IsDefined("_"_key) {
                If (jsonType = "object") || '$IsObject(pPart.%Get("_"_key)) || 'pPart.%Get("_"_key).%IsA("%DynamicObject") {
                    Do ..Invalid("Primitive metadata must be an Element object")
                }
                Set result.metadata = pPart.%Get("_"_key)
            }
            If (result.jsonType = "object") || (result.jsonType = "array") {
                Set result.jsonType = ""
            }
            Do result.%Set("value", value, result.jsonType)
        } ElseIf key = "resource" {
            Set count = count+1
            If '$IsObject(value) || 'value.%IsA("%DynamicObject") {
                Do ..Invalid("value.resource must be a resource object")
            }
            Set result.type = value.resourceType, result.jsonType = "", result.value = value
            If (result.type = "") || 'pSchema.IsA(result.type, "Resource") {
                Do ..Invalid("value.resource must have a valid resourceType")
            }
        }
    }
    If pPart.%IsDefined("part") {
        If (count '= 0) || (pExpected = "x-multi") || '$IsObject(pPart.part) || 'pPart.part.%IsA("%DynamicArray") || ($Get(@pSchema.PtiGbl@(pExpected),"o") '= "o") {
            Do ..Invalid("Anonymous value requires one concrete complex datatype")
        }
        Set result.type = pExpected, result.jsonType = "", result.value = {}
        For index = 0:1:pPart.part.%Size()-1 {
            Set part = pPart.part.%Get(index)
            If '$IsObject(part) || 'part.%IsA("%DynamicObject") || (part.%GetTypeOf("name") '= "string") {
                Do ..Invalid("Anonymous value part must be an object")
            }
            Set name = part.name, expected = $$$GetPropertyFHIRType(pSchema, pExpected, name)
            If expected = "" {
                Do ..Invalid("Unknown anonymous value element: "_pExpected_"."_name)
            }
            Set child = ..Value(part, pSchema, expected)
            Set field = ..Field(pSchema, pExpected, name, child.type)
            If $$$IsPropertyArray(pSchema, pExpected, name) {
                If 'result.value.%IsDefined(field) {
                    Do result.value.%Set(field, [])
                }
                Do result.value.%Get(field).%Push(child.value, child.jsonType)
            } Else {
                Do ..RequireAbsent(result.value, pSchema, pExpected, name)
                Do result.value.%Set(field, child.value, child.jsonType)
            }
            If child.%IsDefined("metadata") {
                If $$$IsPropertyArray(pSchema, pExpected, name) {
                    If 'result.value.%IsDefined("_"_field) {
                        Do result.value.%Set("_"_field, [])
                    }
                    Set metadata = result.value.%Get("_"_field)
                    While metadata.%Size() < result.value.%Get(field).%Size()-1 {
                        Do metadata.%Push("", "null")
                    }
                    Do metadata.%Push(child.metadata)
                } Else {
                    Do result.value.%Set("_"_field, child.metadata)
                }
            } ElseIf $$$IsPropertyArray(pSchema, pExpected, name), result.value.%IsDefined("_"_field) {
                Do result.value.%Get("_"_field).%Push("", "null")
            }
        }
        Set count = 1
    }
    If count '= 1 {
        Do ..Invalid("value must contain exactly one value[x], resource, or part")
    }
    If (pExpected '= "x-multi"), (result.type '= pExpected), 'pSchema.IsA(result.type, pExpected) {
        Do ..Invalid("Expected "_pExpected_", received "_result.type)
    }
    Return result
}

ClassMethod OwnerPointer(ByRef pLocations) As %String
{
    Set count = $Length(pLocations(1,"pointer"),"/")-1
    If pLocations(1,"parent").%IsA("%DynamicArray") {
        Set count = count-1
    }
    Return $Piece(pLocations(1,"pointer"),"/",1,count)
}

ClassMethod LocationMetadata(pOperations As %DynamicArray, ByRef pLocations, pSchema As HS.FHIRServer.Schema, pKind As %String, pValue = "", pIndex As %Integer = -1, pDestination As %Integer = -1)
{
    If $Get(@pSchema.PtiGbl@(pLocations(1,"t")),"o") = "o" {
        Return
    }
    Set isArray = pLocations(1,"parent").%IsA("%DynamicArray")
    If isArray, pIndex = -1 {
        Set pIndex = pLocations(1,"key")
    }
    Do ..Metadata(pOperations, pLocations(1,"owner"), pLocations(1,"field"), ..OwnerPointer(.pLocations), pKind, pIndex, pDestination, pValue, isArray)
}

/// Rebuild primitive metadata arrays alongside values, including null padding.
ClassMethod Metadata(pOperations As %DynamicArray, pOwner As %DynamicObject, pField As %String, pPointer As %String, pKind As %String, pIndex As %Integer = -1, pDestination As %Integer = -1, pValue = "", pArray As %Boolean = 0)
{
    Set field = "_"_pField, pointer = pPointer_"/"_##class(FHIR.Python.PathResolver).Escape(field)
    Set hasValue = $IsObject(pValue) && pValue.%IsDefined("metadata")
    Set exists = pOwner.%IsDefined(field)
    If 'exists && 'hasValue {
        Return
    }
    If 'pArray {
        If hasValue && (pKind '= "delete") {
            Set descriptor = {"value":(pValue.metadata),"jsonType":""}
            Do pOperations.%Push(..JSONOperation("add", pointer, descriptor))
        } ElseIf exists {
            Do pOperations.%Push({"op":"remove","path":(pointer)})
        }
        Return
    }
    Set metadata = pOwner.%Get(field), values = pOwner.%Get(pField), size = 0
    If $IsObject(values), values.%IsA("%DynamicArray") {
        Set size = values.%Size()
    }
    If exists {
        If '$IsObject(metadata) || 'metadata.%IsA("%DynamicArray") {
            Do ..Invalid("Repeating primitive metadata must be an array: "_field)
        }
        If metadata.%Size() > size {
            Do ..Invalid("Extension-only primitive array suffixes are not supported: "_field)
        }
    } Else {
        Set metadata = []
    }
    If pKind = "add" {
        Set pIndex = size, pKind = "insert"
    }
    Set newSize = size+$Case(pKind,"insert":1,"delete":-1,:0), result = [], nonNull = 0
    For index = 0:1:newSize-1 {
        Set source = index, replacement = 0
        If pKind = "delete", index >= pIndex {
            Set source = index+1
        } ElseIf pKind = "insert" {
            Set replacement = index=pIndex
            If index > pIndex {
                Set source = index-1
            }
        } ElseIf pKind = "replace" {
            Set replacement = index=pIndex
        } ElseIf pKind = "move" {
            If index = pDestination {
                Set source = pIndex
            } ElseIf (pIndex < pDestination) && (index >= pIndex) && (index < pDestination) {
                Set source = index+1
            } ElseIf (pIndex > pDestination) && (index > pDestination) && (index <= pIndex) {
                Set source = index-1
            }
        }
        If replacement {
            If hasValue {
                Do result.%Push(pValue.metadata)
                Set nonNull = 1
            } Else {
                Do result.%Push("", "null")
            }
        } ElseIf metadata.%GetTypeOf(source) = "object" {
            Do result.%Push(metadata.%Get(source))
            Set nonNull = 1
        } Else {
            Do result.%Push("", "null")
        }
    }
    If nonNull {
        Set descriptor = {"value":(result),"jsonType":""}
        Do pOperations.%Push(..JSONOperation("add", pointer, descriptor))
    } ElseIf exists {
        Do pOperations.%Push({"op":"remove","path":(pointer)})
    }
}

ClassMethod JSONOperation(pKind As %String, pPath As %String, pValue As %DynamicObject) As %DynamicObject
{
    Set operation = {"op":(pKind),"path":(pPath)}
    Do operation.%Set("value", pValue.value, pValue.jsonType)
    Return operation
}

}
