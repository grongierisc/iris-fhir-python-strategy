import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

spec = importlib.util.spec_from_file_location(
    "fhir_e2e_fixtures", Path(__file__).parents[1] / "e2e" / "conftest.py"
)
assert spec is not None and spec.loader is not None
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)


def container(compatible=True):
    result = Mock()
    result.status = "running"
    result.attrs = {
        "Config": {"Env": [
            "FHIR_CUSTOMIZATION_PATH=/irisdev/app/tests/e2e/fixtures/",
            f"FHIR_CUSTOMIZATION_MODULE={'fhir_customization' if compatible else 'user_module'}",
        ]},
        "State": {"Health": {"Status": "healthy"}},
        "NetworkSettings": {"Ports": {"52773/tcp": [{"HostPort": "12345"}]}},
    }
    result.exec_run.return_value = SimpleNamespace(exit_code=0, output=b"FHIR RESTART OK")
    return result


def prepare(monkeypatch, test_container):
    client = Mock()
    client.containers.run.return_value = test_container
    client.containers.get.return_value = test_container
    monkeypatch.setitem(sys.modules, "docker", SimpleNamespace(from_env=lambda: client))
    monkeypatch.setattr(fixtures.requests, "get", lambda *a, **kw: SimpleNamespace(status_code=200))
    return client


def test_default_owns_separate_container(monkeypatch):
    monkeypatch.delenv("FHIR_TEST_CONTAINER", raising=False)
    owned = container()
    client = prepare(monkeypatch, owned)
    runtime = fixtures._fhir_runtime.__wrapped__()
    assert next(runtime) == (owned, "http://localhost:12345")
    client.containers.list.assert_not_called()
    client.containers.get.assert_not_called()
    arguments = client.containers.run.call_args.kwargs
    assert arguments["ports"] == {"52773/tcp": None}
    assert arguments["name"].startswith("iris-fhir-python-strategy-test-")
    runtime.close()
    owned.stop.assert_called_once()
    owned.remove.assert_called_once()


def test_explicit_container_never_removed(monkeypatch):
    monkeypatch.setenv("FHIR_TEST_CONTAINER", "selected")
    selected = container()
    client = prepare(monkeypatch, selected)
    runtime = fixtures._fhir_runtime.__wrapped__()
    assert next(runtime)[0] is selected
    runtime.close()
    client.containers.run.assert_not_called()
    selected.stop.assert_not_called()
    selected.remove.assert_not_called()


def test_incompatible_selected_container_fails_without_changes(monkeypatch):
    monkeypatch.setenv("FHIR_TEST_CONTAINER", "selected")
    selected = container(compatible=False)
    client = prepare(monkeypatch, selected)
    with pytest.raises(RuntimeError, match="incompatible"):
        next(fixtures._fhir_runtime.__wrapped__())
    client.containers.run.assert_not_called()
    selected.exec_run.assert_not_called()
    selected.stop.assert_not_called()
    selected.remove.assert_not_called()
