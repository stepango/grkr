import gleam/int
import gleam/list

import grkr/github_picker/ffi
import grkr/github_picker/field
import grkr/github_picker/query
import grkr/github_picker/types

@external(javascript, "../github_picker/file.mjs", "readFileSync")
fn read_file_sync(path: String) -> Result(String, String)

/// Main entry for live fetch: tries GraphQL user then org (with pagination), falls back to gh project item-list.
/// Returns the items_json string in shape decoder expects ({items:..} or raw).
pub fn fetch_project_items_json(
  cfg: types.GitHubPickerConfig,
) -> Result(String, types.ProviderError) {
  case try_fetch_scope("user", cfg) {
    Ok(json) if json != "" -> Ok(json)
    _ ->
      case try_fetch_scope("organization", cfg) {
        Ok(json) if json != "" -> Ok(json)
        _ ->
          case ffi.run_gh_project_item_list(int.to_string(cfg.project_number), cfg.project_owner) {
            Ok(j) -> Ok(j)
            Error(e) -> Error(types.Query("all fetches failed: " <> e))
          }
      }
  }
}

fn try_fetch_scope(
  scope: String,
  cfg: types.GitHubPickerConfig,
) -> Result(String, String) {
  case fetch_all_nodes(scope, cfg.project_owner, cfg.project_number) {
    Ok(nodes) -> {
      // wrap in {items: nodes} to match shell normalized shape (decoder prefers it)
      Ok(ffi.build_items_json(nodes))
    }
    Error(e) -> Error(e)
  }
}

fn fetch_all_nodes(
  scope: String,
  owner: String,
  project_number: Int,
) -> Result(List(ffi.JsonValue), String) {
  fetch_nodes_page(scope, owner, project_number, Error(Nil), [])
}

fn fetch_nodes_page(
  scope: String,
  owner: String,
  project_number: Int,
  cursor: Result(String, Nil),
  acc: List(ffi.JsonValue),
) -> Result(List(ffi.JsonValue), String) {
  let q = case scope {
    "user" -> query.build_user_project_items_query(owner, project_number, cursor)
    _ -> query.build_org_project_items_query(owner, project_number, cursor)
  }

  case ffi.run_gh_api_graphql(q) {
    Error(e) -> Error(e)
    Ok(resp) ->
      case ffi.parse(resp) {
        Error(e) -> Error("JSON parse failed: " <> e)
        Ok(json) -> {
          let nodes = extract_nodes(json, scope)
          let acc2 = list.append(acc, nodes)
          let #(has_next, next_cursor) = extract_page_info(json, scope)
          case has_next {
            False -> Ok(acc2)
            True ->
              case next_cursor {
                "" -> Ok(acc2)
                c -> fetch_nodes_page(scope, owner, project_number, Ok(c), acc2)
              }
          }
        }
      }
  }
}

fn extract_nodes(json: ffi.JsonValue, scope: String) -> List(ffi.JsonValue) {
  let path = case scope {
    "user" -> ["data", "user", "projectV2", "items", "nodes"]
    _ -> ["data", "organization", "projectV2", "items", "nodes"]
  }
  case field.walk_path(json, path) |> ffi.decode_array {
    Ok(n) -> n
    Error(_) -> []
  }
}

fn extract_page_info(json: ffi.JsonValue, scope: String) -> #(Bool, String) {
  let path = case scope {
    "user" -> ["data", "user", "projectV2", "items", "pageInfo"]
    _ -> ["data", "organization", "projectV2", "items", "pageInfo"]
  }
  let pi = field.walk_path(json, path)
  let has = case ffi.get_field(pi, "hasNextPage") |> ffi.decode_bool {
    Ok(True) -> True
    _ -> False
  }
  let cursor = case ffi.get_field(pi, "endCursor") |> ffi.decode_string {
    Ok(c) if c != "" -> c
    _ -> ""
  }
  #(has, cursor)
}

/// For fixture mode: read the file content (the test JSON or live fixture shape)
pub fn read_fixture(path: String) -> Result(String, types.ProviderError) {
  case read_file_sync(path) {
    Ok(contents) -> Ok(contents)
    Error(msg) -> Error(types.Query("failed to read GITHUB_FIXTURE_PATH: " <> msg))
  }
}
