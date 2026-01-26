import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[1]
PYTHON_SRC = PROJECT_ROOT / "src" / "python"
sys.path.insert(0, str(PROJECT_ROOT))
sys.path.insert(0, str(PYTHON_SRC))


@pytest.fixture()
def fake_fhir_request():
    def _factory(username="alice", roles="doctor"):
        return SimpleNamespace(Username=username, Roles=roles)
    return _factory
