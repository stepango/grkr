import gleam/int
import gleam/string

import grkr/github_picker/client
import grkr/github_picker/config
import grkr/github_picker/decoder
import grkr/github_picker/query
import grkr/github_picker/selector
import grkr/github_picker/types

@external(javascript, "../github_picker/cli_ffi.mjs", "argv")
fn argv() -> List(String)

@external(javascript, "console", "log")
fn console_log(s: String) -> Nil

@external(javascript, "process", "exit")
fn exit(code: Int) -> Nil

fn shell_quote(value: String) -> String {
  "\""
    <> {
    value
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
    |> string.replace("$", "\\$")
    |> string.replace("`", "\\`")
  }
    <> "\""
}

fn emit(key: String, value: String) {
  console_log(key <> "=" <> shell_quote(value))
}

fn emit_error(msg: String) {
  console_log("ERROR=" <> shell_quote(msg))
}

/// CLI entrypoint for github_picker (GitHub-only v2).
/// Subcommands (safe, non-mutating, for discovery):
///   items-query   Print the GraphQL query for project items (using current config)
/// Default (no args): run picker (live or GITHUB_FIXTURE_PATH), emit SELECTED etc or ERROR
pub fn main() {
  let args = argv()
  case args {
    ["items-query"] -> emit_items_query()
    ["help"] -> emit_usage()
    [] ->
      case run() {
        Ok(_) -> Nil
        Error(e) -> emit_provider_error(e)
      }
    _ -> emit_usage()
  }
}

pub fn pick_next() -> Result(types.SelectedGitHubIssue, types.ProviderError) {
  /// Pure library entry for direct Gleam calls (e.g. from supervisor pick phase).
  /// No side effects, no console emit, no process.exit. Returns Selected or ProviderError.
  /// Respects GITHUB_FIXTURE_PATH for tests/fixtures. Reuses client/decoder/selector/config.
  /// CLI run() now delegates to this + handles emit/exit for compat.
  case config.load() {
    Error(e) -> Error(types.Config(e))
    Ok(cfg) -> {
      let fixture_path = get_env("GITHUB_FIXTURE_PATH")
      let items_json_res = case fixture_path == "" {
        True -> client.fetch_project_items_json(cfg)
        False -> client.read_fixture(fixture_path)
      }
      case items_json_res {
        Error(e) -> Error(e)
        Ok(items_json) ->
          case decoder.decode_project_items(items_json, cfg) {
            Error(de) -> Error(types.Decode(de))
            Ok(items) ->
              case selector.pick(items, cfg) {
                Ok(s) -> Ok(s)
                Error(se) -> Error(types.Selection(se))
              }
          }
      }
    }
  }
}

pub fn run() -> Result(types.SelectedGitHubIssue, types.ProviderError) {
  case pick_next() {
    Ok(sel) -> {
      emit("SELECTED", "1")
      emit("ISSUE_NUMBER", int.to_string(sel.issue_number))
      emit("ISSUE_TITLE", sel.issue_title)
      emit("ISSUE_UPDATED_AT", sel.issue_updated_at)
      emit("PRIORITY_NAME", sel.priority_name)
      emit("PRIORITY_NUMBER", sel.priority_number)
      emit("JOB_KEY", sel.job_key)
      emit("TASK_SLUG", sel.task_slug)
      emit("PROJECT_ITEM_ID", sel.project_item_id)
      exit(0)
      Ok(sel)
    }
    Error(types.Selection(types.NoMatchingIssue)) -> {
      emit("SELECTED", "0")
      exit(0)
      Error(types.Selection(types.NoMatchingIssue))
    }
    Error(e) -> {
      emit_provider_error(e)
      Error(e)
    }
  }
}

fn emit_items_query() {
  case config.load() {
    Ok(cfg) -> {
      let q = query.build_user_project_items_query_first(
        cfg.project_owner,
        cfg.project_number,
      )
      console_log(q)
      exit(0)
    }
    Error(e) -> {
      console_log("Error loading config: " <> config_error_to_string(e))
      exit(1)
    }
  }
}

fn emit_usage() {
  console_log("Usage: gleam run -m grkr/github_picker/main")
  console_log("       gleam run -m grkr/github_picker/main items-query")
  console_log("       gleam run -m grkr/github_picker/main help")
  console_log("")
  console_log("GitHub picker (v2) subcommands:")
  console_log("  (no args)     Select a GitHub issue from project Todo and emit shell vars")
  console_log("  items-query   Print the GraphQL query for fetching project items (safe)")
  console_log("  help          This message")
  console_log("")
  console_log("Supports GITHUB_FIXTURE_PATH for test fixtures (bypasses gh).")
  console_log("Requires gh CLI auth for live runs.")
  exit(2)
}

fn emit_provider_error(e: types.ProviderError) {
  emit_error(types.provider_error_to_string(e))
  exit(1)
}

fn config_error_to_string(e: types.ConfigError) -> String {
  case e {
    types.MissingRequired(f) -> "Missing required: " <> f
    types.InvalidProjectNumber(v) -> "Invalid PROJECT_NUMBER: " <> v
    types.InvalidPriorityMode(v) -> "Invalid PRIORITY_MODE: " <> v
    types.ActiveJobsUnreadable(p) -> "Active jobs unreadable: " <> p
  }
}

@external(javascript, "../github_picker/env.mjs", "getEnv")
fn get_env(name: String) -> String
