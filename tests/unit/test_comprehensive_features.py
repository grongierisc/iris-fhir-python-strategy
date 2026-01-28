
import pytest
from src.python.fhir_decorators import FhirDecorators, fhir

class TestComprehensiveFeatures:
    
    @pytest.fixture(autouse=True)
    def setup_registry(self):
        """Reset the global registry before each test."""
        # We need to recreate the registry or clear it
        # Since 'fhir' is a global instance in the module, we can clear its internal lists/dicts
        fhir._capability_statement_handlers = []
        fhir._before_request_handlers = []
        fhir._after_request_handlers = []
        fhir._post_process_read_handlers = {}
        fhir._post_process_search_handlers = {}
        fhir._consent_handlers = {}
        fhir._operations = {}
        fhir._on_create_handlers = {}
        fhir._on_update_handlers = {}
        fhir._on_delete_handlers = {}
        fhir._oauth_set_instance_handlers = []
        fhir._validate_resource_handlers = {}
        # ... clear other oauth/validation if needed
        return fhir

    def test_capability_statement_registration(self):
        @fhir.on_capability_statement
        def my_cap_handler(cs): return cs
        
        handlers = fhir.get_capability_statement_handlers()
        assert len(handlers) == 1
        assert handlers[0] == my_cap_handler

    def test_request_hooks_registration(self):
        @fhir.before_request
        def pre_req(fs, fr, b, t): pass
        
        @fhir.after_request
        def post_req(fs, fr, fres, b): pass
        
        assert len(fhir.get_before_request_handlers()) == 1
        assert len(fhir.get_after_request_handlers()) == 1

    def test_crud_hooks_registration_specific(self):
        @fhir.on_create("Patient")
        def create_patient(*args): pass
        
        @fhir.on_update("Observation")
        def update_observation(*args): pass
        
        @fhir.on_delete("Patient")
        def delete_patient(*args): pass
        
        # Test Create
        patient_create = fhir.get_create_handlers("Patient")
        obs_create = fhir.get_create_handlers("Observation")
        assert len(patient_create) == 1
        assert len(obs_create) == 0 # specific
        
        # Test Update
        assert len(fhir.get_update_handlers("Observation")) == 1
        
        # Test Delete
        delete_handlers = fhir.get_delete_handlers("Patient")
        assert len(delete_handlers) == 1

    def test_crud_hooks_wildcard(self):
        @fhir.on_create() # Defaults to *
        def create_any(*args): pass
        
        # Should appear for Patient AND generic
        # The implementation of get_on_create_handlers usually requires checking how it filters
        # Let's assume the registry stores it under "*"
        
        handlers = fhir._on_create_handlers.get("*")
        assert len(handlers) == 1
        
        # Depending on implementation of get_handlers(type), it might return * + specific or just specific
        # We should verify implementation behavior. Usually it returns both.
        
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
        @fhir.on_read("Patient")
        def read_pt(*args): pass
        
        @fhir.on_search("Patient")
        def search_pt(*args): pass
        
        @fhir.consent("Patient")
        def consent_pt(*args): pass
        
        assert len(fhir.get_post_process_read_handlers("Patient")) == 1
        assert len(fhir.get_post_process_search_handlers("Patient")) == 1
        assert len(fhir.get_consent_handlers("Patient")) == 1

    def test_validation_handlers(self):
        @fhir.validate_resource("Patient")
        def validate_pt(res): pass
        
        handlers = fhir.get_validate_resource_handlers("Patient")
        assert len(handlers) == 1
        assert handlers[0] == validate_pt
        
        # Check fallback/wildcard if supported (Registry usually treats * separate)
        assert len(fhir.get_validate_resource_handlers("Other")) == 0

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

