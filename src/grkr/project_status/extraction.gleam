import gleam/list
import gleam/option.{type Option, None, Some}
import grkr/issue_provider/ffi
import grkr/project_status/types.{type ProjectMetadata, ProjectMetadata}

pub fn extract_item_id(
  issue_json: String,
  project_number: Option(Int),
) -> Option(String) {
  case ffi.parse(issue_json) {
    Ok(obj) -> {
      let items = get_project_items(obj)
      case first_matching_project_item(items, project_number) {
        Some(item) -> get_string(item, "id")
        None -> first_item_id(items)
      }
    }
    Error(_) -> None
  }
}

pub fn extract_status_name(
  issue_json: String,
  project_number: Option(Int),
) -> Option(String) {
  case ffi.parse(issue_json) {
    Ok(obj) -> {
      let items = get_project_items(obj)
      case first_matching_project_item(items, project_number) {
        Some(item) -> status_name(item)
        None -> first_status_name(items)
      }
    }
    Error(_) -> None
  }
}

pub fn extract_project_metadata(
  project_json: String,
) -> Result(ProjectMetadata, String) {
  case ffi.parse(project_json) {
    Ok(obj) -> {
      let project = ffi.get_field(obj, "project")
      let id =
        first_string([ffi.get_field(obj, "id"), ffi.get_field(project, "id")])
      let number =
        first_int([
          ffi.get_field(obj, "number"),
          ffi.get_field(project, "number"),
        ])
      let owner =
        first_string([
          ffi.get_field(obj, "owner"),
          ffi.get_field(project, "owner"),
        ])
      case id {
        Some(project_id) ->
          Ok(ProjectMetadata(
            id: project_id,
            number: option.unwrap(number, 0),
            owner: option.unwrap(owner, ""),
          ))
        None -> Error("Missing required project id")
      }
    }
    Error(_) -> Error("Invalid project JSON")
  }
}

pub fn extract_issue_number(issue_json: String) -> Result(Int, String) {
  case ffi.parse(issue_json) {
    Ok(obj) ->
      case decode_int(ffi.get_field(obj, "number")) {
        Some(number) -> Ok(number)
        None -> Error("Missing issue number")
      }
    Error(_) -> Error("Invalid issue JSON")
  }
}

pub fn find_item_id_by_issue_number(
  items_json: String,
  issue_number: Int,
) -> Option(String) {
  case ffi.parse(items_json) {
    Ok(obj) -> {
      let items = case decode_array(ffi.get_field(obj, "items")) {
        Ok(values) -> values
        Error(_) ->
          case decode_array(obj) {
            Ok(values) -> values
            Error(_) -> []
          }
      }

      case
        list.find(items, fn(item) {
          content_issue_number(item) == Some(issue_number)
        })
      {
        Ok(item) -> get_string(item, "id")
        Error(_) -> None
      }
    }
    Error(_) -> None
  }
}

fn get_project_items(obj: ffi.JsonValue) -> List(ffi.JsonValue) {
  case decode_array(ffi.get_field(obj, "projectItems")) {
    Ok(items) -> items
    Error(_) -> []
  }
}

fn first_matching_project_item(
  items: List(ffi.JsonValue),
  project_number: Option(Int),
) -> Option(ffi.JsonValue) {
  case project_number {
    None ->
      case items {
        [first, ..] -> Some(first)
        [] -> None
      }
    Some(number) ->
      case
        list.find(items, fn(item) { item_project_number(item) == Some(number) })
      {
        Ok(item) -> Some(item)
        Error(_) -> None
      }
  }
}

fn first_item_id(items: List(ffi.JsonValue)) -> Option(String) {
  case items {
    [first, ..] -> get_string(first, "id")
    [] -> None
  }
}

fn first_status_name(items: List(ffi.JsonValue)) -> Option(String) {
  case items {
    [first, ..] -> status_name(first)
    [] -> None
  }
}

fn status_name(item: ffi.JsonValue) -> Option(String) {
  let status = ffi.get_field(item, "status")
  get_string(status, "name")
}

fn item_project_number(item: ffi.JsonValue) -> Option(Int) {
  let project = ffi.get_field(item, "project")
  first_int([
    ffi.get_field(project, "number"),
    ffi.get_field(item, "number"),
  ])
}

fn content_issue_number(item: ffi.JsonValue) -> Option(Int) {
  let content = ffi.get_field(item, "content")
  let content_issue = ffi.get_field(content, "issue")
  let issue = ffi.get_field(item, "issue")
  first_int([
    ffi.get_field(content, "number"),
    ffi.get_field(content_issue, "number"),
    ffi.get_field(issue, "number"),
    ffi.get_field(item, "number"),
  ])
}

fn get_string(obj: ffi.JsonValue, field: String) -> Option(String) {
  decode_string(ffi.get_field(obj, field))
}

fn first_string(values: List(ffi.JsonValue)) -> Option(String) {
  case values {
    [] -> None
    [first, ..rest] ->
      case decode_string(first) {
        Some(value) -> Some(value)
        None -> first_string(rest)
      }
  }
}

fn first_int(values: List(ffi.JsonValue)) -> Option(Int) {
  case values {
    [] -> None
    [first, ..rest] ->
      case decode_int(first) {
        Some(value) -> Some(value)
        None -> first_int(rest)
      }
  }
}

fn decode_string(value: ffi.JsonValue) -> Option(String) {
  case ffi.decode_string(value) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn decode_int(value: ffi.JsonValue) -> Option(Int) {
  case ffi.decode_int(value) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn decode_array(value: ffi.JsonValue) -> Result(List(ffi.JsonValue), String) {
  ffi.decode_array(value)
}
