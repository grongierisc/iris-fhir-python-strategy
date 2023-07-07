# iris-fhir-validation

## Example of request

```http
GET http://localhost:8083/fhir/r4/metadata
Accept: application/json+fhir
```

### Get a patient from EAI

```http
GET http://localhost:8083/fhir/r4/Patient/178/$everything
Content-Type: application/json+fhir
Accept: application/json+fhir
```

```http
GET http://localhost:8083/fhir/r4/Observation
Content-Type: application/json+fhir
Accept: application/json+fhir
```

```http
GET http://localhost:8083/fhir/r4/Observation
Content-Type: application/json+fhir
Accept: application/json+fhir
Authorization: Basic U3VwZXJVc2VyOlNZUw==
```

### Post an Organisation from EAI

```http
POST http://localhost:8083/fhir/r4/Organization
Content-Type: application/json+fhir
Accept: application/json+fhir
Prefer: return=representation

{
  "resourceType": "Organization",
  "identifier": [
    {
      "system": "http://terminology.hl7.org/CodeSystem/v2-0203",
      "value": "12345"
    }
  ],
  "active": true,
  "type": [
    {
      "coding": [
        {
          "system": "http://terminology.hl7.org/CodeSystem/organization-type",
          "code": "prov",
          "display": "Healthcare Provider"
        }
      ],
      "text": "Healthcare Provider"
    }
  ],
  "name": "Acme Healthcare",
  "telecom": [
    {
      "system": "phone",
      "value": "(555) 234-4321"
    }
  ],
  "address": [
    {
      "use": "work",
      "line": [
        "3300 Washtenaw Avenue"
      ],
      "city": "Ann Arbor",
      "state": "MI",
      "postalCode": "48104",
      "country": "USA"
    }
  ]
}
```

### Post a Claim from EAI

```http
POST http://localhost:8083/fhir/r4/Claim

{
  "resourceType": "Claim",
  "id": "100150",
  "text": {
    "status": "generated",
    "div": "<div xmlns=\"http://www.w3.org/1999/xhtml\">A human-readable rendering of the Oral Health Claim</div>"
  },
  "identifier": [
    {
      "system": "http://happyvalley.com/claim",
      "value": "12345"
    }
  ],
  "status": "active",
  "type": {
    "coding": [
      {
        "system": "http://terminology.hl7.org/CodeSystem/claim-type",
        "code": "oral"
      }
    ]
  },
  "use": "claim",
  "patient": {
    "reference": "http://irisfhir:52773/fhir/r4/Patient/2027"
  },
  "created": "2014-08-16",
  "insurer": {
    "reference": "http://hapifhirorganization:8080/fhir/Organization/1"
  },
  "provider": {
    "reference": "http://hapifhirorganization:8080/fhir/Organization/1"
  },
  "priority": {
    "coding": [
      {
        "code": "normal"
      }
    ]
  },
  "payee": {
    "type": {
      "coding": [
        {
          "code": "provider"
        }
      ]
    }
  },
  "careTeam": [
    {
      "sequence": 1,
      "provider": {
        "reference": "http://irisfhir:52773/fhir/r4/Practitioner/3"
      }
    }
  ],
  "diagnosis": [
    {
      "sequence": 1,
      "diagnosisCodeableConcept": {
        "coding": [
          {
            "code": "123456"
          }
        ]
      }
    }
  ],
  "insurance": [
    {
      "sequence": 1,
      "focal": true,
      "identifier": {
        "system": "http://happyvalley.com/claim",
        "value": "12345"
      },
      "coverage": {
        "reference": "Coverage/9876B1"
      }
    }
  ],
  "item": [
    {
      "sequence": 1,
      "careTeamSequence": [
        1
      ],
      "productOrService": {
        "coding": [
          {
            "code": "1200"
          }
        ]
      },
      "servicedDate": "2014-08-16",
      "unitPrice": {
        "value": 135.57,
        "currency": "USD"
      },
      "net": {
        "value": 135.57,
        "currency": "USD"
      }
    }
  ]
}
```

### Post a simple Patient from EAI

```http
POST http://localhost:8083/fhir/r4/Patient
Content-Type: application/json+fhir
Accept: application/json+fhir
Prefer: return=representation

{
  "resourceType": "Patient",
  "id": "example",
  "text": {
    "status": "generated",
    "div": "<div xmlns=\"http://www.w3.org/1999/xhtml\">\n\t\t\t<table>\n\t\t\t\t<tbody>\n\t\t\t\t\t<tr>\n\t\t\t\t\t\t<td>Name</td>\n\t\t\t\t\t\t<td>Peter James \n              <b>Chalmers</b> (&quot;Jim&quot;)\n            </td>\n\t\t\t\t\t</tr>\n\t\t\t\t\t<tr>\n\t\t\t\t\t\t<td>Address</td>\n\t\t\t\t\t\t<td>534 Erewhon, Pleasantville, Vic, 3999</td>\n\t\t\t\t\t</tr>\n\t\t\t\t\t<tr>\n\t\t\t\t\t\t<td>Contacts</td>\n\t\t\t\t\t\t<td>Home: unknown. Work: (03) 5555 6473</td>\n\t\t\t\t\t</tr>\n\t\t\t\t\t<tr>\n\t\t\t\t\t\t<td>Id</td>\n\t\t\t\t\t\t<td>MRN: 12345 (Acme Healthcare)</td>\n\t\t\t\t\t</tr>\n\t\t\t\t</tbody>\n\t\t\t</table>\n\t\t</div>"
  },
  "identifier": [
    {
      "use": "usual",
      "type": {
        "coding": [
          {
            "system": "http://terminology.hl7.org/CodeSystem/v2-0203",
            "code": "MR"
          }
        ]
      },
      "system": "urn:oid:1.2.36.146.595.217.0.1",
      "value": "12345",
      "period": {
        "start": "2001-05-06"
      },
      "assigner": {
        "display": "Acme Healthcare"
      }
    }
  ],
  "active": true,
  "name": [
    {
      "use": "official",
      "family": "Chalmers",
      "given": [
        "Peter",
        "James"
      ]
    },
    {
      "use": "usual",
      "given": [
        "Jim"
      ]
    },
    {
      "use": "maiden",
      "family": "Windsor",
      "given": [
        "Peter",
        "James"
      ],
      "period": {
        "end": "2002"
      }
    }
  ],
  "telecom": [
    {
      "use": "home"
    },
    {
      "system": "phone",
      "value": "(03) 5555 6473",
      "use": "work",
      "rank": 1
    },
    {
      "system": "phone",
      "value": "(03) 3410 5613",
      "use": "mobile",
      "rank": 2
    },
    {
      "system": "phone",
      "value": "(03) 5555 8834",
      "use": "old",
      "period": {
        "end": "2014"
      }
    }
  ],
  "gender": "male",
  "birthDate": "1974-12-25",
  "deceasedBoolean": false,
  "address": [
    {
      "use": "home",
      "type": "both",
      "text": "534 Erewhon St PeasantVille, Rainbow, Vic  3999",
      "line": [
        "534 Erewhon St"
      ],
      "city": "PleasantVille",
      "district": "Rainbow",
      "state": "Vic",
      "postalCode": "3999",
      "period": {
        "start": "1974-12-25"
      }
    }
  ],
  "contact": [
    {
      "relationship": [
        {
          "coding": [
            {
              "system": "http://terminology.hl7.org/CodeSystem/v2-0131",
              "code": "N"
            }
          ]
        }
      ],
      "name": {
        "family": "du Marché",
        "given": [
          "Bénédicte"
        ]
      },
      "telecom": [
        {
          "system": "phone",
          "value": "+33 (237) 998327"
        }
      ],
      "address": {
        "use": "home",
        "type": "both",
        "line": [
          "534 Erewhon St"
        ],
        "city": "PleasantVille",
        "district": "Rainbow",
        "state": "Vic",
        "postalCode": "3999",
        "period": {
          "start": "1974-12-25"
        }
      },
      "gender": "female",
      "period": {
        "start": "2012"
      }
    }
  ],
  "managingOrganization": {
    "reference": "http://hapifhirorganization:8080/fhir/Organization/1"
  }
}
```

### validate patient

```http
POST http://localhost:8083/fhir/custom/Patient/
Content-Type: application/json+fhir
Accept: application/json+fhir
Prefer: return=representation

{
  "resourceType": "Patient",
  "id": "PatientExample",
  "meta": {
    "profile": [
      "http://example.org/StructureDefinition/MyPatient"
    ]
  },
  "extension": [
    {
      "url": "http://example.org/StructureDefinition/birthsex-extension",
      "valueCode": "F"
    }
  ],
  "name": [
    {
      "given": [
        "Janette"
      ],
      "family": "Smith"
    }
  ],
  "maritalStatus": {
    "coding": [
      {
        "code": "M",
        "system": "http://terminology.hl7.org/CodeSystem/v3-MaritalStatus",
        "display": "Married"
      }
    ]
  }
}

```