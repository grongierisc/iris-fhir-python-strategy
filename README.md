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
2. Import the `fhir` registry.
3. Decorate your functions.

### Example: Validation before Create

```python
from fhir_decorators import fhir

@fhir.on_before_create("Patient")
def validate_patient(service, request, body, timeout):
    if "identifier" not in body:
         raise ValueError("Patient must have an identifier")
```

### Example: Post-processing Read (Masking)

```python
@fhir.on_after_read("Patient")
def mask_patient(resource):
    # Hide sensitive data
    if "telecom" in resource:
        del resource["telecom"]
    return True # Return False to hide the resource completely (404)
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