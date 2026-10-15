Include (HS.FHIRServer, %outUnitTest)

Class FHIR.Python.Tests.Merge.GateTest Extends %UnitTest.TestCase
{

Parameter Endpoint = "/fhir/python-test/r4";

Method TestNestedRollback()
{
    Set service = ##class(HS.FHIRServer.Service).EnsureInstance(..#Endpoint)
    Set interactions = service.interactions
    Set entry = $TLevel
    Try {
        TStart
        Set patient = {"resourceType":"Patient","active":true}
        Set id = interactions.Add(patient)
        Set patient.active = 0
        Do interactions.Update(patient)
        Do $$$AssertEquals(patient.meta.versionId, "2", "Update creates a new version")
        Set table = service.strategy.GetResourceTable("")
        Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM " _ table _ " WHERE ResourceType = 'Patient' AND ResourceId = ?", id)
        Do $$$AssertEquals(result.%SQLCODE, 0, "Current table is queryable")
        Do result.%Next()
        Do $$$AssertEquals(result.N, 1, "Current resource exists inside transaction")
        TRollback 1
        Do $$$AssertEquals($TLevel, entry, "Rollback preserves caller transaction level")
        Do $$$AssertEquals(interactions.FindResourceMeta("Patient", id), "", "Resource creation rolled back")
        Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM " _ service.strategy.GetResourceVersionTable("") _ " WHERE ResourceType = 'Patient' AND ResourceId = ?", id)
        Do $$$AssertEquals(result.%SQLCODE, 0, "History table is queryable")
        Do result.%Next()
        Do $$$AssertEquals(result.N, 0, "Historical version rolled back")
        Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM " _ service.strategy.GetSearchTable("Patient") _ " WHERE Key = ?", "Patient/" _ id)
        Do $$$AssertEquals(result.%SQLCODE, 0, "Patient search table is queryable")
        Do result.%Next()
        Do $$$AssertEquals(result.N, 0, "Search index rolled back")
    } Catch ex {
        TRollback:$TLevel>entry 1
        Throw ex
    }
}

}
