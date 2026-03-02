"""
Context management for FHIR Python Strategy.

Two separate scopes are provided, mirroring the ObjectScript model:

InteractionsContext — service-level singleton
    Created once when IRIS loads the Python module (``%OnNew``).  Survives
    across all requests for the lifetime of the IRIS process.  Use it to
    cache objects that are expensive to construct: loaded ML models,
    connection pools, decoded configuration, etc.  Analogous to the
    ObjectScript ``Interactions`` object itself.

RequestContext — per-request, isolated
    Created at the very start of every FHIR request (``OnBeforeRequest``)
    and destroyed at the end (``OnAfterRequest``).  Each OS thread (or
    asyncio task) has its own independent slot, so multi-threaded IRIS
    processes cannot bleed data between concurrent requests.

ObjectScript bridge
-------------------
``FHIR.Python.Interactions.cls`` calls three helpers::

    // %OnNew – once when the service starts
    set ctx_mod = ##class(%SYS.Python).Import("iris_fhir_python_strategy")
    do ctx_mod."init_interactions"($this)

    // OnBeforeRequest – before any handler runs
    do ctx_mod."begin_request"($this)

    // OnAfterRequest – after all handlers have run
    do ctx_mod."end_request"()

Handler usage
-------------
::

    from iris_fhir_python_strategy import (
        fhir,
        get_interactions_context,
        get_request_context,
    )

    # Populate service-level state once at module import (e.g. load config)
    ictx = get_interactions_context()

    @fhir.on_before_request
    def capture_user(service, request, body, timeout):
        ctx = get_request_context()       # per-request
        ctx.username = request.Username
        ctx.roles    = request.Roles

    @fhir.on_after_read("Patient")
    def mask_patient(resource):
        ictx = get_interactions_context() # service-level (config, caches…)
        ctx  = get_request_context()      # per-request  (user, roles…)
        if "admin" not in ctx.roles:
            resource.pop("telecom", None)
        return True

Testing
-------
Both contexts have a context manager for clean, isolated unit tests::

    from iris_fhir_python_strategy import interactions_context, request_context

    def test_mask_for_non_admin():
        with interactions_context():
            with request_context(username="alice", roles="nurse"):
                resource = {"id": "1", "telecom": [{"value": "555"}]}
                assert mask_patient(resource) is True
            assert "telecom" not in resource   # masked

    def test_mask_skipped_for_admin():
        with interactions_context():
            with request_context(username="bob", roles="admin"):
                resource = {"id": "2", "telecom": [{"value": "555"}]}
                assert mask_patient(resource) is True
            assert "telecom" in resource       # not masked for admin

"""
from __future__ import annotations

from contextlib import contextmanager
from contextvars import ContextVar, Token
from dataclasses import dataclass, field
from typing import Any, Generator, List, Optional


# ===========================================================================
# InteractionsContext — service-level singleton
# ===========================================================================

class InteractionsContext:
    """
    Service-level context that persists across all FHIR requests.

    A single instance is created when IRIS loads the Python module
    (:func:`init_interactions`) and lives for the lifetime of the process.
    All handler functions share the same instance, making it the right place
    to store objects that are expensive or impossible to recreate per-request.

    Typical use-cases
    -----------------
    * A decoded / cached configuration dict.
    * A database connection pool.
    * A pre-loaded ML model or embedding matrix.
    * A ``requests.Session`` (HTTP client with connection keep-alive).
    * Any Python object you want to share without re-constructing every call.

    All attributes are set dynamically — there is no fixed schema beyond the
    two built-in fields below.  Simply assign any attribute you need::

        ictx = get_interactions_context()
        ictx.some_model  = MyModel.load("/path/to/weights")
        ictx.http_client = requests.Session()
        ictx.config      = json.load(open("/app/config.json"))

    Attributes
    ----------
    interactions : Any
        The live ``FHIR.Python.Interactions`` ObjectScript object (``$this``).
        Injected automatically by :func:`init_interactions` — **do not set
        this from handler code**.  Use it to call back into IRIS::

            ictx = get_interactions_context()
            raw  = ictx.interactions.Read("Patient", patient_id)._ToJSON()

    _initialised : bool
        ``True`` once :func:`init_interactions` has been called.
    """

    def __init__(self) -> None:
        object.__setattr__(self, "interactions", None)
        object.__setattr__(self, "_initialised", False)


# Module-level singleton — one per Python process.
_interactions_context: InteractionsContext = InteractionsContext()

# Stack used by interactions_context() to save/restore the singleton.
_interactions_context_stack: list = []


def get_interactions_context() -> InteractionsContext:
    """
    Return the service-level :class:`InteractionsContext` singleton.

    Always returns the same instance within a given process, or the current
    :func:`interactions_context` test-override if one is active.

    Returns
    -------
    InteractionsContext
        The mutable service-level context object.
    """
    return _interactions_context


def init_interactions(iris_interactions: Any = None) -> InteractionsContext:
    """
    Initialise the service-level context with the IRIS ``Interactions`` object.

    Called **once** by ``FHIR.Python.Interactions.%OnNew`` when the FHIR
    service first loads.  If IRIS ever reloads the class, subsequent calls
    update the ``interactions`` reference in-place so that user-added attributes
    (caches, models, …) are preserved rather than discarded.

    Parameters
    ----------
    iris_interactions : Any
        The IRIS ``$this`` reference (``FHIR.Python.Interactions`` instance).

    Returns
    -------
    InteractionsContext
        The updated singleton.
    """
    ictx = _interactions_context
    ictx.interactions = iris_interactions
    ictx._initialised = True
    return ictx


@contextmanager
def interactions_context(**kwargs: Any) -> Generator[InteractionsContext, None, None]:
    """
    Context manager that temporarily replaces the service-level singleton.

    Designed for **unit tests**.  Creates a fresh :class:`InteractionsContext`
    pre-populated with *kwargs* and makes it the current one for the duration
    of the ``with`` block.  The original singleton is always restored on exit,
    even if the block raises.

    Parameters
    ----------
    **kwargs
        Any attribute to pre-populate on the temporary context, e.g.
        ``config={"masking_enabled": True}``, ``interactions=MockIRIS()``.

    Yields
    ------
    InteractionsContext
        The temporary context (also returned by
        :func:`get_interactions_context` inside the block).

    Examples
    --------
    ::

        class MockIRIS:
            def Read(self, rtype, rid, vid=""):
                import json
                from types import SimpleNamespace
                payload = json.dumps({"resourceType": rtype, "id": rid})
                return SimpleNamespace(_ToJSON=lambda: payload)

        def test_get_security_empty_on_exception():
            with interactions_context(interactions=MockIRIS()):
                result = get_security("scope-that-does-not-exist")
            assert result == []

    Nested contexts are fully isolated::

        def test_nested_ictx():
            with interactions_context(flag=1) as outer:
                assert get_interactions_context().flag == 1
                with interactions_context(flag=2) as inner:
                    assert get_interactions_context().flag == 2
                assert get_interactions_context().flag == 1
    """
    global _interactions_context
    new_ctx = InteractionsContext()
    for key, value in kwargs.items():
        setattr(new_ctx, key, value)
    _interactions_context_stack.append(_interactions_context)
    _interactions_context = new_ctx
    try:
        yield new_ctx
    finally:
        _interactions_context = _interactions_context_stack.pop()


# ===========================================================================
# RequestContext — per-request, ContextVar-isolated
# ===========================================================================

@dataclass
class RequestContext:
    """
    Holds all data scoped to a single FHIR request.

    An instance is created at the very start of every request (by
    :func:`begin_request`) and discarded at the end (by :func:`end_request`).
    Handlers obtain the current instance via :func:`get_request_context` and
    may freely mutate its fields.

    Because this is backed by a :class:`contextvars.ContextVar`, each OS
    thread (or asyncio task) has its own independent copy — concurrent FHIR
    requests handled by separate threads cannot interfere with each other.

    Attributes
    ----------
    username : str
        Authenticated user name from ``pFHIRRequest.Username``.
    roles : str
        Comma-separated role string from ``pFHIRRequest.Roles``.
    scope_list : list[str]
        OAuth scopes parsed from the decoded access token.
    security_list : list[str]
        Application-specific security labels derived from ``scope_list``.
    token_string : str
        Raw OAuth access-token string (available after ``oauth_set_instance``).
    oauth_client : str
        OAuth client identifier (available after ``oauth_set_instance``).
    base_url : str
        Base URL of the FHIR endpoint (available after ``oauth_set_instance``).
    interactions : Any
        Short-cut to the IRIS ``FHIR.Python.Interactions`` object for the
        current request.  Identical to
        ``get_interactions_context().interactions`` but available on the
        request context for convenience.  Injected by :func:`begin_request`;
        **do not set this from handler code**.
    """

    username: str = ""
    roles: str = ""
    scope_list: List[str] = field(default_factory=list)
    security_list: List[str] = field(default_factory=list)
    token_string: str = ""
    oauth_client: str = ""
    base_url: str = ""
    interactions: Any = field(default=None, repr=False)


# One ContextVar slot per thread / asyncio task.
_request_context_var: ContextVar[Optional[RequestContext]] = ContextVar(
    "fhir_request_context", default=None
)
# Token stored so end_request() can restore the *previous* value rather than
# blindly setting None — important for nested request_context() test blocks.
_current_token: ContextVar[Optional[Token]] = ContextVar(
    "fhir_request_context_token", default=None
)


def get_request_context() -> RequestContext:
    """
    Return the :class:`RequestContext` for the current FHIR request.

    If called outside a request lifecycle (e.g. at module import time, or in
    a test that has not used :func:`request_context`), a temporary default
    instance is returned; it is *not* stored, so mutations have no lasting
    effect.

    Returns
    -------
    RequestContext
        The mutable context object for the current request.
    """
    ctx = _request_context_var.get()
    if ctx is None:
        ctx = RequestContext()
    return ctx


def begin_request(iris_interactions: Any = None) -> RequestContext:
    """
    Start a new request lifecycle and return a fresh :class:`RequestContext`.

    Called by ``FHIR.Python.Interactions.OnBeforeRequest`` **before** any
    Python handler runs.  Guarantees that:

    * Every handler sees a clean, empty context — no stale data from a
      previous request.
    * ``ctx.interactions`` is already set, so handlers can call back into
      IRIS immediately without additional setup.
    * The service-level :class:`InteractionsContext` singleton also has its
      ``interactions`` reference refreshed (handles IRIS class reloads).

    Parameters
    ----------
    iris_interactions : Any
        The IRIS ``$this`` reference.

    Returns
    -------
    RequestContext
        The newly created, active context.
    """
    # Keep the service-level singleton's interactions reference in sync.
    _interactions_context.interactions = iris_interactions

    ctx = RequestContext(interactions=iris_interactions)
    token = _request_context_var.set(ctx)
    _current_token.set(token)
    return ctx


def end_request() -> None:
    """
    End the current request lifecycle and clear the per-request context.

    Called by ``FHIR.Python.Interactions.OnAfterRequest`` after all handlers
    have run.  Restores the ContextVar to whatever value it held before
    :func:`begin_request` was called (``None`` in production; the enclosing
    test context in nested :func:`request_context` blocks).

    Safe to call even when no request was started.
    """
    token = _current_token.get()
    if token is not None:
        _request_context_var.reset(token)
        _current_token.set(None)
    else:
        _request_context_var.set(None)


@contextmanager
def request_context(**kwargs: Any) -> Generator[RequestContext, None, None]:
    """
    Context manager that provides a clean, isolated :class:`RequestContext`.

    Designed for **unit tests**.  Creates a fresh ``RequestContext``
    pre-populated with *kwargs*, makes it the current context for the duration
    of the ``with`` block, then restores the previous context on exit — even
    if the block raises.

    Parameters
    ----------
    **kwargs
        Any fields accepted by :class:`RequestContext`, e.g.
        ``username="alice"``, ``roles="doctor"``,
        ``scope_list=["patient/*.read"]``.

    Yields
    ------
    RequestContext
        The isolated context (also returned by :func:`get_request_context`
        inside the block).

    Examples
    --------
    ::

        def test_mask_applied_for_non_admin():
            with request_context(username="alice", roles="nurse"):
                resource = {"id": "1", "telecom": [{"value": "555"}]}
                result = mask_patient_data(resource)
            assert result is True
            assert "telecom" not in resource  # masked

        def test_mask_skipped_for_admin():
            with request_context(username="bob", roles="admin"):
                resource = {"id": "2", "telecom": [{"value": "555"}]}
                result = mask_patient_data(resource)
            assert result is True
            assert "telecom" in resource      # not masked

    Nested contexts are fully isolated::

        def test_nested():
            with request_context(username="outer"):
                assert get_request_context().username == "outer"
                with request_context(username="inner"):
                    assert get_request_context().username == "inner"
                assert get_request_context().username == "outer"
    """
    ctx = RequestContext(**kwargs)
    token = _request_context_var.set(ctx)
    try:
        yield ctx
    finally:
        _request_context_var.reset(token)
