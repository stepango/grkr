import gleam/list
import gleam/result
import gleam/string
import grkr/linear/oauth
import grkr/linear/types

const default_secret_path = "~/.linear/secret.txt"

pub fn parse_oauth_credentials(
  content: String,
) -> Result(types.OAuthCredentials, String) {
  let lines = string.split(content, "\n")

  let get_field = fn(field_name: String) -> Result(String, String) {
    lines
    |> list.find_map(fn(line) { parse_field_line(line, field_name) })
    |> result.replace_error("Missing or invalid " <> field_name)
  }

  case get_field("client_id") {
    Error(err) -> Error(err)
    Ok(client_id) ->
      case get_field("client_secret") {
        Error(err) -> Error(err)
        Ok(client_secret) ->
          case client_id, client_secret {
            "", _ -> Error("Empty client_id")
            _, "" -> Error("Empty client_secret")
            _, _ -> Ok(types.OAuthCredentials(client_id, client_secret))
          }
      }
  }
}

fn parse_field_line(line: String, field_name: String) -> Result(String, Nil) {
  let trimmed = string.trim(line)
  case string.starts_with(trimmed, field_name <> "=") {
    True ->
      trimmed
      |> string.drop_start(string.length(field_name) + 1)
      |> string.trim
      |> Ok
    False ->
      case string.starts_with(trimmed, field_name <> ":") {
        True ->
          trimmed
          |> string.drop_start(string.length(field_name) + 1)
          |> string.trim
          |> Ok
        False -> Error(Nil)
      }
  }
}

pub fn redact_credentials(_creds: types.OAuthCredentials) -> String {
  "client_id: ****\nclient_secret: ****"
}

pub fn is_e2e_enabled() -> Bool {
  case get_env_var("GRKR_LINEAR_E2E") {
    "1" -> True
    "true" -> True
    _ -> False
  }
}

pub fn load_e2e_config() -> Result(types.E2EConfig, String) {
  let enabled = is_e2e_enabled()

  case enabled {
    False ->
      Ok(types.E2EConfig(
        credentials: types.OAuthCredentials("", ""),
        token: Error(Nil),
        enabled: False,
      ))
    True -> {
      case read_secret_file() {
        Error(err) -> Error(err)
        Ok(secret_content) ->
          case parse_oauth_credentials(secret_content) {
            Error(err) -> Error(err)
            Ok(creds) -> {
              let token = load_access_token()
              Ok(types.E2EConfig(
                credentials: creds,
                token: token,
                enabled: True,
              ))
            }
          }
      }
    }
  }
}

fn load_access_token() -> Result(types.LinearToken, Nil) {
  // First, try to load from OAuth token store
  let token_path = oauth.get_token_store_path()

  case oauth.load_token(token_path) {
    Ok(token) -> Ok(types.LinearToken(token))
    Error(_) -> {
      // Fall back to environment variable
      case get_env_var("GRKR_LINEAR_ACCESS_TOKEN") {
        "" -> Error(Nil)
        token -> Ok(types.LinearToken(token))
      }
    }
  }
}

fn read_secret_file() -> Result(String, String) {
  let path = case get_env_var("GRKR_LINEAR_SECRET_PATH") {
    "" -> default_secret_path
    p -> p
  }

  read_file(path)
}

pub fn redact_config(config: types.E2EConfig) -> String {
  let enabled_str = case config.enabled {
    True -> "enabled"
    False -> "disabled"
  }

  let token_status = case config.token {
    Ok(_) -> "present"
    Error(_) -> "missing"
  }

  "Linear E2E: "
  <> enabled_str
  <> "\n"
  <> "Credentials: "
  <> redact_credentials(config.credentials)
  <> "\n"
  <> "Token: "
  <> token_status
}

@external(javascript, "../linear/config_ffi.mjs", "get_env_var")
fn get_env_var(name: String) -> String

@external(javascript, "../linear/config_ffi.mjs", "read_file")
fn read_file(path: String) -> Result(String, String)
