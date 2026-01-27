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


@fhir.on_read("Patient")
def deny_blocked_patient_read(resource):
    resource_id = resource.get("id", "")
    if resource_id.startswith(BLOCKED_PREFIX):
        return False
    return True

