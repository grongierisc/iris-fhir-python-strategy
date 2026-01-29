import json
import uuid

import requests
import pytest


@pytest.mark.e2e
def test_fhir_metadata_via_container(fhir_base_url: str):
    metadata_url = f"{fhir_base_url}/fhir/r4/metadata"

    response = requests.get(metadata_url, headers={"Accept": "application/fhir+json"})
    response_text = response.text

    try:
        response_json = json.loads(response_text)
    except json.JSONDecodeError:
        assert False, f"Response is not valid JSON: {response_text}"

    assert response_json is not None, "FHIR metadata endpoint did not respond in time"
    assert response_json.get("resourceType") == "CapabilityStatement"

@pytest.mark.e2e
def test_fhir_metadata_missing_account_resource(fhir_base_url: str):
    metadata_url = f"{fhir_base_url}/fhir/r4/metadata"

    response = requests.get(metadata_url, headers={"Accept": "application/fhir+json"})
    response_text = response.text

    try:
        response_json = json.loads(response_text)
    except json.JSONDecodeError:
        assert False, f"Response is not valid JSON: {response_text}"

    resources = response_json.get("rest", [])[0].get("resource", [])
    resource_types = [r.get("type") for r in resources]
    assert "Account" not in resource_types, "Account resource should have been removed from CapabilityStatement"


@pytest.mark.e2e
def test_fhir_read_patient_by_id(fhir_base_url: str):
    patient_id = f"e2e-{uuid.uuid4()}"
    create_url = f"{fhir_base_url}/fhir/r4/Patient/{patient_id}"
    patient = {
        "resourceType": "Patient",
        "id": patient_id,
        "active": True,
        "name": [{"family": "Doe"}],
    }

    create_response = requests.put(
        create_url,
        headers={"Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
        json=patient,
        timeout=10,
    )
    assert create_response.status_code in (200, 201), create_response.text
    patient_id = patient["id"]
    if create_response.text.strip():
        created = create_response.json()
        patient_id = created.get("id") or patient_id
    assert patient_id, "FHIR server did not return created patient id"

    read_url = f"{fhir_base_url}/fhir/r4/Patient/{patient_id}"
    read_response = requests.get(
        read_url,
        headers={"Accept": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
        timeout=10,
    )
    assert read_response.status_code == 200, read_response.text
    read_body = read_response.json()
    assert read_body.get("resourceType") == "Patient"
    assert read_body.get("id") == patient_id
