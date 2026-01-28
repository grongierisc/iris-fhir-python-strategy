import pytest
import requests

@pytest.mark.e2e
def test_non_existent_operation_returns_400(fhir_base_url):
    """
    Verify that calling a non-existent operation returns a 400 Bad Request
    instead of 200 OK.
    """
    op_url = f"{fhir_base_url}/fhir/r4/Patient/$doesnotexist"
    op_response = requests.post(
        op_url,
        headers={"Accept": "application/fhir+json", "Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
        json={"resourceType": "Parameters"},
        timeout=10,
    )
    
    # We expect failure 400 (Bad Request).
    # The current behavior we observed with curl is 400.
    assert op_response.status_code == 400, f"Expected 400, got {op_response.status_code}. Body: {op_response.text}"
    
    body = op_response.json()
    assert body.get("resourceType") == "OperationOutcome"
    issues = body.get("issue", [])
    assert len(issues) > 0
    assert issues[0]["code"] == "not-supported"
