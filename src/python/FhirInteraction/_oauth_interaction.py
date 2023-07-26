import abc
import iris

class OAuthInteraction(object):
    __metaclass__ = abc.ABCMeta

    token_string:str = None

    oauth_client:str = None

    base_url:str = None

    username:str = None

    token_obj:dict = None

    scopes:list = None

    verify_search_results:bool = None

    @abc.abstractmethod
    def set_instance(self, token:str,oauth_client:str,base_url:str,username:str):
        """
        Set or re-set the properties of the current token handler instance, based on the input parameters.<br>
        /// @Input pTokenString The access token string.<br>
        /// @Input pOAuthClient The OAuth 2.0 Client Name, as defined in the Management Portal at System Administration > Security > OAuth 2.0 > Client.
        /// @Input pBaseURL The base URL, including scheme, host, port and path of the end point for the current FHIR interaction.
        /// @Input pUserame The effective username for the current FHIR interaction.
        """

    @abc.abstractmethod
    def get_introspection(self)->dict:
        """
        /// Call introspection for the current access token, and return a JSON token object and return a status.<br>
        /// Properties of this class are expected to be implemented and available during execution of any
        /// overriden version of this method. ..OAuthClient and ..TokenString are essential to introspection
        /// calls, and are expected to be available along with all other instance properties.
        /// @Output pJWTObj : JSON object returned by introspection call.<br>
        /// @Return         : %Status return value.
        """

    @abc.abstractmethod
    def get_user_info(self,basic_auth_username:str,basic_auth_roles:str)->dict:
        """
        /// Derive user information from the current OAuth 2.0 token, and return that
        /// data if desired.<br>
        /// Input:<br>
        /// - pBAUsername: Existing basic authentication username (e.g., $username value).
        /// - pBARoles   : Existing basic authentication user roles (e.g., $roles value).
        /// Output:<br>
        /// - pUserInfo(): Array of user information, subscripted by item name (e.g. pUserInfo("Username") = "_SYSTEM").
        """

    @abc.abstractmethod
    def verify_resource_id_request(self,resource_type:str,resource_id:str,required_privilege:str):
        """
        /// Verify that the access token allows the current interaction request based on the resource type,
        /// resource id and required privilege. If not allowed, this method will Throw. Otherwise, it will
        /// simply Return.
        """

    @abc.abstractmethod
    def verify_resource_content(self,resource_dict:dict,required_privilege:str,allow_shared_resource:bool):
        """
        /// Verify that the access token allows the current interaction on the specified resource, based on
        /// the content and required privilege. If not allowed, this method will Throw. Otherwise, it will
        /// simply Return.
        """

    @abc.abstractmethod
    def verify_history_instance_response(self,resource_type:str,resource_dict:dict,required_privilege:str):
        """
        /// Verify that the access token allows the history-instance request based on the contents of
        /// the interaction response and required privilege. If not allowed, this method will Throw.
        /// Otherwise, it will simply Return.
        """

    @abc.abstractmethod
    def verify_delete_request(self,resource_type:str,resource_id:str,required_privilege:str):
        """
        /// Verify that the access token allows the delete request based on the specified resource type
        /// and resource id. If not allowed, this method will Throw. Otherwise, it will simply Return.
        """

    @abc.abstractmethod
    def verify_search_request(self,
                              resource_type:str,
                              compartment_resource_type:str,
                              compartment_resource_id:str,
                              parameters:'iris.HS.FHIRServer.API.Data.QueryParameters',
                              required_privilege:str):
        """
        /// Verify that the access token allows the search request based on some or all of resource type,
        /// resource id, compartment type, search parameters and required privilege. If not allowed, this
        /// method will Throw. Otherwise, it will simply Return.
        """

    @abc.abstractmethod
    def verify_system_level_request(self):
        """
        /// Verify that the access token allows the system-level request. If not allowed, this method will
        /// Throw. Otherwise, it will simply Return.
        """