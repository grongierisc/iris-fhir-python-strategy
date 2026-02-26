
import pytest
import sys
from unittest.mock import MagicMock, patch
from iris_fhir_python_strategy import fhir
from iris_fhir_python_strategy import dynamic_object_from_json

class TestCoverageGap:
    
    def teardown_method(self):
        # Clean up registry
        fhir._on_before_read_handlers = {}
        fhir._on_before_search_handlers = {}

    def test_on_before_read_registration(self):
        @fhir.on_before_read("Patient")
        def pre_read_patient(fs, fr, b, t): pass
        
        @fhir.on_before_read() # wildcard
        def pre_read_any(fs, fr, b, t): pass
        
        handlers_pt = fhir.get_on_before_read_handlers("Patient")
        assert len(handlers_pt) == 2 # 1 specific + 1 wildcard
        assert pre_read_patient in handlers_pt
        assert pre_read_any in handlers_pt
        
        handlers_obs = fhir.get_on_before_read_handlers("Observation")
        assert len(handlers_obs) == 1 # only wildcard
        assert pre_read_any in handlers_obs

    def test_on_before_search_registration(self):
        @fhir.on_before_search("Patient")
        def pre_search_patient(fs, fr, b, t): pass
        
        @fhir.on_before_search() # wildcard
        def pre_search_any(fs, fr, b, t): pass
        
        handlers_pt = fhir.get_on_before_search_handlers("Patient")
        assert len(handlers_pt) == 2
        assert pre_search_patient in handlers_pt
        
        handlers_obs = fhir.get_on_before_search_handlers("Observation")
        assert len(handlers_obs) == 1

    def test_iris_adapter_success(self):
        # Mock iris module
        mock_iris = MagicMock()
        mock_dynamic_object = MagicMock()
        mock_iris.cls.return_value = mock_dynamic_object
        
        with patch.dict(sys.modules, {'iris': mock_iris}):
            data = {"foo": "bar"}
            dynamic_object_from_json(data)
            
            mock_iris.cls.assert_called_with("%DynamicObject")
            mock_dynamic_object._FromJSON.assert_called_with(data)

    def test_iris_adapter_failure_no_iris(self):
        # Force ImportError for 'iris'
        import builtins
        real_import = builtins.__import__

        def side_effect(name, globals=None, locals=None, fromlist=(), level=0):
            if name == 'iris':
                raise ImportError("No module named iris")
            return real_import(name, globals, locals, fromlist, level)

        with patch('builtins.__import__', side_effect=side_effect):
            with pytest.raises(RuntimeError) as excinfo:
                dynamic_object_from_json("{}")
            
            assert "iris is not available" in str(excinfo.value)
