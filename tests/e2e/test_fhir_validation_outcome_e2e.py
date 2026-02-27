"""
E2E tests for validation handlers that return an OperationOutcome dict.

These tests require the Docker container to be running with the e2e fixture
module (``fhir_customization.py``) loaded. The ``fhir_base_url`` session
fixture in ``conftest.py`` manages the container lifecycle.

Scenarios covered:
1. Single-error OperationOutcome → 400 with the correct issue text/code/expression
2. Multi-error OperationOutcome  → 400 with all issue details present
3. Partial OperationOutcome (one of two validation branches triggered) → 400 with one issue
4. Warning-only OperationOutcome → request passes (201 / 200)
   (ObjectScript only fails on severity=error)
5. Existing raise-exception behaviour is unchanged
"""

import pytest
import requests


# ------------------------------------------------------------------ #
# Helpers                                                             #
# ------------------------------------------------------------------ #

_HEADERS = {"Content-Type": "application/fhir+json"}
_AUTH = ("SuperUser", "SYS")


def _issues(response_json: dict) -> list:
    """Return the issue list from an OperationOutcome response."""
    return response_json.get("issue", [])


def _issue_texts(response_json: dict) -> list[str]:
    return [
        i.get("details", {}).get("text", "")
        for i in _issues(response_json)
    ]


# ------------------------------------------------------------------ #
# 1. Single-error OperationOutcome – Medication missing 'code'       #
# ------------------------------------------------------------------ #

@pytest.mark.e2e
def test_validate_medication_single_error_outcome(fhir_base_url: str):
    """
    Medication without a 'code' field should be rejected via OperationOutcome return.
    Expects 400 with a single error issue describing Medication.code.
    """
    medication_no_code = {
        "resourceType": "Medication",
        "id": "med-no-code-1",
        "status": "active",
    }

    response = requests.put(
        f"{fhir_base_url}/fhir/r4/Medication/med-no-code-1",
        headers=_HEADERS,
        auth=_AUTH,
        json=medication_no_code,
        timeout=10,
    )

    assert response.status_code == 400, (
        f"Expected 400 for missing Medication.code, got {response.status_code}\n{response.text}"
    )

    body = response.json()
    assert body.get("resourceType") == "OperationOutcome", response.text
    texts = _issue_texts(body)
    assert any("Medication.code is required" in t for t in texts), (
        f"Expected 'Medication.code is required' in issues, got: {texts}"
    )
    # IRIS preserves the expression array from $$$OutcomeWithPath
    expressions = [
        expr
        for issue in _issues(body)
        for expr in issue.get("expression", [])
    ]
    assert "Medication.code" in expressions, (
        f"Expected expression 'Medication.code' in response, got: {expressions}"
    )


@pytest.mark.e2e
def test_validate_medication_passes_when_code_present(fhir_base_url: str):
    """
    Medication WITH a 'code' field must be accepted (201 or 200).
    """
    medication_valid = {
        "resourceType": "Medication",
        "id": "med-valid-1",
        "status": "active",
        "code": {"text": "Aspirin"},
    }

    response = requests.put(
        f"{fhir_base_url}/fhir/r4/Medication/med-valid-1",
        headers=_HEADERS,
        auth=_AUTH,
        json=medication_valid,
        timeout=10,
    )

    assert response.status_code in (200, 201), (
        f"Expected 200/201 for valid Medication, got {response.status_code}\n{response.text}"
    )


# ------------------------------------------------------------------ #
# 2. Multi-error OperationOutcome – Device missing identifier + bad  #
#    status                                                           #
# ------------------------------------------------------------------ #

@pytest.mark.e2e
def test_validate_device_multi_error_outcome(fhir_base_url: str):
    """
    Device missing both 'identifier' and with an invalid 'status' triggers two
    error issues in the returned OperationOutcome.
    """
    device_bad = {
        "resourceType": "Device",
        "id": "device-bad-1",
        "status": "not-a-real-status",
        # deliberately missing 'identifier'
    }

    response = requests.put(
        f"{fhir_base_url}/fhir/r4/Device/device-bad-1",
        headers=_HEADERS,
        auth=_AUTH,
        json=device_bad,
        timeout=10,
    )

    assert response.status_code == 400, (
        f"Expected 400 for invalid Device, got {response.status_code}\n{response.text}"
    )

    body = response.json()
    assert body.get("resourceType") == "OperationOutcome", response.text
    texts = _issue_texts(body)
    assert any("Device.identifier is required" in t for t in texts), (
        f"Expected 'Device.identifier is required' in issues, got: {texts}"
    )
    assert any("Device.status" in t for t in texts), (
        f"Expected status error in issues, got: {texts}"
    )


# ------------------------------------------------------------------ #
# 3. Partial OperationOutcome – Device has identifier but bad status #
# ------------------------------------------------------------------ #

@pytest.mark.e2e
def test_validate_device_partial_error_only_status(fhir_base_url: str):
    """
    Device WITH identifier but invalid status → only the status issue fires.
    """
    device_partial = {
        "resourceType": "Device",
        "id": "device-partial-1",
        "identifier": [{"value": "dev-123"}],
        "status": "broken",   # not in allowed set
    }

    response = requests.put(
        f"{fhir_base_url}/fhir/r4/Device/device-partial-1",
        headers=_HEADERS,
        auth=_AUTH,
        json=device_partial,
        timeout=10,
    )

    assert response.status_code == 400, (
        f"Expected 400 for invalid Device status, got {response.status_code}\n{response.text}"
    )

    body = response.json()
    texts = _issue_texts(body)
    assert any("Device.status" in t for t in texts), (
        f"Expected status error, got: {texts}"
    )
    # identifier issue must NOT be present
    assert not any("identifier" in t for t in texts), (
        f"Identifier error should not appear, got: {texts}"
    )


@pytest.mark.e2e
def test_validate_device_passes_when_valid(fhir_base_url: str):
    """
    Device with valid identifier and status must be accepted.
    """
    device_valid = {
        "resourceType": "Device",
        "id": "device-valid-1",
        "identifier": [{"value": "dev-ok-1"}],
        "status": "active",
    }

    response = requests.put(
        f"{fhir_base_url}/fhir/r4/Device/device-valid-1",
        headers=_HEADERS,
        auth=_AUTH,
        json=device_valid,
        timeout=10,
    )

    assert response.status_code in (200, 201), (
        f"Expected 200/201 for valid Device, got {response.status_code}\n{response.text}"
    )


# ------------------------------------------------------------------ #
# 4. Warning-only OperationOutcome – request must succeed            #
# ------------------------------------------------------------------ #

@pytest.mark.e2e
def test_validate_practitioner_warning_only_passes(fhir_base_url: str):
    """
    Practitioner without 'qualification' triggers a warning-only OperationOutcome.
    ObjectScript must only block on severity=error, so the request succeeds.
    """
    practitioner_no_qual = {
        "resourceType": "Practitioner",
        "id": "prac-no-qual-1",
        "active": True,
        "name": [{"family": "House", "given": ["Gregory"]}],
        # deliberately no 'qualification'
    }

    response = requests.put(
        f"{fhir_base_url}/fhir/r4/Practitioner/prac-no-qual-1",
        headers=_HEADERS,
        auth=_AUTH,
        json=practitioner_no_qual,
        timeout=10,
    )

    assert response.status_code in (200, 201), (
        f"Warning-only outcome should not block request, "
        f"got {response.status_code}\n{response.text}"
    )


# ------------------------------------------------------------------ #
# 5. Regression – exception-raise behaviour still works              #
# ------------------------------------------------------------------ #

@pytest.mark.e2e
def test_raise_exception_validation_still_works(fhir_base_url: str):
    """
    Existing raise-based validation (Patient missing 'id') must still return 400.
    This guards against regressions introduced by the OperationOutcome plumbing.
    """
    patient_no_id = {
        "resourceType": "Patient",
        "active": True,
    }

    response = requests.post(
        f"{fhir_base_url}/fhir/r4/Patient",
        headers=_HEADERS,
        auth=_AUTH,
        json=patient_no_id,
        timeout=10,
    )

    assert response.status_code == 400, (
        f"Expected 400 for Patient missing id, got {response.status_code}\n{response.text}"
    )
    assert "Patient must have id" in response.text
