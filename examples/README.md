# Examples

These modules demonstrate how to customize the FHIR server with decorators.
They are not used by the test suite; tests target the decorator registry directly.

## Usage
- Add the project root to `PYTHONPATH`, or set `FHIR_CUSTOMIZATION_PATH` to it.
- Set `FHIR_CUSTOMIZATION_MODULE=examples.custom_decorators`.
- Run the FHIR server so it can import the module and register handlers.

## Notes
- The examples use lazy imports to avoid importing Iris and other dependencies
  until the relevant handlers are invoked.
- Replace placeholder functions (like clearance checks) with real logic.
