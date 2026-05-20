import gleam/int
import gleam/list
import gleam/string

import grkr/github_picker/ffi

/// Normalize repo name for comparison (ported from bash jq normalize_repo_name + selector)
/// Strips github urls and .git, trims. Used for exact repo match in is_candidate.
pub fn normalize_repo(r: String) -> String {
  r
  |> string.replace("https://github.com/", "")
  |> string.replace("http://github.com/", "")
  |> string.replace(".git", "")
  |> string.trim
}

/// Walk nested fields in JsonValue (for decoder extract)
pub fn walk_path(obj: ffi.JsonValue, path: List(String)) -> ffi.JsonValue {
  case path {
    [] -> obj
    [head, ..tail] -> {
      let next = ffi.get_field(obj, head)
      walk_path(next, tail)
    }
  }
}

/// Try to extract the items.nodes array from GraphQL response (user or org fallback)
/// Ported from decoder, now shared for potential fallback shape handling too.
pub fn extract_items_nodes(json: ffi.JsonValue) -> List(ffi.JsonValue) {
  // Prefer {items: [...]} shape returned by fetch_project_items_json
  // (wraps graphql nodes from user/org queries, or flat items from gh project item-list fallback)
  let items_path = ["items"]
  case walk_path(json, items_path) |> ffi.decode_array {
    Ok(nodes) -> nodes
    Error(_) -> {
      // Fallback: raw GraphQL responses with data.user... or data.organization...
      let user_path = ["data", "user", "projectV2", "items", "nodes"]
      case walk_path(json, user_path) |> ffi.decode_array {
        Ok(nodes) -> nodes
        Error(_) -> {
          let org_path = ["data", "organization", "projectV2", "items", "nodes"]
          case walk_path(json, org_path) |> ffi.decode_array {
            Ok(nodes) -> nodes
            Error(_) -> []
          }
        }
      }
    }
  }
}

/// Find the fieldValue node for a given field name (status or priority) from fieldValues.nodes
/// Handles the GraphQL shape; falls back to direct field.
pub fn get_field_value_by_name(
  item_node: ffi.JsonValue,
  field_name: String,
) -> ffi.JsonValue {
  let field_values = ffi.get_field(item_node, "fieldValues")
  let nodes_res = ffi.get_field(field_values, "nodes") |> ffi.decode_array
  case nodes_res {
    Ok(nodes) -> {
      // find the node whose .field.name == field_name
      case
        list.find(nodes, fn(n) {
          let f = ffi.get_field(n, "field")
          case ffi.get_field(f, "name") |> ffi.decode_string {
            Ok(name) -> name == field_name
            _ -> False
          }
        })
      {
        Ok(found) -> found
        Error(_) -> {
          // fallback, perhaps the field is direct on some responses
          ffi.get_field(item_node, field_name)
        }
      }
    }
    Error(_) -> ffi.get_field(item_node, field_name)
  }
}

/// Extract display text from a field value node. Prefers name, title, text, then number as string.
/// Ported from decoder (used for status_name, priority name, title etc)
pub fn field_text(fv: ffi.JsonValue) -> String {
  // Prefer name, title, text, then number as string
  case ffi.get_field(fv, "name") |> ffi.decode_string {
    Ok(s) if s != "" -> s
    _ ->
      case ffi.get_field(fv, "title") |> ffi.decode_string {
        Ok(s) if s != "" -> s
        _ ->
          case ffi.get_field(fv, "text") |> ffi.decode_string {
            Ok(s) if s != "" -> s
            _ ->
              case ffi.get_field(fv, "number") |> ffi.decode_int {
                Ok(n) -> int.to_string(n)
                _ -> ""
              }
          }
      }
  }
}
