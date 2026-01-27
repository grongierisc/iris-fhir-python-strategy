import time
from pathlib import Path

import pytest


def _find_running_container(client, image_name):
    for container in client.containers.list():
        if image_name in (container.image.tags or []):
            return container
    return None


def _get_host_port(container, container_port):
    ports = container.attrs.get("NetworkSettings", {}).get("Ports", {})
    binding = ports.get(f"{container_port}/tcp")
    if not binding:
        return None
    return binding[0].get("HostPort")


def _run_restart_script(container):
    result = container.exec_run(
        ["/bin/sh", "-c", "iris session iris < /irisdev/app/iris.script.restart.fhir"],
        stdout=True,
        stderr=True,
        user="root",
    )
    if result.exit_code != 0:
        raise RuntimeError(result.output.decode("utf-8", errors="replace"))

def _container_has_env(container, key, value):
    env_list = container.attrs.get("Config", {}).get("Env", [])
    return f"{key}={value}" in env_list


@pytest.fixture(scope="session")
def fhir_base_url():
    docker = pytest.importorskip("docker")
    client = docker.from_env()

    image_name = "iris-fhr-python-strategy:latest"
    running = _find_running_container(client, image_name)
    created = None

    if running is not None:
        desired_path = "/irisdev/app/tests/e2e/fixtures/"
        desired_module = "fhir_customization"
        if (
            not _container_has_env(running, "FHIR_CUSTOMIZATION_PATH", desired_path)
            or not _container_has_env(running, "FHIR_CUSTOMIZATION_MODULE", desired_module)
        ):
            running.stop()
            running.remove()
            running = None
        else:
            _run_restart_script(running)


    if running is None:
        repo_root = Path(__file__).resolve().parents[2]
        created = client.containers.run(
            image_name,
            detach=True,
            environment={
                "ISC_CPF_MERGE_FILE": "/irisdev/app/merge.cpf",
                "FHIR_CUSTOMIZATION_PATH": "/irisdev/app/tests/e2e/fixtures/",
                "FHIR_CUSTOMIZATION_MODULE": "fhir_customization",
            },
            ports={"52773/tcp": 8082},
            volumes={str(repo_root): {"bind": "/irisdev/app", "mode": "rw"}},
            name="iris-fhir-python-strategy-iris-1",
        )
        running = created

    host_port = _get_host_port(running, 52773)
    assert host_port, "Running container does not expose 52773/tcp"

    deadline = time.time() + 120
    while time.time() < deadline:
        running.reload()
        if running.status == "running":
            break
        time.sleep(1)

    if created is not None:
        _run_restart_script(running)

    yield f"http://localhost:{host_port}"

    if created is not None:
        created.stop()
        created.remove()
