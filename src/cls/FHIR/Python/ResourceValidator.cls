Class FHIR.Python.ResourceValidator Extends HS.FHIRServer.Util.ResourceValidator
{

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

		// Call decorator handlers for additional validation
		do ##class(FHIR.Python.Helper).GetCustomizationSettings(.customPath, .customModule)
		
		do ##class(FHIR.Python.Helper).SetPythonPath(customPath)
		set sys = ##class(%SYS.Python).Import("sys")
		do sys.path.insert(0, customPath)
		
		set importlib = ##class(%SYS.Python).Import("importlib")
		do importlib."import_module"(customModule)
		
		set decoratorsModule = ##class(%SYS.Python).Import("fhir_decorators")
		set registry = decoratorsModule.fhir
		
		set resourceType = pResourceObject.resourceType

		// convert pResourceObject to Python object
		set jsonLib = ##class(%SYS.Python).Import("json")
		set resourceJson = pResourceObject.%ToJSON()
		set resourcePyObj = jsonLib.loads(resourceJson)

		set handlers = registry."get_validate_resource_handlers"(resourceType)
		if handlers."__len__"() = 0 {
			do ##super(pResourceObject, pIsInTransaction)
			quit
		}
		set iterator = handlers."__iter__"()
		set handler = ""
		Try {
			for {
				set handler = iterator."__next__"()
				quit:handler=""
				do handler."__call__"(resourcePyObj, pIsInTransaction)
			}
		}
		Catch ex {
			if (ex.Data '[ "StopIteration") { // StopIteration
				throw ex
			}
		}
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
	pCodeableRefInfo As %String) [ Internal ]
{
	// Call superclass to perform standard validation
	set stati = ##super(pFHIRObject, pFHIRTypename, pPath, pStati, pIsInTransaction, pCodeableRefInfo)

	// Call decorator handlers for additional resource validation
	do ##class(FHIR.Python.Helper).GetCustomizationSettings(.customPath, .customModule)
	
	do ##class(FHIR.Python.Helper).SetPythonPath(customPath)
	set sys = ##class(%SYS.Python).Import("sys")
	do sys.path.insert(0, customPath)
	
	set importlib = ##class(%SYS.Python).Import("importlib")
	do importlib."import_module"(customModule)

	set decoratorsModule = ##class(%SYS.Python).Import("fhir_decorators")
	set registry = decoratorsModule.fhir

	set resourceType = pFHIRTypename
	// convert pFHIRObject to Python object
	set jsonLib = ##class(%SYS.Python).Import("json")
	set resourceJson = pFHIRObject.%ToJSON()
	set resourcePyObj = jsonLib.loads(resourceJson)
	set handlers = registry."get_validate_object_handlers"(resourceType)
	if handlers."__len__"() > 0 {
		set iterator = handlers."__iter__"()
		set handler = ""
		Try {
			for {
				set handler = iterator."__next__"()
				quit:handler=""
				do handler."__call__"(resourcePyObj, pPath, .stati, pIsInTransaction)
			}
		}
		Catch ex {
			if (ex.Data '[ "StopIteration") { // StopIteration
				throw ex
			}
		}
	}
	Quit stati
}

}
