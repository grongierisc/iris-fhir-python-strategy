# 1. iris-fhir-python-strategy

- [1. iris-fhir-python-strategy](#1-iris-fhir-python-strategy)
  - [1.1. Description](#11-description)
  - [1.2. Installation](#12-installation)
    - [1.2.1. Prerequisites](#121-prerequisites)
    - [1.2.2. Installation steps](#122-installation-steps)
  - [1.3. Consent](#13-consent)
  - [1.4. Custom CapabilityStatement](#14-custom-capabilitystatement)
  - [1.5. How iris-fhir-python-strategy works](#15-how-iris-fhir-python-strategy-works)
    - [1.5.1. Introduction](#151-introduction)
    - [1.5.2. Remarks](#152-remarks)
    - [1.5.3. Where to find the code](#153-where-to-find-the-code)
    - [1.5.4. How to implement a Strategy](#154-how-to-implement-a-strategy)
    - [1.5.5. Implementation of InteractionsStrategy](#155-implementation-of-interactionsstrategy)
    - [1.5.6. Implementation of Interactions](#156-implementation-of-interactions)
    - [1.5.7. Interactions in Python](#157-interactions-in-python)
    - [1.5.8. Available decorators](#158-available-decorators)
    - [1.5.9. Configuration](#159-configuration)
    - [1.5.10. Too long, do a summary](#1510-too-long-do-a-summary)

## 1.1. Description

With InterSystems IRIS FHIR Server you can build a Strategy to customize the behavior of the server (see [documentation](https://docs.intersystems.com/irisforhealth20231/csp/docbook/DocBook.UI.Page.cls?KEY=HXFHIR_server_customize_arch) for more details).

![Image](https://github.com/intersystems-ib/workshop-healthcare-interop/raw/main/img/fhirserver.png)

This repository contains a Python Strategy that can be used as a starting point to build your own Strategy in python.

This demo strategy provides the following features:

- Update the capability statement to remove the `Account` resource
- Simulate a consent management system to allow or not access to the `Observation` resource
  - If the User has sufficient rights, the `Observation` resource is returned
  - Otherwise, the `Observation` resource is not returned

## 1.2. Installation

### 1.2.1. Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- [Git](https://git-scm.com/downloads)

### 1.2.2. Installation steps

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
GET http://localhost:8089/fhir/r4/Patient/3/$everything
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
GET http://localhost:8089/fhir/r4/Patient/3/$everything
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

## 1.3. Consent

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

## 1.4. Custom CapabilityStatement

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


## 1.5. How iris-fhir-python-strategy works

### 1.5.1. Introduction

First of all, we have to understand how IRIS FHIR Server works.

Every IRIS FHIR Server implements a `Strategy`.

A `Strategy` is a set of two classes :

| Superclass | Subclass Parameters |
| ---------- | ------------------- |
| HS.FHIRServer.API.InteractionsStrategy |     `StrategyKey` — Specifies a unique identifier for the InteractionsStrategy.<br>    `InteractionsClass` — Specifies the name of your Interactions subclass.|
| HS.FHIRServer.API.RepoManager |     `StrategyClass` — Specifies the name of your InteractionsStrategy subclass.<br>    `StrategyKey` — Specifies a unique identifier for the InteractionsStrategy. Must match the StrategyKey parameter in the InteractionsStrategy subclass.|

Both classes are `Abstract` classes.

- `HS.FHIRServer.API.InteractionsStrategy` is an `Abstract` class that must be implemented to customize the behavior of the FHIR Server.
- `HS.FHIRServer.API.RepoManager` is an `Abstract` class that must be implemented to customize the storage of the FHIR Server.

### 1.5.2. Remarks

For our example, we will only focus on the `HS.FHIRServer.API.InteractionsStrategy` class even if the `HS.FHIRServer.API.RepoManager` class is also implemented and mandatory to customize the FHIR Server.
The `HS.FHIRServer.API.RepoManager` class is implemented by `HS.FHIRServer.Storage.Json.RepoManager` class, which is the default implementation of the FHIR Server.

### 1.5.3. Where to find the code

All source code can be found in the `src` folder.
The `src` folder contains the following folders :
- `python` : contains the python code
- `cls` : contains the ObjectScript code that is used to call the python code

### 1.5.4. How to implement a Strategy

In this proof of concept, we will only be interested in how to implement a `Strategy` in Python, not how to implement a `RepoManager`.

To implement a `Strategy` you need to create at least two classes :

- A class that inherits from `HS.FHIRServer.API.InteractionsStrategy` class
- A class that inherits from `HS.FHIRServer.API.Interactions` class

### 1.5.5. Implementation of InteractionsStrategy

`HS.FHIRServer.API.InteractionsStrategy` class aim to customize the behavior of the FHIR Server by overriding the following methods :

- `GetMetadataResource` : called to get the metadata of the FHIR Server
  - this is the only method we will override in this proof of concept

`HS.FHIRServer.API.InteractionsStrategy` has also two parameters :

- `StrategyKey` : a unique identifier for the InteractionsStrategy
- `InteractionsClass` : the name of your Interactions subclass

### 1.5.6. Implementation of Interactions

`HS.FHIRServer.API.Interactions` class aim to customize the behavior of the FHIR Server by overriding the following methods :

- `OnBeforeRequest` : called before the request is sent to the server
- `OnAfterRequest` : called after the request is sent to the server
- `PostProcessRead` : called after the read operation is done
- `PostProcessSearch` : called after the search operation is done
- `Read` : called to read a resource
- `Add` : called to add a resource
- `Update` : called to update a resource
- `Delete` : called to delete a resource
- and many more...

We implement `HS.FHIRServer.API.Interactions` class in the `src/cls/FHIR/Python/Interactions.cls` class. It loads the Python decorator module and executes any registered handlers. If no decorator is registered for a hook, the default ObjectScript behavior runs via `##super(...)`.

<details> 
<summary>Click to see the code</summary>

```objectscript
Class FHIR.Python.Interactions Extends (HS.FHIRServer.Storage.JsonAdvSQL.Interactions, FHIR.Python.Helper)
{

Method %OnNew(pStrategy As HS.FHIRServer.Storage.JsonAdvSQL.InteractionsStrategy) As %Status
{
    do ..GetCustomizationSettings(.tPythonPath, .tPythonModule)
    set ..PythonPath = tPythonPath
    set ..PythonModule = tPythonModule

    do ..SetPythonPath(..PythonPath)
    set importlib = ##class(%SYS.Python).Import("importlib")
    set ..PythonModule = importlib."import_module"(..PythonModule)
    do importlib."reload"(..PythonModule)

    set fhirDecorators = ##class(%SYS.Python).Import("fhir_decorators")
    set ..PythonClass = fhirDecorators.fhir

    quit ##super(pStrategy)
}

Method OnBeforeRequest(
    pFHIRService As HS.FHIRServer.API.Service,
    pFHIRRequest As HS.FHIRServer.API.Data.Request,
    pTimeout As %Integer)
{
    if $ISOBJECT(..PythonClass) {
        set handlers = ..PythonClass."get_before_request_handlers"()
        if handlers."__len__"() = 0 {
            do ##super(pFHIRService, pFHIRRequest, pTimeout)
            quit
        }
        // Call decorator handlers...
    }
}
```

</details>

### 1.5.7. Interactions in Python

`FHIR.Python.Interactions` class calls handlers registered with decorators in `examples/custom_decorators.py`.

```python
from fhir_decorators import fhir

@fhir.before_request
def extract_user_context(fhir_service, fhir_request, body, timeout):
    # called before request processing
    pass

@fhir.on_read("Patient")
def filter_patient_read(fhir_object):
    # return False to hide a resource
    return True
```

### 1.5.8. Available decorators

| Decorator | Purpose |
| --- | --- |
| `@fhir.on_capability_statement` | Customize the capability statement |
| `@fhir.before_request` | Hook before each request |
| `@fhir.after_request` | Hook after each request |
| `@fhir.post_process_read(type)` | Post-process reads |
| `@fhir.post_process_search(type)` | Post-process searches |
| `@fhir.on_read(type)` | Alias for `post_process_read` |
| `@fhir.on_search(type)` | Alias for `post_process_search` |
| `@fhir.consent(type)` | Consent rules |
| `@fhir.on_create(type)` | Hook on create (POST) |
| `@fhir.on_update(type)` | Hook on update (PUT) |
| `@fhir.on_delete(type)` | Hook on delete (DELETE) |
| `@fhir.operation(name, scope, type)` | Custom `$operation` |
| `@fhir.oauth_set_instance` | Configure OAuth token |
| `@fhir.oauth_get_introspection` | Token introspection |
| `@fhir.oauth_get_user_info` | Extract user info |
| `@fhir.oauth_verify_resource_id(type)` | Verify access by resource ID |
| `@fhir.oauth_verify_resource_content(type)` | Verify access by resource content |
| `@fhir.oauth_verify_history(type)` | Verify access to history |
| `@fhir.oauth_verify_delete(type)` | Verify delete access |
| `@fhir.oauth_verify_search(type)` | Verify search access |
| `@fhir.oauth_verify_system_level` | Verify system-level access |
| `@fhir.validate_resource(type)` | Custom resource validation |
| `@fhir.validate_bundle` | Custom bundle validation |

### 1.5.9. Configuration

The module path and name are configured via environment variables:

```
FHIR_CUSTOMIZATION_PATH=/irisdev/app/
FHIR_CUSTOMIZATION_MODULE=examples.custom_decorators
```

If not set, the defaults above are used. The module must be importable and should register decorators at import time.

### 1.5.10. Too long, do a summary

The ObjectScript classes load `examples/custom_decorators.py`, collect registered decorators, and invoke them during FHIR interactions.
If no decorator exists for a hook, the default ObjectScript behavior is preserved via `##super(...)`.
