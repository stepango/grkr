import gleam/option.{None, Some}
import gleam/result
import gleam/string
import grkr/issue_provider/types.{
  type CredentialConfig, type CredentialResult, InvalidCredentialShape, Linear,
  LinearOAuthApp, LinearPersonalToken, MissingCredentials,
  OAuthAppCredentialsWithoutToken,
}

/// Validate Linear credentials for API use
pub fn validate_linear_credentials(
  config: CredentialConfig,
) -> CredentialResult(Nil) {
  case config {
    LinearOAuthApp(client_id, client_secret, access_token) -> {
      // Validate OAuth app credentials
      use _ <- result.try(validate_oauth_app_shape(client_id, client_secret))

      // Check if access token is available
      case access_token {
        Some(_) -> Ok(Nil)
        None -> Error(OAuthAppCredentialsWithoutToken(provider: Linear))
      }
    }
    LinearPersonalToken(token) -> {
      // Validate personal token format
      case string.length(token) {
        0 -> Error(MissingCredentials(provider: Linear))
        _ -> Ok(Nil)
      }
    }
    _ ->
      Error(InvalidCredentialShape(
        provider: Linear,
        reason: "Not a Linear credential type",
      ))
  }
}

/// Validate OAuth app credential shape
fn validate_oauth_app_shape(
  client_id: String,
  client_secret: String,
) -> CredentialResult(Nil) {
  let valid_client_id = string.length(client_id) > 0
  let valid_client_secret = string.length(client_secret) > 0

  case valid_client_id, valid_client_secret {
    True, True -> Ok(Nil)
    _, _ ->
      Error(InvalidCredentialShape(
        provider: Linear,
        reason: "OAuth app credentials require both client_id and client_secret",
      ))
  }
}

/// Check if Linear credentials represent OAuth app credentials
pub fn is_linear_oauth_app(config: CredentialConfig) -> Bool {
  case config {
    LinearOAuthApp(_, _, _) -> True
    _ -> False
  }
}

/// Check if Linear credentials are ready for GraphQL use
pub fn is_linear_ready_for_graphql(config: CredentialConfig) -> Bool {
  case config {
    LinearOAuthApp(_, _, Some(_)) -> True
    LinearPersonalToken(_) -> True
    _ -> False
  }
}

/// Get a redacted representation of credentials for error messages
pub fn redact_credential(config: CredentialConfig) -> String {
  case config {
    LinearOAuthApp(client_id, _, _) -> {
      let redacted_id = string.slice(client_id, 0, 4) <> "****"
      "OAuthApp(" <> redacted_id <> ", ****)"
    }
    LinearPersonalToken(token) -> {
      let redacted_token = string.slice(token, 0, 4) <> "****"
      "PersonalToken(" <> redacted_token <> ")"
    }
    _ -> "UnknownCredential"
  }
}
