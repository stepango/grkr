import gleam/list
import gleam/string
import grkr/issue_provider/ffi
import grkr/issue_provider/types

/// Decode Linear state from JSON
pub fn decode_state(obj: ffi.JsonValue) -> Result(types.LinearState, String) {
  let id = ffi.get_field(obj, "id")
  let name = ffi.get_field(obj, "name")
  let state_type = ffi.get_field(obj, "type")

  case
    ffi.decode_string(id),
    ffi.decode_string(name),
    ffi.decode_string(state_type)
  {
    Ok(i), Ok(n), Ok(t) -> Ok(types.LinearState(id: i, name: n, state_type: t))
    _, _, _ -> Error("Invalid state")
  }
}

/// Decode Linear assignee from JSON
fn decode_assignee(obj: ffi.JsonValue) -> Result(types.LinearAssignee, String) {
  let id = ffi.get_field(obj, "id")
  let name = ffi.get_field(obj, "name")
  let display_name = ffi.get_field(obj, "displayName")

  case
    ffi.decode_string(id),
    ffi.decode_string(name),
    ffi.decode_string(display_name)
  {
    Ok(i), Ok(n), Ok(d) ->
      Ok(types.LinearAssignee(id: i, name: n, display_name: d))
    _, _, _ -> Error("Invalid assignee")
  }
}

/// Decode Linear project from JSON
fn decode_project(obj: ffi.JsonValue) -> Result(types.LinearProject, String) {
  let id = ffi.get_field(obj, "id")
  let name = ffi.get_field(obj, "name")
  let url = ffi.get_field(obj, "url")

  case ffi.decode_string(id), ffi.decode_string(name), ffi.decode_string(url) {
    Ok(i), Ok(n), Ok(u) -> Ok(types.LinearProject(id: i, name: n, url: u))
    _, _, _ -> Error("Invalid project")
  }
}

/// Decode Linear team from JSON
fn decode_team(obj: ffi.JsonValue) -> Result(types.LinearTeam, String) {
  let id = ffi.get_field(obj, "id")
  let key = ffi.get_field(obj, "key")
  let name = ffi.get_field(obj, "name")

  case ffi.decode_string(id), ffi.decode_string(key), ffi.decode_string(name) {
    Ok(i), Ok(k), Ok(n) -> Ok(types.LinearTeam(id: i, key: k, name: n))
    _, _, _ -> Error("Invalid team")
  }
}

/// Decode Linear priority from the API value.
fn decode_priority(str: ffi.JsonValue) -> types.LinearPriority {
  case ffi.decode_int(str) {
    Ok(value) -> types.parse_priority_number(value)
    Error(_) -> {
      case ffi.decode_string(str) {
        Ok(s) -> types.parse_priority(string.lowercase(s))
        Error(_) -> types.NoPriority
      }
    }
  }
}

/// Decode Linear issue from JSON
pub fn decode_issue(obj: ffi.JsonValue) -> Result(types.LinearIssue, String) {
  let id = ffi.get_field(obj, "id")
  let identifier = ffi.get_field(obj, "identifier")
  let title = ffi.get_field(obj, "title")
  let description = ffi.get_field(obj, "description")
  let url = ffi.get_field(obj, "url")
  let state_obj = ffi.get_field(obj, "state")
  let priority_val = ffi.get_field(obj, "priority")
  let assignee_obj = ffi.get_field(obj, "assignee")
  let project_obj = ffi.get_field(obj, "project")
  let team_obj = ffi.get_field(obj, "team")
  let created_at = ffi.get_field(obj, "createdAt")
  let updated_at = ffi.get_field(obj, "updatedAt")

  case
    ffi.decode_string(id),
    ffi.decode_string(identifier),
    ffi.decode_string(title),
    ffi.decode_string(url),
    ffi.decode_string(created_at),
    ffi.decode_string(updated_at)
  {
    Ok(i), Ok(ident), Ok(t), Ok(u), Ok(ca), Ok(ua) -> {
      let state = case decode_state(state_obj) {
        Ok(s) -> s
        Error(_) -> types.LinearState(id: "", name: "", state_type: "")
      }

      let priority = decode_priority(priority_val)

      let assignee = case ffi.is_null(assignee_obj) {
        True -> Error(Nil)
        False ->
          case decode_assignee(assignee_obj) {
            Ok(a) -> Ok(a)
            Error(_) -> Error(Nil)
          }
      }

      let project = case ffi.is_null(project_obj) {
        True -> Error(Nil)
        False ->
          case decode_project(project_obj) {
            Ok(p) -> Ok(p)
            Error(_) -> Error(Nil)
          }
      }

      let team = case ffi.is_null(team_obj) {
        True -> Error(Nil)
        False ->
          case decode_team(team_obj) {
            Ok(t) -> Ok(t)
            Error(_) -> Error(Nil)
          }
      }

      let description_str = case ffi.decode_string(description) {
        Ok(d) -> d
        Error(_) -> ""
      }

      Ok(types.LinearIssue(
        id: i,
        identifier: ident,
        title: t,
        description: description_str,
        url: u,
        state: state,
        priority: priority,
        assignee: assignee,
        project: project,
        team: team,
        created_at: ca,
        updated_at: ua,
      ))
    }
    _, _, _, _, _, _ -> Error("Invalid issue")
  }
}

/// Decode a list of Linear issues
pub fn decode_issues(
  arr: ffi.JsonValue,
) -> Result(List(types.LinearIssue), String) {
  case ffi.decode_array(arr) {
    Ok(items) -> {
      list.try_map(items, decode_issue)
    }
    Error(_) -> Error("Expected array")
  }
}

/// Decode Linear API response with issues
pub fn decode_issues_response(
  json_string: String,
) -> Result(List(types.LinearIssue), String) {
  case ffi.parse(json_string) {
    Ok(parsed) -> {
      let data = ffi.get_field(parsed, "data")
      let viewer = ffi.get_field(data, "viewer")
      let assigned_issues = ffi.get_field(viewer, "assignedIssues")
      let nodes = ffi.get_field(assigned_issues, "nodes")

      decode_issues(nodes)
    }
    Error(msg) -> Error("JSON parse error: " <> msg)
  }
}

/// Decode Linear teams response
pub fn decode_teams_response(
  json_string: String,
) -> Result(List(types.LinearTeam), String) {
  case ffi.parse(json_string) {
    Ok(parsed) -> {
      let data = ffi.get_field(parsed, "data")
      let viewer = ffi.get_field(data, "viewer")
      let teams = ffi.get_field(viewer, "teams")
      let nodes = ffi.get_field(teams, "nodes")

      case ffi.decode_array(nodes) {
        Ok(items) -> list.try_map(items, decode_team)
        Error(_) -> Error("Expected array")
      }
    }
    Error(msg) -> Error("JSON parse error: " <> msg)
  }
}

/// Decode Linear projects response
pub fn decode_projects_response(
  json_string: String,
) -> Result(List(types.LinearProject), String) {
  case ffi.parse(json_string) {
    Ok(parsed) -> {
      let data = ffi.get_field(parsed, "data")
      let team = ffi.get_field(data, "team")
      let projects = ffi.get_field(team, "projects")
      let nodes = ffi.get_field(projects, "nodes")

      case ffi.decode_array(nodes) {
        Ok(items) -> list.try_map(items, decode_project)
        Error(_) -> Error("Expected array")
      }
    }
    Error(msg) -> Error("JSON parse error: " <> msg)
  }
}
