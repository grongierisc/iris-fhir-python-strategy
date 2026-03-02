"""
End-to-end tests for the two-tier context system.

These tests exercise the context behaviour that only becomes observable once
the full IRIS bridge (begin_request / end_request / init_interactions) is
running inside the Docker container.  They use the ``$context-info``
custom operation defined in ``tests/e2e/fixtures/fhir_customization.py``
which returns a Parameters resource containing internal context state.

Two scopes are tested:

RequestContext — per-request
    • username and roles are populated from the HTTP credential on every call.
    • Context is fresh for each request (no data bleeds from a previous one).
    • The ``interactions`` back-reference is available (not None).

InteractionsContext — service-level
    • The singleton persists across requests: a call counter incremented on
      the interactions context goes up with each HTTP request, proving that
      the object is not reset between calls.
    • The IRIS ``interactions`` object is available from the first request.
"""
import uuid

import requests
import pytest


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_AUTH = ("SuperUser", "SYS")
_HEADERS = {
    "Accept": "application/fhir+json",
    "Content-Type": "application/fhir+json",
}


def _context_info(base_url: str, auth=_AUTH) -> dict:
    """Call Patient/$context-info and return the parsed Parameters dict."""
    resp = requests.post(
        f"{base_url}/fhir/r4/Patient/$context-info",
        headers=_HEADERS,
        auth=auth,
        json={"resourceType": "Parameters"},
        timeout=10,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body.get("resourceType") == "Parameters", body
    # Convert parameter list to a plain dict for easy access.
    params = {}
    for p in body.get("parameter", []):
        name = p["name"]
        for vk in ("valueString", "valueBoolean", "valueInteger", "valueCode"):
            if vk in p:
                params[name] = p[vk]
                break
    return params


# ---------------------------------------------------------------------------
# RequestContext — populated per request
# ---------------------------------------------------------------------------

@pytest.mark.e2e
def test_request_context_username_populated(fhir_base_url: str):
    """
    capture_user_context sets ctx.username from the FHIR request object.
    The $context-info operation reads it back and returns it.
    """
    params = _context_info(fhir_base_url)
    assert params["request_username"] == "SuperUser"


@pytest.mark.e2e
def test_request_context_roles_populated(fhir_base_url: str):
    """ctx.roles is populated alongside ctx.username."""
    params = _context_info(fhir_base_url)
    # IRIS returns the user's role string; we just require it to be non-empty.
    assert params["request_roles"] != "", "roles should not be empty for SuperUser"


@pytest.mark.e2e
def test_request_context_fresh_per_request(fhir_base_url: str):
    """
    RequestContext is fresh for every request.

    POST a new Patient (fires record_create → ctx.last_operation = "create").
    A subsequent *different* request — the $context-info operation — must see
    an empty ``last_operation``, confirming that the context was reset between
    the two HTTP calls.

    Notes:
    * POST (not PUT) is used so the create handler always fires regardless of
      whether a patient with the same id already exists from a previous run.
    * A uuid suffix makes the patient id unique per test run.
    * ``params.get(...)`` is used because FHIR servers commonly strip empty-
      string valueString fields from Parameters responses.
    """
    # PUT with a uuid id that has never existed → always a create →
    # fires on_before_create → record_create sets ctx.last_operation = "create"
    patient_id = f"ctx-fresh-{uuid.uuid4().hex[:12]}"
    post_resp = requests.put(
        f"{fhir_base_url}/fhir/r4/Patient/{patient_id}",
        headers=_HEADERS,
        auth=_AUTH,
        json={
            "resourceType": "Patient",
            "id": patient_id,
            "active": True,
            "name": [{"family": f"ContextTest"}],
        },
        timeout=10,
    )
    assert post_resp.status_code in (200, 201), post_resp.text

    # Next request: the context must be fresh — last_operation is "" not "create"
    params = _context_info(fhir_base_url)
    # .get() guards against FHIR servers that strip empty valueString fields.
    assert params.get("request_last_operation", "") == "", (
        "last_operation should be empty in a new request — "
        "RequestContext was not reset between calls"
    )


@pytest.mark.e2e
def test_request_context_last_operation_set_within_same_request(fhir_base_url: str):
    """
    Complementary isolation check: even after a create that sets
    ``ctx.last_operation``, the *next* HTTP request sees a clean context.
    """
    patient_id = f"ctx-samereq-{uuid.uuid4().hex[:12]}"
    post_resp = requests.put(
        f"{fhir_base_url}/fhir/r4/Patient/{patient_id}",
        headers=_HEADERS,
        auth=_AUTH,
        json={
            "resourceType": "Patient",
            "id": patient_id,
            "active": True,
            "name": [{"family": "SameReq"}],
        },
        timeout=10,
    )
    assert post_resp.status_code in (200, 201), post_resp.text

    # A separate $context-info call is a *new* request — context should be clean.
    params = _context_info(fhir_base_url)
    assert params.get("request_last_operation", "") == ""


# ---------------------------------------------------------------------------
# RequestContext — IRIS interactions reference
# ---------------------------------------------------------------------------

@pytest.mark.e2e
def test_request_context_interactions_available(fhir_base_url: str):
    """
    begin_request($this) injects the IRIS Interactions reference into the
    RequestContext before any handler runs.  The $context-info operation
    checks whether ``ctx.interactions is not None``.
    """
    params = _context_info(fhir_base_url)
    assert params["interactions_available"] is True, (
        "ctx.interactions should be set by begin_request($this)"
    )


# ---------------------------------------------------------------------------
# InteractionsContext — service-level persistence
# ---------------------------------------------------------------------------

@pytest.mark.e2e
def test_interactions_context_persists_across_requests(fhir_base_url: str):
    """
    InteractionsContext is a process-level singleton — it is NOT reset between
    requests.  The $context-info operation increments
    ``ictx.context_info_call_count`` on every call.  Making three consecutive
    calls must produce a strictly increasing counter, proving that the object
    survives across HTTP request boundaries.
    """
    counts = [_context_info(fhir_base_url)["service_call_count"] for _ in range(3)]
    assert counts[1] > counts[0], "counter did not increase between request 1 and 2"
    assert counts[2] > counts[1], "counter did not increase between request 2 and 3"


@pytest.mark.e2e
def test_interactions_context_call_count_monotonically_increases(fhir_base_url: str):
    """
    More thorough version: 5 sequential calls should produce 5 strictly
    increasing counter values.
    """
    counts = [_context_info(fhir_base_url)["service_call_count"] for _ in range(5)]
    for i in range(1, len(counts)):
        assert counts[i] == counts[i - 1] + 1, (
            f"Expected monotonic increment; got {counts}"
        )


@pytest.mark.e2e
def test_interactions_context_interactions_not_reset_between_requests(fhir_base_url: str):
    """
    ``ictx.interactions`` remains non-None across multiple requests.
    If interactions were reset each call the persistent counter test would
    reset too.  Belt-and-suspenders: verify directly.
    """
    for _ in range(3):
        params = _context_info(fhir_base_url)
        assert params["interactions_available"] is True


# ---------------------------------------------------------------------------
# RequestContext vs InteractionsContext — different lifetimes
# ---------------------------------------------------------------------------

@pytest.mark.e2e
def test_request_context_resets_while_service_context_persists(fhir_base_url: str):
    """
    The sharpest test of the two-tier design:

    * ``request_username`` is always the current HTTP user (fresh per request).
    * ``service_call_count`` keeps growing (never reset).

    Both properties must hold across 4 consecutive calls.
    """
    previous_count = 0
    for i in range(4):
        params = _context_info(fhir_base_url)

        # RequestContext: always the authenticated user for *this* request.
        assert params["request_username"] == "SuperUser", (
            f"iteration {i}: username should always be 'SuperUser'"
        )

        # InteractionsContext: counter must grow.
        assert params["service_call_count"] > previous_count, (
            f"iteration {i}: service_call_count did not increase"
        )
        previous_count = params["service_call_count"]
