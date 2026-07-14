import gleam/string
import grkr/issue_provider/types

pub const endpoint = "https://api.linear.app/graphql"

pub fn access_token_from_env() -> Result(String, types.ProviderError) {
  require_access_token(get_env("GRKR_LINEAR_ACCESS_TOKEN"))
}

/// Resolve OAuth access token for Linear GraphQL.
/// Order: `GRKR_LINEAR_ACCESS_TOKEN`, then `GRKR_LINEAR_TOKEN_PATH` / `~/.linear/token.txt`
/// (token=... or raw token file shapes). Never treats OAuth app secrets as tokens.
pub fn resolve_access_token() -> Result(String, types.ProviderError) {
  case string.trim(get_env("GRKR_LINEAR_ACCESS_TOKEN")) {
    "" -> {
      let path = token_store_path()
      case read_token_file(path) {
        Ok(raw) -> require_access_token(normalize_token_file(raw))
        Error(_) ->
          Error(types.QueryError(
            "Linear live calls need GRKR_LINEAR_ACCESS_TOKEN or a token file at "
            <> path
            <> " (OAuth app credentials in secret.txt are not API tokens)",
          ))
      }
    }
    token -> Ok(token)
  }
}

pub fn token_store_path() -> String {
  case string.trim(get_env("GRKR_LINEAR_TOKEN_PATH")) {
    "" -> home_dir() <> "/.linear/token.txt"
    path -> path
  }
}

pub fn normalize_token_file(raw: String) -> String {
  let trimmed = string.trim(raw)
  case string.split(trimmed, "\n") {
    [first, ..] -> {
      let line = string.trim(first)
      case string.starts_with(line, "token=") {
        True -> string.trim(string.drop_start(line, 6))
        False ->
          case string.starts_with(line, "token:") {
            True -> string.trim(string.drop_start(line, 6))
            False -> line
          }
      }
    }
    [] -> ""
  }
}

pub fn require_access_token(
  token: String,
) -> Result(String, types.ProviderError) {
  case string.trim(token) {
    "" ->
      Error(types.QueryError(
        "Linear live issue selection requires an OAuth-derived access token in GRKR_LINEAR_ACCESS_TOKEN; OAuth app client credentials are not API tokens",
      ))
    value -> Ok(value)
  }
}

pub fn run_assigned_issues_query(
  access_token: String,
  graphql_query: String,
) -> Result(String, types.ProviderError) {
  run_graphql_query(access_token, graphql_query)
}

/// Run any Linear GraphQL query/mutation body with bearer auth.
pub fn run_graphql_query(
  access_token: String,
  graphql_query: String,
) -> Result(String, types.ProviderError) {
  use token <- result_try(require_access_token(access_token))
  case post_graphql(endpoint, authorization_header(token), graphql_query) {
    Ok(body) -> Ok(body)
    Error(message) -> Error(types.QueryError(redact(message, token)))
  }
}

/// Run Linear GraphQL with query + variables (for planned mutations).
/// Reuses redaction and token validation. Does not affect run_graphql_query callers.
pub fn run_graphql_with_variables(
  access_token: String,
  graphql_query: String,
  variables_json: String,
) -> Result(String, types.ProviderError) {
  use token <- result_try(require_access_token(access_token))
  case post_graphql_with_variables(
    endpoint,
    authorization_header(token),
    graphql_query,
    variables_json,
  ) {
    Ok(body) -> Ok(body)
    Error(message) -> Error(types.QueryError(redact(message, token)))
  }
}

pub fn authorization_header(access_token: String) -> String {
  case string.starts_with(access_token, "Bearer ") {
    True -> access_token
    False -> "Bearer " <> access_token
  }
}

pub fn redact(message: String, secret: String) -> String {
  case secret == "" {
    True -> message
    False -> string.replace(message, secret, "[REDACTED]")
  }
}

fn result_try(
  result: Result(String, types.ProviderError),
  next: fn(String) -> Result(String, types.ProviderError),
) -> Result(String, types.ProviderError) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}

@external(javascript, "../issue_provider/env.mjs", "getEnv")
fn get_env(name: String) -> String

@external(javascript, "../issue_provider/env.mjs", "homeDir")
fn home_dir() -> String

@external(javascript, "../issue_provider/file.mjs", "readFileSync")
fn read_token_file(path: String) -> Result(String, String)

@external(javascript, "../issue_provider/linear_http.mjs", "postGraphqlSync")
fn post_graphql(
  endpoint: String,
  access_token: String,
  query: String,
) -> Result(String, String)

@external(javascript, "../issue_provider/linear_http.mjs", "postGraphqlWithVariablesSync")
fn post_graphql_with_variables(
  endpoint: String,
  access_token: String,
  query: String,
  variables_json: String,
) -> Result(String, String)
