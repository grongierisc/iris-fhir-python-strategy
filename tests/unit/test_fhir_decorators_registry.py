import pytest

from fhir_decorators import FhirDecorators


@pytest.mark.unit
def test_registers_capability_and_request_hooks():
    fhir = FhirDecorators()

    @fhir.on_capability_statement
    def cap_handler(statement):
        return statement

    @fhir.before_request
    def before_handler(service, request, body, timeout):
        return None

    @fhir.after_request
    def after_handler(service, request, response, body):
        return None

    assert fhir.get_capability_statement_handlers() == [cap_handler]
    assert fhir.get_before_request_handlers() == [before_handler]
    assert fhir.get_after_request_handlers() == [after_handler]


@pytest.mark.unit
def test_post_process_read_orders_wildcard_then_specific():
    fhir = FhirDecorators()

    @fhir.post_process_read()
    def wildcard_handler(resource):
        return True

    @fhir.post_process_read("Patient")
    def patient_handler(resource):
        return True

    handlers = fhir.get_post_process_read_handlers("Patient")
    assert handlers == [wildcard_handler, patient_handler]


@pytest.mark.unit
def test_operation_resolution_prefers_specific_then_wildcard():
    fhir = FhirDecorators()

    @fhir.operation("diff", scope="Instance", resource_type="*")
    def wildcard_op(*args):
        return "wildcard"

    @fhir.operation("diff", scope="Instance", resource_type="Patient")
    def patient_op(*args):
        return "patient"

    assert fhir.get_operation_handler("diff", "Instance", "Patient") is patient_op
    assert fhir.get_operation_handler("diff", "Instance", "Observation") is wildcard_op


@pytest.mark.unit
def test_validate_resource_handlers_include_wildcard():
    fhir = FhirDecorators()

    @fhir.validate_resource("*")
    def validate_any(resource, is_in_transaction=False):
        return None

    @fhir.validate_resource("Patient")
    def validate_patient(resource, is_in_transaction=False):
        return None

    handlers = fhir.get_validate_resource_handlers("Patient")
    assert handlers == [validate_any, validate_patient]


@pytest.mark.unit
def test_oauth_handlers_collected_by_resource_type():
    fhir = FhirDecorators()

    @fhir.oauth_verify_resource_id("*")
    def verify_any(resource_type, resource_id, required_privilege):
        return None

    @fhir.oauth_verify_resource_id("Patient")
    def verify_patient(resource_type, resource_id, required_privilege):
        return None

    handlers = fhir.get_oauth_verify_resource_id_handlers("Patient")
    assert handlers == [verify_any, verify_patient]
