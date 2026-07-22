//// linear_mutation_policy.gleam
//// Policy/apply-sidecar concern for linear_mutation (LOC hygiene split).
//// Token checks, retry/idempotency, live/strict gates, sidecar format/classify.
//// Zero intentional behavior change.

import gleam/list
import gleam/result
import gleam/string
import grkr/progress/linear_mutation_types.{
  type LinearTokenStatus, type MutationResult, MutationFailed, MutationNeedsToken,
  MutationStateUpdateSuccess, MutationSuccess, TokenAvailable, TokenInvalid,
  TokenUnavailable,
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

/// Literal gate: only "1" enables live apply. All other values (unset, "", "0", "true") stay dry-run.
pub fn should_apply_live(env_get: fn(String) -> String) -> Bool {
  env_get("GRKR_LINEAR_MUTATE") == "1"
}

/// Literal gate: only "1" enables hard-fail on non-idempotent apply failures.
/// Refuse paths are always soft (even under STRICT). Default (unset/anything != "1") is soft.
pub fn should_strict_hard_fail(env_get: fn(String) -> String) -> Bool {
  env_get("GRKR_LINEAR_MUTATE_STRICT") == "1"
}

/// Returns true if the dump's basename starts with "refusal." (e.g. refusal.linear-mutation.txt).
/// Refuse apply failures remain soft even when STRICT=1.
pub fn dump_is_refuse_path(path: String) -> Bool {
  let base = last_path_segment(path)
  string.starts_with(base, "refusal.")
}

fn last_path_segment(p: String) -> String {
  // Support / and \ ; take the final segment or whole string if none.
  let after_slash =
    p
    |> string.split("/")
    |> list.reverse
    |> list.first
    |> result.unwrap(p)
  after_slash
  |> string.split("\\")
  |> list.reverse
  |> list.first
  |> result.unwrap(after_slash)
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
