//// checkpoint_plan.gleam
//// Cluster A extracted from progress/main.gleam for LOC hygiene (t_8c7cd0a0).
//// Checkpoint render planning + stage validation + marker/idempotency fns.
/// Public surface preserved via thin facade in main.gleam.
/// Delegates to lower checkpoint_* modules. Zero behavior change.

import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import grkr/progress/checkpoint_id
import grkr/progress/checkpoint_render
import grkr/progress/checkpoint_stage
import grkr/progress/linear_mutation

pub type ProgressUpdate {
  ProgressUpdate(
    task_slug: String,
    stage: checkpoint_stage.CheckpointStage,
    body: String,
    pr_url: Option(String),
    linear_issue_id: Option(linear_mutation.LinearIssueId),
  )
}

pub fn plan_checkpoint_render(
  task_slug: String,
  stage: checkpoint_stage.CheckpointStage,
  body: String,
) -> String {
  let content =
    checkpoint_render.CheckpointContent(
      stage: stage,
      task_slug: task_slug,
      body: body,
      pr_url: None,
    )

  checkpoint_render.render_checkpoint(content)
}

pub fn plan_checkpoint_render_with_pr(
  task_slug: String,
  stage: checkpoint_stage.CheckpointStage,
  body: String,
  pr_url: String,
) -> String {
  let content =
    checkpoint_render.CheckpointContent(
      stage: stage,
      task_slug: task_slug,
      body: body,
      pr_url: Some(pr_url),
    )

  checkpoint_render.render_checkpoint(content)
}

pub fn plan_refusal_render(
  task_slug: String,
  reason_class: String,
  reasoning: String,
) -> String {
  checkpoint_render.render_refusal(task_slug, reason_class, reasoning)
}

pub fn plan_pr_summary_render(
  task_slug: String,
  pr_url: String,
  branch_url: String,
) -> String {
  checkpoint_render.render_pr_summary(task_slug, pr_url, branch_url)
}

pub fn validate_checkpoint_stage(
  stage_str: String,
) -> Result(checkpoint_stage.CheckpointStage, String) {
  checkpoint_stage.from_string(stage_str)
}

pub fn extract_stage_from_existing_comment(
  comment: String,
) -> Result(checkpoint_stage.CheckpointStage, String) {
  checkpoint_render.extract_stage_from_comment(comment)
}

pub fn has_checkpoint_marker(
  comment: String,
  stage_str: String,
  task_slug: String,
) -> Result(Bool, String) {
  use stage <- result.try(checkpoint_stage.from_string(stage_str))
  Ok(checkpoint_render.has_checkpoint_marker(comment, stage, task_slug))
}

pub fn generate_idempotency_key(
  stage: checkpoint_stage.CheckpointStage,
  task_slug: String,
) -> String {
  let marker = checkpoint_id.marker(stage, task_slug)
  checkpoint_id.to_idempotency_key(marker)
}

pub fn format_checkpoint_marker(
  stage: checkpoint_stage.CheckpointStage,
  task_slug: String,
) -> String {
  let marker = checkpoint_id.marker(stage, task_slug)
  checkpoint_id.to_html_comment(marker)
}

pub fn cli_render_checkpoint(
  stage: String,
  task_slug: String,
  body: String,
) -> Result(String, String) {
  use validated_stage <- result.try(validate_checkpoint_stage(stage))
  Ok(plan_checkpoint_render(task_slug, validated_stage, body) |> string.trim())
}

pub fn cli_render_checkpoint_with_pr(
  stage: String,
  task_slug: String,
  body: String,
  pr_url: String,
) -> Result(String, String) {
  use validated_stage <- result.try(validate_checkpoint_stage(stage))
  Ok(plan_checkpoint_render_with_pr(task_slug, validated_stage, body, pr_url))
}

pub fn cli_render_refusal(
  task_slug: String,
  reason_class: String,
  reasoning: String,
) -> String {
  plan_refusal_render(task_slug, reason_class, reasoning)
}

pub fn cli_render_pr_summary(
  task_slug: String,
  pr_url: String,
  branch_url: String,
) -> String {
  plan_pr_summary_render(task_slug, pr_url, branch_url)
}
