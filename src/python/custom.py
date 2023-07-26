from FhirInteraction import Interaction, Strategy, OAuthInteraction

from google.oauth2 import id_token
from google.auth.transport import requests

import requests as rq

import os
import json

# The following is an example of a custom OAuthInteraction class that
class CustomOAuthInteraction(OAuthInteraction):
    
    client_id = None

    def set_instance(self, token:str,oauth_client:str,base_url:str,username:str):
        # try to set the client id
        try:
            # first by the environment variable GOOGLE_CLIENT_ID
            self.client_id = os.environ['GOOGLE_CLIENT_ID']
            # if not set, then by the secret.json file
            if not self.client_id:
                with open(os.environ['ISC_OAUTH_SECRET_PATH'],encoding='utf-8') as f:
                    data = json.load(f)
                    self.client_id = data['web']['client_id']
        except FileNotFoundError:
            pass

        self.verify_token(token)

    def verify_token(self,token:str):
        # check if the token is an access token or an id token
        if token.startswith('ya29.'):
            self.verify_access_token(token)
        else:
            self.verify_id_token(token)

    def verify_access_token(self,token:str):
        # verify the access token is valid
        response = rq.get(f"https://www.googleapis.com/oauth2/v3/tokeninfo?access_token={token}")
        response.raise_for_status()

    def verify_id_token(self,token:str):
        # Verify the token and get the user info
        idinfo = id_token.verify_oauth2_token(token, requests.Request(), self.client_id)
        if idinfo['iss'] not in ['accounts.google.com', 'https://accounts.google.com']:
            raise ValueError('Wrong issuer.')

    def get_introspection(self)->dict:
        return {}
    
    def get_user_info(self,basic_auth_username:str,basic_auth_roles:str)->list:
        return []
    
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
                                resource_dict:dict,
                                required_privilege:str,
                                allow_shared_resource:bool):
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

def set_capability_statement():
    from FhirInteraction import Utils
    utils = Utils()
    utils.update_capability_statement("/fhir/r4")

if __name__ == '__main__':
    custom_oauth_interaction = CustomOAuthInteraction()
    custom_oauth_interaction.set_instance("eyJhbGciOiJSUzI1NiIsImtpZCI6ImEzYmRiZmRlZGUzYmFiYjI2NTFhZmNhMjY3OGRkZThjMGIzNWRmNzYiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJhY2NvdW50cy5nb29nbGUuY29tIiwiYXpwIjoiNTc3NjgzODIwMjU5LW5xN2FmbTZicGJuNWhjZnVlMWQ4aTFsMWdtbzFrcG0xLmFwcHMuZ29vZ2xldXNlcmNvbnRlbnQuY29tIiwiYXVkIjoiNTc3NjgzODIwMjU5LW5xN2FmbTZicGJuNWhjZnVlMWQ4aTFsMWdtbzFrcG0xLmFwcHMuZ29vZ2xldXNlcmNvbnRlbnQuY29tIiwic3ViIjoiMTAxOTE3MDk4MTQzOTgyOTg1NzI3IiwiYXRfaGFzaCI6IlJMXzNfV2FicFFoaGNXcnZodnVhUUEiLCJpYXQiOjE2OTAzNzIwOTYsImV4cCI6MTY5MDM3NTY5Nn0.OlV24r-44CV3v5Z_FcOr3Xh1-IOMgWTSnINceTiKpk0CrQIQDZZMPpVnfggyy5DVLH2UPtubE-LtF_4ZQ1vntcAMmIDHnDpTejI6Q3j805LrjAaRKI3aF6-j2R2mxzqO9ScHg7PNp0WrHyu3L2QM7xmOvTmutMewN8QbmtDsNaI76LZufD30HlYgn9dUCg0RV_o173_YPLK_g-uqSKqOKO8u7Ccz09atUeL1WAbdaAq3qpYD8sbBnPVxn3mu8VZXmoCNiVtZC19J2p13-aY7iC4RPiPDT-4ALRjSkUDUDxY4MufnBg2-pP8tB1tkRMpdCispUD3Rh-xIJqzAd9xIKw","oauth_client","base_url","username")
    print('end')