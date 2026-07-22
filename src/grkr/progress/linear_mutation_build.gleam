//// linear_mutation_build.gleam
//// Build/format concern for linear_mutation (LOC hygiene split).
//// Mutation request construction, logging format, id helpers.
//// Zero intentional behavior change.

import gleam/string
import grkr/progress/checkpoint_id
import grkr/progress/checkpoint_stage
import grkr/progress/linear_mutation_types.{
  type LinearIssueId, type MutationRequest, LinearIssueId, MutationRequest,
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

/// Stage-scoped state mutation (preferred). Key: grkr-state-<stage>-<issueId>.
/// Empty stage falls back to "update" segment (still scoped form, no parallel unscoped API).
/// Production callers (via CLI 3-arg or plan_..._scoped) pass explicit stage.
pub fn update_state_mutation_scoped(
  issue_id: LinearIssueId,
  state_id: String,
  stage: String,
) -> MutationRequest {
  let query =
    "mutation ($issueId: String!, $stateId: String!) { issueUpdate(id: $issueId, input: {stateId: $stateId}) { issue { id state { id name } } success } }"

  let variables_json =
    "{\"issueId\":\""
    <> escape_json_string(issue_id.value)
    <> "\",\"stateId\":\""
    <> escape_json_string(state_id)
    <> "\"}"

  let stage_part = case string.trim(stage) {
    "" -> "update"
    s -> s
  }
  let idempotency_key = "grkr-state-" <> stage_part <> "-" <> issue_id.value

  MutationRequest(
    query: query,
    variables_json: variables_json,
    idempotency_key: idempotency_key,
  )
}

/// 2-arg form kept for CLI legacy ("linear-state-mutation <id> <sid>" without stage) and a few tests.
/// Delegates to scoped with "update" fallback so it emits grkr-state-update-<id> (semantically the update stage).
/// Prefer update_state_mutation_scoped (or 3-arg CLI) with explicit stage to avoid cross-stage key collisions.
pub fn update_state_mutation(
  issue_id: LinearIssueId,
  state_id: String,
) -> MutationRequest {
  update_state_mutation_scoped(issue_id, state_id, "")
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

pub fn escape_json_string(value: String) -> String {
  value
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
}

pub fn to_linear_issue_id(issue_id: String) -> LinearIssueId {
  LinearIssueId(value: issue_id)
}

pub fn extract_idempotency_key(request: MutationRequest) -> String {
  request.idempotency_key
}
