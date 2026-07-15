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
  let trimmed = string.trim(response)
  let lower = string.lowercase(trimmed)

  // Strict: top-level "errors" array JSON shape only (not bare word in messages).
  case has_top_level_errors_array(trimmed, lower) {
    True -> {
      case is_idempotent_error(response) {
        True -> MutationSuccess("idempotent-duplicate")
        False -> MutationFailed("Linear mutation returned errors")
      }
    }
    False -> {
      // Comment success: require commentCreate section + id under it.
      case extract_comment_id(trimmed, lower) {
        Ok(cid) ->
          MutationSuccess(case cid {
            "" -> "created"
            c -> c
          })
        Error(_) ->
          case is_state_update_success(lower) {
            True -> MutationStateUpdateSuccess
            // Unrecognized shapes must not become false "applied"
            False -> MutationFailed("unrecognized Linear mutation response")
          }
      }
    }
  }
}

fn has_top_level_errors_array(resp: String, lower: String) -> Bool {
  // JSON-ish top level errors array: "errors":[ or "errors": [  or starts-with {"errors"
  string.contains(lower, "\"errors\":[")
  || string.contains(lower, "\"errors\": [")
  || string.contains(lower, "\"errors\" :[")
  || string.contains(lower, "\"errors\" : [")
  || string.starts_with(string.trim(resp), "{\"errors\"")
  || string.contains(lower, "{\"errors\":[")
}

fn is_state_update_success(lower: String) -> Bool {
  // Require issueUpdate section + explicit success:true (space tolerant).
  case string.contains(lower, "issueupdate") {
    True ->
      string.contains(lower, "\"success\":true")
      || string.contains(lower, "\"success\": true")
      || string.contains(lower, "\"success\" :true")
      || string.contains(lower, "\"success\" : true")
    False -> False
  }
}

fn extract_comment_id(resp: String, lower: String) -> Result(String, Nil) {
  case string.contains(lower, "commentcreate") {
    True -> {
      let id = extract_id_after_section(resp, "commentCreate")
      case id {
        "" -> {
          // fallback to simple near "comment" only after confirming shape
          let cid = extract_first_quoted_id_after(resp, "\"comment\"")
          case cid {
            "" -> Ok("created")
            c -> Ok(c)
          }
        }
        c -> Ok(c)
      }
    }
    False -> Error(Nil)
  }
}

fn extract_id_after_section(response: String, section: String) -> String {
  let lower = string.lowercase(response)
  let sec_lower = string.lowercase(section)
  case string.contains(lower, sec_lower) {
    False -> ""
    True -> {
      // Take text after first occurrence of section and find first id value.
      let parts = string.split(response, section)
      case parts {
        [_, after, ..] -> extract_first_quoted_id(after)
        _ -> ""
      }
    }
  }
}

fn extract_first_quoted_id(s: String) -> String {
  let parts = string.split(s, "\"id\":\"")
  case parts {
    [_, after, ..] -> {
      case string.split(after, "\"") {
        [id, ..] -> id
        _ -> ""
      }
    }
    _ -> ""
  }
}

fn extract_first_quoted_id_after(response: String, marker: String) -> String {
  let lower = string.lowercase(response)
  case string.contains(lower, string.lowercase(marker)) {
    False -> ""
    True -> {
      let parts = string.split(response, marker)
      case parts {
        [_, after, ..] -> extract_first_quoted_id(after)
        _ -> ""
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

/// Alias for the three-line dump parser (used by apply + tests).
pub fn parse_three_line_dump(content: String) -> Result(#(String, String, String), String) {
  parse_mutation_dump(content)
}

/// Literal gate: only "1" enables live apply. All other values (unset, "", "0", "true") stay dry-run.
pub fn should_apply_live(env_get: fn(String) -> String) -> Bool {
  env_get("GRKR_LINEAR_MUTATE") == "1"
}

/// Parse a three-line dump (query\nvariables_json\nkey) or name-only form.
/// Returns Ok(#(query, vars, key)) for full; Error for name-only or invalid.
pub fn parse_mutation_dump(content: String) -> Result(#(String, String, String), String) {
  let lines = string.split(string.trim(content), "\n")
  case lines {
    [q, v, k] ->
      case string.starts_with(q, "TARGET_STATE=") {
        True -> Error("name-only:" <> content)
        False -> Ok(#(q, v, k))
      }
    [first, ..] ->
      case string.starts_with(first, "TARGET_STATE=") {
        True -> Error("name-only:" <> content)
        False ->
          case list_length(lines) >= 3 {
            True -> {
              // tolerate extra newlines
              let q = case lines {
                [qq, ..] -> qq
                _ -> ""
              }
              let v = case lines {
                [_, vv, ..] -> vv
                _ -> ""
              }
              let k = case lines {
                [_, _, kk, ..] -> kk
                _ -> ""
              }
              case q {
                "" -> Error("invalid dump")
                _ -> Ok(#(q, v, k))
              }
            }
            False -> Error("invalid dump: " <> content)
          }
      }
    _ -> Error("invalid dump: " <> content)
  }
}

fn list_length(l: List(a)) -> Int {
  case l {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}

/// Format sidecar content for *.linear-apply-result.txt
/// Example: key=... status=applied comment_id=...
pub fn format_apply_sidecar(
  key: String,
  status: String,
  detail: String,
) -> String {
  let base = "key=" <> key <> " status=" <> status
  case string.trim(detail) {
    "" -> base
    d -> base <> " " <> d
  }
}

/// Classify apply outcome for logging/markers from result + context.
/// Returns tuple (marker_status, extra_info)
pub fn classify_apply_outcome(
  result: MutationResult,
  _had_token: Bool,
  already_sidecar: Bool,
) -> #(String, String) {
  case already_sidecar {
    True -> #("skipped-already", "")
    False ->
      case result {
        MutationSuccess(id) ->
          case id {
            "idempotent-duplicate" -> #("applied", "comment_id=" <> id)
            _ -> #("applied", "comment_id=" <> id)
          }
        MutationStateUpdateSuccess -> #("applied", "state_id=ok")
        MutationNeedsToken -> #("skipped-no-token", "")
        MutationFailed(e) -> #("failed", "error=" <> redact_for_marker(e))
      }
  }
}

/// Returns true only for terminal sidecar statuses that mean "already done, do not retry".
/// - "applied" and "skipped-already" are terminal success.
/// - "skipped-no-state-id" is terminal (no state id is stable for the run).
/// Soft non-terminal (must allow resume):
/// - "skipped-no-token" (token may appear later)
/// - "failed" (transient or fixable)
pub fn sidecar_indicates_already_done(prior: String) -> Bool {
  string.contains(prior, "status=applied")
  || string.contains(prior, "status=skipped-already")
  || string.contains(prior, "status=skipped-no-state-id")
}

fn redact_for_marker(s: String) -> String {
  // Simple redaction for marker (token already redacted upstream)
  s
  |> string.replace("\n", " ")
  |> string.replace("\"", "'")
  |> string.slice(0, 120)
}
