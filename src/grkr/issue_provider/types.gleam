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

/// Linear issue state mapping
pub type LinearState {
  LinearState(id: String, name: String, state_type: String)
}

/// Linear priority levels
pub type LinearPriority {
  Urgent
  High
  Medium
  Low
  NoPriority
}

/// Linear assignee
pub type LinearAssignee {
  LinearAssignee(id: String, name: String, display_name: String)
}

/// Linear project
pub type LinearProject {
  LinearProject(id: String, name: String, url: String)
}

/// Linear team
pub type LinearTeam {
  LinearTeam(id: String, key: String, name: String)
}

/// Linear issue
pub type LinearIssue {
  LinearIssue(
    id: String,
    identifier: String,
    title: String,
    description: String,
    url: String,
    state: LinearState,
    priority: LinearPriority,
    assignee: Result(LinearAssignee, Nil),
    project: Result(LinearProject, Nil),
    team: Result(LinearTeam, Nil),
    created_at: String,
    updated_at: String,
  )
}

/// Filter criteria for issue selection
pub type IssueFilter {
  IssueFilter(
    state_name: String,
    assignee_id: String,
    project_id: Result(String, Nil),
    team_id: Result(String, Nil),
  )
}

/// Selected issue result
pub type SelectedIssue {
  SelectedIssue(
    identifier: String,
    title: String,
    url: String,
    state_name: String,
    priority: LinearPriority,
    updated_at: String,
  )
}

/// Configuration errors
pub type ConfigError {
  MissingCredentialPath
  InvalidCredentialFormat
  MissingProjectId
  MissingTeamId
  InvalidProvider(name: String)
}

/// Issue provider errors
pub type ProviderError {
  ConfigError(ConfigError)
  QueryError(String)
  ParseError(String)
  NoMatchingIssue
}

/// Priority ordering for sorting
pub type PriorityOrder {
  PriorityOrder(urgent: Int, high: Int, medium: Int, low: Int, no_priority: Int)
}

/// Issue selection result with metadata
pub type SelectionResult {
  SelectionSuccess(selected: SelectedIssue, total_candidates: Int)
  NoMatchingIssues
  ProviderFailed(error: ProviderError)
}

/// Parse priority from string value
pub fn parse_priority(value: String) -> LinearPriority {
  case value {
    "urgent" -> Urgent
    "high" -> High
    "medium" -> Medium
    "low" -> Low
    _ -> NoPriority
  }
}

/// Parse Linear's numeric priority value.
pub fn parse_priority_number(value: Int) -> LinearPriority {
  case value {
    1 -> Urgent
    2 -> High
    3 -> Medium
    4 -> Low
    _ -> NoPriority
  }
}

/// Get priority weight for ordering (lower = higher priority)
pub fn priority_weight(order: PriorityOrder, priority: LinearPriority) -> Int {
  case priority {
    Urgent -> order.urgent
    High -> order.high
    Medium -> order.medium
    Low -> order.low
    NoPriority -> order.no_priority
  }
}

/// Default priority ordering
pub fn default_priority_order() -> PriorityOrder {
  PriorityOrder(urgent: 0, high: 1, medium: 2, low: 3, no_priority: 4)
}

/// Create issue filter from config values
pub fn make_filter(
  state_name: String,
  assignee_id: String,
  project_id: Result(String, Nil),
  team_id: Result(String, Nil),
) -> IssueFilter {
  IssueFilter(
    state_name: state_name,
    assignee_id: assignee_id,
    project_id: project_id,
    team_id: team_id,
  )
}

/// Convert Linear issue to selected issue format
pub fn issue_to_selected(issue: LinearIssue) -> SelectedIssue {
  SelectedIssue(
    identifier: issue.identifier,
    title: issue.title,
    url: issue.url,
    state_name: issue.state.name,
    priority: issue.priority,
    updated_at: issue.updated_at,
  )
}
