
import pytest
from src.python.iris_fhir_python_strategy import FhirDecorators, fhir

class TestComprehensiveFeatures:
    
    @pytest.fixture(autouse=True)
    def setup_registry(self):
        """Reset the global registry before each test."""
        # Reset internal lists/dicts
        fhir._capability_statement_handlers = []
        fhir._on_before_request_handlers = []
        fhir._on_after_request_handlers = []
        
        fhir._on_before_create_handlers = {}
        fhir._on_before_read_handlers = {}
        fhir._on_before_update_handlers = {}
        fhir._on_before_delete_handlers = {}
        fhir._on_before_search_handlers = {}

        fhir._on_after_create_handlers = {}
        fhir._on_after_read_handlers = {}
        fhir._on_after_update_handlers = {}
        fhir._on_after_delete_handlers = {}
        fhir._on_after_search_handlers = {}
        
        fhir._consent_handlers = {}
        fhir._operations = {}
        
        fhir._oauth_set_instance_handlers = []
        # Reset specific oauth lists if needed, but this is a broad reset
        
        fhir._validate_resource_handlers = {}
        fhir._validate_bundle_handlers = []
        return fhir

    def test_capability_statement_registration(self):
        @fhir.on_capability_statement
        def my_cap_handler(cs): return cs
        
        handlers = fhir.get_capability_statement_handlers()
        assert len(handlers) == 1
        assert handlers[0] == my_cap_handler

    def test_request_hooks_registration(self):
        @fhir.on_before_request
        def pre_req(fs, fr, b, t): pass
        
        @fhir.on_after_request
        def post_req(fs, fr, fres, b): pass
        
        assert len(fhir.get_on_before_request_handlers()) == 1
        assert len(fhir.get_on_after_request_handlers()) == 1

    def test_crud_hooks_registration_specific(self):
        @fhir.on_before_create("Patient")
        def create_patient(*args): pass
        
        @fhir.on_before_update("Observation")
        def update_observation(*args): pass
        
        @fhir.on_before_delete("Patient")
        def delete_patient(*args): pass
        
        # Test Create
        patient_create = fhir.get_on_before_create_handlers("Patient")
        obs_create = fhir.get_on_before_create_handlers("Observation")
        assert len(patient_create) == 1
        assert len(obs_create) == 0 # specific
        
        # Test Update
        assert len(fhir.get_on_before_update_handlers("Observation")) == 1
        
        # Test Delete
        delete_handlers = fhir.get_on_before_delete_handlers("Patient")
        assert len(delete_handlers) == 1

    def test_crud_hooks_wildcard(self):
        @fhir.on_before_create("*") # Explicit Wildcard
        def create_wildcard(*args): pass
        
        @fhir.on_before_create() # Global
        def create_global(*args): pass
        
        # Test generic retrieval
        handlers = fhir.get_on_before_create_handlers("Patient")
        # Ordering: Global, Specific (none here), Wildcard
        assert len(handlers) == 2
        assert handlers[0] == create_global
        assert handlers[1] == create_wildcard

    def test_operations_registration(self):
        @fhir.operation("my-op", scope="System")
        def sys_op(*args): pass
        
        @fhir.operation("my-type-op", scope="Type", resource_type="Patient")
        def type_op(*args): pass
        
        @fhir.operation("my-inst-op", scope="Instance", resource_type="Patient")
        def inst_op(*args): pass
        
        # Check retrieval
        h1 = fhir.get_operation_handler("my-op", "System")
        assert h1 == sys_op
        
        h2 = fhir.get_operation_handler("my-type-op", "Type", "Patient")
        assert h2 == type_op
        
        # mismatched type
        h3 = fhir.get_operation_handler("my-type-op", "Type", "Observation")
        assert h3 is None

    def test_read_search_consent_hooks(self):
        @fhir.on_after_read("Patient")
        def read_pt(*args): pass
        
        @fhir.on_after_search("Patient")
        def search_pt(*args): pass
        
        @fhir.consent("Patient")
        def consent_pt(*args): pass
        
        assert len(fhir.get_on_after_read_handlers("Patient")) == 1
        assert len(fhir.get_on_after_search_handlers("Patient")) == 1
        assert len(fhir.get_consent_handlers("Patient")) == 1

    def test_validation_handlers(self):
        @fhir.on_validate_resource("Patient")
        def validate_pt(res): pass
        
        handlers = fhir.get_on_validate_resource_handlers("Patient")
        assert len(handlers) == 1
        assert handlers[0] == validate_pt
        
        # Check fallback/wildcard if supported (Registry usually treats * separate)
        assert len(fhir.get_on_validate_resource_handlers("Other")) == 0

    def test_oauth_handlers(self):
        @fhir.oauth_set_instance
        def oauth_check(*args): pass
        
        # Based on file inspection, oauth_set_instance might store to _oauth_set_instance_handlers list or dict
        # Looking at __init__: self._oauth_set_instance_handlers = []
        # So it might apply to all? Or the decorator args logic is different.
        # Let's inspect source if needed, but assuming standard registration
        handlers = fhir.get_oauth_set_instance_handlers()
        assert len(handlers) == 1
        assert handlers[0] == oauth_check

    def test_multiple_handlers_execution_order(self):
        execution_order = []
        
        @fhir.on_before_create("Patient")
        def handler_one(*args):
            execution_order.append(1)
            
        @fhir.on_before_create("Patient")
        def handler_two(*args):
            execution_order.append(2)
            
        handlers = fhir.get_on_before_create_handlers("Patient")
        assert len(handlers) == 2
        
        # Simulate execution
        for h in handlers:
            h()
            
        assert execution_order == [1, 2]

    def test_wildcard_mixed_with_specific(self):
        @fhir.on_before_update() # Global
        def global_handler(*args): pass
        
        @fhir.on_before_update("Patient") # Specific
        def specific_handler(*args): pass
        
        # Getting Patient handlers
        updated_handlers = fhir.get_on_before_update_handlers("Patient")
        assert len(updated_handlers) == 2
        # Order: Global then Specific
        assert updated_handlers == [global_handler, specific_handler]
        
        # Getting Observation handlers should only return global
        obs_handlers = fhir.get_on_before_update_handlers("Observation")
        assert len(obs_handlers) == 1
        assert obs_handlers == [global_handler]

