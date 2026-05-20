import gleam/int
import gleam/list
import grkr/github_picker/ffi
import grkr/github_picker/field
import grkr/github_picker/types

/// Try to extract the items.nodes array from GraphQL response (user or org fallback)
pub fn extract_items_nodes(json: ffi.JsonValue) -> List(ffi.JsonValue) {
  field.extract_items_nodes(json)
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

  let status_node = field.get_field_value_by_name(node, cfg.status_field_name)
  let status_name = field.field_text(status_node)

  let priority_node = field.get_field_value_by_name(node, cfg.priority_field_name)
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

  let title = field.field_text(ffi.get_field(content, "title"))

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
      let name = field.field_text(fv)
      case name {
        "" -> types.NoPriority
        n -> types.SingleSelectValue(n)
      }
    }
  }
}

/// General helper to treat a JsonValue as array (empty on null/missing per design)
pub fn arrayify(v: ffi.JsonValue) -> List(ffi.JsonValue) {
  case ffi.decode_array(v) {
    Ok(a) -> a
    Error(_) -> []
  }
}

/// Decode all items from the GraphQL response JSON string.
/// Stops on first decode error (early return style).
pub fn decode_project_items(
  json_string: String,
  cfg: types.GitHubPickerConfig,
) -> Result(List(types.ProjectItem), String) {
  case ffi.parse(json_string) {
    Ok(json) -> {
      let nodes = extract_items_nodes(json)
      try_map_decode(nodes, cfg)
    }
    Error(e) -> Error("JSON parse failed: " <> e)
  }
}

/// Internal early-exit mapper for decode (avoids processing all on error)
fn try_map_decode(
  nodes: List(ffi.JsonValue),
  cfg: types.GitHubPickerConfig,
) -> Result(List(types.ProjectItem), String) {
  case nodes {
    [] -> Ok([])
    [head, ..tail] ->
      case decode_project_item(head, cfg) {
        Ok(item) ->
          case try_map_decode(tail, cfg) {
            Ok(rest) -> Ok([item, ..rest])
            err -> err
          }
        Error(e) -> Error(e)
      }
  }
}
