Include (HS.FHIRServer, HS.HC.InstanceConfig, HS.HC)

Class FHIR.Python.Helper Extends %RegisteredObject
{

Property PythonClass As %SYS.Python;

Property PythonModule As %String;

Property PythonPath As %String;

Property PythonClassname As %String;

Parameter TRACEBACKS = 1;

ClassMethod SetPythonPath(pClasspaths)
{
    set sys = ##class(%SYS.Python).Import("sys")
    if (sys.path."__len__"() > 0) && (sys.path."__getitem__"(0) = pClasspaths) { Quit }

    while (sys.path."__contains__"(pClasspaths)) {
        do sys.path.remove(pClasspaths)
    }
    do sys.path.insert(0, pClasspaths)
}

ClassMethod GetPythonInstance(
	pModule,
	pRemoteClassname) As %SYS.Python
{
    set builtins = ##class(%SYS.Python).Import("builtins")
    if '..TryImportModule(pModule, .module) {
        quit ""
    }

    set class = builtins.getattr(module, pRemoteClassname)
    return class."__new__"(class)
}

ClassMethod TryImportModule(
	pModule As %String,
	Output pModuleObj As %SYS.Python,
	pReload As %Boolean = 0) As %Boolean
{
	set pModuleObj = ""
	set importlib = ##class(%SYS.Python).Import("importlib")
	Try {

		/// Trace debugging
		/// Uncomment to display python tracebacks rest calls
		/// Warning every HTTP code will be 200 OK
		do $system.Python.Debugging(..#TRACEBACKS)
		/// End trace debugging

		set pModuleObj = importlib."import_module"(pModule)
		if pReload {
			do importlib."reload"(pModuleObj)
		}
		return 1
	}
	Catch ex {
		// Allow the server to start even when customization module is missing.
		return 0
	}
}

ClassMethod GetCustomizationSettings(
	Output pPythonPath As %String,
	Output pPythonModule As %String) As %Status
{
	set pPythonPath = $system.Util.GetEnviron("FHIR_CUSTOMIZATION_PATH")
	set pPythonModule = $system.Util.GetEnviron("FHIR_CUSTOMIZATION_MODULE")

	if (pPythonPath = "") || (pPythonModule = "") {
		set pPythonPath = "/irisdev/app/"
		set pPythonModule = "iris_fhir_python_strategy"
	}

	quit $$$OK
}

ClassMethod DeleteFHIRData(pFHIRData As %String)
{
    set strategy = ##class(HS.FHIRServer.API.InteractionsStrategy).GetStrategyForEndpoint(pFHIRData)
    set options("deleteDataOnly") = 1
    do strategy.Delete(.options)
}

ClassMethod GetPythonTraceback() As %String
{
    set tbString = ""
    try {
        set sys = ##class(%SYS.Python).Import("sys")
        set tracebackModule = ##class(%SYS.Python).Import("traceback")
        
        set traceback = sys."last_traceback"
        if $isObject(traceback) {
             set tb = tracebackModule."format_exception"(sys."last_type", sys."last_value", traceback)
             for i=0:1:(tb."__len__"()-1) {
                set tbString = tbString _ tb."__getitem__"(i)
             }
        }
    } catch {
        // ignore errors getting traceback
    }
    quit tbString
}

ClassMethod RecoverPythonException(pEx As %Exception.AbstractException) As %Exception.PythonException
{
    set newEx = pEx
    if ..#TRACEBACKS {
        try {
            set sys = ##class(%SYS.Python).Import("sys")
            set pyEx = sys."last_value"
            set tbString = ..GetPythonTraceback()
            
            if (tbString '= "") {
                 set newEx = ##class(%Exception.PythonException).%New(sys."last_value", "", "", "", $$$NULLOREF, tbString, pyEx)
            }
        } catch {
            // ignore
        }
    }
    // Ensure it's a PythonException
    if 'newEx.%IsA("%Exception.PythonException") {
         set newEx = ##class(%Exception.PythonException).%New(pEx.DisplayString())
    }
    return newEx
}

ClassMethod RunHandlers(
	handlers As %SYS.Python,
	args...)
{
    if handlers."__len__"() = 0 Quit 
    set len = handlers."__len__"()
    set sc = $$BeginCapture^%SYS.Capture(.msg)
    try {
        for i=0:1:len-1 {
            set handler = handlers."__getitem__"(i)
            if $Get(args) = 0 do handler."__call__"()
            if $Get(args) = 1 do handler."__call__"(args(1))
            if $Get(args) = 2 do handler."__call__"(args(1), args(2))
            if $Get(args) = 3 do handler."__call__"(args(1), args(2), args(3))
            if $Get(args) = 4 do handler."__call__"(args(1), args(2), args(3), args(4))
            if $Get(args) = 5 do handler."__call__"(args(1), args(2), args(3), args(4), args(5))
        }
    } catch ex {
        set sc = $$EndCapture^%SYS.Capture(msg,.msgArray)
        set ex = ##class(FHIR.Python.Helper).RecoverPythonException(ex)
        do ##class(FHIR.Python.Helper).HandlePythonException(ex)
        throw ex
    }
    set sc = $$EndCapture^%SYS.Capture(msg,.msgArray)
}

ClassMethod RunBooleanHandlers(
	handlers As %SYS.Python,
	args...) As %Boolean
{
    if handlers."__len__"() = 0 Quit 1
    set len = handlers."__len__"()
    set sc = $$BeginCapture^%SYS.Capture(.msg)
    try {
        for i=0:1:len-1 {
            set handler = handlers."__getitem__"(i)
            if $Get(args) = 0 set result = handler."__call__"()
            if $Get(args) = 1 set result = handler."__call__"(args(1))
            if $Get(args) = 2 set result = handler."__call__"(args(1), args(2))
            if $Get(args) = 3 set result = handler."__call__"(args(1), args(2), args(3))
            if $Get(args) = 4 set result = handler."__call__"(args(1), args(2), args(3), args(4))
            if $Get(args) = 5 set result = handler."__call__"(args(1), args(2), args(3), args(4), args(5))
            
            if 'result {
                 set sc = $$EndCapture^%SYS.Capture(msg,.msgArray)
                 return 0
            }
        }
    } catch ex {
        set sc = $$EndCapture^%SYS.Capture(msg,.msgArray)
        set ex = ##class(FHIR.Python.Helper).RecoverPythonException(ex)
        do ##class(FHIR.Python.Helper).HandlePythonException(ex)
        throw ex
    }
    set sc = $$EndCapture^%SYS.Capture(msg,.msgArray)
    return 1
}

ClassMethod HandlePythonException(pEx As %Exception.PythonException)
{
    // Default to 500 if not recognized
    Set tHTTPCode = 500
    Set tCode = "exception"
    Set tSeverity = "error"
    Set tDetailsText = pEx.DisplayString()
    Set msg = tDetailsText
    
    // Attempt to inspect Python exception type
    // pEx.ExceptionObject is the Python exception instance
    if $IsObject(pEx.ExceptionObject) {
        Try {
            set builtins = ##class(%SYS.Python).Import("builtins")
            set typeObj = builtins.type(pEx.ExceptionObject)
            set typeStr = ""_typeObj."__name__"
            
            set msg = ""_builtins.str(pEx.ExceptionObject)
            
            // If the object is the class itself (type="type"), retrieve name from object and msg from Data
            if (typeStr = "type") {
                 set typeStr = ""_pEx.ExceptionObject."__name__"
                 // Data format: <class 'module.ValueError'>: Message or <class 'ValueError'>: Message
                 // We extract the message after the first ": "
                 set startMsg = $Find(pEx.Data, ": ")
                 if (startMsg > 0) {
                     set msg = $Extract(pEx.Data, startMsg, *)
                 }
            }
            
            if (typeStr = "ValueError") {
                set tHTTPCode = 400
                set tCode = "invalid"
                set tDetailsText = msg
            }
            elseif (typeStr = "PermissionError") {
                set tHTTPCode = 403
                set tCode = "forbidden"
                set tDetailsText = msg
            }
            elseif (typeStr = "FileNotFoundError") {
                set tHTTPCode = 404
                set tCode = "not-found"
                set tDetailsText = msg
            }
        } Catch exInternal {
            // Logic failed, stick to defaults
             Set msg = "Internal Error: " _ exInternal.DisplayString()
        }
    }
    
    // Append Traceback if enabled
    if ..#TRACEBACKS {
        set tb = ..GetPythonTraceback()
    }
	if ..#TRACEBACKS {
	    	set oneError = $$$ERROR($$$PythonGeneralError, msg, $$$OutcomeWithPath(tHTTPCode, "error", tCode, tb))

	}
	else {
		set oneError = $$$ERROR($$$GeneralError, msg, $$$OutcomeWithPath(tHTTPCode, "error", tCode, ""))
	}
	
	$$$ThrowOnError(oneError)
}

/// Run validation handlers that may raise exceptions OR return an OperationOutcome dict.
/// Errors from all handlers are aggregated before throwing.
ClassMethod RunValidationHandlers(
	handlers As %SYS.Python,
	args...)
{
	if handlers."__len__"() = 0 Quit
	set len = handlers."__len__"()
	set jsonLib = ##class(%SYS.Python).Import("json")
	set errorStatus = $$$OK
	set sc = $$BeginCapture^%SYS.Capture(.msg)
	try {
		for i=0:1:len-1 {
			set handler = handlers."__getitem__"(i)
			if $Get(args) = 0 set result = handler."__call__"()
			if $Get(args) = 1 set result = handler."__call__"(args(1))
			if $Get(args) = 2 set result = handler."__call__"(args(1), args(2))
			if $Get(args) = 3 set result = handler."__call__"(args(1), args(2), args(3))
			if $Get(args) = 4 set result = handler."__call__"(args(1), args(2), args(3), args(4))
			if $Get(args) = 5 set result = handler."__call__"(args(1), args(2), args(3), args(4), args(5))

			// If the handler returned a Python object (OperationOutcome dict), collect its errors
			if $IsObject(result) {
				set outcomeJson = jsonLib.dumps(result)
				set errorStatus = ..MergeOperationOutcomeErrors(outcomeJson, errorStatus)
			}
		}
	} catch ex {
		set sc = $$EndCapture^%SYS.Capture(msg,.msgArray)
		set ex = ##class(FHIR.Python.Helper).RecoverPythonException(ex)
		do ##class(FHIR.Python.Helper).HandlePythonException(ex)
		throw ex
	}
	set sc = $$EndCapture^%SYS.Capture(msg,.msgArray)
	$$$ThrowOnError(errorStatus)
}

/// Parse a JSON OperationOutcome and append any severity=error issues to existingStatus.
ClassMethod MergeOperationOutcomeErrors(
	json As %String,
	existingStatus As %Status) As %Status
{
	set operationOutcome = {}.%FromJSON(json)
	if operationOutcome.resourceType '= "OperationOutcome" return existingStatus

	set errorStatus = existingStatus
	set iter = operationOutcome.issue.%GetIterator()
	while iter.%GetNext(.key, .issue)
	{
		if (issue.severity = "error")
		{
			set expression = ""
			if $IsObject(issue.expression) {
				set expression = issue.expression.%Get(0)
			}
			set detailsText = ""
			if $IsObject(issue.details) {
				set detailsText = issue.details.text
			}
			set oneError = $$$ERROR($$$GeneralError, detailsText, $$$OutcomeWithPath(400, "error", issue.code, expression))
			$$$FHIRAddError(errorStatus, oneError)
		}
	}
	return errorStatus
}

ClassMethod UpdateDynamicObject(
	pTarget As %DynamicObject,
	pSource As %SYS.Python)
{
    Try {
        // Convert Python dict to JSON string then to temporary IRIS Object
        set jsonLib = ##class(%SYS.Python).Import("json")
        set jsonStr = jsonLib.dumps(pSource)
        set newObj = ##class(%DynamicObject).%FromJSON(jsonStr)
        
        // Collect keys to remove (avoid modifying while iterating)
        set keysToRemove = ""
        set iter = pTarget.%GetIterator()
        while iter.%GetNext(.key) {
            set keysToRemove = keysToRemove_$ListBuild(key)
        }
        
        // Remove all properties
        set ptr = 0
        while $ListNext(keysToRemove, ptr, key) {
            do pTarget.%Remove(key)
        }
        
        // Copy properties from newObj to pTarget
        set iter = newObj.%GetIterator()
        while iter.%GetNext(.key, .val) {
            do pTarget.%Set(key, val)
        }
    } Catch ex {
        // Log error to console - this prevents server crash (500)
        // In real system, consider logging to a global or system log
        // write !,"Error in UpdateDynamicObject: ", ex.DisplayString()
    }
}

}
