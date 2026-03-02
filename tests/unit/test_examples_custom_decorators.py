from types import SimpleNamespace
from typing import Any, Callable, Generator
from unittest.mock import Mock

import pytest

from iris_fhir_python_strategy import get_request_context, request_context
from examples import custom_decorators as ex


@pytest.fixture(autouse=True)
def isolated_request_context() -> Generator[None, None, None]:
    """Each test runs inside a clean, isolated RequestContext."""
    with request_context():
        yield


@pytest.mark.unit
def test_extract_user_context_populates_fields(fake_fhir_request: Callable[..., SimpleNamespace]):
    req = fake_fhir_request(username="alice", roles="doctor")

    ex.extract_user_context(Mock(), req, None, None)

    ctx = get_request_context()
    assert ctx.username == "alice"
    assert ctx.roles == "doctor"


@pytest.mark.unit
def test_check_consent_uses_context_security():
    ctx = get_request_context()
    ctx.security_list = ["R"]

    resource = {"meta": {"security": [{"code": "R"}]}}
    assert ex.check_consent(resource) is False


@pytest.mark.unit
def test_check_consent_passes_when_no_overlap():
    ctx = get_request_context()
    ctx.security_list = ["S"]

    resource = {"meta": {"security": [{"code": "R"}]}}
    assert ex.check_consent(resource) is True


@pytest.mark.unit
def test_patient_consent_rules_reads_security_list():
    ctx = get_request_context()
    ctx.security_list = ["S"]

    resource = {"meta": {"security": [{"code": "S"}]}}
    assert ex.patient_consent_rules(resource, {}) is False


@pytest.mark.unit
def test_get_security_returns_empty_without_interactions():
    # ctx.interactions is None inside the isolated context — should return []
    assert ex.get_security("scope-1") == []


@pytest.mark.unit
def test_oauth_token_setup_and_introspection():
    ex.setup_oauth_token("token", "client", "https://example", "alice")

    info = ex.get_token_introspection()
    assert info["client_id"] == "client"
    assert info["username"] == "alice"

    user_info = ex.extract_user_info("basic", "roles")
    assert user_info["Username"] == "alice"


@pytest.mark.unit
def test_verify_patient_deletion_requires_admin():
    ctx = get_request_context()
    ctx.roles = "doctor"

    with pytest.raises(PermissionError):
        ex.verify_patient_deletion("Patient", "1", "delete")


@pytest.mark.unit
def test_verify_patient_deletion_succeeds_for_admin():
    ctx = get_request_context()
    ctx.roles = "admin"

    # Should not raise
    ex.verify_patient_deletion("Patient", "1", "delete")


@pytest.mark.unit
def test_verify_system_access_requires_system_admin():
    ctx = get_request_context()
    ctx.roles = "doctor"

    with pytest.raises(PermissionError):
        ex.verify_system_access()


@pytest.mark.unit
def test_verify_system_access_succeeds_for_system_admin():
    ctx = get_request_context()
    ctx.roles = "system-admin"

    # Should not raise
    ex.verify_system_access()


@pytest.mark.unit
def test_verify_patient_content_access_restricted_raises():
    resource = {"meta": {"security": [{"code": "R"}]}}
    with pytest.raises(PermissionError):
        ex.verify_patient_content_access(resource, "read", False)


@pytest.mark.unit
def test_patient_diff_operation_builds_response(monkeypatch):
    class DummyDiff:
        def __init__(self, *args, **kwargs):
            pass

        def to_json(self):
            return '{"diff":"ok"}'

    monkeypatch.setitem(
        __import__("sys").modules, "deepdiff", SimpleNamespace(DeepDiff=DummyDiff)
    )
    monkeypatch.setattr(ex, "dynamic_object_from_json", lambda data: {"json": data})

    class DummyInteractions:
        def Read(self, resource_type, resource_id):
            return SimpleNamespace(_ToJSON=lambda: '{"resourceType":"Patient"}')

    service = SimpleNamespace(interactions=DummyInteractions())
    req = SimpleNamespace(Type="Patient", Id="1", Json=SimpleNamespace(_ToJSON=lambda: '{"id":"1"}'))
    response = SimpleNamespace(Json=None)

    result = ex.patient_diff_operation("diff", "Instance", {}, service, req, response)
    assert result.Json == {"json": '{"diff":"ok"}'}


@pytest.mark.unit
def test_generic_resource_validation_requires_id():
    with pytest.raises(ValueError):
        ex.generic_resource_validation({"resourceType": "Patient"})


@pytest.mark.unit
def test_validate_patient_resource_rules():
    # Missing name
    with pytest.raises(ValueError):
        ex.validate_patient_resource({"id": "1", "active": True})

    # Missing active
    with pytest.raises(ValueError):
        ex.validate_patient_resource({"id": "1", "name": [{"family": "Doe"}]})

    # Bad MRN format
    with pytest.raises(ValueError):
        ex.validate_patient_resource(
            {
                "id": "1",
                "name": [{"family": "Doe"}],
                "active": True,
                "identifier": [{"system": "http://hospital.org/mrn", "value": "123"}],
            }
        )

    # Valid — should not raise
    ex.validate_patient_resource(
        {
            "id": "1",
            "name": [{"family": "Doe"}],
            "active": True,
            "identifier": [{"system": "http://hospital.org/mrn", "value": "MRN-123"}],
        }
    )


@pytest.mark.unit
def test_validate_observation_resource_requires_note():
    with pytest.raises(ValueError):
        ex.validate_observation_resource(
            {"code": {"coding": [{"code": "critical-001"}]}}
        )


@pytest.mark.unit
def test_validate_transaction_bundle_rules():
    # Invalid HTTP method
    with pytest.raises(ValueError):
        ex.validate_transaction_bundle(
            {"type": "transaction", "entry": [{"request": {"method": "FETCH"}}]}, "R4"
        )

    # Missing request key
    with pytest.raises(ValueError):
        ex.validate_transaction_bundle(
            {"type": "transaction", "entry": [{}]}, "R4"
        )

    # Valid bundle — should not raise
    ex.validate_transaction_bundle(
        {"type": "transaction", "entry": [{"request": {"method": "POST"}}]}, "R4"
    )
