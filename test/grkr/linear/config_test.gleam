import gleam/string
import gleeunit
import gleeunit/should
import grkr/linear/config
import grkr/linear/types

pub fn main() {
  gleeunit.main()
}

pub fn parse_oauth_credentials_test() {
  let valid_credentials =
    "client_id: test_client_id_123\n"
    <> "client_secret: test_client_secret_456\n"

  case config.parse_oauth_credentials(valid_credentials) {
    Ok(creds) -> {
      creds.client_id
      |> should.equal("test_client_id_123")

      creds.client_secret
      |> should.equal("test_client_secret_456")
    }
    Error(_) -> should.fail()
  }
}

pub fn parse_oauth_credentials_with_whitespace_test() {
  let credentials_with_whitespace =
    "client_id: test_client_id_123\n"
    <> "client_secret: test_client_secret_456\n"
    <> "\n"

  case config.parse_oauth_credentials(credentials_with_whitespace) {
    Ok(creds) -> {
      creds.client_id
      |> should.equal("test_client_id_123")

      creds.client_secret
      |> should.equal("test_client_secret_456")
    }
    Error(_) -> should.fail()
  }
}

pub fn parse_oauth_credentials_with_equals_test() {
  let credentials_with_equals =
    "client_id=test_client_id_123\n" <> "client_secret=test_client_secret_456\n"

  case config.parse_oauth_credentials(credentials_with_equals) {
    Ok(creds) -> {
      creds.client_id
      |> should.equal("test_client_id_123")

      creds.client_secret
      |> should.equal("test_client_secret_456")
    }
    Error(_) -> should.fail()
  }
}

pub fn parse_oauth_credentials_missing_client_id_test() {
  let missing_client_id = "client_secret: test_client_secret_456\n"

  case config.parse_oauth_credentials(missing_client_id) {
    Error(_) -> True
    Ok(_) -> False
  }
  |> should.be_true()
}

pub fn parse_oauth_credentials_missing_client_secret_test() {
  let missing_client_secret = "client_id: test_client_id_123\n"

  case config.parse_oauth_credentials(missing_client_secret) {
    Error(_) -> True
    Ok(_) -> False
  }
  |> should.be_true()
}

pub fn parse_oauth_credentials_empty_client_id_test() {
  let empty_client_id =
    "client_id: \n" <> "client_secret: test_client_secret_456\n"

  case config.parse_oauth_credentials(empty_client_id) {
    Error(_) -> True
    Ok(_) -> False
  }
  |> should.be_true()
}

pub fn parse_oauth_credentials_empty_client_secret_test() {
  let empty_client_secret =
    "client_id: test_client_id_123\n" <> "client_secret: \n"

  case config.parse_oauth_credentials(empty_client_secret) {
    Error(_) -> True
    Ok(_) -> False
  }
  |> should.be_true()
}

pub fn redact_credentials_test() {
  let creds =
    types.OAuthCredentials(
      client_id: "test_client_id_12345678901234",
      client_secret: "secret_12345",
    )

  let redacted = config.redact_credentials(creds)

  redacted
  |> string.contains("test_client_id_12345678901234")
  |> should.be_false

  redacted
  |> string.contains("secret_12345")
  |> should.be_false

  redacted
  |> string.contains("****")
  |> should.be_true

  redacted
  |> string.contains("client_id:")
  |> should.be_true

  redacted
  |> string.contains("client_secret:")
  |> should.be_true
}
