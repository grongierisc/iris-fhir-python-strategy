from iris_fhir_python_strategy import fhir, get_request_context
from iris_fhir_python_strategy.fhir_decorators import FhirDecorators

_saved = None
_mode = "observe"
_events = []


def install():
    global _saved, _mode
    _saved = fhir.__dict__
    fhir.__dict__ = FhirDecorators().__dict__
    _mode = "observe"
    _events.clear()

    @fhir.on_before_request
    def before(service, request, body, timeout):
        _events.append(("before", request.Interaction))
        get_request_context().username = "bridge-test"

    @fhir.on_after_request
    def after(service, request, response, body):
        _events.append(("after", request.Interaction))
        if _mode == "after-error":
            raise ValueError("Injected after-request failure")

    @fhir.on_before_create("Patient")
    def create(service, request, body, timeout):
        _events.append(("create", body["resourceType"]))

    @fhir.on_validate_resource("*")
    def validate(resource, in_transaction):
        _events.append(("resource", resource["resourceType"]))
        if _mode == "reject-patient" and resource["resourceType"] == "Patient":
            raise ValueError("Patient rejected by Python")
        return {
            "resourceType": "OperationOutcome",
            "issue": [{"severity": "warning", "code": "informational"}],
        }

    @fhir.on_validate_bundle
    def bundle(resource, version):
        for entry in resource.get("entry", []):
            if entry.get("request", {}).get("method") == "PATCH":
                _events.append(("bundle", entry["resource"]["resourceType"]))
        if _mode == "reject-bundle":
            raise ValueError("Bundle rejected by Python")

    @fhir.consent("Patient")
    def consent(resource):
        return _mode != "deny"

    @fhir.on_after_read("Patient")
    def mask(resource):
        if _mode == "mask":
            resource.pop("identifier", None)
        return True

    @fhir.on_capability_statement
    def metadata(resource):
        resource["publisher"] = "Python bridge test"
        return resource


def configure(mode):
    global _mode
    _mode = mode
    if mode == "override":
        @fhir.operation(name="merge", scope="Type", resource_type="Patient")
        def merge(name, scope, body, service, request, response):
            response.Json = {"resourceType": "Parameters", "parameter": [
                {"name": "python", "valueBoolean": True},
            ]}
            response.Status = 200
            return response
    if mode == "wildcard":
        @fhir.operation(name="merge", scope="Type", resource_type="*")
        def merge(name, scope, body, service, request, response):
            response.Json = {"resourceType": "Parameters"}
            response.Status = 200
            return response
    if mode == "instance":
        @fhir.operation(name="merge", scope="Instance", resource_type="Patient")
        def merge(name, scope, body, service, request, response):
            response.Json = {"resourceType": "Parameters"}
            response.Status = 200
            return response


def count(kind, value):
    return _events.count((kind, value))


def context_clear():
    return get_request_context().username != "bridge-test"


def restore():
    global _saved
    if _saved is not None:
        fhir.__dict__ = _saved
        _saved = None
