"""
Intentionally broken customization module used only by e2e tests.

The consent handler below declares two required positional parameters.
The IRIS bridge only ever passes one (the resource dict), so this would
previously produce the cryptic runtime error::

    <OBJECT DISPATCH> 2603 RunBooleanHandlers+8^FHIR.Python.Helper.1

Since the fix, ``@fhir.consent`` wraps bad-signature handlers at *decoration
time* rather than raising immediately.  The module now *imports cleanly*;
the ``TypeError`` with a descriptive message is raised when the handler is
actually *called* (i.e. when the IRIS bridge invokes it at request time),
producing a proper FHIR OperationOutcome instead of the cryptic OBJECT
DISPATCH error.
"""
from typing import Any, Dict

from iris_fhir_python_strategy import fhir


@fhir.consent("Patient")
def patient_consent_bad_signature(fhir_object: Dict[str, Any], user_context: Any) -> bool:
    """Bad handler: two required params, but the IRIS bridge only passes one."""
    return True
