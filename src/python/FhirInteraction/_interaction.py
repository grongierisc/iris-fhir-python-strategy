import abc
import iris

class Interaction(object):
    __metaclass__ = abc.ABCMeta

    @abc.abstractmethod
    def on_before_request(self, 
                          fhir_service:'iris.HS.FHIRServer.API.Service',
                          fhir_request:'iris.HS.FHIRServer.API.Data.Request',
                          body:dict,
                          timeout:int):
        """
        on_before_request is called before the request is sent to the server.
        param fhir_service: the fhir service object iris.HS.FHIRServer.API.Service
        param fhir_request: the fhir request object iris.FHIRServer.API.Data.Request
        param timeout: the timeout in seconds
        return: None
        """
        

    @abc.abstractmethod
    def on_after_request(self,
                         fhir_service:'iris.HS.FHIRServer.API.Service',
                         fhir_request:'iris.HS.FHIRServer.API.Data.Request',
                         fhir_response:'iris.HS.FHIRServer.API.Data.Response',
                         body:dict):
        """
        on_after_request is called after the request is sent to the server.
        param fhir_service: the fhir service object iris.HS.FHIRServer.API.Service
        param fhir_request: the fhir request object iris.FHIRServer.API.Data.Request
        param fhir_response: the fhir response object iris.FHIRServer.API.Data.Response
        return: None
        """
        

    @abc.abstractmethod
    def post_process_read(self,
                          fhir_object:dict) -> bool:
        """
        post_process_read is called after the read operation is done.
        param fhir_object: the fhir object
        return: True the resource should be returned to the client, False otherwise
        """
        

    @abc.abstractmethod
    def post_process_search(self,
                            rs:'iris.HS.FHIRServer.Util.SearchResult',
                            resource_type:str):
        """
        post_process_search is called after the search operation is done.
        param rs: the search result iris.HS.FHIRServer.Util.SearchResult
        param resource_type: the resource type
        return: None
        """
        
