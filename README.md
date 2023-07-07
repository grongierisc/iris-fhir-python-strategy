# iris-fhir-python-strategy

## Description

With InterSystems IRIS FHIR Server you can build a Strategy to customize the behavior of the server (see [documentation](https://docs.intersystems.com/irisforhealth20231/csp/docbook/DocBook.UI.Page.cls?KEY=HXFHIR_server_customize_arch) for more details).

![Image](https://github.com/intersystems-ib/workshop-healthcare-interop/raw/main/img/fhirserver.png)

This repository contains a Python Strategy that can be used as a starting point to build your own Strategy in python.

This demo strategy provides the following features:

- Update the capability statement to remove the `Account` resource
- Simulate a consent management system to allow or not access to the `Observation` resource
  - If the User has sufficient rights, the `Observation` resource is returned
  - Otherwise, the `Observation` resource is not returned

## Installation

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- [Git](https://git-scm.com/downloads)

### Installation steps

1. Clone this repository

```bash
git clone git@github.com:grongierisc/iris-fhir-python-strategy.git
```

2. Build the docker image

```bash
docker-compose build
```

3. Run the docker image

```bash
docker-compose up -d
```

4. Open the FHIR server in your browser

```http
GET http://localhost:8083/fhir/r4/metadata
Accept: application/json+fhir
```

The `Account` resource should not be present in the Capability Statement.

```http
GET http://localhost:8083/fhir/r4/Account
Accept: application/json+fhir
```

returns :

```json
{
  "resourceType": "OperationOutcome",
  "issue": [
    {
      "severity": "error",
      "code": "not-supported",
      "diagnostics": "<HSFHIRErr>ResourceNotSupported",
      "details": {
        "text": "Resource type 'Account' is not supported."
      }
    }
  ]
}
```

5. Open get a patient without authentication (you shouldn't have access to Observation)

```http
GET http://localhost:8083/fhir/r4/Observation?patient=178
Content-Type: application/json+fhir
Accept: application/json+fhir
```

returns :

```json
{
  "resourceType": "Bundle",
  "id": "feaa09c0-1cb7-11ee-b77a-0242c0a88002",
  "type": "searchset",
  "timestamp": "2023-07-07T11:07:49Z",
  "total": 0,
  "link": [
    {
      "relation": "self",
      "url": "http://localhost:8083/fhir/r4/Observation?patient=178"
    }
  ]
}
```

6. Open get a patient with authentication (you should have access to Observation)

```http
GET http://localhost:8083/fhir/r4/Observation?patient=178
Content-Type: application/json+fhir
Accept: application/json+fhir
Authorization: Basic U3VwZXJVc2VyOlNZUw==
```

returns :

```json
{
  "resourceType": "Bundle",
  "id": "953a1b06-1cb7-11ee-b77b-0242c0a88002",
  "type": "searchset",
  "timestamp": "2023-07-07T11:08:04Z",
  "total": 100,
  "link": [
    {
      "relation": "self",
      "url": "http://localhost:8083/fhir/r4/Observation?patient=178"
    }
  ],
  "entry": [
    {
      "fullUrl": "http://localhost:8083/fhir/r4/Observation/277",
      "resource": {
        "resourceType": "Observation",
        "id": "277",
        "status": "final",
        "category": [
          ...
        ],
      }
    },
    ...
  ]
}
```

More details on a next section about Consent.

## Consent

The consent management system is simulated by the `consent` method in the `CustomInteraction` class in the `custom` module.

The `consent` method returns `True` if the user has sufficient rights to access the resource, `False` otherwise.

```python
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
```

The `consent` function is part of the `CustomInteraction`.

The `CustomInteraction` class is an implementation of the `Interaction` class.

The `Interaction` class is an Abstract class that must be implemented by the Strategy. It part of the `FhirInteraction` module.

```python
class Interaction(object):
    __metaclass__ = abc.ABCMeta

    @abc.abstractmethod
    def on_before_request(self, 
                          fhir_service:'iris.HS.FHIRServer.API.Service',
                          fhir_request:'iris.FHIRServer.API.Data.Request',
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
                         fhir_request:'iris.FHIRServer.API.Data.Request',
                         fhir_response:'iris.FHIRServer.API.Data.Response',
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
```

The `CustomInteraction` class is an implementation of the `Interaction` class.

```python
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
```

You can modify the `custom` module to implement your own consent logic.

All modifications to the `custom` module will be directly reflected in the FHIR Server.

Other behaviors can be implemented by overriding the `Interaction` classes.

- WIP

## Custom CapabilityStatement

IRIS FHIR Server provides a default CapabilityStatement based on the Implementation Guide guiven at installation time.

More information how to customize the CapabilityStatement can be found at [FHIR CapabilityStatement](https://docs.intersystems.com/irisforhealth20231/csp/docbook/DocBook.UI.Page.cls?KEY=HXFHIR_server_customize_arch#HXFHIR_server_customize_capability).

For this example, the Implementation Guide is raw FHIR R4.

To customize the CapabilityStatement, you can modify the `custom` module.

The `CustomStrategy` class is an implementation of the `Strategy` class.

The `Strategy` class is an Abstract class that must be implemented by the Strategy. It part of the `FhirInteraction` module.

```python
class Strategy(object):
    __metaclass__ = abc.ABCMeta

    @abc.abstractmethod
    def on_get_capability_statement(self,capability_statement:dict)-> dict:
        """
        on_after_get_capability_statement is called after the capability statement is retrieved.
        param capability_statement: the capability statement
        return: None
        """
```

The `on_get_capability_statement` method is called after the CapabilityStatement is generated.

The `CustomStrategy` class is an implementation of the `Strategy` class.

```python
class CustomStrategy(Strategy):
    
    def on_get_capability_statement(self, capability_statement):
        # Example : del resources Account
        capability_statement['rest'][0]['resource'] = [resource for resource in capability_statement['rest'][0]['resource'] if resource['type'] != 'Account']
        return capability_statement
```

You can modify the `custom` module to implement your own Custom CapabilityStatement.

To apply the changes, you need to update the fhir server configuration.

```bash
cd /irisdev/app/src/python
/usr/irissys/bin/irispython
>>> import custom
>>> custom.set_capability_statement()
```