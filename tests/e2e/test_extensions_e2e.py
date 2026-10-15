import uuid

import pytest
import requests

pytestmark = pytest.mark.e2e
HEADERS = {"Content-Type": "application/fhir+json", "Prefer": "return=representation"}
AUTH = ("SuperUser", "SYS")


def request(base, method, path="", body=None):
    return requests.request(
        method, f"{base}/fhir/r4/{path}", json=body,
        headers=HEADERS, auth=AUTH, timeout=30,
    )


def patients(base):
    prefix = "merge-" + uuid.uuid4().hex
    for suffix in ("source", "target"):
        resource = {
            "resourceType": "Patient", "id": f"{prefix}-{suffix}", "active": True,
            "identifier": [{"system": "urn:python-merge-test", "value": suffix + prefix}],
        }
        result = request(base, "PUT", f"Patient/{resource['id']}", resource)
        assert result.status_code == 201, result.text
    return prefix + "-source", prefix + "-target"


def merge_input(source, target, preview):
    return {"resourceType": "Parameters", "parameter": [
        {"name": "source-patient", "valueReference": {"reference": f"Patient/{source}"}},
        {"name": "target-patient", "valueReference": {"reference": f"Patient/{target}"}},
        {"name": "preview", "valueBoolean": preview},
    ]}


def patch_bundle(resource_id, kind="transaction", invalid=False):
    return {"resourceType": "Bundle", "type": kind, "entry": [{
        "request": {"method": "PATCH", "url": f"Patient/{resource_id}"},
        "resource": {"resourceType": "Parameters", "parameter": [{
            "name": "operation", "part": [
                {"name": "type", "valueCode": "replace"},
                {"name": "path", "valueString": "Patient.active"},
                {"name": "value", **({"valueString": "invalid"} if invalid else {"valueBoolean": False})},
            ],
        }]},
    }]}


def test_merge_metadata_and_definition(fhir_base_url):
    result = request(fhir_base_url, "GET", "metadata")
    assert result.status_code == 200, result.text
    patient = next(r for r in result.json()["rest"][0]["resource"] if r["type"] == "Patient")
    operations = [o for o in patient["operation"] if o["name"] == "merge"]
    assert len(operations) == 1
    result = request(fhir_base_url, "GET", "OperationDefinition/Patient-merge-r4")
    assert result.status_code == 200, result.text
    assert operations[0]["definition"] == result.json()["url"]


def test_merge_preview_commit_and_patch(fhir_base_url):
    source, target = patients(fhir_base_url)
    result = request(fhir_base_url, "POST", "Patient/$merge", merge_input(source, target, True))
    assert result.status_code == 200, result.text
    assert [p["name"] for p in result.json()["parameter"]] == ["input", "outcome", "result"]
    assert "versionId" not in result.json()["parameter"][2]["resource"]["meta"]
    assert request(fhir_base_url, "GET", f"Patient/{target}").json()["meta"]["versionId"] == "1"
    result = request(fhir_base_url, "POST", "Patient/$merge", merge_input(source, target, False))
    assert result.status_code == 200, result.text
    assert result.json()["parameter"][2]["resource"]["meta"]["versionId"] == "2"
    source_resource = request(fhir_base_url, "GET", f"Patient/{source}").json()
    assert source_resource["active"] is False
    assert source_resource["link"][0]["type"] == "replaced-by"
    result = request(fhir_base_url, "POST", body=patch_bundle(target))
    assert result.status_code == 200, result.text
    stored = request(fhir_base_url, "GET", f"Patient/{target}").json()
    assert stored["active"] is False
    assert stored["meta"]["versionId"] == "3"
    assert len(stored["identifier"]) == 2
    assert request(fhir_base_url, "GET", f"Patient/{source}/$everything").status_code == 400


def test_patch_transaction_rollback_with_python_validators(fhir_base_url):
    source, target = patients(fhir_base_url)
    bundle = patch_bundle(source)
    bundle["entry"].extend(patch_bundle(target, invalid=True)["entry"])
    result = request(fhir_base_url, "POST", body=bundle)
    assert result.status_code == 400, result.text
    for resource_id in (source, target):
        stored = request(fhir_base_url, "GET", f"Patient/{resource_id}").json()
        assert stored["active"] is True
        assert stored["meta"]["versionId"] == "1"


def test_patch_batch_isolation(fhir_base_url):
    source, target = patients(fhir_base_url)
    bundle = patch_bundle(source, "batch")
    bundle["entry"].extend(patch_bundle(target, "batch", invalid=True)["entry"])
    result = request(fhir_base_url, "POST", body=bundle)
    assert result.status_code == 200, result.text
    entries = result.json()["entry"]
    assert entries[0]["response"]["status"].startswith("200")
    assert entries[1]["response"]["status"].startswith("400")
    assert entries[1]["response"]["outcome"]["resourceType"] == "OperationOutcome"
    assert request(fhir_base_url, "GET", f"Patient/{source}").json()["active"] is False
    assert request(fhir_base_url, "GET", f"Patient/{target}").json()["active"] is True


def test_installed_package_upgrade_preserves_data(fhir_base_url, fhir_container):
    source, _ = patients(fhir_base_url)
    resource = request(fhir_base_url, "GET", f"Patient/{source}").json()
    resource["active"] = False
    assert request(fhir_base_url, "PUT", f"Patient/{source}", resource).status_code == 200
    before = request(fhir_base_url, "GET", f"Patient/{source}/_history").json()
    definition = request(fhir_base_url, "GET", "OperationDefinition/Patient-merge-r4").json()
    result = fhir_container.exec_run([
        "python3", "-m", "iris_fhir_python_strategy",
        "--namespace", "FHIRSERVER", "--endpoint", "/fhir/r4",
    ], workdir="/")
    assert result.exit_code == 0, result.output.decode("utf-8", errors="replace")
    stored = request(fhir_base_url, "GET", f"Patient/{source}").json()
    assert stored["active"] is False
    assert stored["meta"]["versionId"] == "2"
    after = request(fhir_base_url, "GET", f"Patient/{source}/_history").json()
    assert len(after["entry"]) == len(before["entry"]) == 2
    indexed = request(fhir_base_url, "GET", f"Patient?identifier=urn:python-merge-test|{resource['identifier'][0]['value']}")
    assert indexed.status_code == 200, indexed.text
    assert any(e["resource"]["id"] == source for e in indexed.json()["entry"])
    refreshed = request(fhir_base_url, "GET", "OperationDefinition/Patient-merge-r4").json()
    assert refreshed["meta"]["versionId"] == definition["meta"]["versionId"]
