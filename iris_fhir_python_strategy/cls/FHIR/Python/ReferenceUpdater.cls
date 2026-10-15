Include HS.FHIRServer

Class FHIR.Python.ReferenceUpdater Extends %RegisteredObject
{

Property Metadata As HS.FHIRMeta.API;

Property BaseURLs As %List;

Property Source As %DynamicObject;

Property TargetId As %String;

Property Changed As %Boolean [ Private ];

Property Signed As %Boolean;

Method Process(resource As %DynamicObject) As %Boolean
{
    Set ..Changed = 0, ..Signed = 0
    Do ..Visit(resource, resource.resourceType)
    If ..Changed && ..Signed {
        $$$ThrowFHIR($$$GeneralError, "Merge would invalidate a resource signature", $$$OutcomeIs(422, "error", "business-rule"))
    }
    Return ..Changed
}

Method Visit(node, type As %String, lineage As %Boolean = 0)
{
    If '$IsObject(node) {
        Return
    }
    If node.%IsA("%DynamicArray") {
        Set iterator = node.%GetIterator()
        While iterator.%GetNext(.index, .value) {
            Do ..Visit(value, type, lineage)
        }
        Return
    }
    If (type = "Resource") || (type = "DomainResource") {
        Set type = node.resourceType
    }
    If type = "Signature" {
        Set ..Signed = 1
    }
    If (type = "Reference") && 'lineage {
        Do ..Reference(node)
    }
    Set iterator = node.%GetIterator()
    While iterator.%GetNext(.property, .value) {
        If '$IsObject(value) {
            Continue
        }
        Set childType = ..Metadata.GetPropertyFHIRType(type, property)
        If $Extract(property) = "_" {
            Set childType = "Element"
        }
        If childType = "" {
            $$$ThrowFHIR($$$GeneralError, "Cannot determine FHIR type for " _ type _ "." _ property, $$$OutcomeIs(422, "error", "not-supported"))
        }
        Set preserveLink = (type = "Patient.link") && (property = "other") &&
            ((node.type = "replaces") || (node.type = "replaced-by"))
        Do ..Visit(value, childType, preserveLink)
    }
}

Method Reference(reference As %DynamicObject)
{
    Set local = ..PatientReference(reference.reference, ..BaseURLs, .id, .version, .prefix)
    If local && (id = ..Source.id) {
        If version '= "" {
            $$$ThrowFHIR($$$GeneralError, "Merge requires rewriting a version-specific Patient reference", $$$OutcomeIs(422, "error", "not-supported"))
        }
        Set reference.reference = prefix _ "Patient/" _ ..TargetId
        Set ..Changed = 1
    } ElseIf (reference.reference = "") && $IsObject(reference.identifier) &&
        ((reference.type = "") || ($Piece(reference.type, "/", *) = "Patient")) &&
        ..HasIdentifier(..Source, reference.identifier) {
        $$$ThrowFHIR($$$GeneralError, "Merge requires resolving an identifier-only Patient reference", $$$OutcomeIs(422, "error", "not-supported"))
    }
}

ClassMethod PatientReference(reference As %String, bases As %List, Output id As %String, Output version As %String, Output prefix As %String) As %Boolean
{
    Set id = "", version = "", prefix = ""
    Set path = reference
    If $Extract(path, 1, 8) '= "Patient/" {
        Set matched = 0
        For i = 1:1:$ListLength(bases) {
            Set base = $ListGet(bases, i)
            If base = "" {
                Continue
            }
            If $Extract(base, *) '= "/" {
                Set base = base _ "/"
            }
            If $Extract(reference, 1, $Length(base)) = base {
                Set path = $Extract(reference, $Length(base) + 1, *)
                Set prefix = base, matched = 1
                Quit
            }
        }
        If 'matched {
            Return 0
        }
    }
    If $Piece(path, "/") '= "Patient" {
        Return 0
    }
    Set id = $Piece(path, "/", 2)
    If '..ValidId(id) {
        Return 0
    }
    If $Length(path, "/") = 2 {
        Return 1
    }
    If ($Length(path, "/") = 4) && ($Piece(path, "/", 3) = "_history") &&
        ..ValidId($Piece(path, "/", 4)) {
        Set version = $Piece(path, "/", 4)
        Return 1
    }
    Set id = ""
    Return 0
}

ClassMethod ValidId(id As %String) As %Boolean
{
    If (id = "") || ($Length(id) > 64) {
        Return 0
    }
    Return $Translate(id, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-.") = ""
}

ClassMethod IsMerged(patient As %DynamicObject) As %Boolean
{
    If '$IsObject(patient.link) {
        Return 0
    }
    Set iterator = patient.link.%GetIterator()
    While iterator.%GetNext(.index, .link) {
        If link.type = "replaced-by" {
            Return 1
        }
    }
    Return 0
}

ClassMethod HasIdentifier(patient As %DynamicObject, identifier As %DynamicObject) As %Boolean
{
    If '$IsObject(patient.identifier) {
        Return 0
    }
    Set iterator = patient.identifier.%GetIterator()
    While iterator.%GetNext(.index, .candidate) {
        If (candidate.value = identifier.value) &&
            ((identifier.system = "") || (candidate.system = identifier.system)) {
            Return 1
        }
    }
    Return 0
}

}
