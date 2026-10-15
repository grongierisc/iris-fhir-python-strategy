Include HS.FHIRServer

Class FHIR.Python.Tests.Setup
{

ClassMethod Prepare() As %String
{
    Set lock = ##class(%ZHSLIB.LockManager).%New()
    $$$ThrowOnError(lock.Lock("^FHIR.Python.Tests.SetupLock", , 300))
    Set endpoint = "/fhir/python-test/r4"
    If '##class(HS.FHIRServer.ServiceInstance).ExistsByUrl(endpoint) {
        Do ##class(HS.FHIRServer.Installer).InstallInstance(endpoint, "FHIR.Python.InteractionsStrategy", $ListBuild("hl7.fhir.r4.core@4.0.1"), "", "Disposable Python strategy tests", 0)
    }
    Set instance = ##class(HS.FHIRServer.ServiceInstance).FindByUrl(endpoint)
    If instance.packageList '= $ListBuild("hl7.fhir.r4.core@4.0.1") {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "Merge tests require the R4 core package"))
    }
    Do ##class(FHIR.Python.Setup).PublishDefinition(endpoint)
    Set mergeService = ##class(HS.FHIRServer.Service).EnsureInstance(endpoint)
    Set config = {}.%FromJSON(mergeService.strategy.RepoInstance.strategyConfigData)
    Do config.%Set("max_merge_writes", 1000, "number")
    Do ##class(HS.FHIRServer.ServiceAdmin).SetInstanceStrategyConfigData(mergeService.strategy.InstanceKey, config)
    Set name = "Python strategy isolated PATCH tests"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT serviceId FROM HS_FHIRServer.RepoInstance WHERE name = ? AND (cspUrl IS NULL OR cspUrl = '')", name)
    If rs.%SQLCODE < 0 {
        $$$ThrowStatus($$$ERROR($$$GeneralError, rs.%Message))
    }
    If rs.%Next() {
        Set instance = ##class(HS.FHIRServer.ServiceInstance).GetById(rs.serviceId)
        If instance.parentRepo.strategyClass '= "FHIR.Python.InteractionsStrategy" {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "Isolated test service uses a different strategy"))
        }
        Return rs.serviceId
    }
    Do ##class(HS.FHIRServer.Installer).InstallInstance("", "FHIR.Python.InteractionsStrategy", $ListBuild("hl7.fhir.r4.core@4.0.1"), "", "", 0, "", "", name)
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT serviceId FROM HS_FHIRServer.RepoInstance WHERE name = ? AND (cspUrl IS NULL OR cspUrl = '')", name)
    If (rs.%SQLCODE '= 0) || 'rs.%Next() {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "Could not locate isolated PATCH test service"))
    }
    Return rs.serviceId
}

ClassMethod Run() As %Status
{
    Set previousRoot = $Get(^UnitTestRoot), hadRoot = $Data(^UnitTestRoot)
    Try {
        Set id = ..Prepare()
        Set ^UnitTestRoot = "/irisdev/app/tests/native"
        Do ##class(%UnitTest.Manager).RunTest("FHIR/Python/Tests/Merge", "/noload/nodelete")
        Do ##class(%UnitTest.Manager).RunTest("FHIR/Python/Tests/Patch", "/noload/nodelete", id)
        Do ##class(%UnitTest.Manager).RunTest("FHIR/Python/Tests/Bridge", "/noload/nodelete", id)
    } Catch ex {
        If hadRoot { Set ^UnitTestRoot = previousRoot } Else { Kill ^UnitTestRoot }
        Return ex.AsStatus()
    }
    If hadRoot { Set ^UnitTestRoot = previousRoot } Else { Kill ^UnitTestRoot }
    Return $$$OK
}

}
