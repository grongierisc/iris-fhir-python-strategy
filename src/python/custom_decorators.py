"""
FHIR Server Customization using Decorators.

This module demonstrates how to use decorators to customize FHIR server behavior.
Simply import fhir and decorate your functions.
"""

from fhir_decorators import fhir
import jwt
import iris
from deepdiff import DeepDiff
import json

# ==================== State Management ====================
# Use a simple class to manage request-scoped state
class RequestContext:
    """Stores request-scoped data."""
    def __init__(self):
        self.requesting_user = ""
        self.requesting_roles = ""
        self.scope_list = []
        self.security_list = []
        self.interactions = None  # Will be set by ObjectScript

# Global context (will be set per request)
context = RequestContext()


# ==================== Capability Statement ====================

@fhir.on_capability_statement
def customize_capability_statement(capability_statement):
    """
    Remove Account resource from capability statement.
    """
    capability_statement['rest'][0]['resource'] = [
        resource for resource in capability_statement['rest'][0]['resource'] 
        if resource['type'] != 'Account'
    ]
    return capability_statement


# ==================== Request/Response Hooks ====================

@fhir.before_request
def extract_user_context(fhir_service, fhir_request, body, timeout):
    """
    Extract user and roles for consent evaluation.
    """
    context.requesting_user = fhir_request.Username
    context.requesting_roles = fhir_request.Roles
    context.scope_list = []
    context.security_list = []
    
    # Uncomment to extract OAuth token scopes
    # token = fhir_request.AdditionalInfo.GetAt("USER:OAuthToken") or ""
    # if token:
    #     decoded_token = jwt.decode(token, options={"verify_signature": False})
    #     context.scope_list = decoded_token.get("scope", "").split(" ")
    #     for scope in context.scope_list:
    #         context.security_list += get_security(scope)


@fhir.after_request
def cleanup_context(fhir_service, fhir_request, fhir_response, body):
    """
    Clear request-scoped state.
    """
    context.requesting_user = ""
    context.requesting_roles = ""
    context.scope_list = []
    context.security_list = []


# ==================== Read/Search Processing ====================

@fhir.on_read("Patient")
def filter_patient_read(fhir_object):
    """
    Apply consent rules to Patient reads.
    Return False to hide the resource (returns 404).
    """
    # Uncomment to enable consent checking
    # return check_consent(fhir_object)
    return True


@fhir.on_read()  # All resource types
def log_all_reads(fhir_object):
    """
    Log all read operations.
    """
    # print(f"Reading {fhir_object.get('resourceType')} with ID {fhir_object.get('id')}")
    return True


@fhir.on_search("Patient")
def filter_patient_search(rs, resource_type):
    """
    Filter Patient search results based on consent.
    """
    # Uncomment to enable consent filtering
    # rs._SetIterator(0)
    # while rs._Next():
    #     resource_id = rs._Get("ResourceId")
    #     version_id = rs._Get("VersionId")
    #     json_str = context.interactions.Read(resource_type, resource_id, version_id)._ToJSON()
    #     resource_dict = json.loads(json_str)
    #     if not check_consent(resource_dict):
    #         rs.MarkAsDeleted()
    #         rs._SaveRow()
    pass


# ==================== Consent Rules ====================

@fhir.consent("Patient")
def patient_consent_rules(fhir_object, user_context):
    """
    Check if user has consent to access Patient resource.
    """
    if "meta" in fhir_object:
        if "security" in fhir_object["meta"]:
            for security in fhir_object["meta"]["security"]:
                if security.get("code") in context.security_list:
                    return False
    return True


# ==================== CRUD Operations ====================

@fhir.on_create("Patient")
def validate_patient_creation(fhir_service, fhir_request, body, timeout):
    """
    Validate Patient resource before creation.
    """
    # Add custom validation logic here
    pass


@fhir.on_update("Patient")
def audit_patient_update(fhir_service, fhir_request, body, timeout):
    """
    Audit Patient updates.
    """
    # Log patient updates for compliance
    pass


# ==================== Custom Operations ====================

@fhir.operation("diff", scope="Instance", resource_type="Patient")
def patient_diff_operation(operation_name, operation_scope, body,
                          fhir_service, fhir_request, fhir_response):
    """
    Custom $diff operation to compare two Patient resources.
    """
    # Get the primary resource
    primary_resource = json.loads(
        fhir_service.interactions.Read(
            fhir_request.Type, 
            fhir_request.Id
        )._ToJSON()
    )
    
    # Get the secondary resource from request body
    secondary_resource = json.loads(fhir_request.Json._ToJSON())
    
    # Calculate diff using deepdiff
    diff = DeepDiff(primary_resource, secondary_resource, ignore_order=True).to_json()
    
    # Create response
    result = iris.cls('%DynamicObject')._FromJSON(diff)
    fhir_response.Json = result
    
    return fhir_response


@fhir.operation("validate", scope="Type", resource_type="Patient")
def validate_patient_operation(operation_name, operation_scope, body,
                               fhir_service, fhir_request, fhir_response):
    """
    Custom $validate operation for Patient resources.
    """
    # Use FhirValidateOperation for validation
    from FhirInteraction import FhirValidateOperation
    validator = FhirValidateOperation()
    return validator.process_validate_operation(
        operation_name,
        operation_scope,
        body,
        fhir_service,
        fhir_request,
        fhir_response
    )


# ==================== Helper Functions ====================

def get_security(scope):
    """Extract security labels from Permission resources."""
    security = []
    try:
        permission = context.interactions.Read("Permission", scope)._ToJSON()
        permission_dict = json.loads(permission)
        for rule in permission_dict.get("rule", []):
            for data in rule.get("data", []):
                for sec in data.get("security", []):
                    security.append(sec.get("code"))
    except Exception:
        pass
    return security


def check_consent(resource_dict):
    """
    Check if user has consent to access resource.
    Returns False if access should be denied.
    """
    if "meta" in resource_dict:
        if "security" in resource_dict["meta"]:
            for security in resource_dict["meta"]["security"]:
                if security.get("code") in context.security_list:
                    return False
    return True


# ==================== OAuth Decorators ====================

@fhir.oauth_set_instance
def setup_oauth_token(token_string, oauth_client, base_url, username):
    """Setup OAuth token instance."""
    context.token_string = token_string
    context.oauth_client = oauth_client
    context.base_url = base_url
    context.username = username
    print(f"OAuth token set for user: {username}")


@fhir.oauth_get_introspection
def get_token_introspection():
    """
    Get OAuth token introspection.
    Returns JWT object from introspection call.
    """
    # Example: Call your OAuth server's introspection endpoint
    # In real implementation, make HTTP request to introspection endpoint
    return {
        "active": True,
        "scope": "patient/*.read patient/*.write",
        "client_id": context.oauth_client,
        "username": context.username,
        "token_type": "Bearer"
    }


@fhir.oauth_get_user_info
def extract_user_info(basic_auth_username, basic_auth_roles):
    """
    Extract user information from OAuth token.
    Returns dict with user info.
    """
    # Example: Extract from token or call user info endpoint
    return {
        "Username": context.username or basic_auth_username,
        "Roles": "doctor,admin",
        "Department": "Cardiology"
    }


@fhir.oauth_verify_resource_id("Patient")
def verify_patient_access_by_id(resource_type, resource_id, required_privilege):
    """
    Verify OAuth access to a Patient by ID.
    Raises exception if access denied.
    """
    # Example: Check if user has access to this specific patient
    # In real implementation, check patient compartment or ownership
    print(f"Verifying {required_privilege} access to {resource_type}/{resource_id}")
    
    # Example check
    if resource_id == "restricted-patient-123":
        raise PermissionError(f"Access denied to Patient/{resource_id}")


@fhir.oauth_verify_resource_content("Patient")
def verify_patient_content_access(resource_dict, required_privilege, allow_shared):
    """
    Verify OAuth access based on Patient resource content.
    Checks security labels, patient compartment, etc.
    """
    # Example: Check security labels
    if "meta" in resource_dict:
        security = resource_dict["meta"].get("security", [])
        for label in security:
            if label.get("code") == "R":  # Restricted
                # Check if user has clearance for restricted data
                if not has_clearance_for_restricted():
                    raise PermissionError("Insufficient clearance for restricted Patient data")


@fhir.oauth_verify_delete("Patient")
def verify_patient_deletion(resource_type, resource_id, required_privilege):
    """
    Verify OAuth access for Patient deletion.
    """
    # Example: Only admins can delete patients
    if "admin" not in context.roles.lower():
        raise PermissionError("Only administrators can delete Patient resources")


@fhir.oauth_verify_search("Patient")
def verify_patient_search(resource_type, compartment_type, compartment_id, 
                          parameters, required_privilege):
    """
    Verify OAuth access for Patient searches.
    Can restrict search parameters or compartments.
    """
    # Example: Ensure user can only search within their compartment
    if compartment_type and compartment_type != "Patient":
        # Verify user has access to this compartment
        pass
    
    print(f"Verifying search access: {resource_type} in {compartment_type}/{compartment_id}")


@fhir.oauth_verify_system_level
def verify_system_access():
    """
    Verify OAuth access for system-level operations.
    System-level operations require special privileges.
    """
    # Example: Only system administrators can perform system-level operations
    if "system-admin" not in context.roles.lower():
        raise PermissionError("System-level operations require system-admin role")


# ==================== Validation Decorators ====================

@fhir.validate_resource("*")
def generic_resource_validation(resource_object, is_in_transaction=False):
    """
    Generic resource validation for all resource types.
    Raises exception if validation fails.
    """
    # Example: Ensure resource has an ID
    if "id" not in resource_object:
        raise ValueError("Resource must have an 'id' field")

@fhir.validate_resource("Patient")
def validate_patient_resource(resource_object, is_in_transaction=False):
    """
    Custom validation for Patient resources.
    Raises exception if validation fails.
    """
    # Example: Ensure Patient has required fields beyond FHIR spec
    if not resource_object.get("name"):
        raise ValueError("Patient must have at least one name")
    
    # Check for custom business rules
    if resource_object.get("active") is None:
        raise ValueError("Patient active status must be explicitly set")
    
    # Validate custom identifier system
    if "identifier" in resource_object:
        for identifier in resource_object["identifier"]:
            if identifier.get("system") == "http://hospital.org/mrn":
                # Validate MRN format
                value = identifier.get("value", "")
                if not value.startswith("MRN-"):
                    raise ValueError("Hospital MRN must start with 'MRN-'")


@fhir.validate_resource("Observation")
def validate_observation_resource(resource_object, is_in_transaction=False):
    """
    Custom validation for Observation resources.
    """
    # Example: Ensure critical observations have comments
    if "code" in resource_object:
        coding = resource_object["code"].get("coding", [])
        for code in coding:
            if code.get("code") in ["critical-001", "critical-002"]:
                if "note" not in resource_object:
                    raise ValueError("Critical observations must include a note")


@fhir.validate_bundle
def validate_transaction_bundle(resource_object, fhir_version):
    """
    Custom validation for Bundle resources.
    """
    # Example: Enforce business rules on transaction bundles
    if resource_object.get("type") == "transaction":
        entries = resource_object.get("entry", [])
        
        # Example: Limit transaction size
        if len(entries) > 100:
            raise ValueError("Transaction bundles cannot exceed 100 entries")
        
        # Example: Ensure all entries have proper request methods
        for entry in entries:
            if "request" not in entry:
                raise ValueError("Transaction bundle entries must have a request")
            
            request = entry["request"]
            if request.get("method") not in ["GET", "POST", "PUT", "DELETE", "PATCH"]:
                raise ValueError(f"Invalid HTTP method: {request.get('method')}")


