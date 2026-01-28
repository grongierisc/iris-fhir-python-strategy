Include (HS.FHIRServer, HS.HC.InstanceConfig, HS.HC)

Class FHIR.Python.Helper Extends %RegisteredObject
{

Property PythonClass As %SYS.Python;

Property PythonModule As %String;

Property PythonPath As %String;

Property PythonClassname As %String;

ClassMethod SetPythonPath(pClasspaths)
{
    set sys = ##class(%SYS.Python).Import("sys")
    if (sys.path."__len__"() > 0) && (sys.path."__getitem__"(0) = pClasspaths) { Quit }

    for i=0:1:(sys.path."__len__"()-1) {
        Try {
            if sys.path."__getitem__"(i) = pClasspaths {
                do sys.path."__delitem__"(i)
            }
        }
        Catch ex {
            // do nothing
        }

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
		set pPythonModule = "examples.custom_decorators"
	}

	quit $$$OK
}

ClassMethod DeleteFHIRData(pFHIRData As %String)
{
    set strategy = ##class(HS.FHIRServer.API.InteractionsStrategy).GetStrategyForEndpoint(pFHIRData)
    set options("deleteDataOnly") = 1
    do strategy.Delete(.options)
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
    
	#dim oneError As %Status = $$$ERROR($$$GeneralError, msg, $$$OutcomeWithPath(tHTTPCode, "error", tCode, ""))
	
	$$$ThrowOnError(oneError)
}

}
