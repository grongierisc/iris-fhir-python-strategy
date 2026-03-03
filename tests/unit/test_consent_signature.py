"""
Regression tests ensuring @fhir.consent signature validation works.

Background
----------
ObjectScript's RunBooleanHandlers always calls consent handlers with exactly
one positional argument (the resource dict).  Registering a handler that
requires a second argument (e.g. ``user_context``) would cause a Python
TypeError that surfaces as the cryptic IRIS error:
    <OBJECT DISPATCH> 2603 RunBooleanHandlers+8^FHIR.Python.Helper.1

The ``@fhir.consent`` decorator wraps bad handlers at registration time.
The wrapper raises a clear ``TypeError`` when called by the IRIS bridge,
producing a proper FHIR OperationOutcome with a meaningful diagnostics
message instead of the cryptic OBJECT DISPATCH error.
"""
from typing import Any, Dict, Generator

import pytest

from iris_fhir_python_strategy import FhirDecorators, get_request_context, request_context


@pytest.fixture()
def fhir() -> FhirDecorators:
    """Fresh, isolated registry for each test."""
    return FhirDecorators()


@pytest.fixture(autouse=True)
def isolated_request_context() -> Generator[None, None, None]:
    with request_context():
        yield


# ---------------------------------------------------------------------------
# Registration-time: decoration must succeed, error deferred to call time
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_consent_two_required_args_raises_at_call_time(fhir: FhirDecorators):
    """Bad handler registers silently; calling it raises TypeError."""
    @fhir.consent("Patient")
    def bad_handler(fhir_object: Dict[str, Any], user_context: Any) -> bool:
        return True

    handlers = fhir.get_consent_handlers("Patient")
    assert len(handlers) == 1
    with pytest.raises(TypeError, match="IRIS bridge only passes 1"):
        handlers[0]({"resourceType": "Patient"})


@pytest.mark.unit
def test_consent_zero_args_raises_at_call_time(fhir: FhirDecorators):
    """Zero-arg handler registers silently; calling it raises TypeError."""
    @fhir.consent("Patient")
    def bad_handler() -> bool:
        return True

    handlers = fhir.get_consent_handlers("Patient")
    assert len(handlers) == 1
    with pytest.raises(TypeError, match="IRIS bridge passes 1"):
        handlers[0]({"resourceType": "Patient"})


@pytest.mark.unit
def test_consent_error_message_names_bad_params(fhir: FhirDecorators):
    """The call-time error message must include the unexpected parameter names."""
    @fhir.consent("Patient")
    def bad_handler(fhir_object: Dict[str, Any], user_context: Any) -> bool:
        return True

    with pytest.raises(TypeError, match="user_context"):
        fhir.get_consent_handlers("Patient")[0]({"resourceType": "Patient"})


@pytest.mark.unit
def test_consent_error_message_names_handler(fhir: FhirDecorators):
    """The call-time error message must include the handler function name."""
    @fhir.consent("Patient")
    def my_broken_handler(fhir_object: Dict[str, Any], user_context: Any) -> bool:
        return True

    with pytest.raises(TypeError, match="my_broken_handler"):
        fhir.get_consent_handlers("Patient")[0]({"resourceType": "Patient"})


@pytest.mark.unit
def test_consent_error_suggests_docstring(fhir: FhirDecorators):
    """The call-time error message must point users to the decorator docstring."""
    @fhir.consent("Patient")
    def bad_handler(fhir_object: Dict[str, Any], user_context: Any) -> bool:
        return True

    with pytest.raises(TypeError, match="decorator docstring"):
        fhir.get_consent_handlers("Patient")[0]({"resourceType": "Patient"})


@pytest.mark.unit
def test_consent_bad_handler_registered_as_wrapper(fhir: FhirDecorators):
    """A bad-signature handler IS added to the registry as an error-raising wrapper."""
    @fhir.consent("Patient")
    def bad_handler(fhir_object: Dict[str, Any], user_context: Any) -> bool:
        return True

    handlers = fhir.get_consent_handlers("Patient")
    assert len(handlers) == 1
    with pytest.raises(TypeError):
        handlers[0]({"resourceType": "Patient"})


# ---------------------------------------------------------------------------
# Valid signatures that must be accepted
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_consent_one_required_arg_registers_successfully(fhir: FhirDecorators):
    """A handler with exactly 1 required arg must register without error."""
    @fhir.consent("Patient")
    def good_handler(fhir_object: Dict[str, Any]) -> bool:
        return True

    assert good_handler in fhir.get_consent_handlers("Patient")


@pytest.mark.unit
def test_consent_one_required_plus_optional_registers_successfully(fhir: FhirDecorators):
    """A handler with 1 required arg and optional kwargs must be accepted."""
    @fhir.consent("Patient")
    def good_handler(fhir_object: Dict[str, Any], extra: Any = None) -> bool:
        return True

    assert good_handler in fhir.get_consent_handlers("Patient")


@pytest.mark.unit
def test_consent_wildcard_valid_handler(fhir: FhirDecorators):
    """Wildcard consent registration with valid signature must work."""
    @fhir.consent("*")
    def wildcard_handler(resource: Dict[str, Any]) -> bool:
        return True

    assert wildcard_handler in fhir.get_consent_handlers("Patient")


# ---------------------------------------------------------------------------
# Runtime behaviour — handler called with the resource dict
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_consent_handler_called_with_one_arg(fhir: FhirDecorators):
    """Handler must be invokeable with a single positional argument."""
    calls = []

    @fhir.consent("Patient")
    def capture(fhir_object: Dict[str, Any]) -> bool:
        calls.append(fhir_object)
        return True

    resource = {"resourceType": "Patient", "id": "p1"}
    result = capture(resource)

    assert result is True
    assert calls == [resource]


@pytest.mark.unit
def test_consent_handler_uses_request_context_for_user_data(fhir: FhirDecorators):
    """
    Reproduce the original bug scenario: the handler must reach user data via
    get_request_context(), not via a second parameter.
    """
    ctx = get_request_context()
    ctx.security_list = ["confidential"]

    @fhir.consent("Patient")
    def consent_check(fhir_object: Dict[str, Any]) -> bool:
        c = get_request_context()
        for sec in fhir_object.get("meta", {}).get("security", []):
            if sec.get("code") in c.security_list:
                return False
        return True

    blocked_resource = {"meta": {"security": [{"code": "confidential"}]}}
    open_resource = {"meta": {"security": [{"code": "public"}]}}

    assert consent_check(blocked_resource) is False
    assert consent_check(open_resource) is True
