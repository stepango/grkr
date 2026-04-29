import gleam/string
import grkr/progress/checkpoint_id
import grkr/progress/checkpoint_stage

pub type LinearIssueId {
  LinearIssueId(value: String)
}

pub type LinearTokenStatus {
  TokenAvailable
  TokenUnavailable
  TokenInvalid
}

pub type MutationRequest {
  MutationRequest(
    query: String,
    variables_json: String,
    idempotency_key: String,
  )
}

pub type MutationResult {
  MutationSuccess(comment_id: String)
  MutationStateUpdateSuccess
  MutationNeedsToken
  MutationFailed(error: String)
}

pub fn create_comment_mutation(
  issue_id: LinearIssueId,
  body: String,
  stage: checkpoint_stage.CheckpointStage,
  task_slug: String,
) -> MutationRequest {
  let marker = checkpoint_id.marker(stage, task_slug)
  let idempotency_key = checkpoint_id.to_idempotency_key(marker)
  let body_with_marker = checkpoint_id.to_html_comment(marker) <> "\n\n" <> body

  let query =
    "mutation ($issueId: ID!, $body: String!) { commentCreate(input: {issueId: $issueId, body: $body}) { comment { id } } }"

  let variables_json =
    "{\"issueId\":\""
    <> escape_json_string(issue_id.value)
    <> "\",\"body\":\""
    <> escape_json_string(body_with_marker)
    <> "\"}"

  MutationRequest(
    query: query,
    variables_json: variables_json,
    idempotency_key: idempotency_key,
  )
}

pub fn update_state_mutation(
  issue_id: LinearIssueId,
  state_id: String,
) -> MutationRequest {
  let query =
    "mutation ($issueId: String!, $stateId: String!) { issueUpdate(id: $issueId, input: {stateId: $stateId}) { issue { id state { id name } } success } }"

  let variables_json =
    "{\"issueId\":\""
    <> escape_json_string(issue_id.value)
    <> "\",\"stateId\":\""
    <> escape_json_string(state_id)
    <> "\"}"

  let idempotency_key = "grkr-state-update-" <> issue_id.value

  MutationRequest(
    query: query,
    variables_json: variables_json,
    idempotency_key: idempotency_key,
  )
}

pub fn create_comment_with_pr_link(
  issue_id: LinearIssueId,
  body: String,
  pr_url: String,
  stage: checkpoint_stage.CheckpointStage,
  task_slug: String,
) -> MutationRequest {
  let pr_section = "\n\n### PR\n\n" <> "PR: " <> pr_url <> "\n"
  let full_body = body <> pr_section

  create_comment_mutation(issue_id, full_body, stage, task_slug)
}

pub fn format_mutation_for_logging(request: MutationRequest) -> String {
  "Query: "
  <> request.query
  <> "\nVariables: "
  <> "[redacted]"
  <> "\nIdempotency key: "
  <> request.idempotency_key
}

fn escape_json_string(value: String) -> String {
  value
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
}

pub fn check_token_status(
  token_getter: fn() -> Result(String, Nil),
) -> LinearTokenStatus {
  case token_getter() {
    Ok(token) -> {
      case string.trim(token) {
        "" -> TokenUnavailable
        _ -> TokenAvailable
      }
    }
    Error(_) -> TokenUnavailable
  }
}

pub fn mutation_result_from_response(response: String) -> MutationResult {
  let lower = string.lowercase(response)
  case string.contains(lower, "errors") {
    True -> MutationFailed("Linear mutation returned errors")
    False -> {
      case string.contains(lower, "commentcreate") {
        True -> MutationSuccess("created")
        False -> MutationFailed("Unknown mutation response")
      }
    }
  }
}

pub fn safe_unavailable_token_result(
  token_status: LinearTokenStatus,
) -> MutationResult {
  case token_status {
    TokenAvailable -> MutationNeedsToken
    TokenUnavailable -> MutationFailed("Linear access token not available")
    TokenInvalid -> MutationFailed("Linear access token invalid")
  }
}

pub fn build_error_context(error: String) -> String {
  "Linear mutation failed: "
  <> error
  <> "\nNote: Linear credentials in ~/.linear/secret.txt are OAuth app credentials, "
  <> "not personal API keys. Write operations require proper OAuth token setup."
}

pub fn is_idempotent_error(error: String) -> Bool {
  let lower = string.lowercase(error)
  string.contains(lower, "duplicate")
  || string.contains(lower, "already exists")
  || string.contains(lower, "unique")
}

pub fn should_retry_mutation(result: MutationResult) -> Bool {
  case result {
    MutationFailed(error) -> !is_idempotent_error(error)
    _ -> False
  }
}

pub fn to_linear_issue_id(issue_id: String) -> LinearIssueId {
  LinearIssueId(value: issue_id)
}

pub fn extract_idempotency_key(request: MutationRequest) -> String {
  request.idempotency_key
}
