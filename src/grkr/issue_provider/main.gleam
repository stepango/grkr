import gleam/io
import gleam/string
import grkr/issue_provider/client
import grkr/issue_provider/config
import grkr/issue_provider/decoder
import grkr/issue_provider/query
import grkr/issue_provider/selector
import grkr/issue_provider/types

/// Linear issue selection entrypoint used by `worker-pick-issue.sh` when
/// `GRKR_ISSUE_PROVIDER=linear`.
///
/// CLI subcommands for safe Linear discovery/query:
/// - `viewer-query`: print viewer GraphQL query
/// - `teams-query`: print teams discovery query
/// - `team-projects-query <team-id>`: print project discovery query for a team
/// - `issue-query <identifier>`: print single issue query
/// - `assigned-issues-query`: print assigned issues query using current config
/// - `fetch-issue <identifier>`: load one issue (fixture or live) and emit shell KEY=val
///
/// Default behavior (no args): select a Linear issue and emit shell assignments
pub fn main() -> Nil {
  case argv() {
    ["viewer-query"] -> emit_query(query.build_viewer_query())
    ["teams-query"] -> emit_query(query.build_teams_query())
    ["team-projects-query", team_id] ->
      emit_query(query.build_team_projects_query(team_id))
    ["issue-query", identifier] ->
      emit_query(query.build_issue_query(identifier))
    ["assigned-issues-query"] -> emit_assigned_issues_query()
    ["fetch-issue", identifier] -> emit_fetch_issue(identifier)
    [] -> {
      case run() {
        Ok(issue) -> emit_success(issue)
        Error(error) -> emit_error(error)
      }
    }
    _ -> emit_usage()
  }
}

pub fn run() -> Result(types.SelectedIssue, types.ProviderError) {
  use linear_config <- result_try_config(config.load_linear_config())
  let fixture_path = get_env("LINEAR_FIXTURE_PATH")

  let filter = config.config_to_filter(linear_config)

  case fixture_path == "" {
    True -> {
      use token <- result_try_provider(client.access_token_from_env())
      let graphql_query = query.build_assigned_issues_query(100, Error(Nil), Ok(filter))
      use contents <- result_try_provider(client.run_assigned_issues_query(
        token,
        graphql_query,
      ))
      use issues <- result_try_provider(decode_fixture(contents))
      select_issue(issues, filter, linear_config.priority_order)
    }
    False -> {
      use contents <- result_try_provider(read_fixture(fixture_path))
      use issues <- result_try_provider(decode_fixture(contents))
      select_issue(issues, filter, linear_config.priority_order)
    }
  }
}

fn emit_usage() -> Nil {
  io.println("Usage: gleam run -m grkr/issue_provider/main")
  io.println("       gleam run -m grkr/issue_provider/main -- viewer-query")
  io.println("       gleam run -m grkr/issue_provider/main -- teams-query")
  io.println("       gleam run -m grkr/issue_provider/main -- team-projects-query <team-id>")
  io.println("       gleam run -m grkr/issue_provider/main -- issue-query <identifier>")
  io.println("       gleam run -m grkr/issue_provider/main -- assigned-issues-query")
  io.println("       gleam run -m grkr/issue_provider/main -- fetch-issue <identifier>")
  io.println("")
  io.println("Linear issue provider discovery/query CLI:")
  io.println("  (no args)           Select a Linear issue and emit shell assignments")
  io.println("  viewer-query        Print the Linear viewer GraphQL query")
  io.println("  teams-query         Print the teams discovery query")
  io.println("  team-projects-query Print the project discovery query for a team")
  io.println("  issue-query         Print a single issue query by identifier")
  io.println("  assigned-issues-query Print the assigned-issues query using current config")
  io.println("  fetch-issue         Load one issue (fixture/live) and emit shell KEY=val")
  io.println("")
  io.println("Query-only commands never read credentials. fetch-issue uses LINEAR_FIXTURE_PATH")
  io.println("when set; otherwise GRKR_LINEAR_ACCESS_TOKEN or ~/.linear/token.txt.")
  exit(2)
}

fn emit_query(graphql_query: String) -> Nil {
  io.println(graphql_query)
}

fn emit_assigned_issues_query() -> Nil {
  case config.load_linear_config() {
    Ok(linear_config) -> {
      let filter = config.config_to_filter(linear_config)
      let graphql_query = query.build_assigned_issues_query(100, Error(Nil), Ok(filter))
      io.println(graphql_query)
    }
    Error(error) -> {
      io.println(
        "Error loading Linear config: "
          <> types.provider_error_to_string(types.ConfigError(error)),
      )
      exit(1)
    }
  }
}

fn select_issue(
  issues: List(types.LinearIssue),
  filter: types.IssueFilter,
  priority_order: types.PriorityOrder,
) -> Result(types.SelectedIssue, types.ProviderError) {
  case selector.select_issue(issues, filter, priority_order) {
    types.SelectionSuccess(selected, _total_candidates) -> Ok(selected)
    types.NoMatchingIssues -> Error(types.NoMatchingIssue)
    types.ProviderFailed(error) -> Error(error)
  }
}

fn result_try_config(
  result: Result(config.LinearConfig, types.ConfigError),
  next: fn(config.LinearConfig) ->
    Result(types.SelectedIssue, types.ProviderError),
) -> Result(types.SelectedIssue, types.ProviderError) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(types.ConfigError(error))
  }
}

fn result_try_provider(
  result: Result(a, types.ProviderError),
  next: fn(a) -> Result(b, types.ProviderError),
) -> Result(b, types.ProviderError) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}

fn read_fixture(path: String) -> Result(String, types.ProviderError) {
  case read_file(path) {
    Ok(contents) -> Ok(contents)
    Error(message) ->
      Error(types.QueryError("failed to read Linear fixture: " <> message))
  }
}

fn decode_fixture(
  contents: String,
) -> Result(List(types.LinearIssue), types.ProviderError) {
  case decoder.decode_issues_response(contents) {
    Ok(issues) -> Ok(issues)
    Error(message) ->
      Error(types.ParseError("failed to decode Linear fixture: " <> message))
  }
}

fn emit_success(issue: types.SelectedIssue) -> Nil {
  io.println("SELECTED=1")
  io.println("ISSUE_IDENTIFIER=" <> shell_quote(issue.identifier))
  io.println("ISSUE_TITLE=" <> shell_quote(issue.title))
  io.println("ISSUE_URL=" <> shell_quote(issue.url))
  io.println("ISSUE_STATE=" <> shell_quote(issue.state_name))
  io.println(
    "ISSUE_PRIORITY=" <> shell_quote(priority_to_string(issue.priority)),
  )
  io.println("ISSUE_UPDATED_AT=" <> shell_quote(issue.updated_at))
  io.println(
    "JOB_KEY=" <> shell_quote(types.job_key_for_identifier(issue.identifier)),
  )
  io.println(
    "TASK_SLUG=" <> shell_quote(types.task_slug_for_identifier(issue.identifier)),
  )
}

fn emit_fetch_issue(identifier: String) -> Nil {
  case string.trim(identifier) {
    "" -> {
      io.println("FOUND=0")
      io.println("ERROR=" <> shell_quote("empty Linear issue identifier"))
      exit(1)
    }
    id ->
      case fetch_issue_by_identifier(id) {
        Ok(issue) -> emit_issue_context(issue)
        Error(error) -> {
          io.println("FOUND=0")
          io.println(
            "ERROR=" <> shell_quote(types.provider_error_to_string(error)),
          )
          exit(1)
        }
      }
  }
}

/// Load one Linear issue by human identifier for `grkr --linear-issue`.
/// Prefer fixture (`LINEAR_FIXTURE_PATH` assigned-issues JSON or single-issue
/// `{data.issue}` JSON). Live path uses resolve_access_token + issue query.
pub fn fetch_issue_by_identifier(
  identifier: String,
) -> Result(types.LinearIssue, types.ProviderError) {
  let fixture_path = get_env("LINEAR_FIXTURE_PATH")
  case fixture_path == "" {
    True -> fetch_issue_live(identifier)
    False -> fetch_issue_from_fixture(fixture_path, identifier)
  }
}

fn fetch_issue_from_fixture(
  path: String,
  identifier: String,
) -> Result(types.LinearIssue, types.ProviderError) {
  use contents <- result_try_provider(read_fixture(path))
  case decoder.decode_issue_response(contents) {
    Ok(issue) -> {
      case string.lowercase(issue.identifier) == string.lowercase(identifier) {
        True -> Ok(issue)
        False ->
          Error(types.QueryError(
            "Fixture issue identifier mismatch: expected "
            <> identifier
            <> ", got "
            <> issue.identifier,
          ))
      }
    }
    Error(_) -> {
      use issues <- result_try_provider(decode_fixture(contents))
      case decoder.find_issue_by_identifier(issues, identifier) {
        Ok(issue) -> Ok(issue)
        Error(message) -> Error(types.QueryError(message))
      }
    }
  }
}

fn fetch_issue_live(
  identifier: String,
) -> Result(types.LinearIssue, types.ProviderError) {
  use token <- result_try_provider(client.resolve_access_token())
  let graphql_query = query.build_issue_query(identifier)
  use contents <- result_try_provider(
    client.run_graphql_query(token, graphql_query),
  )
  case decoder.decode_issue_response(contents) {
    Ok(issue) -> Ok(issue)
    Error(message) -> Error(types.ParseError(message))
  }
}

fn emit_issue_context(issue: types.LinearIssue) -> Nil {
  io.println("FOUND=1")
  io.println("ISSUE_ID=" <> shell_quote(issue.id))
  io.println("ISSUE_IDENTIFIER=" <> shell_quote(issue.identifier))
  io.println("ISSUE_TITLE=" <> shell_quote(issue.title))
  io.println("ISSUE_DESCRIPTION=" <> shell_quote(issue.description))
  io.println("ISSUE_URL=" <> shell_quote(issue.url))
  io.println("ISSUE_STATE=" <> shell_quote(issue.state.name))
  io.println("ISSUE_STATE_ID=" <> shell_quote(issue.state.id))
  io.println(
    "ISSUE_PRIORITY=" <> shell_quote(priority_to_string(issue.priority)),
  )
  io.println("ISSUE_UPDATED_AT=" <> shell_quote(issue.updated_at))
  io.println(
    "JOB_KEY=" <> shell_quote(types.job_key_for_identifier(issue.identifier)),
  )
  io.println(
    "TASK_SLUG=" <> shell_quote(types.task_slug_for_identifier(issue.identifier)),
  )
}

fn emit_error(error: types.ProviderError) -> Nil {
  io.println("SELECTED=0")
  io.println("ERROR=" <> shell_quote(types.provider_error_to_string(error)))
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

@external(javascript, "../issue_provider/cli_ffi.mjs", "argv")
fn argv() -> List(String)

@external(javascript, "process", "exit")
fn exit(code: Int) -> Nil
