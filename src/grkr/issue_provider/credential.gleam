import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import grkr/issue_provider/types.{
  type CredentialConfig, type CredentialResult, type DiscoveredConfig,
  type ProviderConfig, DiscoveredConfig, GitHub, GitHubToken, Linear,
  LinearOAuthApp, LinearPersonalToken, MissingCredentials, ProviderConfig,
}

/// Discover provider configuration from environment and config files
pub fn discover() -> CredentialResult(DiscoveredConfig) {
  // Always discover GitHub as the default
  let github_config = discover_github()

  // Try to discover Linear (optional)
  let linear_config = discover_linear()

  case github_config {
    Error(_) -> {
      // If GitHub fails, we still return Linear if available
      case linear_config {
        Ok(linear) ->
          Ok(DiscoveredConfig(
            providers: dict.from_list([#("linear", linear)]),
            default_provider: Linear,
          ))
        Error(_) -> Error(MissingCredentials(provider: Linear))
      }
    }
    Ok(github) -> {
      let providers =
        dict.from_list([
          #("github", github),
        ])

      let providers = case linear_config {
        Ok(linear) -> dict.insert(providers, "linear", linear)
        Error(_) -> providers
      }

      Ok(DiscoveredConfig(providers: providers, default_provider: GitHub))
    }
  }
}

/// Discover GitHub configuration from environment
fn discover_github() -> CredentialResult(ProviderConfig) {
  use token <- result.try(get_github_token())

  Ok(ProviderConfig(
    provider: GitHub,
    repo: get_env("REPO", "owner/repo"),
    project_owner: get_env("PROJECT_OWNER", "owner"),
    project_number: get_env_int("PROJECT_NUMBER", 1),
    credentials: GitHubToken(token: token),
  ))
}

/// Discover Linear configuration from environment and ~/.linear/secret.txt
fn discover_linear() -> CredentialResult(ProviderConfig) {
  // Check for LINEAR_CREDENTIALS_PATH or default to ~/.linear/secret.txt
  let cred_path = get_env("LINEAR_CREDENTIALS_PATH", "~/.linear/secret.txt")

  use file_content <- result.try(read_linear_credentials_file(cred_path))
  use parsed <- result.try(parse_linear_credentials(file_content))

  Ok(ProviderConfig(
    provider: Linear,
    repo: get_env("LINEAR_WORKSPACE_KEY", ""),
    project_owner: get_env("LINEAR_TEAM_KEY", ""),
    project_number: get_env_int("LINEAR_PROJECT_NUMBER", 1),
    credentials: parsed,
  ))
}

/// Parse Linear credentials from file content without logging or exposing values.
pub fn parse_linear_credentials(
  content: String,
) -> CredentialResult(CredentialConfig) {
  let lines =
    string.split(content, "\n")
    |> list.map(string.trim)
    |> list.filter(fn(s) { !string.is_empty(s) })

  // OAuth app credentials: client_id and client_secret on separate lines
  let client_id = find_line_value(lines, "client_id", "")
  let client_secret = find_line_value(lines, "client_secret", "")

  case string.is_empty(client_id), string.is_empty(client_secret) {
    False, False -> {
      // OAuth app credentials detected. These are not directly usable for
      // GraphQL until an OAuth install/token exchange provides an access token.
      Ok(LinearOAuthApp(
        client_id: client_id,
        client_secret: client_secret,
        access_token: None,
      ))
    }
    _, _ -> {
      // Try to detect a personal API token (single line or "token=")
      let token = find_line_value(lines, "token", "")
      let token = case token, list.length(lines) {
        "", 1 -> list.first(lines) |> result.unwrap("")
        _, _ -> token
      }

      case token {
        "" -> Error(MissingCredentials(provider: Linear))
        _ -> Ok(LinearPersonalToken(token: token))
      }
    }
  }
}

/// Read Linear credentials file
fn read_linear_credentials_file(path: String) -> CredentialResult(String) {
  read_file_ffi(path)
}

/// Find a value in format "key=value" or "key: value" from lines
fn find_line_value(
  lines: List(String),
  key: String,
  default: String,
) -> String {
  lines
  |> list.find_map(fn(line) { parse_key_value_line(line, key) })
  |> result.unwrap(default)
}

fn parse_key_value_line(line: String, key: String) -> Result(String, Nil) {
  case string.starts_with(line, key <> "=") {
    True ->
      line
      |> string.drop_start(string.length(key) + 1)
      |> string.trim
      |> Ok
    False ->
      case string.starts_with(line, key <> ":") {
        True ->
          line
          |> string.drop_start(string.length(key) + 1)
          |> string.trim
          |> Ok
        False -> Error(Nil)
      }
  }
}

/// Get GitHub token from environment (gh CLI or GITHUB_TOKEN)
fn get_github_token() -> CredentialResult(String) {
  let token = get_env("GITHUB_TOKEN", "")

  case token {
    "" -> Error(MissingCredentials(provider: GitHub))
    _ -> Ok(token)
  }
}

/// Get environment variable with default
fn get_env(name: String, default: String) -> String {
  get_env_ffi(name, default)
}

/// Get environment variable as integer
fn get_env_int(name: String, default: Int) -> Int {
  let val = get_env(name, "")
  case int.parse(val) {
    Ok(i) -> i
    Error(_) -> default
  }
}

// External FFI functions
@external(javascript, "./credential_ffi.mjs", "readFile")
fn read_file_ffi(path: String) -> CredentialResult(String)

@external(javascript, "./credential_ffi.mjs", "getEnv")
fn get_env_ffi(name: String, default: String) -> String
