"""
FHIR Server Customization using Decorators.

This module provides a decorator-based API for customizing FHIR server behavior.
Simply decorate your functions to register customizations.

Example:
    from iris_fhir_python_strategy import fhir
    
    @fhir.on_capability_statement
    def customize_capability(capability_statement):
        return capability_statement
    
    @fhir.before_request
    def extract_user(fhir_service, fhir_request, body, timeout):
        pass
    
    @fhir.post_process_read("Patient")
    def filter_patient(fhir_object):
        return True
"""

import functools
import inspect
from typing import Callable, Dict, List, Optional, Any

class FhirDecorators:
    """
    Registry for FHIR customization functions using decorators.
    """
    
    def __init__(self):
        # Registries for different customization points
        self._capability_statement_handlers = []
        self._on_before_request_handlers = []
        self._on_after_request_handlers = []
        
        # CRUD - Before
        self._on_before_create_handlers = {}  # {resource_type: [handlers]}
        self._on_before_read_handlers = {}    # {resource_type: [handlers]}
        self._on_before_update_handlers = {}  # {resource_type: [handlers]}
        self._on_before_delete_handlers = {}  # {resource_type: [handlers]}
        self._on_before_search_handlers = {}  # {resource_type: [handlers]}
        
        # CRUD - After (Post-Process)
        self._on_after_create_handlers = {}   # {resource_type: [handlers]}
        self._on_after_read_handlers = {}     # {resource_type: [handlers]}
        self._on_after_update_handlers = {}   # {resource_type: [handlers]}
        self._on_after_delete_handlers = {}   # {resource_type: [handlers]}
        self._on_after_search_handlers = {}   # {resource_type: [handlers]}
        
        self._consent_handlers = {}  # {resource_type: [handlers]}
        self._operations = {}  # {(name, scope, resource_type): handler}
        
        # OAuth handlers
        self._oauth_set_instance_handlers = []
        self._oauth_get_introspection_handlers = []
        self._oauth_get_user_info_handlers = []
        self._oauth_verify_resource_id_handlers = {}  # {resource_type: [handlers]}
        self._oauth_verify_resource_content_handlers = {}  # {resource_type: [handlers]}
        self._oauth_verify_history_handlers = {}  # {resource_type: [handlers]}
        self._oauth_verify_delete_handlers = {}  # {resource_type: [handlers]}
        self._oauth_verify_search_handlers = {}  # {resource_type: [handlers]}
        self._oauth_verify_system_level_handlers = []
        
        # Validation handlers
        self._validate_resource_handlers = {}  # {resource_type: [handlers]}
        self._validate_bundle_handlers = []
    
    # ==================== Arity validation helper ====================

    @staticmethod
    def _wrap_with_arity_check(func: Callable, decorator_name: str, expected: int) -> Callable:
        """
        Return a validated callable to register for *func*.

        Validation is **deferred to call time** so that a bad handler never
        crashes the application at import/load time.  When the IRIS bridge
        eventually invokes the handler, a clear ``TypeError`` is raised —
        producing a proper FHIR OperationOutcome with a meaningful
        ``diagnostics`` message instead of the cryptic
        ``<OBJECT DISPATCH> 2603 RunBooleanHandlers+8^FHIR.Python.Helper.1``.

        Rules (functions with ``*args`` are always accepted):

        * **Good signature** — *func* is returned unchanged (zero overhead).
        * **Too many required args** — a wrapper is returned that raises
          ``TypeError`` on every call naming the extra required parameters.
        * **Too few positional slots** — same, naming how many args the bridge
          passes.

        Optional parameters (those with defaults) are transparent: a handler
        declared as ``def h(resource, is_in_transaction=False)`` is valid for
        ``expected=2`` because the bridge always passes both values.

        Parameters
        ----------
        func
            Handler being registered.
        decorator_name
            Human-readable decorator name used in the error message.
        expected
            Number of positional args the IRIS bridge will pass.
        """
        sig = inspect.signature(func)

        # *args accepts any number of positional arguments — always valid.
        has_var_positional = any(
            p.kind == inspect.Parameter.VAR_POSITIONAL
            for p in sig.parameters.values()
        )
        if has_var_positional:
            return func

        positional_params = [
            p for p in sig.parameters.values()
            if p.kind in (
                inspect.Parameter.POSITIONAL_OR_KEYWORD,
                inspect.Parameter.POSITIONAL_ONLY,
            )
        ]
        required_positional = [
            p for p in positional_params
            if p.default is inspect.Parameter.empty
        ]
        required_count = len(required_positional)
        total_count = len(positional_params)

        if required_count > expected:
            error_msg = (
                f"@fhir.{decorator_name} handler '{func.__name__}' requires "
                f"{required_count} positional argument(s) but the IRIS bridge "
                f"only passes {expected}. "
                f"Extra required parameter(s): "
                f"{[p.name for p in required_positional[expected:]]}. "
                f"Check the decorator docstring for the expected signature "
                f"(tip: use get_request_context() for per-request user data)."
            )
        elif total_count < expected:
            error_msg = (
                f"@fhir.{decorator_name} handler '{func.__name__}' only accepts "
                f"{total_count} positional argument(s) but the IRIS bridge "
                f"passes {expected}. "
                f"Check the decorator docstring for the expected signature."
            )
        else:
            return func  # good signature — register as-is

        @functools.wraps(func)
        def _bad_signature_wrapper(*args: Any, **kwargs: Any) -> Any:
            raise TypeError(error_msg)

        return _bad_signature_wrapper

    # ==================== Capability Statement ====================
    
    def on_capability_statement(self, func: Callable) -> Callable:
        """
        Decorator to customize the capability statement.
        
        Signature:
            def handler(capability_statement: dict) -> dict:
        
        Example:
            @fhir.on_capability_statement
            def customize_capability(capability_statement: dict) -> dict:
                # Modify capability_statement
                return capability_statement
        """
        wrapped = self._wrap_with_arity_check(func, "on_capability_statement", 1)
        self._capability_statement_handlers.append(wrapped)
        return wrapped
    
    # ==================== Request/Response Hooks ====================
    
    def on_before_request(self, func: Callable) -> Callable:
        """
        Decorator for pre-request processing.
        
        Signature:
            def handler(fhir_service: Any, fhir_request: Any, body: dict, timeout: int) -> None:
        
        Example:
            @fhir.on_before_request
            def extract_user_context(fhir_service, fhir_request, body, timeout):
                # Extract user and roles
                pass
        """
        wrapped = self._wrap_with_arity_check(func, "on_before_request", 4)
        self._on_before_request_handlers.append(wrapped)
        return wrapped
    
    def on_after_request(self, func: Callable) -> Callable:
        """
        Decorator for post-request processing.
        
        Signature:
            def handler(fhir_service: Any, fhir_request: Any, fhir_response: Any, body: dict) -> None:
        
        Example:
            @fhir.on_after_request
            def cleanup(fhir_service, fhir_request, fhir_response, body):
                # Clean up request-scoped state
                pass
        """
        wrapped = self._wrap_with_arity_check(func, "on_after_request", 4)
        self._on_after_request_handlers.append(wrapped)
        return wrapped
    
    # ==================== CRUD Operations - Before ====================
    
    def on_before_create(self, resource_type: Optional[str] = None) -> Callable:
        """
        Decorator for pre-create operations (POST).
        
        Signature:
            def handler(fhir_service: Any, fhir_request: Any, body: dict, timeout: int) -> None:
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "on_before_create", 4)
            if resource_type is None:
                key = "__global__"
            else:
                key = resource_type
            if key not in self._on_before_create_handlers:
                self._on_before_create_handlers[key] = []
            self._on_before_create_handlers[key].append(wrapped)
            return wrapped
        return decorator
    
    def on_before_read(self, resource_type: Optional[str] = None) -> Callable:
        """
        Decorator for pre-read operations (GET).
        
        Signature:
            def handler(fhir_service: Any, fhir_request: Any, body: dict, timeout: int) -> None:
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "on_before_read", 4)
            if resource_type is None:
                key = "__global__"
            else:
                key = resource_type
            if key not in self._on_before_read_handlers:
                self._on_before_read_handlers[key] = []
            self._on_before_read_handlers[key].append(wrapped)
            return wrapped
        return decorator

    def on_before_update(self, resource_type: Optional[str] = None) -> Callable:
        """
        Decorator for pre-update operations (PUT).
        
        Signature:
            def handler(fhir_service: Any, fhir_request: Any, body: dict, timeout: int) -> None:
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "on_before_update", 4)
            if resource_type is None:
                key = "__global__"
            else:
                key = resource_type
            if key not in self._on_before_update_handlers:
                self._on_before_update_handlers[key] = []
            self._on_before_update_handlers[key].append(wrapped)
            return wrapped
        return decorator
    
    def on_before_delete(self, resource_type: Optional[str] = None) -> Callable:
        """
        Decorator for pre-delete operations (DELETE).
        
        Signature:
            def handler(fhir_service: Any, fhir_request: Any, body: dict, timeout: int) -> None:
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "on_before_delete", 4)
            if resource_type is None:
                key = "__global__"
            else:
                key = resource_type
            if key not in self._on_before_delete_handlers:
                self._on_before_delete_handlers[key] = []
            self._on_before_delete_handlers[key].append(wrapped)
            return wrapped
        return decorator

    def on_before_search(self, resource_type: Optional[str] = None) -> Callable:
        """
        Decorator for pre-search operations.
        
        Signature:
            def handler(fhir_service: Any, fhir_request: Any, body: dict, timeout: int) -> None:
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "on_before_search", 4)
            if resource_type is None:
                key = "__global__"
            else:
                key = resource_type
            if key not in self._on_before_search_handlers:
                self._on_before_search_handlers[key] = []
            self._on_before_search_handlers[key].append(wrapped)
            return wrapped
        return decorator

    # ==================== CRUD Operations - After ====================

    def on_after_create(self, resource_type: Optional[str] = None) -> Callable:
        """
        Decorator for post-create operations.
        
        Signature:
            def handler(fhir_service: Any, fhir_request: Any, fhir_response: Any, body: dict) -> None:
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "on_after_create", 4)
            if resource_type is None:
                key = "__global__"
            else:
                key = resource_type
            if key not in self._on_after_create_handlers:
                self._on_after_create_handlers[key] = []
            self._on_after_create_handlers[key].append(wrapped)
            return wrapped
        return decorator

    def on_after_read(self, resource_type: Optional[str] = None) -> Callable:
        """
        Decorator for post-read operations (PostProcessRead).
        
        Signature:
            def handler(resource: dict) -> bool:
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "on_after_read", 1)
            if resource_type is None:
                key = "__global__"
            else:
                key = resource_type
            if key not in self._on_after_read_handlers:
                self._on_after_read_handlers[key] = []
            self._on_after_read_handlers[key].append(wrapped)
            return wrapped
        return decorator
    
    def on_after_update(self, resource_type: Optional[str] = None) -> Callable:
        """
        Decorator for post-update operations.
        
        Signature:
            def handler(fhir_service: Any, fhir_request: Any, fhir_response: Any, body: dict) -> None:
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "on_after_update", 4)
            if resource_type is None:
                key = "__global__"
            else:
                key = resource_type
            if key not in self._on_after_update_handlers:
                self._on_after_update_handlers[key] = []
            self._on_after_update_handlers[key].append(wrapped)
            return wrapped
        return decorator
        
    def on_after_delete(self, resource_type: Optional[str] = None) -> Callable:
        """
        Decorator for post-delete operations.
        
        Signature:
            def handler(fhir_service: Any, fhir_request: Any, fhir_response: Any, body: dict) -> None:
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "on_after_delete", 4)
            if resource_type is None:
                key = "__global__"
            else:
                key = resource_type
            if key not in self._on_after_delete_handlers:
                self._on_after_delete_handlers[key] = []
            self._on_after_delete_handlers[key].append(wrapped)
            return wrapped
        return decorator

    def on_after_search(self, resource_type: Optional[str] = None) -> Callable:
        """
        Decorator for post-search operations (PostProcessSearch).
        
        Signature:
            def handler(rs: Any, resource_type: str) -> None:
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "on_after_search", 2)
            if resource_type is None:
                key = "__global__"
            else:
                key = resource_type
            if key not in self._on_after_search_handlers:
                self._on_after_search_handlers[key] = []
            self._on_after_search_handlers[key].append(wrapped)
            return wrapped
        return decorator
    
    # ==================== Convenience Decorators ====================
    
    # Aliases removed as naming convention is now standard
    
    # ==================== Consent ====================
    
    def consent(self, resource_type: Optional[str] = None) -> Callable:
        """
        Decorator for consent rules.
        
        Args:
            resource_type: Specific resource type or None for all types
        
        The handler receives only the resource dict as its argument.  Access
        the current user's identity via :func:`get_request_context`.

        Example:
            @fhir.consent("Patient")
            def patient_consent(fhir_object: dict) -> bool:
                # Check if user has access to this resource
                ctx = get_request_context()
                for sec in fhir_object.get("meta", {}).get("security", []):
                    if sec.get("code") in ctx.security_list:
                        return False  # deny access
                return True
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "consent", 1)
            key = resource_type or "*"
            if key not in self._consent_handlers:
                self._consent_handlers[key] = []
            self._consent_handlers[key].append(wrapped)
            return wrapped
        return decorator
    
    # ==================== CRUD Operations ====================
     
    # Removed old operations placeholders  
      
    # ==================== Custom Operations ====================
    
    def operation(
        self,
        name: str,
        scope: str = "Instance",
        resource_type: Optional[str] = None
    ) -> Callable:
        """
        Decorator for custom FHIR operations.
        
        Args:
            name: Operation name (e.g., "validate", "diff")
            scope: Operation scope ("System", "Type", or "Instance")
            resource_type: Resource type for Type/Instance scoped operations
        
        Example:
            @fhir.operation("diff", scope="Instance", resource_type="Patient")
            def patient_diff(operation_name, operation_scope, body,
                           fhir_service, fhir_request, fhir_response):
                # Custom diff operation
                return fhir_response
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "operation", 6)
            key = (name, scope, resource_type or "*")
            self._operations[key] = wrapped
            return wrapped
        return decorator
    
    # ==================== Registry Access ====================
    
    def get_capability_statement_handlers(self) -> List[Callable]:
        """Get all registered capability statement handlers."""
        return self._capability_statement_handlers.copy()
    
    def get_on_before_request_handlers(self) -> List[Callable]:
        """Get all registered before_request handlers."""
        return self._on_before_request_handlers.copy()
    
    def get_on_after_request_handlers(self) -> List[Callable]:
        """Get all registered after_request handlers."""
        return self._on_after_request_handlers.copy()
    
    def get_on_before_read_handlers(self, resource_type: str) -> List[Callable]:
        """Get on_before_read handlers for a specific resource type."""
        handlers = []
        handlers.extend(self._on_before_read_handlers.get("__global__", []))
        if resource_type != "*" and resource_type != "__global__":
            handlers.extend(self._on_before_read_handlers.get(resource_type, []))
        handlers.extend(self._on_before_read_handlers.get("*", []))
        return handlers

    def get_on_after_read_handlers(self, resource_type: str) -> List[Callable]:
        """Get post_process_read handlers for a specific resource type."""
        handlers = []
        handlers.extend(self._on_after_read_handlers.get("__global__", []))
        if resource_type != "*" and resource_type != "__global__":
            handlers.extend(self._on_after_read_handlers.get(resource_type, []))
        handlers.extend(self._on_after_read_handlers.get("*", []))
        return handlers

    def get_on_before_search_handlers(self, resource_type: str) -> List[Callable]:
        """Get on_before_search handlers for a specific resource type."""
        handlers = []
        handlers.extend(self._on_before_search_handlers.get("__global__", []))
        if resource_type != "*" and resource_type != "__global__":
            handlers.extend(self._on_before_search_handlers.get(resource_type, []))
        handlers.extend(self._on_before_search_handlers.get("*", []))
        return handlers
    
    def get_on_after_search_handlers(self, resource_type: str) -> List[Callable]:
        """Get post_process_search handlers for a specific resource type."""
        handlers = []
        handlers.extend(self._on_after_search_handlers.get("__global__", []))
        if resource_type != "*" and resource_type != "__global__":
            handlers.extend(self._on_after_search_handlers.get(resource_type, []))
        handlers.extend(self._on_after_search_handlers.get("*", []))
        return handlers
    
    def get_consent_handlers(self, resource_type: str) -> List[Callable]:
        """Get consent handlers for a specific resource type."""
        handlers = []
        # Add wildcard handlers
        handlers.extend(self._consent_handlers.get("*", []))
        # Add type-specific handlers
        handlers.extend(self._consent_handlers.get(resource_type, []))
        return handlers
    
    def get_operation_handler(
        self,
        name: str,
        scope: str,
        resource_type: Optional[str] = None
    ) -> Optional[Callable]:
        """Get operation handler for specific operation."""
        # Try exact match first
        key = (name, scope, resource_type)
        if key in self._operations:
            return self._operations[key]
        
        # Try wildcard resource type
        key = (name, scope, "*")
        if key in self._operations:
            return self._operations[key]
        
        return None
    
    def get_operations(self) -> Dict[tuple, Callable]:
        """Get all registered operations."""
        return self._operations.copy()
    
    def get_on_before_create_handlers(self, resource_type: str) -> List[Callable]:
        """Get on_create handlers for a specific resource type."""
        handlers = []
        handlers.extend(self._on_before_create_handlers.get("__global__", []))
        if resource_type != "*" and resource_type != "__global__":
            handlers.extend(self._on_before_create_handlers.get(resource_type, []))
        handlers.extend(self._on_before_create_handlers.get("*", []))
        return handlers
    
    def get_on_after_create_handlers(self, resource_type: str) -> List[Callable]:
        """Get on_after_create handlers for a specific resource type."""
        handlers = []
        # Global handlers (registered with None) execute first
        handlers.extend(self._on_after_create_handlers.get("__global__", []))
        # Specific handlers (registered with resource_type) execute next
        if resource_type != "*" and resource_type != "__global__":
            handlers.extend(self._on_after_create_handlers.get(resource_type, []))
        # Wildcard handlers (registered with "*") execute last
        handlers.extend(self._on_after_create_handlers.get("*", []))
        return handlers
    
    def get_on_before_update_handlers(self, resource_type: str) -> List[Callable]:
        """Get on_update handlers for a specific resource type."""
        handlers = []
        handlers.extend(self._on_before_update_handlers.get("__global__", []))
        if resource_type != "*" and resource_type != "__global__":
            handlers.extend(self._on_before_update_handlers.get(resource_type, []))
        handlers.extend(self._on_before_update_handlers.get("*", []))
        return handlers

    def get_on_after_update_handlers(self, resource_type: str) -> List[Callable]:
        """Get on_after_update handlers for a specific resource type."""
        handlers = []
        handlers.extend(self._on_after_update_handlers.get("__global__", []))
        if resource_type != "*" and resource_type != "__global__":
            handlers.extend(self._on_after_update_handlers.get(resource_type, []))
        handlers.extend(self._on_after_update_handlers.get("*", []))
        return handlers
    
    def get_on_before_delete_handlers(self, resource_type: str) -> List[Callable]:
        """Get on_delete handlers for a specific resource type."""
        handlers = []
        handlers.extend(self._on_before_delete_handlers.get("__global__", []))
        if resource_type != "*" and resource_type != "__global__":
            handlers.extend(self._on_before_delete_handlers.get(resource_type, []))
        handlers.extend(self._on_before_delete_handlers.get("*", []))
        return handlers

    def get_on_after_delete_handlers(self, resource_type: str) -> List[Callable]:
        """Get on_after_delete handlers for a specific resource type."""
        handlers = []
        handlers.extend(self._on_after_delete_handlers.get("__global__", []))
        if resource_type != "*" and resource_type != "__global__":
            handlers.extend(self._on_after_delete_handlers.get(resource_type, []))
        handlers.extend(self._on_after_delete_handlers.get("*", []))
        return handlers

    # ==================== OAuth Decorators ====================
    
    def oauth_set_instance(self, func: Callable) -> Callable:
        """
        Decorator for customizing OAuth token instance setup.
        
        Example:
            @fhir.oauth_set_instance
            def custom_set_instance(token_string, oauth_client, base_url, username):
                # Custom token setup logic
                pass
        """
        wrapped = self._wrap_with_arity_check(func, "oauth_set_instance", 4)
        self._oauth_set_instance_handlers.append(wrapped)
        return wrapped
    
    def oauth_get_introspection(self, func: Callable) -> Callable:
        """
        Decorator for customizing OAuth token introspection.
        
        Example:
            @fhir.oauth_get_introspection
            def custom_introspection():
                # Return JWT object from introspection
                return {"active": True, "scope": "patient/*.read"}
        """
        wrapped = self._wrap_with_arity_check(func, "oauth_get_introspection", 0)
        self._oauth_get_introspection_handlers.append(wrapped)
        return wrapped
    
    def oauth_get_user_info(self, func: Callable) -> Callable:
        """
        Decorator for deriving user information from OAuth token.
        
        Example:
            @fhir.oauth_get_user_info
            def extract_user_info(basic_auth_username, basic_auth_roles):
                # Return dict with user info
                return {"Username": "john_doe", "Roles": "doctor"}
        """
        wrapped = self._wrap_with_arity_check(func, "oauth_get_user_info", 2)
        self._oauth_get_user_info_handlers.append(wrapped)
        return wrapped
    
    def oauth_verify_resource_id(self, resource_type: str = "*") -> Callable:
        """
        Decorator for verifying OAuth access based on resource type and ID.
        
        Args:
            resource_type: FHIR resource type (e.g., "Patient") or "*" for all types
        
        Example:
            @fhir.oauth_verify_resource_id("Patient")
            def verify_patient_access(resource_type, resource_id, required_privilege):
                # Verify access, raise exception if denied
                if not has_access(resource_id):
                    raise PermissionError("Access denied")
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "oauth_verify_resource_id", 3)
            if resource_type not in self._oauth_verify_resource_id_handlers:
                self._oauth_verify_resource_id_handlers[resource_type] = []
            self._oauth_verify_resource_id_handlers[resource_type].append(wrapped)
            return wrapped
        return decorator
    
    def oauth_verify_resource_content(self, resource_type: str = "*") -> Callable:
        """
        Decorator for verifying OAuth access based on resource content.
        
        Args:
            resource_type: FHIR resource type (e.g., "Patient") or "*" for all types
        
        Example:
            @fhir.oauth_verify_resource_content("Patient")
            def verify_patient_content(resource_dict, required_privilege, allow_shared):
                # Verify access based on resource content
                if not check_security_labels(resource_dict):
                    raise PermissionError("Access denied")
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "oauth_verify_resource_content", 3)
            if resource_type not in self._oauth_verify_resource_content_handlers:
                self._oauth_verify_resource_content_handlers[resource_type] = []
            self._oauth_verify_resource_content_handlers[resource_type].append(wrapped)
            return wrapped
        return decorator
    
    def oauth_verify_history(self, resource_type: str = "*") -> Callable:
        """
        Decorator for verifying OAuth access for history-instance requests.
        
        Args:
            resource_type: FHIR resource type (e.g., "Patient") or "*" for all types
        
        Example:
            @fhir.oauth_verify_history("Patient")
            def verify_history_access(resource_type, resource_dict, required_privilege):
                # Verify access to history
                pass
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "oauth_verify_history", 3)
            if resource_type not in self._oauth_verify_history_handlers:
                self._oauth_verify_history_handlers[resource_type] = []
            self._oauth_verify_history_handlers[resource_type].append(wrapped)
            return wrapped
        return decorator
    
    def oauth_verify_delete(self, resource_type: str = "*") -> Callable:
        """
        Decorator for verifying OAuth access for delete requests.
        
        Args:
            resource_type: FHIR resource type (e.g., "Patient") or "*" for all types
        
        Example:
            @fhir.oauth_verify_delete("Patient")
            def verify_delete_access(resource_type, resource_id, required_privilege):
                # Verify delete permission
                if not can_delete(resource_id):
                    raise PermissionError("Cannot delete this resource")
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "oauth_verify_delete", 3)
            if resource_type not in self._oauth_verify_delete_handlers:
                self._oauth_verify_delete_handlers[resource_type] = []
            self._oauth_verify_delete_handlers[resource_type].append(wrapped)
            return wrapped
        return decorator
    
    def oauth_verify_search(self, resource_type: str = "*") -> Callable:
        """
        Decorator for verifying OAuth access for search requests.
        
        Args:
            resource_type: FHIR resource type (e.g., "Patient") or "*" for all types
        
        Example:
            @fhir.oauth_verify_search("Patient")
            def verify_search_access(resource_type, compartment_type, compartment_id, 
                                    parameters, required_privilege):
                # Verify search access
                pass
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "oauth_verify_search", 5)
            if resource_type not in self._oauth_verify_search_handlers:
                self._oauth_verify_search_handlers[resource_type] = []
            self._oauth_verify_search_handlers[resource_type].append(wrapped)
            return wrapped
        return decorator
    
    def oauth_verify_system_level(self, func: Callable) -> Callable:
        """
        Decorator for verifying OAuth access for system-level requests.
        
        Example:
            @fhir.oauth_verify_system_level
            def verify_system_access():
                # Verify system-level access
                if not is_admin():
                    raise PermissionError("System-level access denied")
        """
        wrapped = self._wrap_with_arity_check(func, "oauth_verify_system_level", 0)
        self._oauth_verify_system_level_handlers.append(wrapped)
        return wrapped
    
    # OAuth getter methods
    
    def get_oauth_set_instance_handlers(self) -> List[Callable]:
        """Get OAuth set_instance handlers."""
        return self._oauth_set_instance_handlers.copy()
    
    def get_oauth_get_introspection_handlers(self) -> List[Callable]:
        """Get OAuth get_introspection handlers."""
        return self._oauth_get_introspection_handlers.copy()
    
    def get_oauth_get_user_info_handlers(self) -> List[Callable]:
        """Get OAuth get_user_info handlers."""
        return self._oauth_get_user_info_handlers.copy()
    
    def get_oauth_verify_resource_id_handlers(self, resource_type: str) -> List[Callable]:
        """Get OAuth verify_resource_id handlers for a specific resource type."""
        handlers = []
        handlers.extend(self._oauth_verify_resource_id_handlers.get("*", []))
        handlers.extend(self._oauth_verify_resource_id_handlers.get(resource_type, []))
        return handlers
    
    def get_oauth_verify_resource_content_handlers(self, resource_type: str) -> List[Callable]:
        """Get OAuth verify_resource_content handlers for a specific resource type."""
        handlers = []
        handlers.extend(self._oauth_verify_resource_content_handlers.get("*", []))
        handlers.extend(self._oauth_verify_resource_content_handlers.get(resource_type, []))
        return handlers
    
    def get_oauth_verify_history_handlers(self, resource_type: str) -> List[Callable]:
        """Get OAuth verify_history handlers for a specific resource type."""
        handlers = []
        handlers.extend(self._oauth_verify_history_handlers.get("*", []))
        handlers.extend(self._oauth_verify_history_handlers.get(resource_type, []))
        return handlers
    
    def get_oauth_verify_delete_handlers(self, resource_type: str) -> List[Callable]:
        """Get OAuth verify_delete handlers for a specific resource type."""
        handlers = []
        handlers.extend(self._oauth_verify_delete_handlers.get("*", []))
        handlers.extend(self._oauth_verify_delete_handlers.get(resource_type, []))
        return handlers
    
    def get_oauth_verify_search_handlers(self, resource_type: str) -> List[Callable]:
        """Get OAuth verify_search handlers for a specific resource type."""
        handlers = []
        handlers.extend(self._oauth_verify_search_handlers.get("*", []))
        handlers.extend(self._oauth_verify_search_handlers.get(resource_type, []))
        return handlers
    
    def get_oauth_verify_system_level_handlers(self) -> List[Callable]:
        """Get OAuth verify_system_level handlers."""
        return self._oauth_verify_system_level_handlers.copy()
    
    
    # ==================== Validation Decorators ====================
    
    def on_validate_resource(self, resource_type: str = "*") -> Callable:
        """
        Decorator for custom resource validation.

        The handler may signal validation failures in two ways:

        1. **Raise an exception** (e.g. ``ValueError``) — the message is returned as a
           single FHIR OperationOutcome error issue.

        2. **Return an OperationOutcome dict** — the dict is parsed by the ObjectScript
           layer; every issue with ``severity == "error"`` becomes a 400 error.  Issues
           with other severities (warning, information) are silently ignored, allowing the
           handler to annotate results without blocking the request.

        Signature:
            def handler(resource: dict, is_in_transaction: bool) -> dict | None:

        Args:
            resource_type: FHIR resource type (e.g., "Patient") or "*" for all types

        Example — raise an exception::

            @fhir.on_validate_resource("Patient")
            def validate_patient(resource, is_in_transaction):
                if not resource.get("name"):
                    raise ValueError("Patient name is required")

        Example — return an OperationOutcome::

            @fhir.on_validate_resource("Patient")
            def validate_patient(resource, is_in_transaction):
                issues = []
                if not resource.get("identifier"):
                    issues.append({
                        "severity": "error",
                        "code": "required",
                        "details": {"text": "Patient must have at least one identifier"},
                        "expression": ["Patient.identifier"],
                    })
                if issues:
                    return {
                        "resourceType": "OperationOutcome",
                        "issue": issues,
                    }
        """
        def decorator(func: Callable) -> Callable:
            wrapped = self._wrap_with_arity_check(func, "on_validate_resource", 2)
            if resource_type not in self._validate_resource_handlers:
                self._validate_resource_handlers[resource_type] = []
            self._validate_resource_handlers[resource_type].append(wrapped)
            return wrapped
        return decorator
    
    def on_validate_bundle(self, func: Callable) -> Callable:
        """
        Decorator for custom bundle validation.

        The handler may signal validation failures in two ways:

        1. **Raise an exception** (e.g. ``ValueError``) — the message is returned as a
           single FHIR OperationOutcome error issue.

        2. **Return an OperationOutcome dict** — the dict is parsed by the ObjectScript
           layer; every issue with ``severity == "error"`` becomes a 400 error.

        Signature:
            def handler(bundle: dict, fhir_version: str) -> dict | None:

        Example — raise an exception::

            @fhir.on_validate_bundle
            def validate_bundle(bundle, fhir_version):
                if bundle.get("type") not in ["transaction", "batch"]:
                    raise ValueError("Invalid bundle type")

        Example — return an OperationOutcome::

            @fhir.on_validate_bundle
            def validate_bundle(bundle, fhir_version):
                issues = []
                if len(bundle.get("entry", [])) > 100:
                    issues.append({
                        "severity": "error",
                        "code": "too-costly",
                        "details": {"text": "Transaction bundle too large (max 100 entries)"},
                        "expression": ["Bundle.entry"],
                    })
                if issues:
                    return {
                        "resourceType": "OperationOutcome",
                        "issue": issues,
                    }
        """
        wrapped = self._wrap_with_arity_check(func, "on_validate_bundle", 2)
        self._validate_bundle_handlers.append(wrapped)
        return wrapped
    
    # Validation getter methods
    
    def get_on_validate_resource_handlers(self, resource_type: str) -> List[Callable]:
        """Get validate_resource handlers for a specific resource type."""
        handlers = []
        handlers.extend(self._validate_resource_handlers.get("*", []))
        handlers.extend(self._validate_resource_handlers.get(resource_type, []))
        return handlers
    
    def get_on_validate_bundle_handlers(self) -> List[Callable]:
        """Get validate_bundle handlers."""
        return self._validate_bundle_handlers.copy()

# Global registry instance
fhir = FhirDecorators()

def dynamic_object_from_json(data: str) -> Any:
    try:
        import iris
    except Exception as exc:
        raise RuntimeError("iris is not available") from exc
    return iris.cls("%DynamicObject")._FromJSON(data)


# Export for convenience
__all__ = ['fhir', 'FhirDecorators']
