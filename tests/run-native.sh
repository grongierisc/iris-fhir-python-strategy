#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
log=$(mktemp)
trap 'rm -f "$log"' EXIT

if ! docker compose exec -T iris iris session iris -U FHIRSERVER >"$log" 2>&1 <<'OBJECTSCRIPT'
Set sc=$System.OBJ.LoadDir("/irisdev/app/iris_fhir_python_strategy/cls","ck",,1)
If $System.Status.IsError(sc) { Do $System.Status.DisplayError(sc) Halt }
Set sc=$System.OBJ.LoadDir("/irisdev/app/tests/native","ck",,1)
If $System.Status.IsError(sc) { Do $System.Status.DisplayError(sc) Halt }
Set sc=##class(FHIR.Python.Tests.Setup).Run()
Do $System.Status.DisplayError(sc)
Halt
OBJECTSCRIPT
then
    cat "$log" >&2
    exit 1
fi
cat "$log"
if [[ $(grep -c '^All PASSED' "$log") -ne 3 ]] ||
   ! grep -q 'TestExactWriteLimit() begins' "$log" ||
   ! grep -q 'TestAllOperationsSequentially() begins' "$log" ||
   ! grep -q 'TestNativeMergeDispatchAndHooks() begins' "$log" ||
   grep -qE 'FAILED|^ERROR #|^<[^>]+>|NO_TESTS_FOUND' "$log"; then
    echo "Native tests failed or required suites did not execute." >&2
    exit 1
fi
