"""
E2E regression test: bad decorator signature raises TypeError when called in the container.

Background
----------
Before the fix, a consent handler that declared an extra required parameter

    @fhir.consent("Patient")
    def bad(fhir_object, user_context):          # 2 required args
        ...

would silently be registered.  When IRIS called it with only one argument
the Python runtime raised ``TypeError`` inside ``RunBooleanHandlers``, which
IRIS surfaced as the cryptic::

    <OBJECT DISPATCH> 2603 RunBooleanHandlers+8^FHIR.Python.Helper.1  →  HTTP 500

After the fix, ``@fhir.consent`` (and every other decorator) wraps bad
handlers at *decoration time*.  The module **imports cleanly** — the bad
handler is registered as an error-raising wrapper.  When the IRIS bridge
calls the wrapper, it raises a clear ``TypeError`` with a descriptive message,
producing a proper FHIR OperationOutcome instead of the cryptic OBJECT
DISPATCH error.

What this test verifies
-----------------------
These tests use ``fhir_customization.py`` (the main e2e fixture) as the base
context and register intentionally bad handlers *inline* inside docker exec
calls, simulating exactly what a real user misconfiguration looks like.

* Registering a bad-signature handler on the live ``fhir`` instance succeeds
  (no load-time crash).
* Calling the wrapper with the args the IRIS bridge would pass raises
  ``TypeError`` with a descriptive message naming the handler and extra params.
* Good handlers from ``fhir_customization.py`` are unaffected.
* The error is a Python ``TypeError``, NOT an ``OBJECT DISPATCH`` error.

These are *host-side* tests that inspect container behaviour via ``docker exec``.
They require the IRIS container to be running (managed by the ``fhir_base_url``
session fixture).
"""
from typing import Any

import pytest


# Path inside the container where the repo is volume-mounted.
_APP = "/irisdev/app"

# Python binary available in the IRIS container image.
_PYTHON = "python3"


def _script(*lines: str) -> str:
    """Join lines with newlines into a multi-line script for python3 -c."""
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Shared inline scripts
# Each script:
#   1. Loads fhir_customization.py (the production fixture).
#   2. Registers a bad-signature handler inline on the shared fhir instance.
#   3. Calls the wrapper exactly as the IRIS bridge would.
#   4. Prints "TypeError: <msg>" and exits 1 on bad signatures.
# ---------------------------------------------------------------------------

# Consent -- bridge passes 1 arg; bad handler requires 2.
_CALL_BAD_CONSENT = _script(
    "import sys",
    "sys.path.insert(0, '/irisdev/app')",
    "import tests.e2e.fixtures.fhir_customization",
    "from iris_fhir_python_strategy import fhir",
    "@fhir.consent('TestBad')",
    "def my_bad_consent_handler(fhir_object, user_context): return True",
    "h = fhir.get_consent_handlers('TestBad')[-1]",
    "try:",
    "    h({'resourceType': 'Patient'})",
    "    print('NO_ERROR')",
    "except TypeError as e:",
    "    print('TypeError: ' + str(e))",
    "    sys.exit(1)",
)

# on_before_request -- bridge passes 4 args; bad handler requires 5.
_CALL_BAD_BEFORE_REQUEST = _script(
    "import sys",
    "sys.path.insert(0, '/irisdev/app')",
    "import tests.e2e.fixtures.fhir_customization",
    "from iris_fhir_python_strategy import fhir",
    "@fhir.on_before_request",
    "def bad_before_request(svc, req, body, timeout, extra): pass",
    "h = fhir.get_on_before_request_handlers()[-1]",
    "try:",
    "    h(None, None, {}, 30)",
    "    print('NO_ERROR')",
    "except TypeError as e:",
    "    print('TypeError: ' + str(e))",
    "    sys.exit(1)",
)

# on_validate_resource -- bridge passes 2 args; bad handler requires 3.
_CALL_BAD_VALIDATE = _script(
    "import sys",
    "sys.path.insert(0, '/irisdev/app')",
    "import tests.e2e.fixtures.fhir_customization",
    "from iris_fhir_python_strategy import fhir",
    "@fhir.on_validate_resource('Encounter')",
    "def bad_validate(resource, is_in_transaction, extra_arg): pass",
    "h = fhir.get_on_validate_resource_handlers('Encounter')[-1]",
    "try:",
    "    h({'resourceType': 'Encounter'}, False)",
    "    print('NO_ERROR')",
    "except TypeError as e:",
    "    print('TypeError: ' + str(e))",
    "    sys.exit(1)",
)


def _exec_python(container: Any, code: str) -> tuple[int, str]:
    """Run *code* as a one-liner inside the container.  Returns (exit_code, output)."""
    result = container.exec_run(
        [_PYTHON, "-c", code],
        environment={"PYTHONPATH": _APP},
        workdir=_APP,
    )
    output = result.output.decode("utf-8", errors="replace")
    return result.exit_code, output


# ---------------------------------------------------------------------------
# Baseline
# ---------------------------------------------------------------------------

@pytest.mark.e2e
def test_fhir_customization_imports_cleanly(
    fhir_base_url: str, fhir_container: Any
):
    """
    Baseline: the main e2e fixture must always import without errors.
    Proves that all good-signature handlers in fhir_customization.py pass the
    arity guard without issue.
    """
    code = _script(
        "import sys",
        "sys.path.insert(0, '/irisdev/app')",
        "import tests.e2e.fixtures.fhir_customization",
        "print('ok')",
    )
    exit_code, output = _exec_python(fhir_container, code)

    assert exit_code == 0, f"fhir_customization import failed:\n{output}"
    assert "ok" in output


# ---------------------------------------------------------------------------
# Consent decorator tests (bridge passes 1 arg)
# ---------------------------------------------------------------------------

@pytest.mark.e2e
def test_bad_consent_registers_without_crashing(
    fhir_base_url: str, fhir_container: Any
):
    """
    Registering a bad-signature consent handler after loading the full fixture
    must NOT crash the process at decoration time.
    """
    code = _script(
        "import sys",
        "sys.path.insert(0, '/irisdev/app')",
        "import tests.e2e.fixtures.fhir_customization",
        "from iris_fhir_python_strategy import fhir",
        "@fhir.consent('TestBad')",
        "def my_bad_consent_handler(fhir_object, user_context): return True",
        "print('registered ok')",
    )
    exit_code, output = _exec_python(fhir_container, code)

    assert exit_code == 0, (
        f"Expected silent registration of bad handler, got exit {exit_code}:\n{output}"
    )
    assert "registered ok" in output


@pytest.mark.e2e
def test_bad_consent_raises_typeerror_when_called(
    fhir_base_url: str, fhir_container: Any
):
    """
    Calling the bad consent wrapper with 1 arg — as the IRIS bridge does —
    must raise a TypeError, not silently pass and not produce OBJECT DISPATCH.
    """
    exit_code, output = _exec_python(fhir_container, _CALL_BAD_CONSENT)

    assert exit_code != 0, f"Expected TypeError on call, but exited cleanly:\n{output}"
    assert "TypeError" in output, f"Expected 'TypeError' in output:\n{output}"
    assert "NO_ERROR" not in output


@pytest.mark.e2e
def test_bad_consent_error_names_handler_and_param(
    fhir_base_url: str, fhir_container: Any
):
    """TypeError message must name the handler function and the extra required parameter."""
    _, output = _exec_python(fhir_container, _CALL_BAD_CONSENT)

    assert "my_bad_consent_handler" in output, (
        f"Expected handler name in error message:\n{output}"
    )
    assert "user_context" in output, (
        f"Expected extra param 'user_context' in error message:\n{output}"
    )
    assert "consent" in output, (
        f"Expected decorator name 'consent' in error message:\n{output}"
    )


@pytest.mark.e2e
def test_bad_consent_error_not_object_dispatch(
    fhir_base_url: str, fhir_container: Any
):
    """The error must not be the old cryptic IRIS OBJECT DISPATCH message."""
    _, output = _exec_python(fhir_container, _CALL_BAD_CONSENT)

    assert "OBJECT DISPATCH" not in output, (
        f"Got OBJECT DISPATCH instead of a clear TypeError:\n{output}"
    )


# ---------------------------------------------------------------------------
# on_before_request decorator tests (bridge passes 4 args)
# ---------------------------------------------------------------------------

@pytest.mark.e2e
def test_bad_before_request_raises_typeerror_when_called(
    fhir_base_url: str, fhir_container: Any
):
    """
    A bad on_before_request handler (5 required args) must raise TypeError
    when called with 4 args by the IRIS bridge.
    """
    exit_code, output = _exec_python(fhir_container, _CALL_BAD_BEFORE_REQUEST)

    assert exit_code != 0, f"Expected TypeError on call, but exited cleanly:\n{output}"
    assert "TypeError" in output, f"Expected 'TypeError' in output:\n{output}"
    assert "bad_before_request" in output, (
        f"Expected handler name 'bad_before_request' in error message:\n{output}"
    )
    assert "extra" in output, (
        f"Expected extra param 'extra' in error message:\n{output}"
    )


# ---------------------------------------------------------------------------
# on_validate_resource decorator tests (bridge passes 2 args)
# ---------------------------------------------------------------------------

@pytest.mark.e2e
def test_bad_validate_resource_raises_typeerror_when_called(
    fhir_base_url: str, fhir_container: Any
):
    """
    A bad on_validate_resource handler (3 required args) must raise TypeError
    when called with 2 args by the IRIS bridge.
    """
    exit_code, output = _exec_python(fhir_container, _CALL_BAD_VALIDATE)

    assert exit_code != 0, f"Expected TypeError on call, but exited cleanly:\n{output}"
    assert "TypeError" in output, f"Expected 'TypeError' in output:\n{output}"
    assert "bad_validate" in output, (
        f"Expected handler name 'bad_validate' in error message:\n{output}"
    )
    assert "extra_arg" in output, (
        f"Expected extra param 'extra_arg' in error message:\n{output}"
    )


# ---------------------------------------------------------------------------
# Regression guard: good handlers from the fixture are unaffected
# ---------------------------------------------------------------------------

@pytest.mark.e2e
def test_good_consent_handler_from_fixture_works(
    fhir_base_url: str, fhir_container: Any
):
    """
    The consent_check handler registered by fhir_customization must still work
    correctly even after a bad handler has been registered alongside it.
    Proves the good and bad wrappers do not interfere with each other.
    """
    code = _script(
        "import sys",
        "sys.path.insert(0, '/irisdev/app')",
        "import tests.e2e.fixtures.fhir_customization",
        "from iris_fhir_python_strategy import fhir",
        # Register a bad handler on Patient alongside the existing good one.
        "@fhir.consent('Patient')",
        "def bad_extra(resource, extra): return True",
        # The good handler (consent_check) was registered first.
        "good = fhir.get_consent_handlers('Patient')[0]",
        "result = good({'resourceType': 'Patient', 'name': [{'family': 'Smith'}]})",
        "assert result is True, f'Expected True, got {result}'",
        "print('ok')",
    )
    exit_code, output = _exec_python(fhir_container, code)

    assert exit_code == 0, f"Good handler call failed:\n{output}"
    assert "ok" in output
