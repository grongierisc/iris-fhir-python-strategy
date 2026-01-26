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
def test_post_process_search_orders_wildcard_then_specific():
    fhir = FhirDecorators()

    @fhir.post_process_search()
    def wildcard_handler(rs, resource_type):
        return None

    @fhir.post_process_search("Patient")
    def patient_handler(rs, resource_type):
        return None

    handlers = fhir.get_post_process_search_handlers("Patient")
    assert handlers == [wildcard_handler, patient_handler]


@pytest.mark.unit
def test_on_read_and_on_search_aliases():
    fhir = FhirDecorators()

    @fhir.on_read("Patient")
    def read_handler(resource):
        return True

    @fhir.on_search("Patient")
    def search_handler(rs, resource_type):
        return None

    assert fhir.get_post_process_read_handlers("Patient") == [read_handler]
    assert fhir.get_post_process_search_handlers("Patient") == [search_handler]


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
    assert fhir.get_operation_handler("missing", "Instance", "Patient") is None


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


@pytest.mark.unit
def test_oauth_other_handlers_collected():
    fhir = FhirDecorators()

    @fhir.oauth_verify_resource_content("*")
    def verify_content_any(resource_dict, required_privilege, allow_shared):
        return None

    @fhir.oauth_verify_delete("Patient")
    def verify_delete_patient(resource_type, resource_id, required_privilege):
        return None

    @fhir.oauth_verify_search("Patient")
    def verify_search_patient(resource_type, compartment_type, compartment_id,
                              parameters, required_privilege):
        return None

    @fhir.oauth_verify_history("Patient")
    def verify_history_patient(resource_type, resource_dict, required_privilege):
        return None

    @fhir.oauth_verify_system_level
    def verify_system():
        return None

    assert fhir.get_oauth_verify_resource_content_handlers("Patient") == [verify_content_any]
    assert fhir.get_oauth_verify_delete_handlers("Patient") == [verify_delete_patient]
    assert fhir.get_oauth_verify_search_handlers("Patient") == [verify_search_patient]
    assert fhir.get_oauth_verify_history_handlers("Patient") == [verify_history_patient]
    assert fhir.get_oauth_verify_system_level_handlers() == [verify_system]


@pytest.mark.unit
def test_create_update_delete_handlers_include_wildcard():
    fhir = FhirDecorators()

    @fhir.on_create()
    def create_any(service, request, body, timeout):
        return None

    @fhir.on_create("Patient")
    def create_patient(service, request, body, timeout):
        return None

    @fhir.on_update()
    def update_any(service, request, body, timeout):
        return None

    @fhir.on_update("Patient")
    def update_patient(service, request, body, timeout):
        return None

    @fhir.on_delete()
    def delete_any(service, request, body, timeout):
        return None

    @fhir.on_delete("Patient")
    def delete_patient(service, request, body, timeout):
        return None

    assert fhir.get_create_handlers("Patient") == [create_any, create_patient]
    assert fhir.get_update_handlers("Patient") == [update_any, update_patient]
    assert fhir.get_delete_handlers("Patient") == [delete_any, delete_patient]


@pytest.mark.unit
def test_consent_handlers_include_wildcard():
    fhir = FhirDecorators()

    @fhir.consent()
    def consent_any(resource, user_context):
        return True

    @fhir.consent("Patient")
    def consent_patient(resource, user_context):
        return True

    handlers = fhir.get_consent_handlers("Patient")
    assert handlers == [consent_any, consent_patient]


@pytest.mark.unit
def test_validate_bundle_handlers_registered():
    fhir = FhirDecorators()

    @fhir.validate_bundle
    def validate_bundle(resource, fhir_version):
        return None

    assert fhir.get_validate_bundle_handlers() == [validate_bundle]


@pytest.mark.unit
def test_oauth_getters_return_copies():
    fhir = FhirDecorators()

    @fhir.oauth_set_instance
    def set_instance(token, client, base_url, username):
        return None

    @fhir.oauth_get_introspection
    def get_introspection():
        return {}

    @fhir.oauth_get_user_info
    def get_user_info(username, roles):
        return {}

    handlers = fhir.get_oauth_set_instance_handlers()
    assert handlers == [set_instance]
    handlers.append("mutated")

    assert fhir.get_oauth_set_instance_handlers() == [set_instance]
    assert fhir.get_oauth_get_introspection_handlers() == [get_introspection]
    assert fhir.get_oauth_get_user_info_handlers() == [get_user_info]


@pytest.mark.unit
def test_get_operations_returns_copy():
    fhir = FhirDecorators()

    @fhir.operation("diff", scope="Instance", resource_type="Patient")
    def patient_op(*args):
        return None

    operations = fhir.get_operations()
    assert operations == {("diff", "Instance", "Patient"): patient_op}
    operations[("diff", "Instance", "Patient")] = "mutated"
    assert fhir.get_operations() == {("diff", "Instance", "Patient"): patient_op}
