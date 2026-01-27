Class FHIR.Python.Helper Extends %RegisteredObject
{

Property PythonClass As %SYS.Python;

Property PythonModule As %String;

Property PythonPath As %String;

Property PythonClassname As %String;

ClassMethod SetPythonPath(pClasspaths)
{
    set sys = ##class(%SYS.Python).Import("sys")

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
	pReload As %Boolean = 1) As %Boolean
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

}
