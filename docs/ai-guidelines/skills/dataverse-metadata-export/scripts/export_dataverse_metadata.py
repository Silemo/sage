#!/usr/bin/env python3
"""Export normalized Dataverse table metadata for Copilot-style agent workflows."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


API_VERSION = "v9.2"
DEFAULT_TIMEOUT_SECONDS = 60
COMMON_HEADERS = {
    "Accept": "application/json",
    "OData-Version": "4.0",
    "OData-MaxVersion": "4.0",
}


TYPE_DETAIL_QUERIES: dict[str, str] = {
    "string": "/Attributes/Microsoft.Dynamics.CRM.StringAttributeMetadata"
    "?$select=LogicalName,SchemaName,MaxLength,Format,FormatName",
    "memo": "/Attributes/Microsoft.Dynamics.CRM.MemoAttributeMetadata"
    "?$select=LogicalName,SchemaName,MaxLength,Format,FormatName",
    "integer": "/Attributes/Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
    "?$select=LogicalName,SchemaName,MinValue,MaxValue,Format,SourceType",
    "bigint": "/Attributes/Microsoft.Dynamics.CRM.BigIntAttributeMetadata"
    "?$select=LogicalName,SchemaName,MinValue,MaxValue",
    "decimal": "/Attributes/Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
    "?$select=LogicalName,SchemaName,MinValue,MaxValue,Precision,PrecisionSource",
    "double": "/Attributes/Microsoft.Dynamics.CRM.DoubleAttributeMetadata"
    "?$select=LogicalName,SchemaName,MinValue,MaxValue,Precision,PrecisionSource",
    "money": "/Attributes/Microsoft.Dynamics.CRM.MoneyAttributeMetadata"
    "?$select=LogicalName,SchemaName,MinValue,MaxValue,Precision,PrecisionSource,CalculationOf",
    "datetime": "/Attributes/Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
    "?$select=LogicalName,SchemaName,Format&$expand=DateTimeBehavior($select=Value)",
    "lookup": "/Attributes/Microsoft.Dynamics.CRM.LookupAttributeMetadata"
    "?$select=LogicalName,SchemaName,Targets",
    "customer": "/Attributes/Microsoft.Dynamics.CRM.CustomerAttributeMetadata"
    "?$select=LogicalName,SchemaName,Targets",
    "owner": "/Attributes/Microsoft.Dynamics.CRM.OwnerAttributeMetadata"
    "?$select=LogicalName,SchemaName,Targets",
    "picklist": "/Attributes/Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
    "?$select=LogicalName,SchemaName&$expand=OptionSet",
    "multiselect": "/Attributes/Microsoft.Dynamics.CRM.MultiSelectPicklistAttributeMetadata"
    "?$select=LogicalName,SchemaName&$expand=OptionSet",
    "state": "/Attributes/Microsoft.Dynamics.CRM.StateAttributeMetadata"
    "?$select=LogicalName,SchemaName&$expand=OptionSet",
    "status": "/Attributes/Microsoft.Dynamics.CRM.StatusAttributeMetadata"
    "?$select=LogicalName,SchemaName&$expand=OptionSet",
    "boolean": "/Attributes/Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
    "?$select=LogicalName,SchemaName&$expand=OptionSet",
}

ATTRIBUTE_FALLBACK_CASTS: dict[str, str] = {
    "Boolean": "BooleanAttributeMetadata",
    "Customer": "CustomerAttributeMetadata",
    "Lookup": "LookupAttributeMetadata",
    "MultiSelectPicklist": "MultiSelectPicklistAttributeMetadata",
    "Owner": "OwnerAttributeMetadata",
    "Picklist": "PicklistAttributeMetadata",
    "State": "StateAttributeMetadata",
    "Status": "StatusAttributeMetadata",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Export Dataverse metadata for one or more tables into normalized JSON "
            "and Markdown summaries."
        )
    )
    parser.add_argument(
        "--environment-url",
        required=True,
        help="Dataverse environment root URL, for example https://org.crm4.dynamics.com",
    )
    parser.add_argument(
        "--table",
        action="append",
        default=[],
        help="Logical table name. Repeat the flag or pass a comma-separated list.",
    )
    parser.add_argument(
        "--table-file",
        help="Optional text file with one logical table name per line.",
    )
    parser.add_argument(
        "--output-dir",
        default="artifacts/dataverse-metadata",
        help="Directory where JSON and Markdown files will be written.",
    )
    parser.add_argument(
        "--token-env",
        default="DATAVERSE_ACCESS_TOKEN",
        help="Environment variable that contains the Dataverse bearer token.",
    )
    parser.add_argument(
        "--label-language",
        type=int,
        default=1033,
        help="Preferred label language LCID. Default: 1033.",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=DEFAULT_TIMEOUT_SECONDS,
        help=f"HTTP timeout in seconds. Default: {DEFAULT_TIMEOUT_SECONDS}.",
    )
    return parser.parse_args()


def normalize_environment_url(raw_url: str) -> str:
    cleaned = raw_url.rstrip("/")
    api_suffix = f"/api/data/{API_VERSION}"
    if cleaned.endswith(api_suffix):
        cleaned = cleaned[: -len(api_suffix)]
    return cleaned


def collect_tables(table_args: list[str], table_file: str | None) -> list[str]:
    tables: list[str] = []

    for raw in table_args:
        for item in raw.split(","):
            logical_name = item.strip()
            if logical_name:
                tables.append(logical_name)

    if table_file:
        for line in Path(table_file).read_text(encoding="utf-8").splitlines():
            logical_name = line.strip()
            if logical_name and not logical_name.startswith("#"):
                tables.append(logical_name)

    unique_tables: list[str] = []
    seen: set[str] = set()
    for table in tables:
        lowered = table.lower()
        if lowered not in seen:
            seen.add(lowered)
            unique_tables.append(table)
    return unique_tables


def require_token(env_var_name: str) -> str:
    token = os.environ.get(env_var_name, "").strip()
    if token:
        return token
    raise SystemExit(
        f"Missing Dataverse bearer token. Set the {env_var_name} environment variable."
    )


class DataverseClient:
    def __init__(self, environment_url: str, bearer_token: str, timeout_seconds: int) -> None:
        self.environment_url = normalize_environment_url(environment_url)
        self.api_root = f"{self.environment_url}/api/data/{API_VERSION}"
        self.timeout_seconds = timeout_seconds
        self.headers = dict(COMMON_HEADERS)
        self.headers["Authorization"] = f"Bearer {bearer_token}"

    def get(self, path: str) -> Any:
        url = self._to_absolute_url(path)
        payload = self._request_json(url)
        if isinstance(payload, dict) and "value" in payload and "@odata.nextLink" in payload:
            payload["value"] = self._collect_all_pages(payload["value"], payload["@odata.nextLink"])
            payload.pop("@odata.nextLink", None)
        return payload

    def _collect_all_pages(self, current_items: list[Any], next_link: str) -> list[Any]:
        items = list(current_items)
        pending = next_link
        while pending:
            page = self._request_json(pending)
            items.extend(page.get("value", []))
            pending = page.get("@odata.nextLink")
        return items

    def _to_absolute_url(self, path: str) -> str:
        if path.startswith("http://") or path.startswith("https://"):
            return path
        if path.startswith("/"):
            return f"{self.api_root}{path}"
        return f"{self.api_root}/{path}"

    def _request_json(self, url: str) -> Any:
        attempt = 0
        while True:
            request = urllib.request.Request(url=url, headers=self.headers, method="GET")
            try:
                with urllib.request.urlopen(request, timeout=self.timeout_seconds) as response:
                    body = response.read().decode("utf-8")
                    return json.loads(body)
            except urllib.error.HTTPError as exc:
                if exc.code in (429, 502, 503, 504) and attempt < 4:
                    delay = self._retry_delay(exc, attempt)
                    time.sleep(delay)
                    attempt += 1
                    continue
                message = exc.read().decode("utf-8", errors="replace")
                raise RuntimeError(f"HTTP {exc.code} for {url}: {message}") from exc
            except urllib.error.URLError as exc:
                raise RuntimeError(f"Request failed for {url}: {exc.reason}") from exc

    @staticmethod
    def _retry_delay(error: urllib.error.HTTPError, attempt: int) -> float:
        retry_after = error.headers.get("Retry-After")
        if retry_after and retry_after.isdigit():
            return float(retry_after)
        return float(2 ** attempt)


def pick_label(label_payload: dict[str, Any] | None, language_code: int) -> str | None:
    if not label_payload:
        return None

    user_localized = label_payload.get("UserLocalizedLabel")
    if isinstance(user_localized, dict):
        label = user_localized.get("Label")
        if label:
            return label

    for localized in label_payload.get("LocalizedLabels", []):
        if localized.get("LanguageCode") == language_code and localized.get("Label"):
            return localized["Label"]

    for localized in label_payload.get("LocalizedLabels", []):
        if localized.get("Label"):
            return localized["Label"]

    return None


def pick_optional_value(payload: dict[str, Any], *path: str) -> Any:
    current: Any = payload
    for part in path:
        if not isinstance(current, dict):
            return None
        current = current.get(part)
        if current is None:
            return None
    return current


def normalize_option_set(option_set: dict[str, Any] | None, language_code: int) -> dict[str, Any] | None:
    if not option_set:
        return None

    normalized_options: list[dict[str, Any]] = []
    if isinstance(option_set.get("Options"), list):
        for option in option_set["Options"]:
            normalized_options.append(
                {
                    "value": option.get("Value"),
                    "label": pick_label(option.get("Label"), language_code),
                    "description": pick_label(option.get("Description"), language_code),
                    "color": option.get("Color"),
                    "state": option.get("State"),
                    "external_value": option.get("ExternalValue"),
                }
            )
    else:
        for key in ("FalseOption", "TrueOption"):
            option = option_set.get(key)
            if not isinstance(option, dict):
                continue
            normalized_options.append(
                {
                    "value": option.get("Value"),
                    "label": pick_label(option.get("Label"), language_code),
                    "description": pick_label(option.get("Description"), language_code),
                    "color": option.get("Color"),
                    "state": option.get("State"),
                    "external_value": option.get("ExternalValue"),
                }
            )

    normalized_options.sort(key=lambda item: (item.get("value") is None, item.get("value")))
    return {
        "is_global": option_set.get("IsGlobal"),
        "name": option_set.get("Name"),
        "display_name": pick_label(option_set.get("DisplayName"), language_code),
        "options": normalized_options,
    }


def normalize_attribute(attribute: dict[str, Any], language_code: int) -> dict[str, Any]:
    attribute_type_name = pick_optional_value(attribute, "AttributeTypeName", "Value")
    if attribute_type_name is None:
        attribute_type_name = attribute.get("AttributeTypeName")

    return {
        "logical_name": attribute.get("LogicalName"),
        "schema_name": attribute.get("SchemaName"),
        "display_name": pick_label(attribute.get("DisplayName"), language_code),
        "description": pick_label(attribute.get("Description"), language_code),
        "attribute_type": attribute.get("AttributeType"),
        "attribute_type_name": attribute_type_name,
        "required_level": pick_optional_value(attribute, "RequiredLevel", "Value"),
        "is_primary_id": attribute.get("IsPrimaryId"),
        "is_primary_name": attribute.get("IsPrimaryName"),
        "is_valid_for_read": attribute.get("IsValidForRead"),
        "is_valid_for_create": attribute.get("IsValidForCreate"),
        "is_valid_for_update": attribute.get("IsValidForUpdate"),
        "is_custom_attribute": attribute.get("IsCustomAttribute"),
        "format": attribute.get("Format"),
        "format_name": pick_optional_value(attribute, "FormatName", "Value"),
        "date_time_behavior": pick_optional_value(attribute, "DateTimeBehavior", "Value"),
        "max_length": attribute.get("MaxLength"),
        "min_value": attribute.get("MinValue"),
        "max_value": attribute.get("MaxValue"),
        "precision": attribute.get("Precision"),
        "precision_source": attribute.get("PrecisionSource"),
        "targets": attribute.get("Targets", []),
        "source_type": attribute.get("SourceType"),
        "calculation_of": attribute.get("CalculationOf"),
        "option_set": normalize_option_set(attribute.get("OptionSet"), language_code),
    }


def merge_attribute_details(
    base_attributes: list[dict[str, Any]], detail_attributes: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    by_logical_name = {item.get("LogicalName"): item for item in base_attributes}
    for detail in detail_attributes:
        logical_name = detail.get("LogicalName")
        if not logical_name:
            continue
        target = by_logical_name.setdefault(logical_name, {})
        for key, value in detail.items():
            if key == "LogicalName":
                continue
            target[key] = value
    return list(by_logical_name.values())


def needs_fallback_detail(attribute: dict[str, Any]) -> bool:
    attribute_type = attribute.get("AttributeType")
    if attribute_type in {"Lookup", "Customer", "Owner"}:
        return not attribute.get("Targets")

    if attribute_type not in {"Picklist", "MultiSelectPicklist", "State", "Status", "Boolean"}:
        return False

    option_set = attribute.get("OptionSet")
    if not isinstance(option_set, dict):
        return True
    if option_set.get("Options"):
        return False
    if option_set.get("FalseOption") or option_set.get("TrueOption"):
        return False
    return True


def enrich_fallback_attribute_details(
    client: DataverseClient, entity_path: str, attributes: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    enriched = list(attributes)
    for attribute in list(enriched):
        if not needs_fallback_detail(attribute):
            continue

        cast_name = ATTRIBUTE_FALLBACK_CASTS.get(attribute.get("AttributeType"))
        logical_name = attribute.get("LogicalName")
        if not cast_name or not logical_name:
            continue

        escaped_logical_name = logical_name.replace("'", "''")
        if attribute.get("AttributeType") in {"Lookup", "Customer", "Owner"}:
            query = (
                f"{entity_path}/Attributes(LogicalName='{escaped_logical_name}')/"
                f"Microsoft.Dynamics.CRM.{cast_name}?$select=LogicalName,SchemaName,Targets"
            )
        else:
            query = (
                f"{entity_path}/Attributes(LogicalName='{escaped_logical_name}')/"
                f"Microsoft.Dynamics.CRM.{cast_name}?$select=LogicalName,SchemaName&$expand=OptionSet"
            )

        detail = client.get(query)
        enriched = merge_attribute_details(enriched, [detail])
    return enriched


def normalize_relationships(payload: list[dict[str, Any]], relationship_type: str) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    for item in payload:
        relationship = {
            "relationship_type": relationship_type,
            "schema_name": item.get("SchemaName"),
            "metadata_id": item.get("MetadataId"),
            "is_custom_relationship": item.get("IsCustomRelationship"),
        }
        if relationship_type in ("one_to_many", "many_to_one"):
            relationship.update(
                {
                    "referenced_entity": item.get("ReferencedEntity"),
                    "referenced_attribute": item.get("ReferencedAttribute"),
                    "referencing_entity": item.get("ReferencingEntity"),
                    "referencing_attribute": item.get("ReferencingAttribute"),
                    "referenced_entity_navigation_property_name": item.get(
                        "ReferencedEntityNavigationPropertyName"
                    ),
                    "referencing_entity_navigation_property_name": item.get(
                        "ReferencingEntityNavigationPropertyName"
                    ),
                    "is_hierarchical": item.get("IsHierarchical"),
                }
            )
        else:
            relationship.update(
                {
                    "intersect_entity_name": item.get("IntersectEntityName"),
                    "entity1_logical_name": item.get("Entity1LogicalName"),
                    "entity1_intersect_attribute": item.get("Entity1IntersectAttribute"),
                    "entity1_navigation_property_name": item.get("Entity1NavigationPropertyName"),
                    "entity2_logical_name": item.get("Entity2LogicalName"),
                    "entity2_intersect_attribute": item.get("Entity2IntersectAttribute"),
                    "entity2_navigation_property_name": item.get("Entity2NavigationPropertyName"),
                }
            )
        normalized.append(relationship)

    normalized.sort(key=lambda item: (item.get("schema_name") or "", item.get("metadata_id") or ""))
    return normalized


def fetch_table_export(
    client: DataverseClient, logical_name: str, language_code: int
) -> dict[str, Any]:
    safe_logical_name = logical_name.replace("'", "''")
    entity_path = f"/EntityDefinitions(LogicalName='{safe_logical_name}')"

    table_raw = client.get(
        entity_path
        + "?$select="
        + ",".join(
            [
                "LogicalName",
                "LogicalCollectionName",
                "SchemaName",
                "EntitySetName",
                "PrimaryIdAttribute",
                "PrimaryNameAttribute",
                "ObjectTypeCode",
                "OwnershipType",
                "IsActivity",
                "IsIntersect",
                "IsCustomEntity",
            ]
        )
        + "&$expand=DisplayName,DisplayCollectionName,Description"
    )

    attributes = client.get(entity_path + "/Attributes").get("value", [])
    for detail_query in TYPE_DETAIL_QUERIES.values():
        detail_items = client.get(entity_path + detail_query).get("value", [])
        attributes = merge_attribute_details(attributes, detail_items)
    attributes = enrich_fallback_attribute_details(client, entity_path, attributes)

    normalized_attributes = [normalize_attribute(item, language_code) for item in attributes]
    normalized_attributes.sort(
        key=lambda item: (
            not item.get("is_primary_id", False),
            not item.get("is_primary_name", False),
            item.get("logical_name") or "",
        )
    )

    one_to_many = client.get(
        entity_path
        + "/OneToManyRelationships?$select="
        + ",".join(
            [
                "SchemaName",
                "MetadataId",
                "IsCustomRelationship",
                "IsHierarchical",
                "ReferencedEntity",
                "ReferencedAttribute",
                "ReferencingEntity",
                "ReferencingAttribute",
                "ReferencedEntityNavigationPropertyName",
                "ReferencingEntityNavigationPropertyName",
            ]
        )
    ).get("value", [])
    many_to_one = client.get(
        entity_path
        + "/ManyToOneRelationships?$select="
        + ",".join(
            [
                "SchemaName",
                "MetadataId",
                "IsCustomRelationship",
                "IsHierarchical",
                "ReferencedEntity",
                "ReferencedAttribute",
                "ReferencingEntity",
                "ReferencingAttribute",
                "ReferencedEntityNavigationPropertyName",
                "ReferencingEntityNavigationPropertyName",
            ]
        )
    ).get("value", [])
    many_to_many = client.get(
        entity_path
        + "/ManyToManyRelationships?$select="
        + ",".join(
            [
                "SchemaName",
                "MetadataId",
                "IsCustomRelationship",
                "IntersectEntityName",
                "Entity1LogicalName",
                "Entity1IntersectAttribute",
                "Entity1NavigationPropertyName",
                "Entity2LogicalName",
                "Entity2IntersectAttribute",
                "Entity2NavigationPropertyName",
            ]
        )
    ).get("value", [])

    return {
        "generated_at_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "environment_url": client.environment_url,
        "table": {
            "logical_name": table_raw.get("LogicalName"),
            "logical_collection_name": table_raw.get("LogicalCollectionName"),
            "schema_name": table_raw.get("SchemaName"),
            "entity_set_name": table_raw.get("EntitySetName"),
            "display_name": pick_label(table_raw.get("DisplayName"), language_code),
            "display_collection_name": pick_label(
                table_raw.get("DisplayCollectionName"), language_code
            ),
            "description": pick_label(table_raw.get("Description"), language_code),
            "primary_id_attribute": table_raw.get("PrimaryIdAttribute"),
            "primary_name_attribute": table_raw.get("PrimaryNameAttribute"),
            "object_type_code": table_raw.get("ObjectTypeCode"),
            "ownership_type": table_raw.get("OwnershipType"),
            "is_activity": table_raw.get("IsActivity"),
            "is_intersect": table_raw.get("IsIntersect"),
            "is_custom_entity": table_raw.get("IsCustomEntity"),
            "odata_collection_path": f"/api/data/{API_VERSION}/{table_raw.get('EntitySetName')}",
            "sql_table_name_hint": table_raw.get("LogicalName"),
        },
        "columns": normalized_attributes,
        "relationships": {
            "one_to_many": normalize_relationships(one_to_many, "one_to_many"),
            "many_to_one": normalize_relationships(many_to_one, "many_to_one"),
            "many_to_many": normalize_relationships(many_to_many, "many_to_many"),
        },
    }


def markdown_escape(value: Any) -> str:
    if value is None:
        return ""
    return str(value).replace("|", "\\|").replace("\n", " ")


def detail_summary(column: dict[str, Any]) -> str:
    details: list[str] = []
    if column.get("format_name"):
        details.append(f"format={column['format_name']}")
    elif column.get("format"):
        details.append(f"format={column['format']}")
    if column.get("date_time_behavior"):
        details.append(f"behavior={column['date_time_behavior']}")
    if column.get("max_length") is not None:
        details.append(f"maxLength={column['max_length']}")
    if column.get("min_value") is not None or column.get("max_value") is not None:
        details.append(f"range={column.get('min_value')}..{column.get('max_value')}")
    if column.get("precision") is not None:
        details.append(f"precision={column['precision']}")
    if column.get("targets"):
        details.append("targets=" + ",".join(column["targets"]))
    option_set = column.get("option_set")
    if option_set and option_set.get("options"):
        details.append(f"options={len(option_set['options'])}")
    return "; ".join(details)


def render_option_sets(columns: list[dict[str, Any]]) -> list[str]:
    lines: list[str] = []
    option_columns = [column for column in columns if column.get("option_set")]
    if not option_columns:
        return lines

    lines.append("## Choice Values")
    lines.append("")
    for column in option_columns:
        lines.append(
            f"### `{column['logical_name']}`"
            + (f" - {column['display_name']}" if column.get("display_name") else "")
        )
        lines.append("")
        lines.append("| Value | Label | State | Description |")
        lines.append("|------:|-------|-------|-------------|")
        for option in column["option_set"].get("options", []):
            lines.append(
                "| {value} | {label} | {state} | {description} |".format(
                    value=markdown_escape(option.get("value")),
                    label=markdown_escape(option.get("label")),
                    state=markdown_escape(option.get("state")),
                    description=markdown_escape(option.get("description")),
                )
            )
        lines.append("")
    return lines


def render_relationship_section(title: str, relationships: list[dict[str, Any]]) -> list[str]:
    lines = [f"## {title}", ""]
    if not relationships:
        lines.append("_None_")
        lines.append("")
        return lines

    if title == "Many-to-Many Relationships":
        lines.append(
            "| Schema | Intersect | Entity 1 | Attribute 1 | Nav 1 | Entity 2 | Attribute 2 | Nav 2 |"
        )
        lines.append(
            "|--------|-----------|----------|-------------|-------|----------|-------------|-------|"
        )
        for item in relationships:
            lines.append(
                "| {schema} | {intersect} | {e1} | {a1} | {n1} | {e2} | {a2} | {n2} |".format(
                    schema=markdown_escape(item.get("schema_name")),
                    intersect=markdown_escape(item.get("intersect_entity_name")),
                    e1=markdown_escape(item.get("entity1_logical_name")),
                    a1=markdown_escape(item.get("entity1_intersect_attribute")),
                    n1=markdown_escape(item.get("entity1_navigation_property_name")),
                    e2=markdown_escape(item.get("entity2_logical_name")),
                    a2=markdown_escape(item.get("entity2_intersect_attribute")),
                    n2=markdown_escape(item.get("entity2_navigation_property_name")),
                )
            )
    else:
        lines.append(
            "| Schema | Referenced Entity | Referenced Attribute | Referencing Entity | Referencing Attribute | Referenced Nav | Referencing Nav |"
        )
        lines.append(
            "|--------|-------------------|----------------------|--------------------|-----------------------|----------------|-----------------|"
        )
        for item in relationships:
            lines.append(
                "| {schema} | {re} | {ra} | {ing_e} | {ing_a} | {re_nav} | {ing_nav} |".format(
                    schema=markdown_escape(item.get("schema_name")),
                    re=markdown_escape(item.get("referenced_entity")),
                    ra=markdown_escape(item.get("referenced_attribute")),
                    ing_e=markdown_escape(item.get("referencing_entity")),
                    ing_a=markdown_escape(item.get("referencing_attribute")),
                    re_nav=markdown_escape(item.get("referenced_entity_navigation_property_name")),
                    ing_nav=markdown_escape(item.get("referencing_entity_navigation_property_name")),
                )
            )
    lines.append("")
    return lines


def render_table_markdown(payload: dict[str, Any]) -> str:
    table = payload["table"]
    columns = payload["columns"]
    relationships = payload["relationships"]

    lines = [
        f"# Dataverse Metadata: `{table['logical_name']}`",
        "",
        f"- Display name: {table.get('display_name') or ''}",
        f"- Entity set name: `{table.get('entity_set_name') or ''}`",
        f"- OData path: `{table.get('odata_collection_path') or ''}`",
        f"- SQL/TDS table hint: `{table.get('sql_table_name_hint') or ''}`",
        f"- Primary id attribute: `{table.get('primary_id_attribute') or ''}`",
        f"- Primary name attribute: `{table.get('primary_name_attribute') or ''}`",
        f"- Ownership type: `{table.get('ownership_type') or ''}`",
        f"- Custom table: `{table.get('is_custom_entity')}`",
        "",
        "## Columns",
        "",
        "| Logical Name | Type | Label | Required | Read | Create | Update | Details |",
        "|--------------|------|-------|----------|------|--------|--------|---------|",
    ]

    for column in columns:
        lines.append(
            "| {logical_name} | {attribute_type} | {display_name} | {required_level} | {read} | {create} | {update} | {details} |".format(
                logical_name=markdown_escape(column.get("logical_name")),
                attribute_type=markdown_escape(column.get("attribute_type")),
                display_name=markdown_escape(column.get("display_name")),
                required_level=markdown_escape(column.get("required_level")),
                read=markdown_escape(column.get("is_valid_for_read")),
                create=markdown_escape(column.get("is_valid_for_create")),
                update=markdown_escape(column.get("is_valid_for_update")),
                details=markdown_escape(detail_summary(column)),
            )
        )

    lines.extend([""])
    lines.extend(render_option_sets(columns))
    lines.extend(
        render_relationship_section(
            "Many-to-One Relationships", relationships.get("many_to_one", [])
        )
    )
    lines.extend(
        render_relationship_section(
            "One-to-Many Relationships", relationships.get("one_to_many", [])
        )
    )
    lines.extend(
        render_relationship_section(
            "Many-to-Many Relationships", relationships.get("many_to_many", [])
        )
    )
    return "\n".join(lines).rstrip() + "\n"


def write_text(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8", newline="\n")


def write_json(path: Path, payload: Any) -> None:
    write_text(path, json.dumps(payload, indent=2, ensure_ascii=False) + "\n")


def render_index_markdown(results: list[dict[str, Any]], output_dir: Path) -> str:
    lines = [
        "# Dataverse Metadata Export",
        "",
        f"- Output directory: `{output_dir.as_posix()}`",
        f"- Tables exported: {len(results)}",
        "",
        "| Table | Display Name | Entity Set | JSON | Markdown |",
        "|-------|--------------|------------|------|----------|",
    ]

    for payload in results:
        table = payload["table"]
        logical_name = table["logical_name"]
        lines.append(
            "| {logical} | {display} | {entity_set} | `{json_name}` | `{md_name}` |".format(
                logical=markdown_escape(logical_name),
                display=markdown_escape(table.get("display_name")),
                entity_set=markdown_escape(table.get("entity_set_name")),
                json_name=f"{logical_name}.json",
                md_name=f"{logical_name}.md",
            )
        )

    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    args = parse_args()
    tables = collect_tables(args.table, args.table_file)
    if not tables:
        raise SystemExit("Provide at least one table via --table or --table-file.")

    token = require_token(args.token_env)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    client = DataverseClient(args.environment_url, token, args.timeout_seconds)
    results: list[dict[str, Any]] = []

    for table_name in tables:
        print(f"[dataverse-metadata-export] Exporting {table_name}...", file=sys.stderr)
        payload = fetch_table_export(client, table_name, args.label_language)
        results.append(payload)
        write_json(output_dir / f"{table_name}.json", payload)
        write_text(output_dir / f"{table_name}.md", render_table_markdown(payload))

    index_payload = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "environment_url": normalize_environment_url(args.environment_url),
        "table_count": len(results),
        "tables": [
            {
                "logical_name": payload["table"]["logical_name"],
                "display_name": payload["table"].get("display_name"),
                "entity_set_name": payload["table"].get("entity_set_name"),
                "json_file": f"{payload['table']['logical_name']}.json",
                "markdown_file": f"{payload['table']['logical_name']}.md",
            }
            for payload in results
        ],
    }
    write_json(output_dir / "index.json", index_payload)
    write_text(output_dir / "index.md", render_index_markdown(results, output_dir))

    print(
        f"[dataverse-metadata-export] Wrote metadata for {len(results)} table(s) to {output_dir}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
