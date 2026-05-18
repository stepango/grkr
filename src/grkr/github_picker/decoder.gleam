import gleam/int
import gleam/list
import grkr/github_picker/ffi
import grkr/github_picker/field
import grkr/github_picker/types

/// Try to extract the items.nodes array from GraphQL response (user or org fallback)
pub fn extract_items_nodes(json: ffi.JsonValue) -> List(ffi.JsonValue) {
  // Try data.user.projectV2.items.nodes
  let user_path = ["data", "user", "projectV2", "items", "nodes"]
  case walk_path(json, user_path) |> ffi.decode_array {
    Ok(nodes) -> nodes
    Error(_) -> {
      // Try data.organization.projectV2.items.nodes
      let org_path = ["data", "organization", "projectV2", "items", "nodes"]
      case walk_path(json, org_path) |> ffi.decode_array {
        Ok(nodes) -> nodes
        Error(_) -> []
      }
    }
  }
}

fn walk_path(obj: ffi.JsonValue, path: List(String)) -> ffi.JsonValue {
  case path {
    [] -> obj
    [head, ..tail] -> {
      let next = ffi.get_field(obj, head)
      walk_path(next, tail)
    }
  }
}

/// Decode a single ProjectItem from a GraphQL item node + cfg for field names
pub fn decode_project_item(
  node: ffi.JsonValue,
  cfg: types.GitHubPickerConfig,
) -> Result(types.ProjectItem, String) {
  let project_item_id = case ffi.get_field(node, "id") |> ffi.decode_string {
    Ok(id) -> id
    Error(_) -> ""
  }

  let content_node = ffi.get_field(node, "content")
  let content = decode_content(content_node)

  let status_node = get_field_value_by_name(node, cfg.status_field_name)
  let status_name = field_text(status_node)

  let priority_node = get_field_value_by_name(node, cfg.priority_field_name)
  let priority = decode_priority_value(priority_node, cfg.priority_mode)

  Ok(
    types.ProjectItem(
      project_item_id: project_item_id,
      content: content,
      status_name: status_name,
      priority: priority,
    ),
  )
}

fn decode_content(content: ffi.JsonValue) -> types.IssueContent {
  // content can be { __typename: "Issue", number, title, ... } or for PR
  // or null for draft items etc.
  let number = case
    ffi.get_field(content, "number") |> ffi.decode_int,
    ffi.get_field(content, "number") |> ffi.decode_string
  {
    Ok(n), _ -> n
    _, Ok(s) ->
      case int.parse(s) {
        Ok(n) -> n
        _ -> 0
      }
    _, _ -> 0
  }

  let title = field_text(ffi.get_field(content, "title"))

  let updated_at =
    case ffi.get_field(content, "updatedAt") |> ffi.decode_string {
      Ok(u) -> u
      _ -> ""
    }

  let state =
    case ffi.get_field(content, "state") |> ffi.decode_string {
      Ok(s) -> s
      _ -> ""
    }

  let repository =
    case ffi.get_field(content, "repository") |> ffi.get_field("nameWithOwner") |> ffi.decode_string {
      Ok(r) -> r
      _ ->
        case ffi.get_field(content, "repository") |> ffi.get_field("name") |> ffi.decode_string {
          Ok(r) -> r
          _ -> ""
        }
    }

  let assignees_node = ffi.get_field(content, "assignees")
  let assignee_logins = case ffi.get_field(assignees_node, "nodes") |> ffi.decode_array {
    Ok(nodes) ->
      nodes
      |> list.map(fn(a) { ffi.get_field(a, "login") |> ffi.decode_string })
      |> list.filter_map(fn(r) {
        case r {
          Ok(login) -> Ok(login)
          _ -> Error(Nil)
        }
      })
    _ -> []
  }

  types.IssueContent(
    number: number,
    title: title,
    updated_at: updated_at,
    state: state,
    repository: repository,
    assignee_logins: assignee_logins,
  )
}

fn get_field_value_by_name(
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

fn field_text(fv: ffi.JsonValue) -> String {
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

fn decode_priority_value(
  fv: ffi.JsonValue,
  mode: types.PriorityMode,
) -> types.PriorityValue {
  case mode {
    types.Number -> {
      case ffi.get_field(fv, "number") |> ffi.decode_int {
        Ok(n) -> types.NumberValue(n)
        _ -> types.NoPriority
      }
    }
    types.SingleSelect -> {
      let name = field_text(fv)
      case name {
        "" -> types.NoPriority
        n -> types.SingleSelectValue(n)
      }
    }
  }
}

/// Decode all items from the GraphQL response JSON string
pub fn decode_project_items(
  json_string: String,
  cfg: types.GitHubPickerConfig,
) -> Result(List(types.ProjectItem), String) {
  case ffi.parse(json_string) {
    Ok(json) -> {
      let nodes = extract_items_nodes(json)
      nodes
      |> list.map(fn(node) { decode_project_item(node, cfg) })
      |> list.fold(Ok([]), fn(acc, res) {
        case acc, res {
          Ok(items), Ok(item) -> Ok(list.append(items, [item]))
          Error(e), _ -> Error(e)
          _, Error(e) -> Error(e)
        }
      })
    }
    Error(e) -> Error("JSON parse failed: " <> e)
  }
}
