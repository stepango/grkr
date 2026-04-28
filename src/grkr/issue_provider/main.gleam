import gleam/int
import gleam/io
import gleam/string
import grkr/issue_provider/config
import grkr/issue_provider/decoder
import grkr/issue_provider/selector
import grkr/issue_provider/types

/// Linear issue selection entrypoint used by `worker-pick-issue.sh` when
/// `GRKR_ISSUE_PROVIDER=linear`.
pub fn main() -> Nil {
  case run() {
    Ok(issue) -> emit_success(issue)
    Error(error) -> emit_error(error)
  }
}

pub fn run() -> Result(types.SelectedIssue, types.ProviderError) {
  use linear_config <- result_try_config(config.load_linear_config())
  let fixture_path = get_env("LINEAR_FIXTURE_PATH")

  case fixture_path == "" {
    True ->
      Error(types.QueryError(
        "Linear live queries require OAuth installation/access-token setup; set LINEAR_FIXTURE_PATH for fixture-backed selection in this slice",
      ))
    False -> {
      use contents <- result_try_provider(read_fixture(fixture_path))
      use issues <- result_try_provider(decode_fixture(contents))
      let filter = config.config_to_filter(linear_config)
      case selector.select_issue(issues, filter, linear_config.priority_order) {
        types.SelectionSuccess(selected, total_candidates) -> {
          io.println(
            "Found "
            <> int.to_string(total_candidates)
            <> " candidate(s), selected: "
            <> selected.identifier,
          )
          Ok(selected)
        }
        types.NoMatchingIssues -> Error(types.NoMatchingIssue)
        types.ProviderFailed(error) -> Error(error)
      }
    }
  }
}

fn result_try_config(
  result: Result(config.LinearConfig, types.ConfigError),
  next: fn(config.LinearConfig) -> Result(types.SelectedIssue, types.ProviderError),
) -> Result(types.SelectedIssue, types.ProviderError) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(types.ConfigError(error))
  }
}

fn result_try_provider(
  result: Result(a, types.ProviderError),
  next: fn(a) -> Result(types.SelectedIssue, types.ProviderError),
) -> Result(types.SelectedIssue, types.ProviderError) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}

fn read_fixture(path: String) -> Result(String, types.ProviderError) {
  case read_file(path) {
    Ok(contents) -> Ok(contents)
    Error(message) -> Error(types.QueryError("failed to read Linear fixture: " <> message))
  }
}

fn decode_fixture(contents: String) -> Result(List(types.LinearIssue), types.ProviderError) {
  case decoder.decode_issues_response(contents) {
    Ok(issues) -> Ok(issues)
    Error(message) -> Error(types.ParseError("failed to decode Linear fixture: " <> message))
  }
}

fn emit_success(issue: types.SelectedIssue) -> Nil {
  io.println("SELECTED=1")
  io.println("ISSUE_IDENTIFIER=" <> shell_quote(issue.identifier))
  io.println("ISSUE_TITLE=" <> shell_quote(issue.title))
  io.println("ISSUE_URL=" <> shell_quote(issue.url))
  io.println("ISSUE_STATE=" <> shell_quote(issue.state_name))
  io.println("ISSUE_PRIORITY=" <> shell_quote(priority_to_string(issue.priority)))
  io.println("ISSUE_UPDATED_AT=" <> shell_quote(issue.updated_at))
  io.println("JOB_KEY=" <> shell_quote("linear:" <> issue.identifier <> ":execution"))
  io.println("TASK_SLUG=" <> shell_quote(slug_from_identifier(issue.identifier)))
}

fn emit_error(error: types.ProviderError) -> Nil {
  io.println("SELECTED=0")
  io.println("ERROR=" <> shell_quote(provider_error_to_string(error)))
}

fn provider_error_to_string(error: types.ProviderError) -> String {
  case error {
    types.ConfigError(config_error) -> config_error_to_string(config_error)
    types.QueryError(message) -> "Query error: " <> message
    types.ParseError(message) -> "Parse error: " <> message
    types.NoMatchingIssue -> "No matching issue found"
  }
}

fn config_error_to_string(error: types.ConfigError) -> String {
  case error {
    types.MissingCredentialPath -> "Missing required Linear config: LINEAR_ASSIGNEE_ID"
    types.InvalidCredentialFormat -> "Invalid Linear config format"
    types.MissingProjectId -> "Missing Linear project id"
    types.MissingTeamId -> "Missing Linear team id"
    types.InvalidProvider(name) -> "Invalid issue provider: " <> name
  }
}

fn priority_to_string(priority: types.LinearPriority) -> String {
  case priority {
    types.Urgent -> "urgent"
    types.High -> "high"
    types.Medium -> "medium"
    types.Low -> "low"
    types.NoPriority -> "none"
  }
}

fn slug_from_identifier(identifier: String) -> String {
  identifier
  |> string.lowercase
  |> string.replace("/", "-")
}

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

@external(javascript, "../issue_provider/env.mjs", "getEnv")
fn get_env(name: String) -> String

@external(javascript, "../issue_provider/file.mjs", "readFileSync")
fn read_file(path: String) -> Result(String, String)
