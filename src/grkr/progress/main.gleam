import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import grkr/progress/checkpoint_stage
import grkr/progress/checkpoint_render
import grkr/progress/checkpoint_id
import grkr/progress/linear_state
import grkr/progress/linear_mutation
import grkr/progress/templates

pub type ProgressUpdate {
  ProgressUpdate(
    task_slug: String,
    stage: checkpoint_stage.CheckpointStage,
    body: String,
    pr_url: Option(String),
    linear_issue_id: Option(linear_mutation.LinearIssueId),
  )
}

/// Planned Linear refuse path (comment checkpoint + backlog state). Dry-run only;
/// no network. Used by progress CLI + shell refuse helpers (post-MVP t_503ca0f3).
pub type LinearRefusalPlan {
  LinearRefusalPlan(
    body: String,
    comment_mutation: linear_mutation.MutationRequest,
    target_state_name: String,
    state_mutation: Option(linear_mutation.MutationRequest),
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

pub fn plan_linear_state_update(
  stage: checkpoint_stage.CheckpointStage,
  env_getter: fn(String) -> String,
) -> Result(String, String) {
  let mapping = linear_state.from_env(env_getter)
  let state_name = linear_state.state_for_stage(mapping, stage)

  Ok(state_name)
}

pub fn plan_linear_comment_mutation(
  linear_issue_id: String,
  body: String,
  stage: checkpoint_stage.CheckpointStage,
  task_slug: String,
) -> linear_mutation.MutationRequest {
  let issue_id = linear_mutation.to_linear_issue_id(linear_issue_id)
  linear_mutation.create_comment_mutation(issue_id, body, stage, task_slug)
}

pub fn plan_linear_state_mutation(
  linear_issue_id: String,
  state_id: String,
) -> linear_mutation.MutationRequest {
  let issue_id = linear_mutation.to_linear_issue_id(linear_issue_id)
  linear_mutation.update_state_mutation(issue_id, state_id)
}


/// Compose refuse checkpoint body + Linear commentCreate plan + Backlog state plan.
/// When `state_id` is non-empty, also plans issueUpdate state mutation (still no network).
pub fn plan_linear_refusal(
  linear_issue_id: String,
  task_slug: String,
  reason_class: String,
  reasoning: String,
  state_id: String,
  env_getter: fn(String) -> String,
) -> LinearRefusalPlan {
  let body = plan_refusal_render(task_slug, reason_class, reasoning)
  let comment_mutation =
    plan_linear_comment_mutation(
      linear_issue_id,
      body,
      checkpoint_stage.Refusal,
      task_slug,
    )
  let mapping = linear_state.from_env(env_getter)
  let target_state_name =
    linear_state.state_for_stage(mapping, checkpoint_stage.Refusal)
  let state_mutation = case string.trim(state_id) {
    "" -> None
    sid -> Some(plan_linear_state_mutation(linear_issue_id, sid))
  }
  LinearRefusalPlan(
    body: body,
    comment_mutation: comment_mutation,
    target_state_name: target_state_name,
    state_mutation: state_mutation,
  )
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

pub fn check_linear_token_availability(
  token_getter: fn() -> Result(String, Nil),
) -> linear_mutation.LinearTokenStatus {
  linear_mutation.check_token_status(token_getter)
}

pub fn explain_unavailable_token() -> String {
  linear_mutation.build_error_context(
    "No Linear access token available",
  )
}

pub fn format_mutation_debug(
  mutation: linear_mutation.MutationRequest,
) -> String {
  linear_mutation.format_mutation_for_logging(mutation)
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

pub fn cli_plan_linear_state(
  stage: String,
  env_getter: fn(String) -> String,
) -> Result(String, String) {
  use validated_stage <- result.try(validate_checkpoint_stage(stage))
  plan_linear_state_update(validated_stage, env_getter)
}

pub fn cli_plan_linear_mutation(
  linear_issue_id: String,
  body: String,
  stage: String,
  task_slug: String,
) -> Result(linear_mutation.MutationRequest, String) {
  use validated_stage <- result.try(validate_checkpoint_stage(stage))
  Ok(plan_linear_comment_mutation(linear_issue_id, body, validated_stage, task_slug))
}

pub fn cli_plan_linear_comment_mutation(
  linear_issue_id: String,
  body: String,
  stage: String,
  task_slug: String,
) -> Result(linear_mutation.MutationRequest, String) {
  use validated_stage <- result.try(validate_checkpoint_stage(stage))
  Ok(plan_linear_comment_mutation(linear_issue_id, body, validated_stage, task_slug))
}

pub fn cli_plan_linear_state_mutation(
  linear_issue_id: String,
  state_id: String,
) -> Result(linear_mutation.MutationRequest, String) {
  Ok(plan_linear_state_mutation(linear_issue_id, state_id))
}


/// Format a LinearRefusalPlan for shell consumption (dry-run KEY=val + mutation dumps).
pub fn format_linear_refusal_plan(plan: LinearRefusalPlan) -> String {
  let comment_id_key = plan.comment_mutation.idempotency_key
  let state_block = case plan.state_mutation {
    None ->
      "STATE_MUTATION_PLANNED=0\n"
      <> "STATE_IDEMPOTENCY_KEY=\n"
    Some(req) ->
      "STATE_MUTATION_PLANNED=1\n"
      <> "STATE_IDEMPOTENCY_KEY="
      <> req.idempotency_key
      <> "\n"
      <> "---STATE_QUERY---\n"
      <> req.query
      <> "\n---STATE_VARIABLES---\n"
      <> req.variables_json
      <> "\n"
  }
  "TARGET_STATE="
  <> plan.target_state_name
  <> "\nCOMMENT_IDEMPOTENCY_KEY="
  <> comment_id_key
  <> "\n"
  <> state_block
  <> "---COMMENT_QUERY---\n"
  <> plan.comment_mutation.query
  <> "\n---COMMENT_VARIABLES---\n"
  <> plan.comment_mutation.variables_json
  <> "\n---BODY---\n"
  <> plan.body
}

pub fn cli_plan_linear_refusal(
  linear_issue_id: String,
  task_slug: String,
  reason_class: String,
  reasoning: String,
  state_id: String,
  env_getter: fn(String) -> String,
) -> String {
  let plan =
    plan_linear_refusal(
      linear_issue_id,
      task_slug,
      reason_class,
      reasoning,
      state_id,
      env_getter,
    )
  format_linear_refusal_plan(plan)
}

pub fn cli_format_mutation_debug(
  linear_issue_id: String,
  body: String,
  stage: String,
  task_slug: String,
) -> Result(String, String) {
  use validated_stage <- result.try(validate_checkpoint_stage(stage))
  let mutation = plan_linear_comment_mutation(linear_issue_id, body, validated_stage, task_slug)
  Ok(format_mutation_debug(mutation))
}

/// Thin CLI delegates for the 8 template renders (exact parity with old grkr-templates.sh).
/// Called by bin/grkr-templates.sh thin wrapper (t_23a1c5ae).

pub fn cli_render_research_checkpoint(
  issue: String,
  title: String,
  body: String,
  url: String,
  task_slug: String,
) -> String {
  templates.render_research_checkpoint(issue, title, body, url, task_slug)
}

pub fn cli_render_plan_checkpoint(
  issue: String,
  title: String,
  task_slug: String,
) -> String {
  templates.render_plan_checkpoint(issue, title, task_slug)
}

pub fn cli_render_decision_prompt(
  issue: String,
  title: String,
  url: String,
  body: String,
  task_slug: String,
  worktree_dir: String,
  grkr_root: String,
  max_file_lines: String,
) -> String {
  templates.render_decision_prompt(
    issue,
    title,
    url,
    body,
    task_slug,
    worktree_dir,
    grkr_root,
    max_file_lines,
  )
}

pub fn cli_render_issue_prompt(
  issue: String,
  title: String,
  url: String,
  body: String,
  task_slug: String,
  worktree_dir: String,
  grkr_root: String,
  max_file_lines: String,
) -> String {
  templates.render_issue_prompt(
    issue,
    title,
    url,
    body,
    task_slug,
    worktree_dir,
    grkr_root,
    max_file_lines,
  )
}

pub fn cli_render_line_limit_fix_prompt(
  issue: String,
  title: String,
  task_slug: String,
  violations: String,
  max_file_lines: String,
) -> String {
  templates.render_line_limit_fix_prompt(
    issue,
    title,
    task_slug,
    violations,
    max_file_lines,
  )
}

pub fn cli_render_default_pr_body(body: String, title: String) -> String {
  templates.render_default_pr_body(body, title)
}

pub fn cli_render_compact_pr_body(short_body: String, short_title: String) -> String {
  templates.render_compact_pr_body(short_body, short_title)
}

pub fn cli_render_issue_footer(issue: String) -> String {
  templates.render_issue_footer(issue)
}
