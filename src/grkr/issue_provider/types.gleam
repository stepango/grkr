import gleam/dict.{type Dict}
import gleam/option.{type Option}

/// Issue provider type (GitHub, Linear, etc.)
pub type Provider {
  GitHub
  Linear
}

/// Configuration for a specific issue provider
pub type ProviderConfig {
  ProviderConfig(
    provider: Provider,
    repo: String,
    // owner/repo for GitHub, workspace key for Linear
    project_owner: String,
    project_number: Int,
    credentials: CredentialConfig,
  )
}

/// Credential configuration for different auth modes
pub type CredentialConfig {
  /// GitHub personal access token or OAuth token
  GitHubToken(token: String)

  /// Linear OAuth app credentials (requires install/token exchange)
  LinearOAuthApp(
    client_id: String,
    client_secret: String,
    /// Optional: if present, this is the actual access token
    access_token: Option(String),
  )

  /// Linear personal API token (not recommended for OAuth apps)
  LinearPersonalToken(token: String)
}

/// Validation errors for credential discovery
pub type CredentialError {
  MissingCredentials(provider: Provider)
  InvalidCredentialShape(provider: Provider, reason: String)
  OAuthAppCredentialsWithoutToken(provider: Provider)
  CredentialFileNotFound(path: String)
  CredentialFileNotReadable(path: String)
  EnvironmentVariableNotSet(name: String)
}

/// Result type for credential operations
pub type CredentialResult(a) =
  Result(a, CredentialError)

/// Provider configuration loaded from environment/files
pub type DiscoveredConfig {
  DiscoveredConfig(
    providers: Dict(String, ProviderConfig),
    default_provider: Provider,
  )
}
