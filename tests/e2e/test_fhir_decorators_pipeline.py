import pytest

from fhir_decorators import FhirDecorators


class DummyService:
    pass


class DummyRequest:
    def __init__(self, user, roles):
        self.Username = user
        self.Roles = roles


@pytest.mark.e2e
def test_handler_pipeline_runs_in_expected_order():
    fhir = FhirDecorators()
    state = {"calls": []}

    @fhir.before_request
    def before_handler(service, request, body, timeout):
        state["calls"].append(("before", request.Username))

    @fhir.post_process_read("Patient")
    def read_handler(resource):
        state["calls"].append(("read", resource["id"]))
        return True

    @fhir.after_request
    def after_handler(service, request, response, body):
        state["calls"].append(("after", request.Username))

    request = DummyRequest("alice", "doctor")
    for handler in fhir.get_before_request_handlers():
        handler(DummyService(), request, None, None)

    resource = {"resourceType": "Patient", "id": "1"}
    results = [handler(resource) for handler in fhir.get_post_process_read_handlers("Patient")]

    for handler in fhir.get_after_request_handlers():
        handler(DummyService(), request, None, None)

    assert results == [True]
    assert state["calls"] == [("before", "alice"), ("read", "1"), ("after", "alice")]


@pytest.mark.e2e
def test_capability_statement_pipeline():
    fhir = FhirDecorators()

    @fhir.on_capability_statement
    def strip_account(statement):
        statement["rest"][0]["resource"] = [
            r for r in statement["rest"][0]["resource"] if r["type"] != "Account"
        ]
        return statement

    capability = {"rest": [{"resource": [{"type": "Account"}, {"type": "Patient"}]}]}
    for handler in fhir.get_capability_statement_handlers():
        capability = handler(capability)

    types = [resource["type"] for resource in capability["rest"][0]["resource"]]
    assert types == ["Patient"]
