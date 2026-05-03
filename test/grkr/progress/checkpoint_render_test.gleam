import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import grkr/progress/checkpoint_stage
import grkr/progress/checkpoint_render

pub fn main() {
  gleeunit.main()
}

pub fn render_checkpoint_test() {
  let content =
    checkpoint_render.CheckpointContent(
      stage: checkpoint_stage.Research,
      task_slug: "issue-123-test",
      body: "Research findings here",
      pr_url: None,
    )

  let result = checkpoint_render.render_checkpoint(content)

  string.contains(result, "grkr:checkpoint")
  |> should.be_true()

  string.contains(result, "stage=research")
  |> should.be_true()

  string.contains(result, "Research checkpoint")
  |> should.be_true()

  string.contains(result, "Research findings here")
  |> should.be_true()
}

pub fn render_checkpoint_with_pr_test() {
  let content =
    checkpoint_render.CheckpointContent(
      stage: checkpoint_stage.Implementation,
      task_slug: "issue-456-foo",
      body: "Implementation complete",
      pr_url: Some("https://github.com/test/repo/pull/123"),
    )

  let result = checkpoint_render.render_checkpoint(content)

  string.contains(result, "Implementation checkpoint")
  |> should.be_true()

  string.contains(result, "Implementation complete")
  |> should.be_true()

  string.contains(result, "### PR")
  |> should.be_true()

  string.contains(result, "https://github.com/test/repo/pull/123")
  |> should.be_true()
}

pub fn render_pr_summary_test() {
  let result =
    checkpoint_render.render_pr_summary(
      "issue-789-bar",
      "https://github.com/test/repo/pull/456",
      "https://github.com/test/repo/tree/feature-branch",
    )

  string.contains(result, "grkr:checkpoint")
  |> should.be_true()

  string.contains(result, "stage=pr_summary")
  |> should.be_true()

  string.contains(result, "PR summary")
  |> should.be_true()

  string.contains(result, "https://github.com/test/repo/pull/456")
  |> should.be_true()

  string.contains(result, "https://github.com/test/repo/tree/feature-branch")
  |> should.be_true()
}

pub fn render_refusal_test() {
  let result =
    checkpoint_render.render_refusal(
      "issue-999-baz",
      "underspecified",
      "This issue needs more details before implementation can proceed.",
    )

  string.contains(result, "grkr:checkpoint")
  |> should.be_true()

  string.contains(result, "stage=refusal")
  |> should.be_true()

  string.contains(result, "Implementation refused")
  |> should.be_true()

  string.contains(result, "**Reason class:** underspecified")
  |> should.be_true()

  string.contains(result, "This issue needs more details")
  |> should.be_true()
}

pub fn extract_stage_from_comment_test() {
  let comment =
    "<!-- grkr:checkpoint stage=plan task=issue-123-test version=1 -->\n\n## Plan checkpoint"

  let result = checkpoint_render.extract_stage_from_comment(comment)

  result
  |> should.equal(Ok(checkpoint_stage.Plan))
}

pub fn has_checkpoint_marker_test() {
  let comment =
    "<!-- grkr:checkpoint stage=test task=issue-123-test version=1 -->\n\n## Test checkpoint"

  let result =
    checkpoint_render.has_checkpoint_marker(comment, checkpoint_stage.Test, "issue-123-test")

  result
  |> should.be_true()

  let false_result =
    checkpoint_render.has_checkpoint_marker(comment, checkpoint_stage.Plan, "issue-123-test")

  false_result
  |> should.be_false()
}
