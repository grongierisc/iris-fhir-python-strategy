# InterSystems IRIS FHIR Python Strategy

A flexible Python-based strategy for customizing InterSystems IRIS FHIR Server behavior using decorators.

## Overview

This project provides a bridge between the high-performance InterSystems IRIS FHIR Server and Python. It allows developers to customize FHIR operations (Create, Read, Update, Delete, Search) and implement business logic (Consent, Validation, OAuth) using familiar Python decorators.

## Features

- **Full CRUD Hook Support**: Pre-processing (`on_before_`) and post-processing (`on_after_`) hooks for all interactions.
- **Pythonic API**: Use decorators like `@fhir.on_before_create("Patient")` to register handlers.
- **Consent Management**: Implement fine-grained consent rules.
- **Custom Operations**: Easily add `$operations` in Python.
- **Validation**: Custom resource and bundle validation.
- **OAuth Customization**: Hooks for token introspection and user context.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- Git

## Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/grongierisc/iris-fhir-python-strategy.git
   cd iris-fhir-python-strategy
   ```

2. **Start the containers**
   ```bash
   docker-compose up -d
   ```

3. **Verify Installation**
   Access the FHIR metadata endpoint:
   ```bash
   curl http://localhost:8083/fhir/r4/metadata
   ```

## Usage Guide

### Defining Custom Logic

1. Open `examples/custom_decorators.py` (or create your own module).
2. Import the `fhir` registry from `fhir_decorators`.
3. Decorate your functions to register them as handlers.

### Detailed Examples

#### 1. Validation Logic
Validate resources before they are saved to the database.

```python
from fhir_decorators import fhir

@fhir.on_validate_resource("Patient")
def validate_patient(resource, is_in_transaction):
    """
    Ensure specific rules for Patient resources.
    Raises ValueError to reject the resource with a 400 Bad Request.
    """
    # Rule: Check if 'identifier' exists
    if "identifier" not in resource:
         raise ValueError("Patient must have at least one identifier")
    
    # Rule: Check for forbidden names
    for name in resource.get("name", []):
        if name.get("family") == "Forbidden":
            raise ValueError("This family name is not allowed")

@fhir.on_validate_bundle
def validate_bundle(bundle, fhir_version):
    """
    Apply rules to the entire bundle.
    """
    if bundle.get("type") == "transaction":
        if len(bundle.get("entry", [])) > 100:
            raise ValueError("Transaction bundle too large (max 100 entries)")
```

#### 2. Pre-Processing Hooks (Modification)
Modify the incoming resource or metadata before the server processes it.

```python
@fhir.on_before_create("Observation")
def enrich_observation(service, request, body, timeout):
    """
    Automatically add a tag to all new Observations.
    """
    meta = body.setdefault("meta", {})
    tags = meta.setdefault("tag", [])
    tags.append({
        "system": "http://my-hospital.org/tags",
        "code": "auto-generated",
        "display": "Auto Generated"
    })
```

#### 3. Post-Processing Hooks (Masking/Filtering)
Modify or filter the response *after* the database operation but *before* sending it to the client.

```python
@fhir.on_after_read("Patient")
def mask_patient_data(resource):
    """
    Mask sensitive fields for non-admin users.
    Returns:
        True: Return the resource (modified or not).
        False: Hide the resource (client receives 404).
    """
    # Assuming user context is stored globally or passed
    user_role = "user" # Replace with actual context retrieval logic
    
    if user_role != "admin":
        # Remove telecom info
        if "telecom" in resource:
            del resource["telecom"]
        
        # Obfuscate birth date
        if "birthDate" in resource:
            resource["birthDate"] = "1900-01-01"
            
    return True
```

#### 4. Custom Operations ($operation)
Implement custom FHIR operations using Python functions.

```python
@fhir.operation(name="echo", scope="Instance", resource_type="Patient")
def echo_patient_operation(name, scope, body, service, request, response):
    """
    Implements POST /Patient/{id}/$echo
    """
    # Logic: Just reflect the input body and operation details
    response_payload = {
        "resourceType": "Parameters",
        "parameter": [
            {"name": "operation", "valueString": name},
            {"name": "received_body", "resource": body}
        ]
    }
    
    # Set the response payload
    # Note: 'response' is the IRIS response object wrapper
    response.Json = response_payload
    return response
```

#### 5. Search Filtering (Row-Level Security)
Intercept search results to enforce fine-grained access control.

```python
@fhir.on_after_search("Patient")
def filter_search_results(result_set, resource_type):
    """
    Iterate through search results and remove restricted items.
    'result_set' is an iris.HS.FHIRServer.Util.SearchResult object.
    """
    # Iterate over the result set
    result_set._SetIterator(0)
    while result_set._Next():
        # Get resource content or ID
        resource_id = result_set._Get("ResourceId")
        
        # Example validation logic
        if resource_id.startswith("restricted-"):
            # Mark this row as deleted so it is excluded from the Bundle
            result_set.MarkAsDeleted()
            result_set._SaveRow()
```

#### 6. Customizing Capability Statement
Remove unsupported resources or add documentation.

```python
@fhir.on_capability_statement
def customize_metadata(capability_statement):
    """
    Remove 'Account' resource from the metadata.
    """
    rest_def = capability_statement['rest'][0]
    resources = rest_def['resource']
    
    # Filter out Account
    rest_def['resource'] = [r for r in resources if r['type'] != 'Account']
    
    return capability_statement
```

## Available Decorators

### Interaction Hooks

These hooks allow you to intercept and modify standard FHIR interactions.

| Pre-Process (Before DB) | Post-Process (After DB) | Description |
|-------------------------|--------------------------|-------------|
| `@fhir.on_before_create(type)` | `@fhir.on_after_create(type)` | Create Hook (POST) |
| `@fhir.on_before_read(type)` | `@fhir.on_after_read(type)` | Read Hook (GET) |
| `@fhir.on_before_update(type)` | `@fhir.on_after_update(type)` | Update Hook (PUT) |
| `@fhir.on_before_delete(type)` | `@fhir.on_after_delete(type)` | Delete Hook (DELETE) |
| `@fhir.on_before_search(type)` | `@fhir.on_after_search(type)` | Search Hook |

*Note: `type` is optional. If omitted (e.g., `@fhir.on_before_create()`), it applies to **all** resource types.*

### Global Request Hooks

| Decorator | Description |
|-----------|-------------|
| `@fhir.on_before_request` | Runs before **any** interaction. Useful for logging or setting up user context. |
| `@fhir.on_after_request` | Runs after **any** interaction sequence. Useful for cleanup. |

### Capability Statement

| Decorator | Description |
|-----------|-------------|
| `@fhir.on_capability_statement` | Customize the server's CapabilityStatement (Metadata). |

### Custom Operations

| Decorator | Description |
|-----------|-------------|
| `@fhir.operation(name, scope, type)` | Implement custom FHIR operations (e.g., `$diff`). |

### OAuth & Security

| Decorator | Description |
|-----------|-------------|
| `@fhir.oauth_get_user_info` | Extract user info from token. |
| `@fhir.oauth_get_introspection` | Customize token introspection. |
| `@fhir.consent(type)` | Implement consent logic. |
| `@fhir.oauth_verify_resource_id(type)` | Verify access by Resource ID. |
| `@fhir.oauth_verify_resource_content(type)` | Verify access by Resource Content. |
| `@fhir.oauth_verify_search(type)` | Verify access for Search parameters. |
| `@fhir.oauth_verify_system_level` | Verify system administration privileges. |

### Validation

| Decorator | Description |
|-----------|-------------|
| `@fhir.on_validate_resource(type)` | Custom logic to validate a resource. |
| `@fhir.on_validate_bundle` | Custom logic to validate a bundle. |

## Configuration

The strategy is configured via environment variables in `docker-compose.yml`:

- `FHIR_CUSTOMIZATION_MODULE`: The Python module to load (default: `examples.custom_decorators`).
- `FHIR_CUSTOMIZATION_PATH`: Path to the Python code (default: `/irisdev/app/`).

## Architecture

1. **Interactions.cls**: The ObjectScript class that intercepts FHIR requests.
2. **fhir_decorators.py**: The Python registry that manages hooks.
3. **Your Module**: The Python code where you define handlers.

When a request arrives (e.g., `POST /Patient`), IRIS calls `Interactions.cls`, which looks up the registered Python handler for `on_before_create` and executes it.

For detailed implementation of the ObjectScript to Python bridge, see `src/cls/FHIR/Python/Interactions.cls` and `src/cls/FHIR/Python/Helper.cls`.
