import pytest
from iris_fhir_python_strategy import FhirDecorators

@pytest.mark.unit
def test_on_after_create_ordering():
    fhir = FhirDecorators()

    @fhir.on_after_create()
    def global_handler(service, request, response, body):
        pass

    @fhir.on_after_create("Patient")
    def specific_handler(service, request, response, body):
        pass

    @fhir.on_after_create("*")
    def wildcard_handler(service, request, response, body):
        pass

    handlers = fhir.get_on_after_create_handlers("Patient")
    
    # Expected order: Global (None), Specific ("Patient"), Wildcard ("*")
    assert handlers == [global_handler, specific_handler, wildcard_handler]

    # Verify that for other resources, we get Global then Wildcard
    handlers_obs = fhir.get_on_after_create_handlers("Observation")
    assert handlers_obs == [global_handler, wildcard_handler]

@pytest.mark.unit
def test_on_before_create_ordering():
    fhir = FhirDecorators()

    @fhir.on_before_create()
    def global_handler(service, request, body, timeout):
        pass

    @fhir.on_before_create("Patient")
    def specific_handler(service, request, body, timeout):
        pass

    @fhir.on_before_create("*")
    def wildcard_handler(service, request, body, timeout):
        pass

    handlers = fhir.get_on_before_create_handlers("Patient")
    
    # Expected order: Global (None), Specific ("Patient"), Wildcard ("*")
    assert handlers == [global_handler, specific_handler, wildcard_handler]

@pytest.mark.unit
def test_on_before_read_ordering():
    fhir = FhirDecorators()

    @fhir.on_before_read()
    def global_handler(service, request, body, timeout):
        pass

    @fhir.on_before_read("Patient")
    def specific_handler(service, request, body, timeout):
        pass

    @fhir.on_before_read("*")
    def wildcard_handler(service, request, body, timeout):
        pass

    handlers = fhir.get_on_before_read_handlers("Patient")
    assert handlers == [global_handler, specific_handler, wildcard_handler]

@pytest.mark.unit
def test_on_after_delete_ordering():
    fhir = FhirDecorators()

    @fhir.on_after_delete()
    def global_handler(service, request, response, body):
        pass

    @fhir.on_after_delete("Patient")
    def specific_handler(service, request, response, body):
        pass

    @fhir.on_after_delete("*")
    def wildcard_handler(service, request, response, body):
        pass

    handlers = fhir.get_on_after_delete_handlers("Patient")
    assert handlers == [global_handler, specific_handler, wildcard_handler]

