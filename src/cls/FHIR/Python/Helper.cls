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
    set importlib = ##class(%SYS.Python).Import("importlib")
    set builtins = ##class(%SYS.Python).Import("builtins")

    set module = importlib."import_module"(pModule)
    do importlib."reload"(module)

    set class = builtins.getattr(module, pRemoteClassname)
    return class."__new__"(class)
}

ClassMethod DeleteFHIRData(pFHIRData As %String)
{
    set strategy = ##class(HS.FHIRServer.API.InteractionsStrategy).GetStrategyForEndpoint(pFHIRData)
    set options("deleteDataOnly") = 1
    do strategy.Delete(.options)
}

}
