from types import SimpleNamespace

import pytest

from iris_fhir_python_strategy import request_context, get_request_context
from tests.e2e.fixtures import fhir_customization as fc


@pytest.fixture(autouse=True)
def isolated_context():
    """Each test runs inside a clean, isolated RequestContext."""
    with request_context():
        yield


@pytest.mark.unit
def test_remove_account_resource():
    capability_statement = {
        "rest": [
            {"resource": [{"type": "Account"}, {"type": "Patient"}]}
        ]
    }

    result = fc.remove_account_resource(capability_statement)
    types = [resource["type"] for resource in result["rest"][0]["resource"]]
    assert "Account" not in types
    assert "Patient" in types


@pytest.mark.unit
def test_capture_user_context(fake_fhir_request):
    request = fake_fhir_request(username="alice", roles="doctor")
    fc.capture_user_context(SimpleNamespace(), request, None, None)

    ctx = get_request_context()
    assert ctx.username == "alice"
    assert ctx.roles == "doctor"


@pytest.mark.unit
def test_deny_blocked_patient_read():
    assert fc.deny_blocked_patient_read({"resourceType": "Patient", "id": "blocked-1"}) is False
    assert fc.deny_blocked_patient_read({"resourceType": "Patient", "id": "ok-1"}) is True
