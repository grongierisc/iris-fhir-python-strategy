from FhirInteraction import Interaction, Strategy, OAuthInteraction, OperationHandler

from google.oauth2 import id_token
from google.auth.transport import requests

import requests as rq

import iris

import time

from deepdiff import DeepDiff

import os
import json

# The following is an example of a custom OAuthInteraction class that
class CustomOAuthInteraction(OAuthInteraction):
    
    client_id = None
    last_time_verified = None
    time_interval = 5

    def clear_instance(self):
        self.token_string = None
        self.oauth_client = None
        self.base_url = None
        self.username = None
        self.token_obj = None
        self.scopes = None
        self.verify_search_results = None

    def set_instance(self, token:str,oauth_client:str,base_url:str,username:str):

        self.clear_instance()

        if not token or not oauth_client:
            # the token or oauth client is not set, skip the verification
            return

        global_time = iris.gref('^FHIR.OAuth2.Time')
        if global_time[token[0:50]]:
            self.last_time_verified = global_time[token[0:50]]

        if self.last_time_verified and (time.time() - float(self.last_time_verified)) < self.time_interval:
            # the token was verified less than 5 seconds ago, skip the verification
            return

        self.token_string = token
        self.oauth_client = oauth_client
        self.base_url = base_url
        self.username = username

        # try to set the client id
        try:
            # first get the var env GOOGLE_CLIENT_ID is not set then None
            self.client_id = os.environ.get('GOOGLE_CLIENT_ID')
            # if not set, then by the secret.json file
            if not self.client_id:
                with open(os.environ.get('ISC_OAUTH_SECRET_PATH'),encoding='utf-8') as f:
                    data = json.load(f)
                    self.client_id = data['web']['client_id']
        except FileNotFoundError:
            pass

        try:
            self.verify_token(token)
        except Exception as e:
            self.clear_instance()
            raise e
        # token is valid, set the last time verified to now
        global_time[token[0:50]]=str(time.time())

    def verify_token(self,token:str):
        # check if the token is an access token or an id token
        if token.startswith('ya29.'):
            self.verify_access_token(token)
        else:
            self.verify_id_token(token)

    def verify_access_token(self,token:str):
        # verify the access token is valid
        # get with a timeout of 5 seconds
        response = rq.get(f"https://www.googleapis.com/oauth2/v3/tokeninfo?access_token={token}",timeout=5)
        try:
            response.raise_for_status()
        except rq.exceptions.HTTPError as e:
            # the token is not valid
            raise e

    def verify_id_token(self,token:str):
        # Verify the token and get the user info
        self.token_obj = id_token.verify_oauth2_token(token, requests.Request(), self.client_id)
        if self.token_obj['iss'] not in ['accounts.google.com', 'https://accounts.google.com']:
            raise ValueError('Wrong issuer.')

    def get_introspection(self)->dict:
        return {}
    
    def get_user_info(self,basic_auth_username:str,basic_auth_roles:str)->dict:
        # try to get the user info from the token
        return {"Username":self.username,"Roles":basic_auth_roles}
    
    def verify_resource_id_request(self,resource_type:str,resource_id:str,required_privilege:str):
        pass

    def verify_resource_content(self,resource_dict:dict,required_privilege:str,allow_shared_resource:bool):
        pass

    def verify_history_instance_response(self,resource_type:str,resource_dict:dict,required_privilege:str):
        pass

    def verify_delete_request(self,resource_type:str,resource_id:str,required_privilege:str):
        pass

    def verify_search_request(self,
                              resource_type:str,
                              compartment_resource_type:str,
                              compartment_resource_id:str,
                              parameters:'iris.HS.FHIRServer.API.Data.QueryParameters',
                              required_privilege:str):
            pass
    
    def verify_system_level_request(self):
        pass

class CustomStrategy(Strategy):
    
    def on_get_capability_statement(self, capability_statement):
        # Example : del resources Account
        capability_statement['rest'][0]['resource'] = [resource for resource in capability_statement['rest'][0]['resource'] if resource['type'] != 'Account']
        return capability_statement

class CustomInteraction(Interaction):

    def on_before_request(self, fhir_service, fhir_request, body, timeout):
        #Extract the user and roles for this request
        #so consent can be evaluated.
        self.requesting_user = fhir_request.Username
        self.requesting_roles = fhir_request.Roles

    def on_after_request(self, fhir_service, fhir_request, fhir_response, body):
        #Clear the user and roles between requests.
        self.requesting_user = ""
        self.requesting_roles = ""

    def post_process_read(self, fhir_object):
        #Evaluate consent based on the resource and user/roles.
        #Returning 0 indicates this resource shouldn't be displayed - a 404 Not Found
        #will be returned to the user.
        return self.consent(fhir_object['resourceType'],
                        self.requesting_user,
                        self.requesting_roles)

    def post_process_search(self, rs, resource_type):
        #Iterate through each resource in the search set and evaluate
        #consent based on the resource and user/roles.
        #Each row marked as deleted and saved will be excluded from the Bundle.
        rs._SetIterator(0)
        while rs._Next():
            if not self.consent(rs.ResourceType,
                            self.requesting_user,
                            self.requesting_roles):
                #Mark the row as deleted and save it.
                rs.MarkAsDeleted()
                rs._SaveRow()

    def consent(self, resource_type, user, roles):
        #Example consent logic - only allow users with the role '%All' to see
        #Observation resources.
        if resource_type == 'Observation':
            if '%All' in roles:
                return True
            else:
                return False
        else:
            return True
        
class CustomOperationHandler(OperationHandler):
    
        def add_supported_operations(self,map:dict) -> dict:
            """
            @API Enumerate the name and url of each Operation supported by this class
            @Output map : A map of operation names to their corresponding URL.
            Example:
            return map.put("restart","http://hl7.org/fhir/OperationDefinition/System-restart")
            """

            # verify the map has attribute resource 
            if not 'resource' in map:
                map['resource'] = {}
            # verify the map has attribute patient in the resource
            if not 'Patient' in map['resource']:
                map['resource']['Patient'] = []
            # add the operation to the map
            map['resource']['Patient'].append({"name": "merge" , "definition": "http://hl7.org/fhir/OperationDefinition/Patient-merge"})

            return map
    
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
            if operation_name == "merge" and operation_scope == "Instance" and fhir_request.RequestMethod == "POST":
                # get the primary resource
                primary_resource = json.loads(fhir_service.interactions.Read(fhir_request.Type, fhir_request.Id)._ToJSON())
                # get the secondary resource
                secondary_resource = json.loads(fhir_request.Json._ToJSON())
                # retun the diff of the two resources
                # make use of deepdiff to get the difference between the two resources
                diff = DeepDiff(primary_resource, secondary_resource, ignore_order=True).to_json()

                # create a new %DynamicObject to store the result
                result = iris.cls('%DynamicObject')._FromJSON(diff)

                # set the result to the response
                fhir_response.Json = result
            
            return fhir_response

def set_capability_statement():
    from FhirInteraction import Utils
    utils = Utils()
    utils.update_capability_statement("/fhir/r4")

if __name__ == '__main__':
    custom_oauth_interaction = CustomOAuthInteraction()
    custom_oauth_interaction.set_instance("eyJhbGciOiJSUzI1NiIsImtpZCI6ImEzYmRiZmRlZGUzYmFiYjI2NTFhZmNhMjY3OGRkZThjMGIzNWRmNzYiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJhY2NvdW50cy5nb29nbGUuY29tIiwiYXpwIjoiNTc3NjgzODIwMjU5LW5xN2FmbTZicGJuNWhjZnVlMWQ4aTFsMWdtbzFrcG0xLmFwcHMuZ29vZ2xldXNlcmNvbnRlbnQuY29tIiwiYXVkIjoiNTc3NjgzODIwMjU5LW5xN2FmbTZicGJuNWhjZnVlMWQ4aTFsMWdtbzFrcG0xLmFwcHMuZ29vZ2xldXNlcmNvbnRlbnQuY29tIiwic3ViIjoiMTAxOTE3MDk4MTQzOTgyOTg1NzI3IiwiYXRfaGFzaCI6IlJMXzNfV2FicFFoaGNXcnZodnVhUUEiLCJpYXQiOjE2OTAzNzIwOTYsImV4cCI6MTY5MDM3NTY5Nn0.OlV24r-44CV3v5Z_FcOr3Xh1-IOMgWTSnINceTiKpk0CrQIQDZZMPpVnfggyy5DVLH2UPtubE-LtF_4ZQ1vntcAMmIDHnDpTejI6Q3j805LrjAaRKI3aF6-j2R2mxzqO9ScHg7PNp0WrHyu3L2QM7xmOvTmutMewN8QbmtDsNaI76LZufD30HlYgn9dUCg0RV_o173_YPLK_g-uqSKqOKO8u7Ccz09atUeL1WAbdaAq3qpYD8sbBnPVxn3mu8VZXmoCNiVtZC19J2p13-aY7iC4RPiPDT-4ALRjSkUDUDxY4MufnBg2-pP8tB1tkRMpdCispUD3Rh-xIJqzAd9xIKw","oauth_client","base_url","username")
    print('end')