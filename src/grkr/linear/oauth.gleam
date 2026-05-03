import gleam/list
import gleam/string
import gleam/javascript/promise.{type Promise}

/// Default path for storing OAuth tokens in ~/.linear/
const default_token_path = "~/.linear/token.txt"

/// Default OAuth scopes for Linear integration
const default_scopes = ["read", "write"]

/// Linear OAuth authorization endpoint
const auth_url_base = "https://linear.app/oauth/authorize"

/// Token store result type
pub type TokenStoreError {
  TokenStoreNotFound
  TokenStoreNotReadable
  TokenStoreInvalid
}

/// Token exchange error types
pub type TokenExchangeError {
  InvalidRequest
  InvalidClient
  InvalidGrant
  UnauthorizedClient
  UnsupportedGrantType
  AccessDenied
  InvalidScope
  ServerError(String)
  NetworkError(String)
  InvalidResponse
}

/// Token exchange response
pub type TokenExchangeResponse {
  TokenExchangeResponse(
    access_token: String,
    token_type: String,
    expires_in: Result(Int, Nil),
    refresh_token: Result(String, Nil),
    scope: Result(String, Nil),
  )
}

/// OAuth authorization parameters
pub type AuthorizationParams {
  AuthorizationParams(
    client_id: String,
    redirect_uri: String,
    scope: List(String),
    state: String,
  )
}

/// Build the Linear OAuth authorization URL
pub fn build_authorization_url(
  client_id: String,
  redirect_uri: String,
  state: String,
) -> String {
  let scopes = string.join(default_scopes, " ")
  let params = [
    #("client_id", client_id),
    #("redirect_uri", redirect_uri),
    #("response_type", "code"),
    #("scope", scopes),
    #("state", state),
  ]

  build_url_with_params(auth_url_base, params)
}

/// Build the Linear OAuth authorization URL with custom scopes
pub fn build_authorization_url_with_scopes(
  client_id: String,
  redirect_uri: String,
  scopes: List(String),
  state: String,
) -> String {
  let scope_str = string.join(scopes, " ")
  let params = [
    #("client_id", client_id),
    #("redirect_uri", redirect_uri),
    #("response_type", "code"),
    #("scope", scope_str),
    #("state", state),
  ]

  build_url_with_params(auth_url_base, params)
}

/// Exchange OAuth authorization code for access token
pub fn exchange_code_for_token(
  client_id: String,
  client_secret: String,
  code: String,
  redirect_uri: String,
) -> Promise(Result(TokenExchangeResponse, TokenExchangeError)) {
  execute_token_exchange(client_id, client_secret, code, redirect_uri)
}

/// Store OAuth token in local token store
pub fn store_token(token: String, path: String) -> Result(Nil, TokenStoreError) {
  write_token_file(path, token)
}

/// Store OAuth token in default location
pub fn store_token_default(token: String) -> Result(Nil, TokenStoreError) {
  write_token_file(default_token_path, token)
}

/// Load OAuth token from local token store
pub fn load_token(path: String) -> Result(String, TokenStoreError) {
  read_token_file(path)
}

/// Load OAuth token from default location
pub fn load_token_default() -> Result(String, TokenStoreError) {
  read_token_file(default_token_path)
}

/// Get token store path from environment or default
pub fn get_token_store_path() -> String {
  case get_env_var("GRKR_LINEAR_TOKEN_PATH") {
    "" -> default_token_path
    path -> path
  }
}

/// Redact token for safe logging
pub fn redact_token(token: String) -> String {
  let token_len = string.length(token)
  case token_len {
    0 -> "<empty>"
    _ -> {
      let visible_chars = case token_len {
        n if n > 8 -> 8
        _ -> token_len
      }
      token
      |> string.slice(0, visible_chars)
      |> fn(prefix) { prefix <> "..." }
    }
  }
}

/// Redact token exchange response for safe logging
pub fn redact_token_response(
  response: TokenExchangeResponse,
) -> String {
  "TokenExchangeResponse(\n"
  <> "  access_token: "
  <> redact_token(response.access_token)
  <> "\n"
  <> "  token_type: "
  <> response.token_type
  <> "\n"
  <> "  expires_in: "
  <> format_expires_in(response.expires_in)
  <> "\n"
  <> "  refresh_token: "
  <> format_refresh_token(response.refresh_token)
  <> "\n"
  <> "  scope: "
  <> format_scope(response.scope)
  <> "\n"
  <> ")"
}

/// Format token exchange error for safe logging
pub fn format_token_exchange_error(err: TokenExchangeError) -> String {
  case err {
    InvalidRequest -> "InvalidRequest: The request is missing a required parameter"
    InvalidClient -> "InvalidClient: Client authentication failed"
    InvalidGrant -> "InvalidGrant: The authorization code is invalid or expired"
    UnauthorizedClient -> "UnauthorizedClient: The client is not authorized"
    UnsupportedGrantType -> "UnsupportedGrantType: The grant type is not supported"
    AccessDenied -> "AccessDenied: The user denied the request"
    InvalidScope -> "InvalidScope: The requested scope is invalid"
    ServerError(msg) -> "ServerError: " <> msg
    NetworkError(msg) -> "NetworkError: " <> msg
    InvalidResponse -> "InvalidResponse: The server response could not be parsed"
  }
}

/// Check if a token file exists at the given path
pub fn token_store_exists(path: String) -> Bool {
  file_exists(path)
}

/// Check if the default token store exists
pub fn token_store_exists_default() -> Bool {
  file_exists(default_token_path)
}

/// Parse token exchange response from JSON
pub fn parse_token_exchange_response(
  json: String,
) -> Result(TokenExchangeResponse, TokenExchangeError) {
  parse_token_response_json(json)
}

// Internal helper functions

fn build_url_with_params(base: String, params: List(#(String, String))) -> String {
  let param_str =
    params
    |> list.map(fn(pair) {
      let #(key, value) = pair
      url_encode(key) <> "=" <> url_encode(value)
    })
    |> string.join("&")

  base <> "?" <> param_str
}

fn url_encode(s: String) -> String {
  s
  |> string.replace(" ", "+")
  |> string.replace("/", "%2F")
  |> string.replace(":", "%3A")
  |> string.replace("?", "%3F")
  |> string.replace("&", "%26")
  |> string.replace("=", "%3D")
}

fn format_expires_in(expires_in: Result(Int, Nil)) -> String {
  case expires_in {
    Ok(seconds) -> int_to_string(seconds) <> " seconds"
    Error(_) -> "<not provided>"
  }
}

fn format_refresh_token(refresh_token: Result(String, Nil)) -> String {
  case refresh_token {
    Ok(token) -> redact_token(token)
    Error(_) -> "<not provided>"
  }
}

fn format_scope(scope: Result(String, Nil)) -> String {
  case scope {
    Ok(s) -> s
    Error(_) -> "<not provided>"
  }
}

fn int_to_string(i: Int) -> String {
  builtin_int_to_string(i)
}

// External FFI functions

@external(javascript, "../linear/oauth_ffi.mjs", "execute_token_exchange")
fn execute_token_exchange(
  client_id: String,
  client_secret: String,
  code: String,
  redirect_uri: String,
) -> Promise(Result(TokenExchangeResponse, TokenExchangeError))

@external(javascript, "../linear/oauth_ffi.mjs", "write_token_file")
fn write_token_file(
  path: String,
  token: String,
) -> Result(Nil, TokenStoreError)

@external(javascript, "../linear/oauth_ffi.mjs", "read_token_file")
fn read_token_file(path: String) -> Result(String, TokenStoreError)

@external(javascript, "../linear/oauth_ffi.mjs", "get_env_var")
fn get_env_var(name: String) -> String

@external(javascript, "../linear/oauth_ffi.mjs", "file_exists")
fn file_exists(path: String) -> Bool

@external(javascript, "../linear/oauth_ffi.mjs", "parse_token_response_json")
fn parse_token_response_json(
  json: String,
) -> Result(TokenExchangeResponse, TokenExchangeError)

@external(javascript, "../linear/oauth_ffi.mjs", "int_to_string")
fn builtin_int_to_string(i: Int) -> String
