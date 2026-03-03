"""
Parametrized arity-validation tests for every @fhir.* decorator.

Background
----------
The IRIS bridge calls each handler with a fixed number of positional
arguments determined by the ObjectScript caller.  A handler that declares
more required positional parameters than the bridge provides previously
caused the cryptic IRIS error::

    <OBJECT DISPATCH> 2603 RunBooleanHandlers+8^FHIR.Python.Helper.1

The ``FhirDecorators._wrap_with_arity_check`` guard wraps bad-signature
handlers at *registration* time.  The wrapper raises a clear ``TypeError``
when *called* by the bridge, producing a proper FHIR OperationOutcome with
a meaningful diagnostics message.  Importantly, a bad handler never crashes
the application at import / load time.

This test module checks every decorator registration point with:
  - A correctly-signed handler → must register without raising
  - A handler with too many required args → decorator must succeed;
    calling the registered wrapper must raise TypeError
  - A handler with too few positional slots → same
  - A handler declared with ``*args`` → must always be accepted

Expected argument counts (derived from the ObjectScript callers):
┌──────────────────────────────────┬──────┐
│ Decorator                        │ Args │
├──────────────────────────────────┼──────┤
│ on_capability_statement          │  1   │
│ on_before_request                │  4   │
│ on_after_request                 │  4   │
│ on_before_create/read/update/    │      │
│   delete/search                  │  4   │
│ on_after_create/update/delete    │  4   │
│ on_after_read                    │  1   │
│ on_after_search                  │  2   │
│ consent                          │  1   │
│ operation                        │  6   │
│ oauth_set_instance               │  4   │
│ oauth_get_introspection          │  0   │
│ oauth_get_user_info              │  2   │
│ oauth_verify_resource_id         │  3   │
│ oauth_verify_resource_content    │  3   │
│ oauth_verify_history             │  3   │
│ oauth_verify_delete              │  3   │
│ oauth_verify_search              │  5   │
│ oauth_verify_system_level        │  0   │
│ on_validate_resource             │  2   │
│ on_validate_bundle               │  2   │
└──────────────────────────────────┴──────┘
"""
from typing import Any, Callable, Dict, List
import pytest

from iris_fhir_python_strategy import FhirDecorators


# ---------------------------------------------------------------------------
# Helpers to build handlers with N required positional params
# ---------------------------------------------------------------------------

def _make_args(n: int) -> str:
    return ", ".join(f"a{i}" for i in range(n))


def _make_handler(n: int) -> Callable:
    """Return a function with exactly *n* required positional parameters."""
    ns: Dict[str, Any] = {}
    exec(f"def handler({_make_args(n)}): pass", ns)
    return ns["handler"]


def _make_handler_with_optional(required: int, optional: int) -> Callable:
    """Return a handler with *required* required + *optional* optional params."""
    req = _make_args(required)
    opt = ", ".join(f"b{i}=None" for i in range(optional))
    sig = ", ".join(filter(None, [req, opt]))
    ns: Dict[str, Any] = {}
    exec(f"def handler({sig}): pass", ns)
    return ns["handler"]


def _make_varargs_handler() -> Callable:
    def handler(*args: Any, **kwargs: Any) -> None:
        pass
    return handler


# ---------------------------------------------------------------------------
# Table of (decorator_factory, expected_arg_count)
# decorator_factory(fhir) → the decorator to use directly.
# ---------------------------------------------------------------------------

def _cases(fhir: FhirDecorators) -> List[tuple]:
    return [
        # (label, decorator, expected_arity)
        ("on_capability_statement",        fhir.on_capability_statement,               1),
        ("on_before_request",              fhir.on_before_request,                     4),
        ("on_after_request",               fhir.on_after_request,                      4),
        ("on_before_create",               fhir.on_before_create("Patient"),           4),
        ("on_before_read",                 fhir.on_before_read("Patient"),             4),
        ("on_before_update",               fhir.on_before_update("Patient"),           4),
        ("on_before_delete",               fhir.on_before_delete("Patient"),           4),
        ("on_before_search",               fhir.on_before_search("Patient"),           4),
        ("on_after_create",                fhir.on_after_create("Patient"),            4),
        ("on_after_read",                  fhir.on_after_read("Patient"),              1),
        ("on_after_update",                fhir.on_after_update("Patient"),            4),
        ("on_after_delete",                fhir.on_after_delete("Patient"),            4),
        ("on_after_search",                fhir.on_after_search("Patient"),            2),
        ("consent",                        fhir.consent("Patient"),                    1),
        ("operation",                      fhir.operation("op", "Instance", "Patient"), 6),
        ("oauth_set_instance",             fhir.oauth_set_instance,                    4),
        ("oauth_get_introspection",        fhir.oauth_get_introspection,               0),
        ("oauth_get_user_info",            fhir.oauth_get_user_info,                   2),
        ("oauth_verify_resource_id",       fhir.oauth_verify_resource_id("Patient"),   3),
        ("oauth_verify_resource_content",  fhir.oauth_verify_resource_content("Patient"), 3),
        ("oauth_verify_history",           fhir.oauth_verify_history("Patient"),       3),
        ("oauth_verify_delete",            fhir.oauth_verify_delete("Patient"),        3),
        ("oauth_verify_search",            fhir.oauth_verify_search("Patient"),        5),
        ("oauth_verify_system_level",      fhir.oauth_verify_system_level,             0),
        ("on_validate_resource",           fhir.on_validate_resource("Patient"),       2),
        ("on_validate_bundle",             fhir.on_validate_bundle,                    2),
    ]


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_correct_arity_registers_without_error():
    """Every decorator accepts a handler with exactly the right number of required args."""
    fhir = FhirDecorators()
    for label, decorator, arity in _cases(fhir):
        handler = _make_handler(arity)
        try:
            decorator(handler)
        except TypeError as exc:
            pytest.fail(f"@fhir.{label} rejected a valid {arity}-arg handler: {exc}")


@pytest.mark.unit
def test_too_many_required_args_raises_at_call_time():
    """Every decorator accepts a bad handler; calling the wrapper raises TypeError."""
    fhir = FhirDecorators()
    for label, decorator, arity in _cases(fhir):
        bad_handler = _make_handler(arity + 1)
        registered = decorator(bad_handler)  # must NOT raise at decoration time
        with pytest.raises(TypeError, match="IRIS bridge only passes"):
            registered()  # wrapper raises on any call


@pytest.mark.unit
def test_too_few_positional_slots_raises_at_call_time():
    """Every decorator accepts a too-narrow handler; calling the wrapper raises TypeError."""
    fhir = FhirDecorators()
    for label, decorator, arity in _cases(fhir):
        if arity == 0:
            # bridge passes 0 args; a function with 0 slots is valid,
            # and there is no valid "too few" case.
            continue
        bad_handler = _make_handler(max(0, arity - 1))
        registered = decorator(bad_handler)  # must NOT raise at decoration time
        with pytest.raises(TypeError, match="IRIS bridge"):
            registered()  # wrapper raises on any call


@pytest.mark.unit
def test_varargs_handler_always_accepted():
    """Every decorator accepts a *args handler regardless of the expected arity."""
    fhir = FhirDecorators()
    for label, decorator, arity in _cases(fhir):
        handler = _make_varargs_handler()
        try:
            decorator(handler)
        except TypeError as exc:
            pytest.fail(f"@fhir.{label} rejected a valid *args handler: {exc}")


@pytest.mark.unit
def test_optional_param_pad_is_accepted():
    """
    Handlers may declare extra optional parameters beyond the required ones.
    The bridge only sends the required args, and the extras take their defaults.
    """
    fhir = FhirDecorators()
    for label, decorator, arity in _cases(fhir):
        # required=arity, optional=1 extra
        handler = _make_handler_with_optional(required=arity, optional=1)
        try:
            decorator(handler)
        except TypeError as exc:
            pytest.fail(
                f"@fhir.{label} rejected a handler with {arity} required + "
                f"1 optional arg: {exc}"
            )


@pytest.mark.unit
def test_required_can_be_replaced_by_optional_up_to_arity():
    """
    A handler where ALL parameters are optional (but there are enough of them)
    is valid — the bridge will fill each positional slot whether or not there
    is a default.

    Example: ``def h(resource, is_in_transaction=False)`` for expected=2.
    """
    fhir = FhirDecorators()
    for label, decorator, arity in _cases(fhir):
        if arity == 0:
            continue  # no positional slots needed; tested separately
        # required=1, optional fills the rest
        handler = _make_handler_with_optional(required=1, optional=arity - 1)
        try:
            decorator(handler)
        except TypeError as exc:
            pytest.fail(
                f"@fhir.{label} rejected a handler with 1 required + "
                f"{arity - 1} optional args (total={arity}): {exc}"
            )


@pytest.mark.unit
def test_error_message_contains_handler_name():
    """The TypeError message raised at call time must name the offending function."""
    fhir = FhirDecorators()
    for label, decorator, arity in _cases(fhir):
        if arity > 0:
            bad = _make_handler(arity - 1)
        else:
            bad = _make_handler(1)
        # Rename to a distinctive name
        bad.__name__ = f"my_{label}_bad_handler"
        registered = decorator(bad)  # must NOT raise at decoration time
        with pytest.raises(TypeError, match=bad.__name__):
            registered()  # error message contains the original function name


@pytest.mark.unit
def test_bad_handler_wrappers_raise_typeerror_with_proper_message():
    """
    Bad-signature handlers are registered as error-raising wrappers.
    Calling any of them raises TypeError with the handler name in the message.
    """
    fhir = FhirDecorators()

    # Use one representative from each arity bucket.
    representative_cases = [
        (fhir.on_capability_statement,                    1),   # flat, 1 arg
        (fhir.on_before_request,                          4),   # flat, 4 args
        (fhir.on_after_read("Patient"),                   1),   # nested, 1 arg
        (fhir.on_after_search("Patient"),                 2),   # nested, 2 args
        (fhir.consent("Patient"),                         1),   # nested, 1 arg
        (fhir.operation("guard-op", "Instance", "Obs"),   6),   # nested, 6 args
        (fhir.oauth_get_introspection,                    0),   # flat, 0 args
        (fhir.on_validate_resource("Patient"),            2),   # nested, 2 args
    ]

    for decorator, arity in representative_cases:
        bad_handler = _make_handler(arity + 1)  # too many required args
        registered = decorator(bad_handler)  # registration must succeed
        with pytest.raises(TypeError, match="IRIS bridge only passes"):
            registered()  # calling the wrapper raises the descriptive error
