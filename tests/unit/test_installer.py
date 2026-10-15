import sys
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

from iris_fhir_python_strategy.__main__ import main


def test_compile_only_and_endpoint_publication(monkeypatch):
    monkeypatch.setenv("IRISNAMESPACE", "TEST_ORIGINAL")
    loader = Mock()
    loader.LoadDir.return_value = 1
    status = Mock()
    status.IsError.return_value = False
    setup = Mock()
    classes = {"%SYSTEM.OBJ": loader, "%SYSTEM.Status": status, "FHIR.Python.Setup": setup}
    monkeypatch.setitem(sys.modules, "iris", SimpleNamespace(cls=classes.__getitem__))
    monkeypatch.setattr(sys, "argv", ["installer", "--namespace", "FHIRSERVER"])
    main()
    setup.PublishDefinition.assert_not_called()
    assert loader.LoadDir.call_args.args[0].endswith("iris_fhir_python_strategy/cls")
    monkeypatch.setattr(sys, "argv", ["installer", "--endpoint", "/fhir/r4"])
    main()
    endpoint, assets = setup.PublishDefinition.call_args.args
    assert endpoint == "/fhir/r4"
    assert assets.endswith("iris_fhir_python_strategy/fhir")
    assert os.environ["IRISNAMESPACE"] == "FHIRSERVER"


def test_failed_compilation_stops_publication(monkeypatch):
    loader = Mock()
    loader.LoadDir.return_value = 0
    status = Mock()
    status.IsError.return_value = True
    status.GetErrorText.return_value = "compile failed"
    setup = Mock()
    classes = {"%SYSTEM.OBJ": loader, "%SYSTEM.Status": status, "FHIR.Python.Setup": setup}
    monkeypatch.setitem(sys.modules, "iris", SimpleNamespace(cls=classes.__getitem__))
    monkeypatch.setattr(sys, "argv", ["installer", "--endpoint", "/fhir/r4"])
    with pytest.raises(RuntimeError, match="compile failed"):
        main()
    setup.PublishDefinition.assert_not_called()
import os
