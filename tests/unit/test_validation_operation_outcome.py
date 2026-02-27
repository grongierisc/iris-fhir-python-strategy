"""
Unit tests for the OperationOutcome-return feature of validation decorators.

These tests exercise the Python side of the feature:
- Handlers that return an OperationOutcome dict
- Handlers that return None (no error, old behaviour)
- Handlers that raise exceptions (old behaviour preserved)
- Aggregation: multiple handlers, multiple issues
- Non-error severities (warning / information) must NOT block

The ObjectScript layer (RunValidationHandlers + MergeOperationOutcomeErrors) is
covered by the e2e tests against the running container. Here we only verify the
decorator registry and the Python return values.
"""

import pytest

from iris_fhir_python_strategy import FhirDecorators


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _call_validate_resource(fhir: FhirDecorators, resource_type: str, resource: dict,
                              is_in_transaction: bool = False):
    """Call every registered validate-resource handler and collect return values."""
    handlers = fhir.get_on_validate_resource_handlers(resource_type)
    return [h(resource, is_in_transaction) for h in handlers]


def _call_validate_bundle(fhir: FhirDecorators, bundle: dict, fhir_version: str = "R4"):
    """Call every registered validate-bundle handler and collect return values."""
    handlers = fhir.get_on_validate_bundle_handlers()
    return [h(bundle, fhir_version) for h in handlers]


# ---------------------------------------------------------------------------
# on_validate_resource – None return (no errors)
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_validate_resource_returns_none_when_valid():
    fhir = FhirDecorators()

    @fhir.on_validate_resource("Patient")
    def validate(resource, is_in_transaction=False):
        # Valid – return nothing
        pass

    results = _call_validate_resource(fhir, "Patient", {"resourceType": "Patient", "id": "1"})
    assert results == [None]


# ---------------------------------------------------------------------------
# on_validate_resource – raise exception (old behaviour)
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_validate_resource_raises_value_error():
    fhir = FhirDecorators()

    @fhir.on_validate_resource("Patient")
    def validate(resource, is_in_transaction=False):
        if "identifier" not in resource:
            raise ValueError("Patient must have at least one identifier")

    handlers = fhir.get_on_validate_resource_handlers("Patient")
    with pytest.raises(ValueError, match="Patient must have at least one identifier"):
        for h in handlers:
            h({"resourceType": "Patient"}, False)


# ---------------------------------------------------------------------------
# on_validate_resource – return OperationOutcome with one error issue
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_validate_resource_returns_operation_outcome_single_error():
    fhir = FhirDecorators()

    @fhir.on_validate_resource("Patient")
    def validate(resource, is_in_transaction=False):
        if "identifier" not in resource:
            return {
                "resourceType": "OperationOutcome",
                "issue": [
                    {
                        "severity": "error",
                        "code": "required",
                        "details": {"text": "Patient must have at least one identifier"},
                        "expression": ["Patient.identifier"],
                    }
                ],
            }

    results = _call_validate_resource(fhir, "Patient", {"resourceType": "Patient"})
    assert len(results) == 1
    oo = results[0]
    assert oo["resourceType"] == "OperationOutcome"
    assert len(oo["issue"]) == 1
    issue = oo["issue"][0]
    assert issue["severity"] == "error"
    assert issue["code"] == "required"
    assert issue["details"]["text"] == "Patient must have at least one identifier"
    assert issue["expression"] == ["Patient.identifier"]


# ---------------------------------------------------------------------------
# on_validate_resource – return OperationOutcome with multiple error issues
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_validate_resource_returns_operation_outcome_multiple_errors():
    fhir = FhirDecorators()

    @fhir.on_validate_resource("Patient")
    def validate(resource, is_in_transaction=False):
        issues = []
        if "identifier" not in resource:
            issues.append({
                "severity": "error",
                "code": "required",
                "details": {"text": "Patient must have at least one identifier"},
                "expression": ["Patient.identifier"],
            })
        for i, name in enumerate(resource.get("name", [])):
            if name.get("use") not in ("official", "usual", None):
                issues.append({
                    "severity": "error",
                    "code": "value",
                    "details": {"text": f"Invalid name use: {name.get('use')}"},
                    "expression": [f"Patient.name[{i}].use"],
                })
        if issues:
            return {"resourceType": "OperationOutcome", "issue": issues}

    resource = {
        "resourceType": "Patient",
        "name": [{"use": "bad-value", "family": "Smith"}],
    }
    results = _call_validate_resource(fhir, "Patient", resource)
    assert len(results) == 1
    oo = results[0]
    assert oo["resourceType"] == "OperationOutcome"
    assert len(oo["issue"]) == 2
    codes = {i["code"] for i in oo["issue"]}
    assert "required" in codes
    assert "value" in codes


# ---------------------------------------------------------------------------
# on_validate_resource – non-error severities must be returned as-is (no raise)
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_validate_resource_returns_warning_outcome_only():
    fhir = FhirDecorators()

    @fhir.on_validate_resource("Patient")
    def validate(resource, is_in_transaction=False):
        return {
            "resourceType": "OperationOutcome",
            "issue": [
                {
                    "severity": "warning",
                    "code": "informational",
                    "details": {"text": "Missing recommended field 'contact'"},
                    "expression": ["Patient.contact"],
                }
            ],
        }

    results = _call_validate_resource(fhir, "Patient", {"resourceType": "Patient", "id": "w1"})
    oo = results[0]
    # The Python layer simply returns the dict; ObjectScript filters severity=error
    assert oo["issue"][0]["severity"] == "warning"


# ---------------------------------------------------------------------------
# on_validate_resource – multiple handlers aggregated
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_validate_resource_multiple_handlers_both_return_outcomes():
    fhir = FhirDecorators()

    @fhir.on_validate_resource("Patient")
    def validate_id(resource, is_in_transaction=False):
        if "id" not in resource:
            return {
                "resourceType": "OperationOutcome",
                "issue": [{"severity": "error", "code": "required",
                            "details": {"text": "id required"},
                            "expression": ["Patient.id"]}],
            }

    @fhir.on_validate_resource("Patient")
    def validate_name(resource, is_in_transaction=False):
        if "name" not in resource:
            return {
                "resourceType": "OperationOutcome",
                "issue": [{"severity": "error", "code": "required",
                            "details": {"text": "name required"},
                            "expression": ["Patient.name"]}],
            }

    resource = {"resourceType": "Patient"}  # missing both id and name
    results = _call_validate_resource(fhir, "Patient", resource)

    # Both handlers return an OperationOutcome
    assert len(results) == 2
    texts = [r["issue"][0]["details"]["text"] for r in results if r]
    assert "id required" in texts
    assert "name required" in texts


# ---------------------------------------------------------------------------
# on_validate_resource – wildcard handler fires for every resource type
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_validate_resource_wildcard_fires_for_any_type():
    fhir = FhirDecorators()
    called_for = []

    @fhir.on_validate_resource("*")
    def global_validate(resource, is_in_transaction=False):
        called_for.append(resource["resourceType"])

    _call_validate_resource(fhir, "Patient", {"resourceType": "Patient"})
    _call_validate_resource(fhir, "Observation", {"resourceType": "Observation"})

    assert "Patient" in called_for
    assert "Observation" in called_for


# ---------------------------------------------------------------------------
# on_validate_resource – is_in_transaction flag is passed through
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_validate_resource_receives_is_in_transaction_flag():
    fhir = FhirDecorators()
    received = {}

    @fhir.on_validate_resource("Patient")
    def validate(resource, is_in_transaction=False):
        received["flag"] = is_in_transaction

    _call_validate_resource(fhir, "Patient", {"resourceType": "Patient"}, is_in_transaction=True)
    assert received["flag"] is True

    _call_validate_resource(fhir, "Patient", {"resourceType": "Patient"}, is_in_transaction=False)
    assert received["flag"] is False


# ---------------------------------------------------------------------------
# on_validate_bundle – None return
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_validate_bundle_returns_none_when_valid():
    fhir = FhirDecorators()

    @fhir.on_validate_bundle
    def validate(bundle, fhir_version):
        pass  # no issues

    results = _call_validate_bundle(fhir, {"resourceType": "Bundle", "type": "transaction", "entry": [{}]})
    assert results == [None]


# ---------------------------------------------------------------------------
# on_validate_bundle – raise exception (old behaviour)
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_validate_bundle_raises_value_error():
    fhir = FhirDecorators()

    @fhir.on_validate_bundle
    def validate(bundle, fhir_version):
        if bundle.get("type") == "transaction" and not bundle.get("entry"):
            raise ValueError("Transaction bundle must have entries")

    with pytest.raises(ValueError, match="Transaction bundle must have entries"):
        _call_validate_bundle(fhir, {"resourceType": "Bundle", "type": "transaction"})


# ---------------------------------------------------------------------------
# on_validate_bundle – return OperationOutcome with one error issue
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_validate_bundle_returns_operation_outcome_single_error():
    fhir = FhirDecorators()

    @fhir.on_validate_bundle
    def validate(bundle, fhir_version):
        if len(bundle.get("entry", [])) > 3:
            return {
                "resourceType": "OperationOutcome",
                "issue": [
                    {
                        "severity": "error",
                        "code": "too-costly",
                        "details": {"text": "Bundle too large (max 3 entries)"},
                        "expression": ["Bundle.entry"],
                    }
                ],
            }

    oversized_bundle = {"resourceType": "Bundle", "type": "transaction",
                        "entry": [{}, {}, {}, {}]}  # 4 entries
    results = _call_validate_bundle(fhir, oversized_bundle)
    assert len(results) == 1
    oo = results[0]
    assert oo["resourceType"] == "OperationOutcome"
    assert oo["issue"][0]["code"] == "too-costly"
    assert oo["issue"][0]["expression"] == ["Bundle.entry"]


# ---------------------------------------------------------------------------
# on_validate_bundle – multiple error issues in one OperationOutcome
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_validate_bundle_returns_operation_outcome_multiple_errors():
    fhir = FhirDecorators()

    @fhir.on_validate_bundle
    def validate(bundle, fhir_version):
        issues = []
        if bundle.get("type") not in ("transaction", "batch"):
            issues.append({
                "severity": "error",
                "code": "value",
                "details": {"text": "Invalid bundle type"},
                "expression": ["Bundle.type"],
            })
        if not bundle.get("entry"):
            issues.append({
                "severity": "error",
                "code": "required",
                "details": {"text": "Bundle must have at least one entry"},
                "expression": ["Bundle.entry"],
            })
        if issues:
            return {"resourceType": "OperationOutcome", "issue": issues}

    bad_bundle = {"resourceType": "Bundle", "type": "document"}
    results = _call_validate_bundle(fhir, bad_bundle)
    oo = results[0]
    assert len(oo["issue"]) == 2
    codes = {i["code"] for i in oo["issue"]}
    assert "value" in codes
    assert "required" in codes


# ---------------------------------------------------------------------------
# on_validate_bundle – non-error severities only
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_validate_bundle_non_error_severity_returned():
    fhir = FhirDecorators()

    @fhir.on_validate_bundle
    def validate(bundle, fhir_version):
        return {
            "resourceType": "OperationOutcome",
            "issue": [
                {
                    "severity": "information",
                    "code": "informational",
                    "details": {"text": "Bundle processed successfully"},
                }
            ],
        }

    results = _call_validate_bundle(fhir, {"resourceType": "Bundle", "type": "transaction", "entry": [{}]})
    oo = results[0]
    assert oo["issue"][0]["severity"] == "information"


# ---------------------------------------------------------------------------
# Decorator registration sanity checks
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_multiple_specific_resource_type_handlers_registered():
    fhir = FhirDecorators()

    @fhir.on_validate_resource("Patient")
    def h1(r, t): pass

    @fhir.on_validate_resource("Patient")
    def h2(r, t): pass

    @fhir.on_validate_resource("Observation")
    def h3(r, t): pass

    assert len(fhir.get_on_validate_resource_handlers("Patient")) == 2
    assert len(fhir.get_on_validate_resource_handlers("Observation")) == 1
    assert len(fhir.get_on_validate_resource_handlers("Medication")) == 0


@pytest.mark.unit
def test_multiple_bundle_handlers_registered():
    fhir = FhirDecorators()

    @fhir.on_validate_bundle
    def h1(b, v): pass

    @fhir.on_validate_bundle
    def h2(b, v): pass

    assert len(fhir.get_on_validate_bundle_handlers()) == 2


# ---------------------------------------------------------------------------
# Mixed: one handler raises, another returns OperationOutcome
# The raise stops execution before the second handler is reached
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_validate_resource_exception_stops_execution():
    fhir = FhirDecorators()
    second_called = []

    @fhir.on_validate_resource("Patient")
    def h1(resource, is_in_transaction=False):
        raise ValueError("First handler fails hard")

    @fhir.on_validate_resource("Patient")
    def h2(resource, is_in_transaction=False):
        second_called.append(True)

    handlers = fhir.get_on_validate_resource_handlers("Patient")
    with pytest.raises(ValueError):
        for h in handlers:
            h({}, False)

    # h1 raised, so h2 should NOT have been called
    assert second_called == []
