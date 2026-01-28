import pytest
import requests

@pytest.mark.e2e
def test_validate_patient_resource_custom_error(fhir_base_url):
    """
    Test that the custom validator for Patient (defined in fhir_customization.py)
    raises an error if 'id' is missing.
    """
    # Patient without ID - standard FHIR allows this (server assigns ID), 
    # but custom validator enforces ID presence.
    patient = {
        "resourceType": "Patient",
        "active": True
    }
    
    response = requests.post(
        f"{fhir_base_url}/fhir/r4/Patient",
        headers={"Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
        json=patient,
        timeout=10,
    )
    
    # Expect failure because custom validator requires 'id'
    assert response.status_code == 400, f"Expected 400, got {response.status_code}\n{response.text}"
    assert "Patient must have id" in response.text
    # The default mapping of python exceptions might result in 500 or 400 depending on implementation.
    # IRIS usually wraps errors.
    # If ValueError is treated as validation error, maybe 400 or 422.
    # Let's check detail if possible, but status code check is enough for now.
    
    # Now try WITH id
    patient_with_id = {
        "resourceType": "Patient",
        "id": "valid-id-123",
        "active": True
    }
    # This is a PUT typically for client-defined ID, or POST if server supports it.
    response_ok = requests.put(
        f"{fhir_base_url}/fhir/r4/Patient/valid-id-123",
         headers={"Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
        json=patient_with_id,
        timeout=10,
    )
    assert response_ok.status_code in (200, 201), response_ok.text

@pytest.mark.e2e
def test_validate_observation_custom_error(fhir_base_url):
    """
    Test that the custom validator for Observation raises custom error.
    """
    # Observation requires 'status' and 'code' in R4.
    observation_invalid = {
        "resourceType": "Observation",
        "id": "invalid-obs-1"
    }
    
    response = requests.put(
        f"{fhir_base_url}/fhir/r4/Observation/invalid-obs-1",
        headers={"Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
        json=observation_invalid,
        timeout=10,
    )
    
    # We now expect 400 Bad Request because we implemented HandlePythonException
    assert response.status_code == 400, f"Expected 400, got {response.status_code} Body: {response.text}"
    assert "Custom Error Observation" in response.text



