import abc

class OperationHandler(object):

    @abc.abstractmethod
    def add_supported_operations(self,map:dict) -> dict:
        """
        @API Enumerate the name and url of each Operation supported by this class
        @Output map : A map of operation names to their corresponding URL.
        Example:
        return map.put("restart","http://hl7.org/fhir/OperationDefinition/System-restart")
        """

    @abc.abstractmethod
    def process_operation(
        self,
        operation_name:str,
        operation_scope:str,
        body:dict,
        fhir_service:'iris.HS.FHIRServer.API.Service',
        fhir_request:'iris.HS.FHIRServer.API.Data.Request',
        fhir_response:'iris.HS.FHIRServer.API.Data.Response'
    ) -> 'iris.HS.FHIRServer.API.Data.Response':
        """
        @API Process an Operation request.
        @Input operation_name : The name of the Operation to process.
        @Input operation_scope : The scope of the Operation to process.
        @Input fhir_service : The FHIR Service object.
        @Input fhir_request : The FHIR Request object.
        @Input fhir_response : The FHIR Response object.
        @Output : The FHIR Response object.
        """
