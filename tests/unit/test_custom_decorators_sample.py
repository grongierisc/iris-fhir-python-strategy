from unittest.mock import Mock

import pytest

from tests.unit.fixtures import custom_decorators as cd


@pytest.fixture(autouse=True)
def reset_context():
    cd.context.user = ""
    cd.context.roles = ""
    yield
    cd.context.user = ""
    cd.context.roles = ""


@pytest.mark.unit
def test_before_after_request_updates_context(fake_fhir_request):
    request_doctor = fake_fhir_request(username="alice", roles="doctor")
    before_handlers = cd.fhir.get_before_request_handlers()
    after_handlers = cd.fhir.get_after_request_handlers()
    assert before_handlers
    assert after_handlers

    for handler in before_handlers:
        handler(Mock(), request_doctor, None, None)

    assert cd.context.user == "alice"
    assert cd.context.roles == "doctor"

    for handler in after_handlers:
        handler(Mock(), request_doctor, Mock(), None)

    assert cd.context.user == ""
    assert cd.context.roles == ""


@pytest.mark.unit
def test_read_handler_allows_doctor(fake_fhir_request):
    request_doctor = fake_fhir_request(username="alice", roles="doctor")
    for handler in cd.fhir.get_before_request_handlers():
        handler(Mock(), request_doctor, None, None)

    results = [handler({"resourceType": "Patient"}) for handler in cd.fhir.get_post_process_read_handlers("Patient")]
    assert results == [True]


@pytest.mark.unit
def test_read_handler_denies_guest(fake_fhir_request):
    request_guest = fake_fhir_request(username="bob", roles="guest")
    for handler in cd.fhir.get_before_request_handlers():
        handler(Mock(), request_guest, None, None)

    results = [handler({"resourceType": "Patient"}) for handler in cd.fhir.get_post_process_read_handlers("Patient")]
    assert results == [False]


@pytest.mark.unit
def test_search_handler_registered():
    handlers = cd.fhir.get_post_process_search_handlers("Patient")
    assert handlers
    assert handlers[0](None, "Patient") is True


@pytest.mark.unit
def test_update_handler_requires_name():
    handlers = cd.fhir.get_update_handlers("Patient")
    assert handlers

    with pytest.raises(ValueError, match="Missing body"):
        handlers[0](Mock(), Mock(), None, None)

    with pytest.raises(ValueError, match="Missing name"):
        handlers[0](Mock(), Mock(), {"resourceType": "Patient"}, None)

    handlers[0](Mock(), Mock(), {"resourceType": "Patient", "name": [{"family": "Doe"}]}, None)


@pytest.mark.unit
def test_operation_handler_sets_payload():
    handler = cd.fhir.get_operation_handler("echo", "Instance", "Patient")
    response = Mock()

    result = handler("echo", "Instance", {"ping": "pong"}, Mock(), Mock(), response)

    assert result is response
    assert response.payload == {"name": "echo", "scope": "Instance", "body": {"ping": "pong"}}


@pytest.mark.unit
def test_oauth_history_handler_is_registered():
    handlers = cd.fhir.get_oauth_verify_history_handlers("Patient")
    assert handlers
    assert handlers[0]("Patient", {"resourceType": "Patient"}, "read") is True


@pytest.mark.unit
def test_oauth_search_handler_is_registered():
    handlers = cd.fhir.get_oauth_verify_search_handlers("Patient")
    assert handlers
    assert handlers[0]("Patient", None, None, {}, "read") is True
