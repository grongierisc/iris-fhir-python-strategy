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
def test_capability_statement_includes_custom_operation(fhir_base_url):
    metadata_url = f"{fhir_base_url}/fhir/r4/metadata"
    response = requests.get(
        metadata_url,
        headers={"Accept": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
        timeout=10,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    
    # Check if $echo is defined for Patient
    resources = body["rest"][0]["resource"]
    patient_resource = next((r for r in resources if r["type"] == "Patient"), None)
    assert patient_resource is not None
    
    # Operation might be in 'operation' field of resource definition
    # or just exposed via definition link.
    # Standard FHIR capability statement format:
    # resource: [ { type: Patient, operation: [ { name: "echo", definition: ... } ] } ]
    
    operations = patient_resource.get("operation", [])
    op_names = {op["name"] for op in operations}
    assert "echo" in op_names, f"Expected 'echo' in {op_names}"



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


@pytest.mark.e2e
def test_allowed_patient_read_returns_200(fhir_base_url):
    patient_id = "allowed-e2e-patient"
    create_url = f"{fhir_base_url}/fhir/r4/Patient/{patient_id}"
    patient = {
        "resourceType": "Patient",
        "id": patient_id,
        "active": True,
        "name": [{"family": "Allowed"}],
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
    assert read_response.status_code == 200, read_response.text


@pytest.mark.e2e
def test_custom_echo_operation(fhir_base_url):
    patient_id = "echo-e2e-patient"
    create_url = f"{fhir_base_url}/fhir/r4/Patient/{patient_id}"
    patient = {
        "resourceType": "Patient",
        "id": patient_id,
        "active": True,
        "name": [{"family": "Echo"}],
    }

    create_response = requests.put(
        create_url,
        headers={"Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
        json=patient,
        timeout=10,
    )
    assert create_response.status_code in (200, 201), create_response.text

    op_url = f"{fhir_base_url}/fhir/r4/Patient/$echo"
    op_response = requests.post(
        op_url,
        headers={"Accept": "application/fhir+json", "Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
        json={"resourceType": "Parameters"},
        timeout=10,
    )
    assert op_response.status_code == 200, op_response.text
    body = op_response.json()
    assert body.get("resourceType") == "Parameters"


@pytest.mark.e2e
def test_validate_bundle_requires_entries(fhir_base_url):
    bundle = {"resourceType": "Bundle", "type": "transaction", "entry": []}
    op_url = f"{fhir_base_url}/fhir/r4/Bundle/$validate"
    response = requests.post(
        op_url,
        headers={"Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
        json=bundle,
        timeout=10,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body.get("resourceType") == "OperationOutcome"


@pytest.mark.e2e
def test_search_filtering_hides_blocked_patients(fhir_base_url):
    # 1. Create a blocked patient
    blocked_id = "blocked-search-1"
    requests.put(
        f"{fhir_base_url}/fhir/r4/Patient/{blocked_id}",
        json={"resourceType": "Patient", "id": blocked_id, "active": True},
        headers={"Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
    )
    
    # 2. Create an allowed patient
    allowed_id = "allowed-search-1"
    requests.put(
        f"{fhir_base_url}/fhir/r4/Patient/{allowed_id}",
        json={"resourceType": "Patient", "id": allowed_id, "active": True},
        headers={"Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
    )
    
    # 3. Search for both
    response = requests.get(
        f"{fhir_base_url}/fhir/r4/Patient",
        params={"_id": f"{blocked_id},{allowed_id}"},
        headers={"Accept": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
    )
    assert response.status_code == 200
    bundle = response.json()
    
    # 4. Verify results
    assert bundle["resourceType"] == "Bundle"
    entries = bundle.get("entry", [])
    ids = [e["resource"]["id"] for e in entries]
    
    assert allowed_id in ids, "Allowed patient should be in search results"
    assert blocked_id not in ids, "Blocked patient should be filtered out from search results"


@pytest.mark.e2e
def test_observation_creation_fails_custom_validation(fhir_base_url):
    """
    Test that creating an Observation triggers the custom validation hook
    and raises a ValueError, which results in an error response.
    """
    obs = {
        "resourceType": "Observation",
        "status": "final",
        "code": {"text": "invalid"}
    }
    
    response = requests.post(
        f"{fhir_base_url}/fhir/r4/Observation",
        json=obs,
        headers={"Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
    )
    
    # Expecting error due to raised ValueError("Custom Error Observation")
    assert response.status_code >= 400
    outcome = response.json()
    assert outcome["resourceType"] == "OperationOutcome"
    text = outcome["issue"][0]["details"]["text"]
    assert "Custom Error Observation" in text


@pytest.mark.e2e
def test_transaction_bundle_fails_custom_validation(fhir_base_url):
    """
    Test that posting a transaction bundle triggers on_validate_bundle.
    """
    bundle = {
        "resourceType": "Bundle",
        "type": "transaction",
        "entry": [] # Helper raises ValueError if entry is missing/empty
    }
    
    response = requests.post(
        f"{fhir_base_url}/fhir/r4",
        json=bundle,
        headers={"Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
    )
    
    # Expect error due to validation failure
    assert response.status_code >= 400
    outcome = response.json()
    text = outcome["issue"][0]["details"]["text"]
    assert "Transaction bundle must have entries" in text


@pytest.mark.e2e
def test_validation_forbidden_name(fhir_base_url):
    """
    Test that creating a Patient with forbidden name fails.
    """
    patient = {
        "resourceType": "Patient",
        "id": "forbidden-patient",
        "active": True,
        "name": [{"family": "Forbidden"}]
    }
    
    response = requests.put(
        f"{fhir_base_url}/fhir/r4/Patient/forbidden-patient",
        json=patient,
        headers={"Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
    )
    
    assert response.status_code >= 400
    outcome = response.json()
    text = outcome["issue"][0]["details"]["text"]
    assert "This family name is not allowed" in text


@pytest.mark.e2e
def test_enrich_observation_tag(fhir_base_url):
    """
    Test that new observations get an auto-generated tag.
    """
    obs = {
        "resourceType": "Observation",
        "status": "final",
        "code": {"text": "enrich-test"}
    }
    
    # Create
    response = requests.post(
        f"{fhir_base_url}/fhir/r4/Observation",
        json=obs,
        headers={"Content-Type": "application/fhir+json", "prefer": "return=representation"},
        auth=("SuperUser", "SYS"),
    )
    assert response.status_code in (200, 201)
    created_id = response.json()["id"]
    
    # Read back
    read_resp = requests.get(
        f"{fhir_base_url}/fhir/r4/Observation/{created_id}",
        headers={"Accept": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
    )
    assert read_resp.status_code == 200
    resource = read_resp.json()
    
    # Check tag
    tags = resource.get("meta", {}).get("tag", [])
    has_tag = any(t.get("code") == "auto-generated" for t in tags)
    assert has_tag, "Observation should have auto-generated tag"


@pytest.mark.e2e
def test_masking_patient_data(fhir_base_url):
    """
    Test that reading 'masked-patient' returns masked data.
    """
    pid = "masked-patient"
    patient = {
        "resourceType": "Patient",
        "id": pid,
        "active": True,
        "birthDate": "1980-01-01",
        "telecom": [{"system": "phone", "value": "555-1234"}]
    }
    
    # Put
    requests.put(
        f"{fhir_base_url}/fhir/r4/Patient/{pid}",
        json=patient,
        headers={"Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
    )
    
    # Read
    resp = requests.get(
        f"{fhir_base_url}/fhir/r4/Patient/{pid}",
        headers={"Accept": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
    )
    assert resp.status_code == 200
    data = resp.json()
    
    # Check masking
    assert "telecom" not in data, "Telecom should be removed"
    assert data["birthDate"] == "1900-01-01", "BirthDate should be masked"


@pytest.mark.e2e
def test_consent_blocking(fhir_base_url):
    """
    Test that @fhir.consent blocks access to patients with family name 'NoConsent'.
    """
    pid = "no-consent-patient"
    patient = {
        "resourceType": "Patient",
        "id": pid,
        "active": True,
        "name": [{"family": "NoConsent"}]
    }
    
    # Put (create should work as consent check is on read)
    create_resp = requests.put(
        f"{fhir_base_url}/fhir/r4/Patient/{pid}",
        json=patient,
        headers={"Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
    )
    assert create_resp.status_code in (200, 201)
    
    # Read (should fail with 404 because consent returns False)
    read_resp = requests.get(
        f"{fhir_base_url}/fhir/r4/Patient/{pid}",
        headers={"Accept": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
    )
    assert read_resp.status_code == 404


@pytest.mark.e2e
def test_unhandled_python_exception_returns_500(fhir_base_url):
    """
    Test that a generic Python exception (ZeroDivisionError) in validation
    results in a 500 error, not a crash of the whole server, and contains details.
    """
    org = {"resourceType": "Organization", "name": "Fail Corp"}
    
    response = requests.post(
        f"{fhir_base_url}/fhir/r4/Organization",
        json=org,
        headers={"Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
    )
    
    # We expect 500 because ZeroDivisionError is not mapped to 4xx in Helper.cls
    assert response.status_code == 500, f"Expected 500, got {response.status_code}"
    outcome = response.json()
    assert outcome["resourceType"] == "OperationOutcome"
    # The diagnostics might contain "ZeroDivisionError" or similar text
    text = outcome["issue"][0]["details"]["text"]
    assert "division by zero" in text or "ZeroDivisionError" in text


@pytest.mark.e2e
def test_operation_crash_handling(fhir_base_url):
    """
    Test that a custom operation raising a generic Exception return 500.
    """
    op_url = f"{fhir_base_url}/fhir/r4/Patient/$crash"
    response = requests.post(
        op_url,
        json={"resourceType": "Parameters"},
        headers={"Content-Type": "application/fhir+json"},
        auth=("SuperUser", "SYS"),
    )
    
    assert response.status_code == 500
    outcome = response.json()
    text = outcome["issue"][0]["details"]["text"]
    assert "Boom! explicit crash" in text
