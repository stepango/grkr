import gleeunit
import gleam/string
import gleeunit/should
import grkr/progress/checkpoint_stage
import grkr/progress/checkpoint_id

pub fn main() {
  gleeunit.main()
}

pub fn marker_test() {
  let marker = checkpoint_id.marker(checkpoint_stage.Research, "issue-123-test")

  checkpoint_id.extract_stage(marker)
  |> should.equal(checkpoint_stage.Research)

  checkpoint_id.extract_task_slug(marker)
  |> should.equal("issue-123-test")
}

pub fn to_html_comment_test() {
  let marker = checkpoint_id.marker(checkpoint_stage.Research, "issue-123-test")
  let comment = checkpoint_id.to_html_comment(marker)

  string.contains(comment, "grkr:checkpoint")
  |> should.be_true()

  string.contains(comment, "stage=research")
  |> should.be_true()

  string.contains(comment, "task=issue-123-test")
  |> should.be_true()

  string.contains(comment, "version=1")
  |> should.be_true()
}

pub fn to_idempotency_key_test() {
  let marker = checkpoint_id.marker(checkpoint_stage.Plan, "issue-456-foo")
  let key = checkpoint_id.to_idempotency_key(marker)

  key
  |> should.equal("grkr-checkpoint-plan-issue-456-foo")
}

pub fn marker_with_version_test() {
  let marker =
    checkpoint_id.marker_with_version(
      checkpoint_stage.Test,
      "issue-789-bar",
      2,
    )
  let comment = checkpoint_id.to_html_comment(marker)

  string.contains(comment, "version=2")
  |> should.be_true()
}

pub fn parse_marker_from_comment_test() {
  let comment =
    "<!-- grkr:checkpoint stage=research task=issue-123-test version=1 -->"

  let result = checkpoint_id.parse_marker_from_comment(comment)

  result
  |> should.equal(Ok(checkpoint_stage.Research))
}

pub fn parse_marker_from_comment_invalid_test() {
  let comment = "<!-- not a checkpoint marker -->"

  let result = checkpoint_id.parse_marker_from_comment(comment)

  result
  |> should.be_error()
}

pub fn matches_marker_test() {
  let comment =
    "<!-- grkr:checkpoint stage=research task=issue-123-test version=1 -->\n\n## Research checkpoint"

  let result =
    checkpoint_id.matches_marker(comment, checkpoint_stage.Research, "issue-123-test")

  result
  |> should.be_true()

  let false_result =
    checkpoint_id.matches_marker(comment, checkpoint_stage.Plan, "issue-123-test")

  false_result
  |> should.be_false()

  let false_result_2 =
    checkpoint_id.matches_marker(
      comment,
      checkpoint_stage.Research,
      "issue-456-other",
    )

  false_result_2
  |> should.be_false()
}
