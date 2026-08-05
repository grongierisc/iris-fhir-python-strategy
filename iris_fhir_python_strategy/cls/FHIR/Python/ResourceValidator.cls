Class FHIR.Python.ResourceValidator Extends (HS.FHIRServer.Util.ResourceValidator, FHIR.Python.Helper)
{

Property Registry As %SYS.Python;

Method GetRegistry() As %SYS.Python
{
    if '$IsObject(..Registry) {
        // Call decorator handlers for additional validation
        do ..GetCustomizationSettings(.customPath, .customModule)
        
        do ..SetPythonPath(customPath)
        
        do ..TryImportModule(customModule, .module)
        
        set decoratorsModule = ##class(%SYS.Python).Import("iris_fhir_python_strategy")
        set ..Registry = decoratorsModule.fhir
    }
    return ..Registry
}

/// @API
/// ValidateResource validates a FHIR Resource.  If a validation error is found, a
/// compound %Status is thrown in a StatusException.  The compound %Status starts with a
/// $$$ValidationFailure code, followed by additional %Status objects for each detected
/// validation error.
/// Inputs:
/// <li>pJsonResource           : (required) %DynamicObject representation of the FHIR resource.
/// <li>Throws					: A StatusException containing a compound %Status representing all
///                             : validation errors.
Method ValidateResource(
	pResourceObject As %DynamicObject,
	pIsInTransaction As %Boolean = 0)
{
	// Skip validation for Bundle entries (handled by BundleValidator)
	if ($get(%inTransactionFlag, $$$NO) '= $$$YES) && (pResourceObject.resourceType '= "CapabilityStatement")
	{
        set registry = ..GetRegistry()
		
		set resourceType = pResourceObject.resourceType

		set jsonLib = ##class(%SYS.Python).Import("json")
		try {
			set jsonStr = pResourceObject.%ToJSON()
			set resourcePyObj = jsonLib.loads(jsonStr)
		} catch ex {
			do ##class(%SYS.System).WriteToConsoleLog("ResourceValidator.ValidateResource: catch ex="_ex.DisplayString(), 0, "FHIR.Python")
			if (ex.Name '= "<MAXSTRING>") && (ex.Name '= "<STRINGSTACK>") throw ex
			try {
				set io = ##class(%SYS.Python).Import("io")
				set jsonStream = ##class(%Stream.TmpCharacter).%New()
				do pResourceObject.%ToJSON(jsonStream)
				do jsonStream.Rewind()
				set pyStream = io.StringIO()
				while 'jsonStream.AtEnd { do pyStream.write(jsonStream.Read(32000)) }
				do pyStream.seek(0)
				set resourcePyObj = jsonLib.load(pyStream)
			} catch exStream {
				do ##class(%SYS.System).WriteToConsoleLog("ResourceValidator.ValidateResource: stream fallback failed - "_exStream.DisplayString(), 2, "FHIR.Python")
				throw exStream
			}
		}

		set handlers = registry."get_on_validate_resource_handlers"(resourceType)

		if handlers."__len__"() = 0 {
			do ##super(pResourceObject, pIsInTransaction)
			quit
		}
		
		do ..RunValidationHandlers(handlers, resourcePyObj, pIsInTransaction)
	}
}

/// This internal method validates the properties of a single class in the FHIR Schema.  If the class contains
/// properties that are objects, then this call is recursed with the sub-object(s)
/// Inputs:<br>
/// pFHIRObject      : The JSON object to validate. <br>
/// pFHIRTypename      : The classname in the FHIR Schema.<br>
/// pPath            : A FHIR-path representation to the object begin verified<br>
/// pStati           : The accumulated status from previous validations.  This invocation will append
///                    the details of any validation failures found.<br>
/// pIsInTransaction : Boolean flag to indicate a condition that affects the evaluation of reference urls.
/// pCodeableRefInfo : Type information related to the CodeableReference data type.
/// Returns:         : An updated status with any additional validation errors included.
Method ValidateObject(
	pFHIRObject As %Library.DynamicObject,
	pFHIRTypename As %String,
	pPath As %String,
	pStati As %Status,
	pIsInTransaction As %Boolean = 0,
	pCodeableRefInfo As %String = "") [ Internal ]
{
	// Call superclass to perform standard validation
	set stati = ##super(pFHIRObject, pFHIRTypename, pPath, pStati, pIsInTransaction, pCodeableRefInfo)

    set registry = ..GetRegistry()

	set resourceType = pFHIRTypename
	set jsonLib = ##class(%SYS.Python).Import("json")
	try {
		set jsonStr = pFHIRObject.%ToJSON()
		set resourcePyObj = jsonLib.loads(jsonStr)
	} catch ex {
		do ##class(%SYS.System).WriteToConsoleLog("ResourceValidator.ValidateObject: catch ex="_ex.DisplayString(), 0, "FHIR.Python")
		if (ex.Name '= "<MAXSTRING>") && (ex.Name '= "<STRINGSTACK>") throw ex
		try {
			set io = ##class(%SYS.Python).Import("io")
			set jsonStream = ##class(%Stream.TmpCharacter).%New()
			do pFHIRObject.%ToJSON(jsonStream)
			do jsonStream.Rewind()
			set pyStream = io.StringIO()
			while 'jsonStream.AtEnd { do pyStream.write(jsonStream.Read(32000)) }
			do pyStream.seek(0)
			set resourcePyObj = jsonLib.load(pyStream)
		} catch exStream {
			do ##class(%SYS.System).WriteToConsoleLog("ResourceValidator.ValidateObject: stream fallback failed - "_exStream.DisplayString(), 2, "FHIR.Python")
			throw exStream
		}
	}
	set pyBuiltins = ##class(%SYS.Python).Import("builtins")
	if pyBuiltins.hasattr(registry, "get_validate_object_handlers") {
		set handlers = registry."get_validate_object_handlers"(resourceType)
		if handlers."__len__"() > 0 {
			set len = handlers."__len__"()
			set sc = $$BeginCapture^%SYS.Capture(.msg)
			try {
				for i=0:1:len-1 {
					set handler = handlers."__getitem__"(i)
					do handler."__call__"(resourcePyObj, pPath, .stati, pIsInTransaction)
				}
			} catch ex {
				set sc = $$EndCapture^%SYS.Capture(msg,.msgArray)
				set ex = ..RecoverPythonException(ex)
				do ..HandlePythonException(ex)
				throw ex
			}
			set sc = $$EndCapture^%SYS.Capture(msg,.msgArray)
		}
	}
	Quit stati
}

}
