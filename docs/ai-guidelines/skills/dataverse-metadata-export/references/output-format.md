# Output Format

Each `<table>.json` file uses this normalized shape:

```json
{
  "generated_at_utc": "2026-03-09T18:00:00Z",
  "environment_url": "https://org.crm4.dynamics.com",
  "table": {
    "logical_name": "account",
    "entity_set_name": "accounts",
    "schema_name": "Account",
    "display_name": "Account",
    "display_collection_name": "Accounts",
    "description": "...",
    "primary_id_attribute": "accountid",
    "primary_name_attribute": "name",
    "object_type_code": 1,
    "ownership_type": "UserOwned",
    "is_activity": false,
    "is_intersect": false,
    "is_custom_entity": false,
    "odata_collection_path": "/api/data/v9.2/accounts",
    "sql_table_name_hint": "account"
  },
  "columns": [
    {
      "logical_name": "accountclassificationcode",
      "schema_name": "AccountClassificationCode",
      "display_name": "Classification",
      "description": null,
      "attribute_type": "Picklist",
      "attribute_type_name": "PicklistType",
      "required_level": "None",
      "is_primary_id": false,
      "is_primary_name": false,
      "is_valid_for_read": true,
      "is_valid_for_create": true,
      "is_valid_for_update": true,
      "is_custom_attribute": false,
      "format": null,
      "format_name": null,
      "date_time_behavior": null,
      "max_length": null,
      "min_value": null,
      "max_value": null,
      "precision": null,
      "precision_source": null,
      "targets": [],
      "option_set": {
        "is_global": false,
        "name": "account_accountclassificationcode",
        "options": [
          {
            "value": 1,
            "label": "Default Value",
            "description": null,
            "color": null,
            "state": null
          }
        ]
      }
    }
  ],
  "relationships": {
    "one_to_many": [],
    "many_to_one": [],
    "many_to_many": []
  }
}
```

## Notes

- `logical_name` is the Dataverse name typically used in OData payloads and TDS/SQL projections.
- `entity_set_name` is the collection name used in Web API paths.
- `sql_table_name_hint` is a convenience hint for TDS/SQL usage when that endpoint is enabled.
- `targets` lists allowed target tables for lookup columns.
- `option_set.options[].value` is the value code to use in integrations and business logic.
- Relationship entries include navigation-property names when Dataverse exposes them.
