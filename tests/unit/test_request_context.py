"""
Unit tests for iris_fhir_python_strategy.request_context.

Tests cover both scopes:
  - InteractionsContext  (service-level singleton, persists across requests)
  - RequestContext       (per-request, ContextVar-isolated)

All tests are fully self-contained: they use the context manager helpers
(interactions_context / request_context) so the global singleton and the
ContextVar are always restored after each test, regardless of pass/fail.
"""
import threading
from types import SimpleNamespace

import pytest

from iris_fhir_python_strategy import (
    # service-level
    InteractionsContext,
    get_interactions_context,
    init_interactions,
    interactions_context,
    # request-level
    RequestContext,
    get_request_context,
    begin_request,
    end_request,
    request_context,
)


# ===========================================================================
# Helpers
# ===========================================================================

def _make_mock_iris(**kwargs):
    """Return a lightweight stand-in for the IRIS Interactions object."""
    return SimpleNamespace(**kwargs)


# ===========================================================================
# InteractionsContext — singleton behaviour
# ===========================================================================

class TestInteractionsContextSingleton:

    def test_get_always_returns_same_object(self):
        with interactions_context() as ctx:
            assert get_interactions_context() is ctx
            assert get_interactions_context() is get_interactions_context()

    def test_init_interactions_sets_iris_ref(self):
        with interactions_context() as ctx:
            mock = _make_mock_iris(name="iris")
            init_interactions(mock)
            assert ctx.interactions is mock
            assert ctx._initialised is True

    def test_init_interactions_preserves_user_attributes(self):
        with interactions_context() as ctx:
            ctx.my_model = "loaded_model"
            mock = _make_mock_iris()
            init_interactions(mock)          # second call – simulates class reload
            assert ctx.my_model == "loaded_model"   # not wiped
            assert ctx.interactions is mock

    def test_arbitrary_attributes_can_be_added(self):
        with interactions_context() as ctx:
            ctx.cache = {"key": "value"}
            ctx.http_session = object()
            assert ctx.cache["key"] == "value"
            assert ctx.http_session is not None

    def test_default_attrs_before_init(self):
        with interactions_context() as ctx:
            assert ctx.interactions is None
            assert ctx._initialised is False


# ===========================================================================
# InteractionsContext — interactions_context() context manager
# ===========================================================================

class TestInteractionsContextManager:
    def test_provides_fresh_isolated_context(self):
        original = get_interactions_context()
        with interactions_context() as ctx:
            assert ctx is not original
            assert get_interactions_context() is ctx
        assert get_interactions_context() is original

    def test_kwargs_are_pre_populated(self):
        with interactions_context(config={"masking": True}, version=3) as ctx:
            assert ctx.config == {"masking": True}
            assert ctx.version == 3

    def test_restores_after_exception(self):
        original = get_interactions_context()
        try:
            with interactions_context():
                raise ValueError("boom")
        except ValueError:
            pass
        assert get_interactions_context() is original

    def test_nested_contexts_are_independent(self):
        with interactions_context(level=1) as outer:
            assert get_interactions_context().level == 1
            with interactions_context(level=2) as inner:
                assert get_interactions_context().level == 2
                assert get_interactions_context() is inner
            assert get_interactions_context().level == 1
            assert get_interactions_context() is outer


# ===========================================================================
# RequestContext — default / fallback behaviour
# ===========================================================================

class TestRequestContextDefaults:
    def test_get_outside_lifecycle_returns_default(self):
        # Ensure no request is active by using a fresh request_context that
        # we enter and immediately exit, then check after the block.
        with request_context():
            pass
        # Outside any block: should return a transient default instance.
        ctx = get_request_context()
        assert isinstance(ctx, RequestContext)
        assert ctx.username == ""
        assert ctx.roles == ""
        assert ctx.interactions is None

    def test_default_is_not_stored(self):
        # Two calls outside any block each get independent transient objects.
        c1 = get_request_context()
        c2 = get_request_context()
        c1.username = "sentinel"
        assert c2.username == ""   # mutation on c1 does not affect c2


# ===========================================================================
# RequestContext — begin_request / end_request lifecycle
# ===========================================================================

class TestBeginEndRequest:
    def test_begin_creates_fresh_context(self):
        mock = _make_mock_iris()
        ctx = begin_request(mock)
        try:
            assert get_request_context() is ctx
            assert ctx.interactions is mock
            assert ctx.username == ""
        finally:
            end_request()

    def test_begin_updates_interactions_singleton(self):
        with interactions_context() as ictx:
            mock = _make_mock_iris()
            begin_request(mock)
            try:
                assert ictx.interactions is mock
            finally:
                end_request()

    def test_end_request_clears_context(self):
        begin_request()
        end_request()
        # After end, get returns a transient default, not the request context.
        ctx = get_request_context()
        assert ctx.username == ""

    def test_end_request_safe_without_begin(self):
        end_request()   # must not raise

    def test_each_begin_provides_clean_slate(self):
        ctx1 = begin_request()
        ctx1.username = "alice"
        end_request()

        ctx2 = begin_request()
        try:
            assert ctx2.username == ""   # fresh — no leftover from ctx1
        finally:
            end_request()


# ===========================================================================
# RequestContext — request_context() context manager
# ===========================================================================

class TestRequestContextManager:
    def test_provides_isolated_context(self):
        with request_context(username="alice", roles="nurse") as ctx:
            assert get_request_context() is ctx
            assert ctx.username == "alice"
            assert ctx.roles == "nurse"

    def test_restores_after_block(self):
        outside_before = get_request_context()
        with request_context(username="temp"):
            pass
        outside_after = get_request_context()
        # Both calls outside the block return fresh transient objects, but
        # neither should carry the "temp" username.
        assert outside_after.username == ""

    def test_restores_after_exception(self):
        with request_context(username="outer") as outer:
            try:
                with request_context(username="inner"):
                    raise RuntimeError("fail")
            except RuntimeError:
                pass
            assert get_request_context().username == "outer"
            assert get_request_context() is outer

    def test_nested_contexts_are_independent(self):
        with request_context(username="outer") as outer:
            assert get_request_context().username == "outer"
            with request_context(username="inner") as inner:
                assert get_request_context().username == "inner"
                assert get_request_context() is inner
            assert get_request_context().username == "outer"
            assert get_request_context() is outer

    def test_extra_attributes_can_be_added(self):
        """RequestContext (dataclass, no __slots__) allows dynamic attributes."""
        with request_context() as ctx:
            ctx.last_operation = "create"   # custom field used by e2e fixture
            assert get_request_context().last_operation == "create"

    def test_kwargs_are_pre_populated(self):
        scopes = ["patient/*.read", "openid"]
        with request_context(username="bob", scope_list=scopes) as ctx:
            assert ctx.scope_list == scopes


# ===========================================================================
# Thread safety
# ===========================================================================

class TestThreadSafety:
    def test_request_contexts_are_isolated_across_threads(self):
        """
        Two threads each see their own RequestContext; mutations in one do not
        bleed into the other.
        """
        errors = []
        barrier = threading.Barrier(2)

        def worker(name, expected):
            try:
                with request_context(username=name):
                    barrier.wait()   # both threads inside the context
                    actual = get_request_context().username
                    if actual != expected:
                        errors.append(f"{name}: got {actual!r}")
            except Exception as exc:
                errors.append(str(exc))

        t1 = threading.Thread(target=worker, args=("alice", "alice"))
        t2 = threading.Thread(target=worker, args=("bob", "bob"))
        t1.start(); t2.start()
        t1.join(); t2.join()

        assert errors == [], errors

    def test_interactions_context_singleton_is_shared_across_threads(self):
        """
        InteractionsContext is *not* thread-local — all threads see the same
        singleton (within an interactions_context() override block).
        """
        seen = []

        def worker():
            seen.append(id(get_interactions_context()))

        with interactions_context() as ictx:
            threads = [threading.Thread(target=worker) for _ in range(4)]
            for t in threads:
                t.start()
            for t in threads:
                t.join()

        assert len(set(seen)) == 1, "all threads should see the same singleton"

    def test_begin_end_request_per_thread(self):
        """begin_request / end_request work independently on each thread."""
        results = {}
        barrier = threading.Barrier(2)

        def worker(name):
            mock = _make_mock_iris(name=name)
            begin_request(mock)
            barrier.wait()
            results[name] = get_request_context().interactions.name
            end_request()

        t1 = threading.Thread(target=worker, args=("thread-A",))
        t2 = threading.Thread(target=worker, args=("thread-B",))
        t1.start(); t2.start()
        t1.join(); t2.join()

        assert results["thread-A"] == "thread-A"
        assert results["thread-B"] == "thread-B"


# ===========================================================================
# Integration: both contexts together (mirrors real handler usage)
# ===========================================================================

class TestBothContextsTogether:
    def test_interactions_ref_available_in_request_context(self):
        mock = _make_mock_iris(Read=lambda rt, rid: SimpleNamespace(_ToJSON=lambda: "{}"))
        with interactions_context(interactions=mock):
            with request_context(interactions=mock, username="alice") as ctx:
                ictx = get_interactions_context()
                rctx = get_request_context()
                assert rctx.interactions is mock
                assert ictx.interactions is mock
                assert rctx.username == "alice"

    def test_begin_request_syncs_interactions_singleton(self):
        mock = _make_mock_iris()
        with interactions_context() as ictx:
            begin_request(mock)
            try:
                assert ictx.interactions is mock
                assert get_request_context().interactions is mock
            finally:
                end_request()
