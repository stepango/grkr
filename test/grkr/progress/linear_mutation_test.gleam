import gleeunit
import gleam/string
import gleeunit/should
import grkr/progress/checkpoint_stage
import grkr/progress/linear_mutation

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

pub fn update_state_mutation_test() {
  let issue_id = linear_mutation.to_linear_issue_id("LIN-456")
  let request = linear_mutation.update_state_mutation(issue_id, "STATE-789")

  string.contains(request.query, "issueUpdate")
  |> should.be_true()

  request.idempotency_key
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
  |> should.equal(linear_mutation.TokenAvailable)

  let empty_token_getter = fn() { Ok("") }
  let empty_status = linear_mutation.check_token_status(empty_token_getter)

  empty_status
  |> should.equal(linear_mutation.TokenUnavailable)

  let error_token_getter = fn() { Error(Nil) }
  let error_status = linear_mutation.check_token_status(error_token_getter)

  error_status
  |> should.equal(linear_mutation.TokenUnavailable)
}

pub fn safe_unavailable_token_result_test() {
  let result = linear_mutation.safe_unavailable_token_result(linear_mutation.TokenAvailable)

  result
  |> should.equal(linear_mutation.MutationNeedsToken)

  let unavailable_result =
    linear_mutation.safe_unavailable_token_result(linear_mutation.TokenUnavailable)

  unavailable_result
  |> should.equal(linear_mutation.MutationFailed("Linear access token not available"))
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
  let retry_result = linear_mutation.MutationFailed("Network timeout")
  let should_retry = linear_mutation.should_retry_mutation(retry_result)

  should_retry
  |> should.be_true()

  let no_retry_result = linear_mutation.MutationFailed("Duplicate comment")
  let should_not_retry = linear_mutation.should_retry_mutation(no_retry_result)

  should_not_retry
  |> should.be_false()

  let success_result = linear_mutation.MutationSuccess("comment-123")
  let should_not_retry_success = linear_mutation.should_retry_mutation(success_result)

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
