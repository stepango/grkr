import gleam/string
import grkr/issue_provider/types

pub const endpoint = "https://api.linear.app/graphql"

pub fn access_token_from_env() -> Result(String, types.ProviderError) {
  require_access_token(get_env("GRKR_LINEAR_ACCESS_TOKEN"))
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
  use token <- result_try(require_access_token(access_token))
  case post_graphql(endpoint, authorization_header(token), graphql_query) {
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

@external(javascript, "../issue_provider/linear_http.mjs", "postGraphqlSync")
fn post_graphql(
  endpoint: String,
  access_token: String,
  query: String,
) -> Result(String, String)
