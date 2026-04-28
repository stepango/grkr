import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import grkr/issue_provider/credential
import grkr/issue_provider/types.{
  GitHub, GitHubToken, InvalidCredentialShape, Linear, LinearOAuthApp,
  LinearPersonalToken, MissingCredentials, OAuthAppCredentialsWithoutToken,
  ProviderConfig,
}
import grkr/issue_provider/validation

pub fn main() {
  gleeunit.main()
}

pub fn github_default_config_model_test() {
  let config =
    ProviderConfig(
      provider: GitHub,
      repo: "owner/repo",
      project_owner: "owner",
      project_number: 1,
      credentials: GitHubToken(token: "ghp_test_token"),
    )

  config.provider
  |> should.equal(GitHub)

  case config.credentials {
    GitHubToken(token) -> string.starts_with(token, "ghp_")
    _ -> False
  }
  |> should.equal(True)
}

pub fn linear_oauth_app_without_access_token_is_not_graphql_ready_test() {
  let oauth_creds =
    LinearOAuthApp(
      client_id: "linear_client_123",
      client_secret: "linear_secret_456",
      access_token: None,
    )

  oauth_creds
  |> validation.is_linear_oauth_app
  |> should.equal(True)

  oauth_creds
  |> validation.is_linear_ready_for_graphql
  |> should.equal(False)

  case validation.validate_linear_credentials(oauth_creds) {
    Error(OAuthAppCredentialsWithoutToken(Linear)) -> True
    _ -> False
  }
  |> should.equal(True)
}

pub fn linear_missing_credentials_test() {
  let empty_token = LinearPersonalToken(token: "")

  case validation.validate_linear_credentials(empty_token) {
    Error(MissingCredentials(Linear)) -> True
    _ -> False
  }
  |> should.equal(True)
}

pub fn linear_invalid_oauth_shape_test() {
  let invalid_oauth =
    LinearOAuthApp(
      client_id: "",
      client_secret: "some_secret",
      access_token: None,
    )

  case validation.validate_linear_credentials(invalid_oauth) {
    Error(InvalidCredentialShape(Linear, _)) -> True
    _ -> False
  }
  |> should.equal(True)
}

pub fn linear_oauth_with_access_token_is_graphql_ready_test() {
  let oauth_creds =
    LinearOAuthApp(
      client_id: "linear_client_123",
      client_secret: "linear_secret_456",
      access_token: Some("linear_api_token_789"),
    )

  oauth_creds
  |> validation.is_linear_ready_for_graphql
  |> should.equal(True)

  validation.validate_linear_credentials(oauth_creds)
  |> should.equal(Ok(Nil))
}

pub fn linear_personal_token_is_graphql_ready_test() {
  let personal_token = LinearPersonalToken(token: "lin_api_test_token")

  personal_token
  |> validation.is_linear_oauth_app
  |> should.equal(False)

  personal_token
  |> validation.is_linear_ready_for_graphql
  |> should.equal(True)

  validation.validate_linear_credentials(personal_token)
  |> should.equal(Ok(Nil))
}

pub fn credential_redaction_never_includes_secret_values_test() {
  let oauth_creds =
    LinearOAuthApp(
      client_id: "linear_client_123",
      client_secret: "linear_secret_456",
      access_token: Some("linear_api_token_789"),
    )

  let redacted = validation.redact_credential(oauth_creds)
  string.contains(redacted, "****")
  |> should.equal(True)
  string.contains(redacted, "linear_client_123")
  |> should.equal(False)
  string.contains(redacted, "linear_secret_456")
  |> should.equal(False)
  string.contains(redacted, "linear_api_token_789")
  |> should.equal(False)

  let personal_token = LinearPersonalToken(token: "lin_api_test_token")
  let redacted = validation.redact_credential(personal_token)
  string.contains(redacted, "****")
  |> should.equal(True)
  string.contains(redacted, "lin_api_test_token")
  |> should.equal(False)
}

pub fn parse_linear_oauth_app_credentials_test() {
  let content = "client_id=linear_client_123\nclient_secret=linear_secret_456"

  case credential.parse_linear_credentials(content) {
    Ok(LinearOAuthApp("linear_client_123", "linear_secret_456", None)) -> True
    _ -> False
  }
  |> should.equal(True)
}

pub fn parse_linear_personal_token_test() {
  credential.parse_linear_credentials("lin_api_test_token")
  |> should.equal(Ok(LinearPersonalToken(token: "lin_api_test_token")))

  credential.parse_linear_credentials("token=lin_api_test_token")
  |> should.equal(Ok(LinearPersonalToken(token: "lin_api_test_token")))
}
