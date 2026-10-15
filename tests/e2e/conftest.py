import os
import time
import uuid
from pathlib import Path
from typing import Any, Generator, Optional

import pytest
import requests


def _get_host_port(container: Any, container_port: int) -> Optional[str]:
    ports = container.attrs.get("NetworkSettings", {}).get("Ports", {})
    binding = ports.get(f"{container_port}/tcp")
    if not binding:
        return None
    return binding[0].get("HostPort")


def _run_restart_script(container: Any) -> None:
    result = container.exec_run(
        ["/bin/sh", "-c", "iris session iris < /irisdev/app/iris.script.restart.fhir"],
        stdout=True,
        stderr=True,
        user="irisowner",
    )
    if result.exit_code != 0 or b"FHIR RESTART OK" not in result.output:
        raise RuntimeError(result.output.decode("utf-8", errors="replace"))

def _container_has_env(container: Any, key: str, value: str) -> bool:
    env_list = container.attrs.get("Config", {}).get("Env", [])
    return f"{key}={value}" in env_list


@pytest.fixture(scope="session")
def _fhir_runtime() -> Generator[tuple[Any, str], None, None]:
    docker = pytest.importorskip("docker")
    client = docker.from_env()

    image_name = os.environ.get("FHIR_TEST_IMAGE", "iris-fhir-python-strategy:latest")
    selected = os.environ.get("FHIR_TEST_CONTAINER")
    running = client.containers.get(selected) if selected else None
    created = None

    if running is not None:
        desired_path = "/irisdev/app/tests/e2e/fixtures/"
        desired_module = "fhir_customization"
        if (
            not _container_has_env(running, "FHIR_CUSTOMIZATION_PATH", desired_path)
            or not _container_has_env(running, "FHIR_CUSTOMIZATION_MODULE", desired_module)
        ):
            client.close()
            raise RuntimeError("Selected FHIR_TEST_CONTAINER has incompatible customization settings")


    if running is None:
        repo_root = Path(__file__).resolve().parents[2]
        created = client.containers.run(
            image_name,
            detach=True,
            environment={
                "FHIR_CUSTOMIZATION_PATH": "/irisdev/app/tests/e2e/fixtures/",
                "FHIR_CUSTOMIZATION_MODULE": "fhir_customization",
            },
            ports={"52773/tcp": None},
            volumes={str(repo_root): {"bind": "/irisdev/app", "mode": "rw"}},
            name=f"iris-fhir-python-strategy-test-{uuid.uuid4().hex[:12]}",
        )
        running = created

    try:
        deadline = time.time() + 600
        while time.time() < deadline:
            running.reload()
            if running.status == "running":
                break
            if running.status in ("exited", "dead"):
                raise RuntimeError(running.logs().decode("utf-8", errors="replace"))
            time.sleep(1)
        else:
            raise RuntimeError(
                "FHIR test container did not become ready:\n"
                + running.logs(tail=80).decode("utf-8", errors="replace")
            )

        host_port = _get_host_port(running, 52773)
        assert host_port, "Running container does not expose 52773/tcp"
        base_url = f"http://localhost:{host_port}"
        deadline = time.time() + 600
        while time.time() < deadline:
            try:
                response = requests.get(f"{base_url}/fhir/r4/metadata", timeout=5)
            except (requests.ConnectionError, requests.Timeout):
                time.sleep(1)
                continue
            if response.status_code == 200:
                break
            time.sleep(1)
        else:
            raise RuntimeError(
                "FHIR test endpoint did not become responsive:\n"
                + running.logs(tail=80).decode("utf-8", errors="replace")
            )
        _run_restart_script(running)
        response = requests.get(f"{base_url}/fhir/r4/metadata", timeout=30)
        if response.status_code != 200:
            raise RuntimeError(f"FHIR metadata failed after compilation: {response.status_code}: {response.text}")
        yield running, base_url
    finally:
        if created is not None:
            created.stop()
            created.remove()
        client.close()

@pytest.fixture(scope="session")
def fhir_base_url(_fhir_runtime: tuple[Any, str]) -> str:
    return _fhir_runtime[1]


@pytest.fixture(scope="session")
def fhir_container(_fhir_runtime: tuple[Any, str]) -> Any:
    return _fhir_runtime[0]
