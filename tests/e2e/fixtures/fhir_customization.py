from contextvars import ContextVar

try:
    from fhir_decorators import fhir
except ModuleNotFoundError:
    import sys
    from pathlib import Path

    PROJECT_ROOT = Path(__file__).resolve().parents[3]
    sys.path.insert(0, str(PROJECT_ROOT / "src" / "python"))
    from fhir_decorators import fhir


class RequestContext:
    def __init__(self):
        self.user = ""
        self.roles = ""
        self.last_operation = ""


_context = ContextVar("fhir_customization_context", default=RequestContext())


def get_context():
    return _context.get()


BLOCKED_PREFIX = "blocked-"


@fhir.on_capability_statement
def remove_account_resource(capability_statement):
    capability_statement["rest"][0]["resource"] = [
        resource for resource in capability_statement["rest"][0]["resource"]
        if resource["type"] != "Account"
    ]
    return capability_statement


@fhir.before_request
def capture_user_context(fhir_service, fhir_request, body, timeout):
    ctx = get_context()
    ctx.user = fhir_request.Username
    ctx.roles = fhir_request.Roles


@fhir.after_request
def clear_user_context(fhir_service, fhir_request, fhir_response, body):
    ctx = get_context()
    ctx.user = ""
    ctx.roles = ""


@fhir.on_read("Patient")
def deny_blocked_patient_read(resource):
    resource_id = resource.get("id", "")
    if resource_id.startswith(BLOCKED_PREFIX):
        return False
    return True


@fhir.post_process_search("Patient")
def filter_blocked_patient_search(rs, resource_type):
    """
    Filter out blocked patients from search results.
    """
    # rs is a ResultIterator
    rs._SetIterator(0)
    while rs._Next():
        resource_id = rs._Get("ResourceId")
        if resource_id.startswith(BLOCKED_PREFIX):
            rs.MarkAsDeleted()
            rs._SaveRow()


@fhir.on_create("Patient")
def record_create(fhir_service, fhir_request, body, timeout):
    ctx = get_context()
    ctx.last_operation = "create"


@fhir.on_update("Patient")
def record_update(fhir_service, fhir_request, body, timeout):
    ctx = get_context()
    ctx.last_operation = "update"


@fhir.on_delete("Patient")
def record_delete(fhir_service, fhir_request, body, timeout):
    ctx = get_context()
    ctx.last_operation = "delete"


@fhir.operation("echo", scope="Type", resource_type="Patient")
def echo_operation(operation_name, operation_scope, body,
                   fhir_service, fhir_request, fhir_response):
    fhir_response.Json = {
        "resourceType": "Parameters",
        "parameter": [
            {"name": "name", "valueString": operation_name},
            {"name": "scope", "valueString": operation_scope},
        ],
    }
    return fhir_response


@fhir.oauth_set_instance
def set_oauth_instance(token_string, oauth_client, base_url, username):
    ctx = get_context()
    ctx.user = username


@fhir.oauth_get_introspection
def get_introspection():
    return {"active": True, "scope": "patient/*.read"}


@fhir.oauth_get_user_info
def get_user_info(basic_auth_username, basic_auth_roles):
    return {"Username": basic_auth_username, "Roles": basic_auth_roles}


@fhir.oauth_verify_resource_id("Patient")
def verify_patient_id_access(resource_type, resource_id, required_privilege):
    return True


@fhir.oauth_verify_resource_content("Patient")
def verify_patient_content_access(resource_dict, required_privilege, allow_shared):
    return True


@fhir.oauth_verify_history("Patient")
def verify_patient_history(resource_type, resource_dict, required_privilege):
    return True


@fhir.oauth_verify_delete("Patient")
def verify_patient_delete(resource_type, resource_id, required_privilege):
    return True


@fhir.oauth_verify_search("Patient")
def verify_patient_search(resource_type, compartment_type, compartment_id,
                          parameters, required_privilege):
    return True


@fhir.oauth_verify_system_level
def verify_system_access():
    return True


@fhir.validate_resource("Patient")
def validate_patient_resource(resource_object, is_in_transaction=False):
    if "id" not in resource_object:
        raise ValueError("Patient must have id")


@fhir.validate_bundle
def validate_bundle(resource_object, fhir_version):
    if resource_object.get("type") == "transaction" and not resource_object.get("entry"):
        raise ValueError("Transaction bundle must have entries")


@fhir.validate_resource("Observation")
def validate_observation(resource_object, is_in_transaction=False):
    raise ValueError("Custom Error Observation")
