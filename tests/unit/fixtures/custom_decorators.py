from iris_fhir_python_strategy import FhirDecorators
from typing import Any, Dict


class RequestContext:
    def __init__(self):
        self.user = ""
        self.roles = ""


context = RequestContext()
fhir = FhirDecorators()


@fhir.on_before_request
def set_user_context(fhir_service: Any, fhir_request: Any, body: Dict[str, Any], timeout: int):
    context.user = fhir_request.Username
    context.roles = fhir_request.Roles


@fhir.on_after_request
def clear_user_context(fhir_service: Any, fhir_request: Any, fhir_response: Any, body: Dict[str, Any]):
    context.user = ""
    context.roles = ""


@fhir.on_after_read("Patient")
def allow_patient_read(resource: Dict[str, Any]) -> bool:
    return "doctor" in context.roles


@fhir.on_after_search("Patient")
def allow_patient_search(rs: Any, resource_type: str) -> bool:
    return True


@fhir.on_before_update("Patient")
def validate_patient_update(fhir_service: Any, fhir_request: Any, body: Dict[str, Any], timeout: int):
    if body is None:
        raise ValueError("Missing body")
    if not body.get("name"):
        raise ValueError("Missing name")


@fhir.operation("echo", scope="Instance", resource_type="Patient")
def echo_operation(operation_name: str, operation_scope: str, body: Dict[str, Any],
                   fhir_service: Any, fhir_request: Any, fhir_response: Any):
    fhir_response.payload = {
        "name": operation_name,
        "scope": operation_scope,
        "body": body,
    }
    return fhir_response


@fhir.oauth_verify_history("Patient")
def verify_patient_history(resource_type, resource_dict, required_privilege):
    return resource_type == "Patient"


@fhir.oauth_verify_search("Patient")
def verify_patient_search(resource_type, compartment_type, compartment_id,
                          parameters, required_privilege):
    return resource_type == "Patient"
