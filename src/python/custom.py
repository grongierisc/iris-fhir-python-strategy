from FhirInteraction import Interaction, Strategy

class CustomStrategy(Strategy):
    
    def on_get_capability_statement(self, capability_statement):
        # Example : del all resources except Patient
        # capability_statement['rest'][0]['resource'] = [resource for resource in capability_statement['rest'][0]['resource'] if resource['type'] == 'Patient']
        # if so is done, the fhir server will only support Patient resource
        return capability_statement

class CustomInteraction(Interaction):

    def on_before_request(self, fhir_service, fhir_request, body, timeout):
        pass

    def on_after_request(self, fhir_service, fhir_request, fhir_response, body):
        pass

    def post_process_read(self, fhir_object):
        return False

    def post_process_search(self, rs, resource_type):
        return True
    
def set_capability_statement():
    from FhirInteraction import Utils
    utils = Utils()
    utils.update_capability_statement("/fhir/r4")