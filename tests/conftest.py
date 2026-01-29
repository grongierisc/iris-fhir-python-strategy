import sys
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Callable

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[1]
PYTHON_SRC = PROJECT_ROOT / "src" / "python"
sys.path.insert(0, str(PROJECT_ROOT))
sys.path.insert(0, str(PYTHON_SRC))


@pytest.fixture()
def fake_fhir_request() -> Callable[[str, str], SimpleNamespace]:
    def _factory(username: str = "alice", roles: str = "doctor") -> SimpleNamespace:
        return SimpleNamespace(Username=username, Roles=roles)
    return _factory
