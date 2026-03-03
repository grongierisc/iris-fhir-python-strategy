"""
End-to-end tests for @fhir.consent handler behaviour.

These tests use the running Docker container and the e2e fixture module
(``tests/e2e/fixtures/fhir_customization.py``).

The fixture registers::

    @fhir.consent("Patient")
    def consent_check(resource: Dict[str, Any]) -> bool:
        for name in resource.get("name", []):
            if name.get("family") == "NoConsent":
                return False
        return True

Background / regression
-----------------------
The original production bug was: every GET on an existing patient returned
HTTP 500 with::

    {"resourceType":"OperationOutcome","issue":[{"severity":"error",
    "code":"exception","diagnostics":"2603",
    "details":{"text":"Python general error
    '<OBJECT DISPATCH> 230 RunBooleanHandlers+8^FHIR.Python.Helper.1'"}}]}

Root cause: the registered consent handler had 2 required positional
parameters (``fhir_object``, ``user_context``) but the IRIS bridge only
ever passes 1 (the resource dict).  Calling the handler with 1 arg when 2
are required raises a Python ``TypeError`` which IRIS surfaces as the
``<OBJECT DISPATCH> 2603`` error.

Fix summary:
  1. ``@fhir.consent`` now validates the signature at registration time and
     raises a clear ``TypeError`` immediately rather than producing a
     cryptic runtime error.
  2. All handlers that need per-request user data must call
     ``get_request_context()`` instead of expecting an extra parameter.
"""
import requests
import pytest

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

AUTH = ("SuperUser", "SYS")
HEADERS_JSON = {"Accept": "application/fhir+json"}
HEADERS_FHIR = {"Content-Type": "application/fhir+json"}


def _put_patient(base_url: str, pid: str, family: str) -> requests.Response:
    return requests.put(
        f"{base_url}/fhir/r4/Patient/{pid}",
        json={"resourceType": "Patient", "id": pid, "name": [{"family": family}]},
        headers=HEADERS_FHIR,
        auth=AUTH,
        timeout=15,
    )


def _get_patient(base_url: str, pid: str) -> requests.Response:
    return requests.get(
        f"{base_url}/fhir/r4/Patient/{pid}",
        headers=HEADERS_JSON,
        auth=AUTH,
        timeout=15,
    )


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@pytest.mark.e2e
def test_consent_allows_normal_patient_read(fhir_base_url: str):
    """
    A patient whose name does NOT trigger the consent guard must be readable
    without errors — specifically it must NOT return the 500 / OBJECT DISPATCH
    error that the original bug produced.
    """
    pid = "consent-e2e-allowed"
    create_resp = _put_patient(fhir_base_url, pid, "Smith")
    assert create_resp.status_code in (200, 201), create_resp.text

    read_resp = _get_patient(fhir_base_url, pid)
    assert read_resp.status_code == 200, (
        f"Expected 200 for an allowed patient, got {read_resp.status_code}. "
        f"Body: {read_resp.text}"
    )
    # Regression guard: the original bug returned a 500 with OperationOutcome
    body = read_resp.json()
    assert body.get("resourceType") == "Patient", (
        f"Response should be a Patient, got: {body.get('resourceType')}"
    )


@pytest.mark.e2e
def test_consent_blocks_patient_read_returns_404(fhir_base_url: str):
    """
    A patient whose name triggers the consent guard must produce a 404 —
    the IRIS bridge returns 404 when PostProcessRead returns False.
    """
    pid = "consent-e2e-blocked"
    create_resp = _put_patient(fhir_base_url, pid, "NoConsent")
    assert create_resp.status_code in (200, 201), create_resp.text

    read_resp = _get_patient(fhir_base_url, pid)
    assert read_resp.status_code == 404, (
        f"Expected 404 for a consent-blocked patient, got {read_resp.status_code}. "
        f"Body: {read_resp.text}"
    )


@pytest.mark.e2e
def test_consent_block_is_not_a_500_error(fhir_base_url: str):
    """
    Even when consent returns False the server must NOT return 500.
    This test directly guards against the original <OBJECT DISPATCH> 2603 bug.
    """
    pid = "consent-e2e-no500"
    _put_patient(fhir_base_url, pid, "NoConsent")

    read_resp = _get_patient(fhir_base_url, pid)
    assert read_resp.status_code != 500, (
        f"Consent block returned 500 — likely the handler has a bad signature. "
        f"Body: {read_resp.text}"
    )


@pytest.mark.e2e
def test_consent_does_not_block_write(fhir_base_url: str):
    """
    Consent is evaluated in PostProcessRead, not on writes.
    Creating/updating a patient with a 'NoConsent' name must still succeed
    (the consent check only prevents the resource from being returned on read).
    """
    pid = "consent-e2e-write-allowed"

    # First PUT (create)
    resp1 = _put_patient(fhir_base_url, pid, "NoConsent")
    assert resp1.status_code in (200, 201), (
        f"PUT (create) should succeed even for NoConsent family. "
        f"Got {resp1.status_code}: {resp1.text}"
    )

    # Second PUT (update)
    resp2 = _put_patient(fhir_base_url, pid, "NoConsent")
    assert resp2.status_code in (200, 201), (
        f"PUT (update) should succeed even for NoConsent family. "
        f"Got {resp2.status_code}: {resp2.text}"
    )


@pytest.mark.e2e
def test_consent_response_body_is_valid_fhir_on_block(fhir_base_url: str):
    """
    When consent blocks a read the server must return a well-formed FHIR
    OperationOutcome (not a raw Python traceback or a malformed payload).
    """
    pid = "consent-e2e-outcome"
    _put_patient(fhir_base_url, pid, "NoConsent")

    read_resp = _get_patient(fhir_base_url, pid)
    assert read_resp.status_code == 404

    body = read_resp.json()
    assert body.get("resourceType") == "OperationOutcome", (
        f"Expected OperationOutcome on consent block, got: {body}"
    )
    assert "issue" in body, f"OperationOutcome missing 'issue': {body}"


@pytest.mark.e2e
def test_consent_handler_called_once_per_read(fhir_base_url: str):
    """
    Sanity check: a single GET /Patient/{id} should either return the patient or
    a 404.  It must never return a 500, and the response code must be stable
    across repeated calls (no race-condition / context bleed).
    """
    pid = "consent-e2e-stable"
    _put_patient(fhir_base_url, pid, "Smith")

    statuses = set()
    for _ in range(3):
        resp = _get_patient(fhir_base_url, pid)
        statuses.add(resp.status_code)
        assert resp.status_code != 500, f"Got 500 on attempt: {resp.text}"

    assert statuses == {200}, f"Expected stable 200 on repeated reads, got: {statuses}"
