# Usage Notes

## OData / Web API

- Build collection routes from `table.odata_collection_path`.
- Use `columns[].logical_name` for `$select`, filter predicates, and payload properties.
- Use `relationships.many_to_one[].referencing_entity_navigation_property_name` and `relationships.one_to_many[].referenced_entity_navigation_property_name` when expanding or binding navigation properties.
- For choice columns, compare or write the numeric `option_set.options[].value`, not the display label.
- For lookups, check `targets` before assuming the referenced table.

## SQL / TDS Endpoint

- Start from `table.sql_table_name_hint` and `columns[].logical_name`.
- Relationship arrays help identify lookup semantics even though SQL uses flattened foreign-key columns.
- Choice fields still store integer values; use exported labels only for display or documentation.

## Implementation Guidance

- Export metadata before adding mappings, validation, synchronization logic, or generated client code.
- Keep the exported JSON alongside the work item or feature branch if multiple agents will use the same schema snapshot.
- Re-export after solution imports or schema changes. Dataverse metadata drifts over time.
