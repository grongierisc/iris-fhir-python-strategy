Include (HS.FHIRMeta, HS.FHIRPath)

Class FHIR.Python.PathResolver Extends HS.FHIRPath.Impl
{

Method Locate(pResource As %DynamicObject, pPath As %String, Output pLocations)
{
    Set input = 1, input(1) = pResource, input(1,"t") = pResource.resourceType
    Set input(1,"pointer") = ""
    Set tree = ..ParsePath(pPath)
    Do ..CheckPath(tree)
    Try {
        Do ..interpretArray(.input, tree, .pLocations)
    } Catch ex {
        If ex.%IsA("%Exception.StatusException") {
            Do ##class(FHIR.Python.FHIRPathPatch).Invalid("Invalid patch path "_pPath_": "_ex.DisplayString())
        }
        Throw ex
    }
    For index = 1:1:pLocations {
        If '$Data(pLocations(index,"pointer")) {
            Do ##class(FHIR.Python.FHIRPathPatch).Invalid("Patch path must select stored elements, not computed values: "_pPath)
        }
    }
}

Method ParsePath(pPath As %String) As HS.FHIRPath.Node
{
    Try {
        Return ##class(HS.FHIRPath.Parser).%New("4.0").parse(pPath)
    } Catch ex {
        // The native parser can report malformed syntax as a runtime exception.
        Do ##class(FHIR.Python.FHIRPathPatch).Invalid("Invalid patch path "_pPath_": "_ex.DisplayString())
    }
}

Method EmptyArray(pResource As %DynamicObject, pPath As %String, Output pTarget)
{
    Set tree = ..ParsePath(pPath)
    If (tree.type '= "ID") || '$IsObject(tree.context) {
        Do ##class(FHIR.Python.FHIRPathPatch).Invalid("insert path must select one repeating element")
    }
    Set input = 1, input(1) = pResource, input(1,"t") = pResource.resourceType, input(1,"pointer") = ""
    Do ..interpretArray(.input, tree.context, .parents)
    Do ##class(FHIR.Python.FHIRPathPatch).RequireSingle(.parents)
    Set owner = parents(1), ownerType = parents(1,"t"), field = tree.name
    If '$IsObject(owner) || 'owner.%IsA("%DynamicObject") || '$$$IsPropertyArray(..schema, ownerType, field) {
        Do ##class(FHIR.Python.FHIRPathPatch).Invalid("insert path must select one repeating element")
    }
    Set array = owner.%Get(field)
    If owner.%IsDefined(field), '$IsObject(array) || 'array.%IsA("%DynamicArray") || array.%Size() {
        Do ##class(FHIR.Python.FHIRPathPatch).Invalid("insert path must select the whole repeating element")
    }
    Set pTarget = {"owner":(owner),"ownerType":(ownerType),"field":(field),"pointer":(parents(1,"pointer")_"/"_..Escape(field)),"type":($$$GetPropertyFHIRType(..schema, ownerType, field)),"ownerPointer":(parents(1,"pointer"))}
}

Method CheckPath(pNode As HS.FHIRPath.Node)
{
    If pNode.type = "ID" {
        If $IsObject(pNode.context) {
            Do ..CheckPath(pNode.context)
        }
    } ElseIf pNode.type = "FN" {
        If ",where,ofType,as,first,last,single,skip,take,tail,subscriptGeneric," '[ (","_pNode.name_",") {
            Do ##class(FHIR.Python.FHIRPathPatch).Invalid("Unsupported patch selector: "_pNode.name)
        }
        If '$IsObject(pNode.context) {
            Do ##class(FHIR.Python.FHIRPathPatch).Invalid("Patch selector requires an element context")
        }
        Do ..CheckPath(pNode.context)
    } ElseIf (pNode.type = "OP") && (pNode.name = "as") {
        Do ..CheckPath(pNode.children.GetAt(1))
    } Else {
        Do ##class(FHIR.Python.FHIRPathPatch).Invalid("Patch path must navigate stored elements")
    }
}

/// Native collections preserve auxiliary subscripts through where(), indexers and type filters.
/// Attach JSON locations during navigation, never by comparing selected values.
Method processID(pNode As HS.FHIRPath.Node, ByRef INPUT, Output OUTPUT)
{
    If $IsObject(pNode.context) {
        Do ..processNode(pNode.context, .INPUT, .contexts)
    } Else {
        Merge contexts = INPUT
    }
    Set OUTPUT = 0
    Set node = ##class(HS.FHIRPath.Node).%New("ID", pNode.name)
    Set node.pushElement = pNode.pushElement
    For index = 1:1:contexts {
        Kill one, selected
        Set one = 1
        Merge one(1) = contexts(index)
        Do ##super(node, .one, .selected)
        If '..schema.IsFHIRType(pNode.name) || ($Extract(pNode.name) '= $ZConvert($Extract(pNode.name),"U")) {
            If $Data(contexts(index,"pointer")), $IsObject(contexts(index)) {
                Set parent = contexts(index), parentType = contexts(index,"t"), field = pNode.name
                Set type = $$$GetPropertyFHIRType(..schema, parentType, field)
                If type = "x-multi", selected {
                    Set field = ..variantFieldName(field, selected(1,"t"))
                }
                If pNode.pushElement, $ListFind($ListBuild("s","n","b"), $$$GetPropertyJsonType(..schema, parentType, pNode.name)) {
                    Set field = "_"_field
                }
                Set value = parent.%Get(field)
                For ordinal = 1:1:selected {
                    // Type filters retain inherited location metadata; navigation gets fresh metadata.
                    Kill selected(ordinal,"parent"), selected(ordinal,"key")
                    Set selected(ordinal,"owner") = parent
                    Set selected(ordinal,"ownerType") = parentType
                    Set selected(ordinal,"field") = field
                    Set selected(ordinal,"schemaField") = pNode.name
                    Set selected(ordinal,"pointer") = contexts(index,"pointer")_"/"_..Escape(field)
                    If $IsObject(value), value.%IsA("%DynamicArray") {
                        Set selected(ordinal,"parent") = value
                        Set selected(ordinal,"key") = ordinal-1
                        Set selected(ordinal,"pointer") = selected(ordinal,"pointer")_"/"_(ordinal-1)
                    } Else {
                        Set selected(ordinal,"parent") = parent
                        Set selected(ordinal,"key") = field
                    }
                }
            }
        }
        For ordinal = 1:1:selected {
            $$$CollPushFromColl(OUTPUT, selected, ordinal)
        }
    }
}

ClassMethod Escape(pName As %String) As %String
{
    Return $Replace($Replace(pName,"~","~0"),"/","~1")
}

}
