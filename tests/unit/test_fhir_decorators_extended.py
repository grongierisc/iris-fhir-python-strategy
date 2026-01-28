import pytest
from fhir_decorators import FhirDecorators

@pytest.mark.unit
def test_validate_resource_pipeline_calls_handlers():
    fhir = FhirDecorators()
    state = []

    @fhir.validate_resource("Patient")
    def validate_one(resource, is_in_transaction=False):
        state.append("one")

    @fhir.validate_resource("Patient")
    def validate_two(resource, is_in_transaction=False):
        state.append("two")

    handlers = fhir.get_validate_resource_handlers("Patient")
    for handler in handlers:
        handler({}, False)
    
    assert state == ["one", "two"]

@pytest.mark.unit
def test_validate_bundle_pipeline_calls_handlers():
    fhir = FhirDecorators()
    state = []

    @fhir.validate_bundle
    def validate(resource, fhir_version):
        state.append("validated")

    handlers = fhir.get_validate_bundle_handlers()
    for handler in handlers:
        handler({}, "R4")

    assert state == ["validated"]

@pytest.mark.unit
def test_create_pipeline_calls_wildcard_and_specific():
    fhir = FhirDecorators()
    state = []

    @fhir.on_create("Patient")
    def create_specific(service, request, body, timeout):
        state.append("specific")

    @fhir.on_create()
    def create_wildcard(service, request, body, timeout):
        state.append("wildcard")

    handlers = fhir.get_create_handlers("Patient")
    # Order usually depends on implementation, but typically wildcards then specific or vice versa. 
    # Based on other tests: wildcard then specific
    for handler in handlers:
        handler(None, None, None, None)

    assert "specific" in state
    assert "wildcard" in state

@pytest.mark.unit
def test_update_pipeline_calls_handlers():
    fhir = FhirDecorators()
    state = []

    @fhir.on_update("Patient")
    def update_handler(service, request, body, timeout):
        state.append("update")

    handlers = fhir.get_update_handlers("Patient")
    for handler in handlers:
        handler(None, None, None, None)

    assert state == ["update"]

@pytest.mark.unit
def test_delete_pipeline_calls_handlers():
    fhir = FhirDecorators()
    state = []

    @fhir.on_delete("Patient")
    def delete_handler(service, request, body, timeout):
        state.append("delete")

    handlers = fhir.get_delete_handlers("Patient")
    for handler in handlers:
        handler(None, None, None, None)

    assert state == ["delete"]

@pytest.mark.unit
def test_operation_structure_for_objectscript():
    """
    Ensure the get_operations method returns the structure expected by OperationHandler.cls
    dictionary with keys (name, scope, resource_type) and values callable.
    """
    fhir = FhirDecorators()

    @fhir.operation("op1", scope="System")
    def op1(): pass

    @fhir.operation("op2", scope="Type", resource_type="Patient")
    def op2(): pass

    ops = fhir.get_operations()
    
    # Check keys are tuples
    keys = list(ops.keys())
    assert ("op1", "System", "*") in keys
    assert ("op2", "Type", "Patient") in keys
    
    # Check values are the functions
    assert ops[("op1", "System", "*")] == op1
    assert ops[("op2", "Type", "Patient")] == op2

