import threading
from typing import Any, Dict, List, Optional

try:
    from iris_fhir_python_strategy import fhir
except ModuleNotFoundError:
    import sys
    from pathlib import Path

    PROJECT_ROOT = Path(__file__).resolve().parents[3]
    sys.path.insert(0, str(PROJECT_ROOT / "src" / "python"))
    from iris_fhir_python_strategy import fhir


class RequestContext:
    def __init__(self):
        self.user = ""
        self.roles = ""
        self.last_operation = ""


_context_local = threading.local()


def get_context():
    if not hasattr(_context_local, "ctx"):
        _context_local.ctx = RequestContext()
    return _context_local.ctx


BLOCKED_PREFIX = "blocked-"


@fhir.on_capability_statement
def remove_account_resource(capability_statement: Dict[str, Any]) -> Dict[str, Any]:
    capability_statement["rest"][0]["resource"] = [
        resource for resource in capability_statement["rest"][0]["resource"]
        if resource["type"] != "Account"
    ]
    return capability_statement


@fhir.on_before_request
def capture_user_context(fhir_service: Any, fhir_request: Any, body: Dict[str, Any], timeout: int):
    ctx = get_context()
    ctx.user = fhir_request.Username
    ctx.roles = fhir_request.Roles


@fhir.on_after_request
def clear_user_context(fhir_service: Any, fhir_request: Any, fhir_response: Any, body: Dict[str, Any]):
    ctx = get_context()
    ctx.user = ""
    ctx.roles = ""


@fhir.on_before_create("Observation")
def enrich_observation(service: Any, request: Any, body: Dict[str, Any], timeout: int):
    """
    Automatically add a tag to all new Observations.
    """
    meta = body.setdefault("meta", {})
    tags = meta.setdefault("tag", [])
    tags.append({
        "system": "http://my-hospital.org/tags",
        "code": "auto-generated",
        "display": "Auto Generated"
    })

@fhir.on_after_read("Patient")
def deny_blocked_patient_read(resource: Dict[str, Any]) -> bool:
    resource_id = resource.get("id", "")
    if resource_id.startswith(BLOCKED_PREFIX):
        return False
    
    # Example from README: Masking
    # Assuming we want to mask for everyone for this test,
    # or strictly for a specific ID to avoid breaking other tests
    if resource_id == "masked-patient":
        if "telecom" in resource:
            del resource["telecom"]
        if "birthDate" in resource:
            resource["birthDate"] = "1900-01-01"
            
    return True


@fhir.consent("Patient")
def consent_check(resource: Dict[str, Any]) -> bool:
    """
    Consent check.
    """
    # Block if name family is "NoConsent"
    for name in resource.get("name", []):
        if name.get("family") == "NoConsent":
            return False
    return True


@fhir.on_after_search("Patient")
def filter_blocked_patient_search(rs: Any, resource_type: str):
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


@fhir.on_before_create("Patient")
def record_create(fhir_service: Any, fhir_request: Any, body: Dict[str, Any], timeout: int):
    ctx = get_context()
    ctx.last_operation = "create"


@fhir.on_before_update("Patient")
def record_update(fhir_service: Any, fhir_request: Any, body: Dict[str, Any], timeout: int):
    ctx = get_context()
    ctx.last_operation = "update"


@fhir.on_before_delete("Patient")
def record_delete(fhir_service: Any, fhir_request: Any, body: Dict[str, Any], timeout: int):
    ctx = get_context()
    ctx.last_operation = "delete"


@fhir.operation("echo", scope="Type", resource_type="Patient")
def echo_operation(operation_name: str, operation_scope: str, body: Dict[str, Any],
                   fhir_service: Any, fhir_request: Any, fhir_response: Any):
    fhir_response.Json = {
        "resourceType": "Parameters",
        "parameter": [
            {"name": "name", "valueString": operation_name},
            {"name": "scope", "valueString": operation_scope},
        ],
    }
    return fhir_response


@fhir.oauth_set_instance
def set_oauth_instance(token_string: str, oauth_client: Any, base_url: str, username: str):
    ctx = get_context()
    ctx.user = username


@fhir.oauth_get_introspection
def get_introspection() -> Dict[str, Any]:
    return {"active": True, "scope": "patient/*.read"}


@fhir.oauth_get_user_info
def get_user_info(basic_auth_username: str, basic_auth_roles: str) -> Dict[str, Any]:
    return {"Username": basic_auth_username, "Roles": basic_auth_roles}


@fhir.oauth_verify_resource_id("Patient")
def verify_patient_id_access(resource_type: str, resource_id: str, required_privilege: str) -> bool:
    return True


@fhir.oauth_verify_resource_content("Patient")
def verify_patient_content_access(resource_dict: Dict[str, Any], required_privilege: str, allow_shared: bool) -> bool:
    return True


@fhir.oauth_verify_history("Patient")
def verify_patient_history(resource_type: str, resource_dict: Dict[str, Any], required_privilege: str) -> bool:
    return True


@fhir.oauth_verify_delete("Patient")
def verify_patient_delete(resource_type: str, resource_id: str, required_privilege: str) -> bool:
    return True


@fhir.oauth_verify_search("Patient")
def verify_patient_search(resource_type: str, compartment_type: str, compartment_id: str,
                          parameters: Dict[str, Any], required_privilege: str) -> bool:
    return True


@fhir.oauth_verify_system_level
def verify_system_access() -> bool:
    return True


@fhir.on_validate_resource("Patient")
def validate_patient_resource(resource_object: Dict[str, Any], is_in_transaction: bool = False):
    if "id" not in resource_object:
        raise ValueError("Patient must have id")
    
    # Example from README: Check for forbidden names
    for name in resource_object.get("name", []):
        if name.get("family") == "Forbidden":
            raise ValueError("This family name is not allowed")


@fhir.on_validate_bundle
def validate_bundle(resource_object: Dict[str, Any], fhir_version: str):
    if resource_object.get("type") == "transaction" and not resource_object.get("entry"):
        raise ValueError("Transaction bundle must have entries")


@fhir.on_validate_resource("Observation")
def validate_observation(resource_object: Dict[str, Any], is_in_transaction: bool = False):
    # Only raise error for specific testing condition
    if resource_object.get("code", {}).get("text") == "invalid":
        raise ValueError("Custom Error Observation")

    # Check ID for forbidden keyword (for e2e testing)
    if "forbidden" in resource_object.get("id", ""):
        raise ValueError("This observation ID is forbidden")


@fhir.on_validate_resource("Organization")
def fail_validation_hard(resource_object: Dict[str, Any], is_in_transaction: bool = False):
    # This raises a generic exception, expecting 500 Internal Server Error
    # or a wrapped error handling depending on Helper.cls
    x = 1 / 0  # ZeroDivisionError


@fhir.operation("crash", scope="Type", resource_type="Patient")
def crash_operation(operation_name: str, operation_scope: str, body: Dict[str, Any],
                   fhir_service: Any, fhir_request: Any, fhir_response: Any):
    raise Exception("Boom! explicit crash")
