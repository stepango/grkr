import gleam/dict
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import grkr/issue_provider/credential
import grkr/issue_provider/decoder
import grkr/issue_provider/query
import grkr/issue_provider/selector
import grkr/issue_provider/types
import grkr/issue_provider/validation

// Fixture JSON data for testing
const fixture_issue_json = "
{
  \"data\": {
    \"viewer\": {
      \"assignedIssues\": {
        \"nodes\": [
          {
            \"id\": \"LIN-001\",
            \"identifier\": \"ENG-123\",
            \"title\": \"Implement Linear integration\",
            \"description\": \"Add Linear issue provider support\",
            \"url\": \"https://linear.app/issue/ENG-123\",
            \"state\": {
              \"id\": \"s1\",
              \"name\": \"Todo\",
              \"type\": \"backlog\"
            },
            \"priority\": 2,
            \"assignee\": {
              \"id\": \"u1\",
              \"name\": \"bot\",
              \"displayName\": \"Robot Bot\"
            },
            \"project\": {
              \"id\": \"p1\",
              \"name\": \"Integration\",
              \"url\": \"https://linear.app/project/p1\"
            },
            \"team\": {
              \"id\": \"t1\",
              \"key\": \"ENG\",
              \"name\": \"Engineering\"
            },
            \"createdAt\": \"2026-04-28T00:00:00Z\",
            \"updatedAt\": \"2026-04-28T12:00:00Z\"
          },
          {
            \"id\": \"LIN-002\",
            \"identifier\": \"ENG-124\",
            \"title\": \"Fix authentication flow\",
            \"description\": \"Resolve OAuth token issues\",
            \"url\": \"https://linear.app/issue/ENG-124\",
            \"state\": {
              \"id\": \"s1\",
              \"name\": \"Todo\",
              \"type\": \"backlog\"
            },
            \"priority\": 1,
            \"assignee\": {
              \"id\": \"u1\",
              \"name\": \"bot\",
              \"displayName\": \"Robot Bot\"
            },
            \"project\": {
              \"id\": \"p1\",
              \"name\": \"Integration\",
              \"url\": \"https://linear.app/project/p1\"
            },
            \"team\": {
              \"id\": \"t1\",
              \"key\": \"ENG\",
              \"name\": \"Engineering\"
            },
            \"createdAt\": \"2026-04-28T00:00:00Z\",
            \"updatedAt\": \"2026-04-28T13:00:00Z\"
          }
        ]
      }
    }
  }
}
"

const fixture_teams_json = "
{
  \"data\": {
    \"viewer\": {
      \"teams\": {
        \"nodes\": [
          {
            \"id\": \"t1\",
            \"key\": \"ENG\",
            \"name\": \"Engineering\"
          },
          {
            \"id\": \"t2\",
            \"key\": \"DES\",
            \"name\": \"Design\"
          }
        ]
      }
    }
  }
}
"

const fixture_projects_json = "
{
  \"data\": {
    \"team\": {
      \"projects\": {
        \"nodes\": [
          {
            \"id\": \"p1\",
            \"name\": \"Integration\",
            \"url\": \"https://linear.app/project/p1\"
          },
          {
            \"id\": \"p2\",
            \"name\": \"Frontend\",
            \"url\": \"https://linear.app/project/p2\"
          }
        ]
      }
    }
  }
}
"

pub fn main() {
  gleeunit.main()
}

pub fn issue_decoder_test() {
  let result = decoder.decode_issues_response(fixture_issue_json)

  case result {
    Ok(issues) -> {
      list.length(issues)
      |> should.equal(2)

      let assert Ok(first_issue) = list.first(issues)

      first_issue.id
      |> should.equal("LIN-001")

      first_issue.identifier
      |> should.equal("ENG-123")

      first_issue.title
      |> should.equal("Implement Linear integration")

      first_issue.priority
      |> should.equal(types.High)
    }
    Error(err) -> {
      io.println("Failed to decode issues: " <> json_error_to_string(err))
      should.fail()
    }
  }
}

pub fn team_decoder_test() {
  let result = decoder.decode_teams_response(fixture_teams_json)

  case result {
    Ok(teams) -> {
      list.length(teams)
      |> should.equal(2)

      let assert Ok(first_team) = list.first(teams)

      first_team.key
      |> should.equal("ENG")

      first_team.name
      |> should.equal("Engineering")
    }
    Error(err) -> {
      io.println("Failed to decode teams: " <> json_error_to_string(err))
      should.fail()
    }
  }
}

pub fn project_decoder_test() {
  let result = decoder.decode_projects_response(fixture_projects_json)

  case result {
    Ok(projects) -> {
      list.length(projects)
      |> should.equal(2)

      let assert Ok(first_project) = list.first(projects)

      first_project.name
      |> should.equal("Integration")
    }
    Error(err) -> {
      io.println("Failed to decode projects: " <> json_error_to_string(err))
      should.fail()
    }
  }
}

pub fn priority_parsing_test() {
  types.parse_priority("urgent")
  |> should.equal(types.Urgent)

  types.parse_priority("high")
  |> should.equal(types.High)

  types.parse_priority("medium")
  |> should.equal(types.Medium)

  types.parse_priority("low")
  |> should.equal(types.Low)

  types.parse_priority("unknown")
  |> should.equal(types.NoPriority)

  types.parse_priority_number(1)
  |> should.equal(types.Urgent)

  types.parse_priority_number(2)
  |> should.equal(types.High)

  types.parse_priority_number(3)
  |> should.equal(types.Medium)

  types.parse_priority_number(4)
  |> should.equal(types.Low)

  types.parse_priority_number(0)
  |> should.equal(types.NoPriority)
}

pub fn priority_weight_test() {
  let order = types.default_priority_order()

  types.priority_weight(order, types.Urgent)
  |> should.equal(0)

  types.priority_weight(order, types.High)
  |> should.equal(1)

  types.priority_weight(order, types.Medium)
  |> should.equal(2)

  types.priority_weight(order, types.Low)
  |> should.equal(3)

  types.priority_weight(order, types.NoPriority)
  |> should.equal(4)
}

pub fn issue_filtering_test() {
  let issues = [
    types.LinearIssue(
      id: "LIN-001",
      identifier: "ENG-123",
      title: "Issue 1",
      description: "Test",
      url: "https://linear.app/issue/ENG-123",
      state: types.LinearState(id: "s1", name: "Todo", state_type: "backlog"),
      priority: types.High,
      assignee: Ok(types.LinearAssignee(
        id: "u1",
        name: "bot",
        display_name: "Robot Bot",
      )),
      project: Ok(types.LinearProject(
        id: "p1",
        name: "Project 1",
        url: "https://linear.app/project/p1",
      )),
      team: Ok(types.LinearTeam(id: "t1", key: "ENG", name: "Engineering")),
      created_at: "2026-04-28T00:00:00Z",
      updated_at: "2026-04-28T12:00:00Z",
    ),
    types.LinearIssue(
      id: "LIN-002",
      identifier: "ENG-124",
      title: "Issue 2",
      description: "Test",
      url: "https://linear.app/issue/ENG-124",
      state: types.LinearState(
        id: "s2",
        name: "In Progress",
        state_type: "started",
      ),
      priority: types.Urgent,
      assignee: Ok(types.LinearAssignee(
        id: "u1",
        name: "bot",
        display_name: "Robot Bot",
      )),
      project: Ok(types.LinearProject(
        id: "p1",
        name: "Project 1",
        url: "https://linear.app/project/p1",
      )),
      team: Ok(types.LinearTeam(id: "t1", key: "ENG", name: "Engineering")),
      created_at: "2026-04-28T00:00:00Z",
      updated_at: "2026-04-28T13:00:00Z",
    ),
  ]

  let filter = selector.default_filter("Todo", "u1")
  let filtered = selector.filter_issues(issues, filter)

  list.length(filtered)
  |> should.equal(1)
}

pub fn issue_selection_test() {
  let issues = [
    types.LinearIssue(
      id: "LIN-001",
      identifier: "ENG-123",
      title: "Low priority issue",
      description: "Test",
      url: "https://linear.app/issue/ENG-123",
      state: types.LinearState(id: "s1", name: "Todo", state_type: "backlog"),
      priority: types.Low,
      assignee: Ok(types.LinearAssignee(
        id: "u1",
        name: "bot",
        display_name: "Robot Bot",
      )),
      project: Ok(types.LinearProject(
        id: "p1",
        name: "Project 1",
        url: "https://linear.app/project/p1",
      )),
      team: Ok(types.LinearTeam(id: "t1", key: "ENG", name: "Engineering")),
      created_at: "2026-04-28T00:00:00Z",
      updated_at: "2026-04-28T10:00:00Z",
    ),
    types.LinearIssue(
      id: "LIN-002",
      identifier: "ENG-124",
      title: "Urgent issue",
      description: "Test",
      url: "https://linear.app/issue/ENG-124",
      state: types.LinearState(id: "s1", name: "Todo", state_type: "backlog"),
      priority: types.Urgent,
      assignee: Ok(types.LinearAssignee(
        id: "u1",
        name: "bot",
        display_name: "Robot Bot",
      )),
      project: Ok(types.LinearProject(
        id: "p1",
        name: "Project 1",
        url: "https://linear.app/project/p1",
      )),
      team: Ok(types.LinearTeam(id: "t1", key: "ENG", name: "Engineering")),
      created_at: "2026-04-28T00:00:00Z",
      updated_at: "2026-04-28T12:00:00Z",
    ),
  ]

  let filter = selector.default_filter("Todo", "u1")
  let order = types.default_priority_order()
  let result = selector.select_issue(issues, filter, order)

  case result {
    types.SelectionSuccess(selected, total_candidates) -> {
      total_candidates
      |> should.equal(2)

      selected.identifier
      |> should.equal("ENG-124")

      selected.priority
      |> should.equal(types.Urgent)
    }
    _ -> should.fail()
  }
}

pub fn state_normalization_test() {
  selector.state_names_match("Todo", "todo")
  |> should.equal(True)

  selector.state_names_match("Todo", "TODO")
  |> should.equal(True)

  selector.state_names_match("Todo", "  Todo  ")
  |> should.equal(True)

  selector.state_names_match("Todo", "In Progress")
  |> should.equal(False)
}

pub fn query_escapes_graphql_strings_test() {
  let built = query.build_team_projects_query("team\"x\nid")

  string.contains(built, "team\\\"x\\nid")
  |> should.equal(True)
}

pub fn github_default_config_model_test() {
  let config =
    types.ProviderConfig(
      provider: types.GitHub,
      repo: "owner/repo",
      project_owner: "owner",
      project_number: 1,
      credentials: types.GitHubToken(token: "ghp_test_token"),
    )

  config.provider
  |> should.equal(types.GitHub)

  case config.credentials {
    types.GitHubToken(token) -> string.starts_with(token, "ghp_")
    _ -> False
  }
  |> should.equal(True)
}

pub fn linear_oauth_app_without_access_token_is_not_graphql_ready_test() {
  let oauth_creds =
    types.LinearOAuthApp(
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
    Error(types.OAuthAppCredentialsWithoutToken(types.Linear)) -> True
    _ -> False
  }
  |> should.equal(True)
}

pub fn linear_missing_credentials_test() {
  let empty_token = types.LinearPersonalToken(token: "")

  case validation.validate_linear_credentials(empty_token) {
    Error(types.MissingCredentials(types.Linear)) -> True
    _ -> False
  }
  |> should.equal(True)
}

pub fn linear_invalid_oauth_shape_test() {
  let invalid_oauth =
    types.LinearOAuthApp(
      client_id: "",
      client_secret: "some_secret",
      access_token: None,
    )

  case validation.validate_linear_credentials(invalid_oauth) {
    Error(types.InvalidCredentialShape(types.Linear, _)) -> True
    _ -> False
  }
  |> should.equal(True)
}

pub fn linear_oauth_with_access_token_is_graphql_ready_test() {
  let oauth_creds =
    types.LinearOAuthApp(
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
  let personal_token = types.LinearPersonalToken(token: "lin_api_test_token")

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
    types.LinearOAuthApp(
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

  let personal_token = types.LinearPersonalToken(token: "lin_api_test_token")
  let redacted = validation.redact_credential(personal_token)
  string.contains(redacted, "****")
  |> should.equal(True)
  string.contains(redacted, "lin_api_test_token")
  |> should.equal(False)
}

pub fn parse_linear_oauth_app_credentials_test() {
  let content = "client_id=linear_client_123\nclient_secret=linear_secret_456"

  case credential.parse_linear_credentials(content) {
    Ok(types.LinearOAuthApp("linear_client_123", "linear_secret_456", None)) ->
      True
    _ -> False
  }
  |> should.equal(True)
}

pub fn parse_linear_personal_token_test() {
  credential.parse_linear_credentials("lin_api_test_token")
  |> should.equal(Ok(types.LinearPersonalToken(token: "lin_api_test_token")))

  credential.parse_linear_credentials("token=lin_api_test_token")
  |> should.equal(Ok(types.LinearPersonalToken(token: "lin_api_test_token")))
}

pub fn discover_reads_linear_credentials_file_test() {
  install_linear_secret(
    "client_id=linear_client_123\nclient_secret=linear_secret_456\n",
  )

  case credential.discover() {
    Ok(discovered) -> {
      case dict.get(discovered.providers, "linear") {
        Ok(types.ProviderConfig(
          credentials: types.LinearOAuthApp(
            client_id: "linear_client_123",
            client_secret: "linear_secret_456",
            access_token: None,
          ),
          ..,
        )) -> True
        _ -> False
      }
    }
    _ -> False
  }
  |> should.equal(True)
}

fn json_error_to_string(err: String) -> String {
  err
}

@external(javascript, "./issue_provider_env_ffi.mjs", "installLinearSecret")
fn install_linear_secret(content: String) -> Nil
