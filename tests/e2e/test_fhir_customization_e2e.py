import requests
import pytest


@pytest.mark.e2e
def test_capability_statement_account_removed(fhir_base_url):
    metadata_url = f"{fhir_base_url}/fhir/r4/metadata"
    response = requests.get(
        metadata_url,
        headers={"Accept": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
        timeout=10,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    resources = body["rest"][0]["resource"]
    types = {resource["type"] for resource in resources}
    assert "Account" not in types


@pytest.mark.e2e
def test_blocked_patient_read_returns_404(fhir_base_url):
    patient_id = "blocked-e2e-patient"
    create_url = f"{fhir_base_url}/fhir/r4/Patient/{patient_id}"
    patient = {
        "resourceType": "Patient",
        "id": patient_id,
        "active": True,
        "name": [{"family": "Blocked"}],
    }

    create_response = requests.put(
        create_url,
        headers={"Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
        json=patient,
        timeout=10,
    )
    assert create_response.status_code in (200, 201), create_response.text

    read_url = f"{fhir_base_url}/fhir/r4/Patient/{patient_id}"
    read_response = requests.get(
        read_url,
        headers={"Accept": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
        timeout=10,
    )
    assert read_response.status_code == 404, read_response.text

