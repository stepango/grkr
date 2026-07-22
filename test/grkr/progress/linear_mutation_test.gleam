import gleam/string
import gleeunit
import gleeunit/should
import grkr/progress/checkpoint_stage
import grkr/progress/linear_mutation
import grkr/progress/linear_mutation_types.{
  MutationFailed, MutationNeedsToken, MutationRequest, MutationStateUpdateSuccess,
  MutationSuccess, TokenAvailable, TokenUnavailable,
}

pub fn main() {
  gleeunit.main()
}

pub fn create_comment_mutation_test() {
  let issue_id = linear_mutation.to_linear_issue_id("LIN-123")
  let request =
    linear_mutation.create_comment_mutation(
      issue_id,
      "Test body",
      checkpoint_stage.Research,
      "issue-456-test",
    )

  string.contains(request.query, "commentCreate")
  |> should.be_true()

  request.idempotency_key
  |> should.equal("grkr-checkpoint-research-issue-456-test")
}

pub fn create_refusal_comment_mutation_test() {
  let issue_id = linear_mutation.to_linear_issue_id("LIN-001")
  let request =
    linear_mutation.create_comment_mutation(
      issue_id,
      "Refusal body",
      checkpoint_stage.Refusal,
      "eng-123",
    )

  string.contains(request.query, "commentCreate")
  |> should.be_true()

  request.idempotency_key
  |> should.equal("grkr-checkpoint-refusal-eng-123")

  string.contains(request.variables_json, "grkr:checkpoint stage=refusal")
  |> should.be_true()
}

pub fn update_state_mutation_test() {
  let issue_id = linear_mutation.to_linear_issue_id("LIN-456")
  let request = linear_mutation.update_state_mutation(issue_id, "STATE-789")

  string.contains(request.query, "issueUpdate")
  |> should.be_true()

  string.contains(request.query, "issueUpdate(id: $issueId, input:")
  |> should.be_true()

  string.contains(request.query, "issueUpdate(input: {id:")
  |> should.be_false()

  request.idempotency_key
  |> should.equal("grkr-state-update-LIN-456")
}

pub fn update_state_mutation_scoped_test() {
  let issue_id = linear_mutation.to_linear_issue_id("LIN-456")
  let request =
    linear_mutation.update_state_mutation_scoped(issue_id, "STATE-789", "implement")

  string.contains(request.query, "issueUpdate")
  |> should.be_true()

  request.idempotency_key
  |> should.equal("grkr-state-implement-LIN-456")

  // default empty stage falls back to "update"
  let req2 =
    linear_mutation.update_state_mutation_scoped(issue_id, "S2", "")
  req2.idempotency_key
  |> should.equal("grkr-state-update-LIN-456")
}

pub fn create_comment_with_pr_link_test() {
  let issue_id = linear_mutation.to_linear_issue_id("LIN-789")
  let request =
    linear_mutation.create_comment_with_pr_link(
      issue_id,
      "Implementation complete",
      "https://github.com/test/repo/pull/123",
      checkpoint_stage.Implementation,
      "issue-999-impl",
    )

  string.contains(request.query, "commentCreate")
  |> should.be_true()

  request.idempotency_key
  |> should.equal("grkr-checkpoint-implementation-issue-999-impl")
}

pub fn check_token_status_test() {
  let mock_token_getter = fn() { Ok("valid-token-123") }
  let status = linear_mutation.check_token_status(mock_token_getter)

  status
  |> should.equal(TokenAvailable)

  let empty_token_getter = fn() { Ok("") }
  let empty_status = linear_mutation.check_token_status(empty_token_getter)

  empty_status
  |> should.equal(TokenUnavailable)

  let error_token_getter = fn() { Error(Nil) }
  let error_status = linear_mutation.check_token_status(error_token_getter)

  error_status
  |> should.equal(TokenUnavailable)
}

pub fn safe_unavailable_token_result_test() {
  let result =
    linear_mutation.safe_unavailable_token_result(
      TokenAvailable,
    )

  result
  |> should.equal(MutationNeedsToken)

  let unavailable_result =
    linear_mutation.safe_unavailable_token_result(
      TokenUnavailable,
    )

  unavailable_result
  |> should.equal(MutationFailed(
    "Linear access token not available",
  ))
}

pub fn is_idempotent_error_test() {
  linear_mutation.is_idempotent_error("Duplicate comment found")
  |> should.be_true()

  linear_mutation.is_idempotent_error("Comment already exists")
  |> should.be_true()

  linear_mutation.is_idempotent_error("Unique constraint violation")
  |> should.be_true()

  linear_mutation.is_idempotent_error("Network error")
  |> should.be_false()
}

pub fn should_retry_mutation_test() {
  let retry_result = MutationFailed("Network timeout")
  let should_retry = linear_mutation.should_retry_mutation(retry_result)

  should_retry
  |> should.be_true()

  let no_retry_result = MutationFailed("Duplicate comment")
  let should_not_retry = linear_mutation.should_retry_mutation(no_retry_result)

  should_not_retry
  |> should.be_false()

  let success_result = MutationSuccess("comment-123")
  let should_not_retry_success =
    linear_mutation.should_retry_mutation(success_result)

  should_not_retry_success
  |> should.be_false()
}

pub fn build_error_context_test() {
  let error_context = linear_mutation.build_error_context("Test error")

  string.contains(error_context, "Test error")
  |> should.be_true()

  string.contains(error_context, "OAuth")
  |> should.be_true()
}

pub fn format_mutation_for_logging_redacts_variables_test() {
  let request =
    MutationRequest(
      query: "mutation SecretMutation",
      variables_json: "{\"body\":\"token=secret-value\"}",
      idempotency_key: "grkr-checkpoint-test-issue-1",
    )

  let log = linear_mutation.format_mutation_for_logging(request)

  string.contains(log, "mutation SecretMutation")
  |> should.be_true()

  string.contains(log, "[redacted]")
  |> should.be_true()

  string.contains(log, "secret-value")
  |> should.be_false()
}

pub fn to_linear_issue_id_test() {
  let issue_id = linear_mutation.to_linear_issue_id("LIN-999")

  issue_id.value
  |> should.equal("LIN-999")
}

pub fn extract_idempotency_key_test() {
  let issue_id = linear_mutation.to_linear_issue_id("LIN-1000")
  let request =
    linear_mutation.create_comment_mutation(
      issue_id,
      "Test",
      checkpoint_stage.Test,
      "issue-1001-test",
    )

  linear_mutation.extract_idempotency_key(request)
  |> should.equal("grkr-checkpoint-test-issue-1001-test")
}

pub fn parse_three_line_dump_test() {
  let full = "mutation Foo {x}\n{\"a\":1}\nkey-xyz"
  case linear_mutation.parse_three_line_dump(full) {
    Ok(#(q, v, k)) -> {
      q |> should.equal("mutation Foo {x}")
      v |> should.equal("{\"a\":1}")
      k |> should.equal("key-xyz")
    }
    Error(_) -> should.fail()
  }

  // name-only should error
  let name_only = "TARGET_STATE=Done\nSTATE_MUTATION_PLANNED=0\n"
  case linear_mutation.parse_three_line_dump(name_only) {
    Error(e) -> string.contains(e, "name-only") |> should.be_true()
    Ok(_) -> should.fail()
  }
}

pub fn should_apply_live_test() {
  linear_mutation.should_apply_live(fn(_) { "1" })
  |> should.be_true()

  linear_mutation.should_apply_live(fn(_) { "" })
  |> should.be_false()

  linear_mutation.should_apply_live(fn(_) { "0" })
  |> should.be_false()

  linear_mutation.should_apply_live(fn(_) { "true" })
  |> should.be_false()
}

pub fn mutation_result_from_response_test() {
  // comment success shape with id (after commentCreate)
  let comment_resp = "{\"data\":{\"commentCreate\":{\"comment\":{\"id\":\"cmt_123\"}}}}"
  case linear_mutation.mutation_result_from_response(comment_resp) {
    MutationSuccess(id) -> id |> should.equal("cmt_123")
    _ -> should.fail()
  }

  // state success with issueUpdate + success true (space variants)
  let state_resp = "{\"data\":{\"issueUpdate\":{\"success\":true}}}"
  case linear_mutation.mutation_result_from_response(state_resp) {
    MutationStateUpdateSuccess -> True |> should.be_true()
    _ -> should.fail()
  }

  let state_resp2 = "{\"data\":{\"issueUpdate\":{\"success\": true }}}"
  case linear_mutation.mutation_result_from_response(state_resp2) {
    MutationStateUpdateSuccess -> True |> should.be_true()
    _ -> should.fail()
  }

  // error array at top -> failed
  let err_resp = "{\"errors\":[{\"message\":\"boom\"}]}"
  case linear_mutation.mutation_result_from_response(err_resp) {
    MutationFailed(_) -> True |> should.be_true()
    _ -> should.fail()
  }

  // idempotent duplicate error -> success idempotent (even with errors array)
  let dup_err = "{\"errors\":[{\"message\":\"Comment already exists (duplicate)\"}]}"
  case linear_mutation.mutation_result_from_response(dup_err) {
    MutationSuccess(id) -> id |> should.equal("idempotent-duplicate")
    _ -> should.fail()
  }

  // NEGATIVE: bare word "success"/"comment" without real shapes must NOT be success/applied
  let bogus_success = "{\"data\":null, \"note\":\"this text mentions success but no shape\"}"
  case linear_mutation.mutation_result_from_response(bogus_success) {
    MutationFailed(_) -> True |> should.be_true()
    _ -> should.fail()
  }

  let bogus_comment = "some random text containing the word comment and success"
  case linear_mutation.mutation_result_from_response(bogus_comment) {
    MutationFailed(_) -> True |> should.be_true()
    _ -> should.fail()
  }

  // data null is not success shapes
  let data_null = "{\"data\":null}"
  case linear_mutation.mutation_result_from_response(data_null) {
    MutationFailed(_) -> True |> should.be_true()
    _ -> should.fail()
  }
}

pub fn format_apply_sidecar_test() {
  linear_mutation.format_apply_sidecar("k1", "applied", "comment_id=xyz")
  |> should.equal("key=k1 status=applied comment_id=xyz")

  linear_mutation.format_apply_sidecar("k2", "skipped-no-token", "")
  |> should.equal("key=k2 status=skipped-no-token")
}

pub fn sidecar_indicates_already_done_test() {
  // terminal
  linear_mutation.sidecar_indicates_already_done("key=k status=applied")
  |> should.be_true()

  linear_mutation.sidecar_indicates_already_done("key=k status=skipped-already")
  |> should.be_true()

  linear_mutation.sidecar_indicates_already_done("key=k status=skipped-no-state-id target=foo")
  |> should.be_true()

  // soft non-terminal: no-token must NOT block resume
  linear_mutation.sidecar_indicates_already_done("key=k status=skipped-no-token")
  |> should.be_false()

  // failed is retryable
  linear_mutation.sidecar_indicates_already_done("key=k status=failed error=boom")
  |> should.be_false()

  // broad old "skipped" substring alone is not enough
  linear_mutation.sidecar_indicates_already_done("key=k status=skipped-no-token foo")
  |> should.be_false()
}
