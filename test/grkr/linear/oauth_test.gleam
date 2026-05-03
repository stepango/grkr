import grkr/linear/oauth
import gleeunit
import gleeunit/should
import gleam/list
import gleam/string

pub fn main() {
  gleeunit.main()
}

pub fn build_authorization_url_test() {
  let client_id = "test_client_id"
  let redirect_uri = "http://localhost:3000/callback"
  let state = "random_state_123"

  let url = oauth.build_authorization_url(client_id, redirect_uri, state)

  url
  |> string.contains("client_id=test_client_id")
  |> should.be_true

  url
  |> string.contains("redirect_uri=")
  |> should.be_true

  url
  |> string.contains("response_type=code")
  |> should.be_true

  url
  |> string.contains("scope=read+write")
  |> should.be_true

  url
  |> string.contains("state=random_state_123")
  |> should.be_true

  url
  |> string.starts_with("https://linear.app/oauth/authorize?")
  |> should.be_true
}

pub fn build_authorization_url_with_custom_scopes_test() {
  let client_id = "test_client_id"
  let redirect_uri = "http://localhost:3000/callback"
  let scopes = ["read", "write", "admin"]
  let state = "random_state_123"

  let url =
    oauth.build_authorization_url_with_scopes(
      client_id,
      redirect_uri,
      scopes,
      state,
    )

  url
  |> string.contains("scope=read+write+admin")
  |> should.be_true

  url
  |> string.contains("state=random_state_123")
  |> should.be_true
}

pub fn redact_token_test() {
  let short_token = "abc123"
  let medium_token = "lin_abcdefghijklmnopqrstuvwxyz1234567890"
  let long_token =
    "lin_123456789012345678901234567890123456789012345678901234567890"
  let empty_token = ""

  let short_redacted = oauth.redact_token(short_token)
  let medium_redacted = oauth.redact_token(medium_token)
  let long_redacted = oauth.redact_token(long_token)
  let empty_redacted = oauth.redact_token(empty_token)

  short_redacted
  |> should.equal("abc123...")

  medium_redacted
  |> string.contains("lin_abc")
  |> should.be_true

  medium_redacted
  |> string.contains("...")
  |> should.be_true

  let medium_is_shorter =
    string.length(medium_redacted) < string.length(medium_token)
  medium_is_shorter
  |> should.be_true

  long_redacted
  |> string.contains("...")
  |> should.be_true

  let long_is_shorter =
    string.length(long_redacted) < string.length(long_token)
  long_is_shorter
  |> should.be_true

  empty_redacted
  |> should.equal("<empty>")
}

pub fn parse_token_exchange_response_test() {
  let valid_json =
    "{"
    <> "\"access_token\": \"lin_1234567890\","
    <> "\"token_type\": \"bearer\","
    <> "\"expires_in\": 7200,"
    <> "\"refresh_token\": \"lin_refresh_abc\","
    <> "\"scope\": \"read write\""
    <> "}"

  case oauth.parse_token_exchange_response(valid_json) {
    Ok(response) -> {
      response.access_token
      |> should.equal("lin_1234567890")

      response.token_type
      |> should.equal("bearer")

      response.expires_in
      |> should.equal(Ok(7200))

      response.refresh_token
      |> should.equal(Ok("lin_refresh_abc"))

      response.scope
      |> should.equal(Ok("read write"))
    }
    Error(_) -> should.fail()
  }
}

pub fn parse_token_exchange_response_minimal_test() {
  let minimal_json =
    "{"
    <> "\"access_token\": \"lin_1234567890\","
    <> "\"token_type\": \"bearer\""
    <> "}"

  case oauth.parse_token_exchange_response(minimal_json) {
    Ok(response) -> {
      response.access_token
      |> should.equal("lin_1234567890")

      response.token_type
      |> should.equal("bearer")

      case response.expires_in {
        Error(_) -> True
        Ok(_) -> False
      }
      |> should.be_true

      case response.refresh_token {
        Error(_) -> True
        Ok(_) -> False
      }
      |> should.be_true

      case response.scope {
        Error(_) -> True
        Ok(_) -> False
      }
      |> should.be_true
    }
    Error(_) -> should.fail()
  }
}

pub fn parse_token_exchange_response_invalid_test() {
  let invalid_json = "{ invalid json }"

  let assert Error(_) = oauth.parse_token_exchange_response(invalid_json)
}

pub fn parse_token_exchange_response_missing_token_test() {
  let missing_token =
    "{"
    <> "\"token_type\": \"bearer\""
    <> "}"

  let assert Error(_) = oauth.parse_token_exchange_response(missing_token)
}

pub fn format_token_exchange_error_test() {
  let errors = [
    oauth.InvalidRequest,
    oauth.InvalidClient,
    oauth.InvalidGrant,
    oauth.UnauthorizedClient,
    oauth.UnsupportedGrantType,
    oauth.AccessDenied,
    oauth.InvalidScope,
    oauth.ServerError("test error"),
    oauth.NetworkError("network failure"),
    oauth.InvalidResponse,
  ]

  errors
  |> list.map(fn(err) {
    let formatted = oauth.format_token_exchange_error(err)
    let is_non_empty = string.length(formatted) > 0
    is_non_empty
    |> should.be_true
  })
}

pub fn redact_token_response_test() {
  let response =
    oauth.TokenExchangeResponse(
      access_token: "lin_12345678901234567890",
      token_type: "bearer",
      expires_in: Ok(7200),
      refresh_token: Ok("lin_refresh_abcdefghij"),
      scope: Ok("read write"),
    )

  let redacted = oauth.redact_token_response(response)

  redacted
  |> string.contains("lin_12345678901234567890")
  |> should.be_false

  redacted
  |> string.contains("lin_refresh_abcdefghij")
  |> should.be_false

  redacted
  |> string.contains("bearer")
  |> should.be_true

  redacted
  |> string.contains("7200 seconds")
  |> should.be_true

  redacted
  |> string.contains("read write")
  |> should.be_true
}
