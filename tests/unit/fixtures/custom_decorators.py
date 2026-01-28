from fhir_decorators import FhirDecorators


class RequestContext:
    def __init__(self):
        self.user = ""
        self.roles = ""


context = RequestContext()
fhir = FhirDecorators()


@fhir.before_request
def set_user_context(fhir_service, fhir_request, body, timeout):
    context.user = fhir_request.Username
    context.roles = fhir_request.Roles


@fhir.after_request
def clear_user_context(fhir_service, fhir_request, fhir_response, body):
    context.user = ""
    context.roles = ""


@fhir.on_read("Patient")
def allow_patient_read(resource):
    return "doctor" in context.roles


@fhir.on_search("Patient")
def allow_patient_search(rs, resource_type):
    return True


@fhir.on_update("Patient")
def validate_patient_update(fhir_service, fhir_request, body, timeout):
    if body is None:
        raise ValueError("Missing body")
    if not body.get("name"):
        raise ValueError("Missing name")


@fhir.operation("echo", scope="Instance", resource_type="Patient")
def echo_operation(operation_name, operation_scope, body,
                   fhir_service, fhir_request, fhir_response):
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
