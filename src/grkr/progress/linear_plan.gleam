//// linear_plan.gleam
//// Cluster B extracted from progress/main.gleam for LOC hygiene (t_8c7cd0a0).
//// Linear planning surface (state/comment mutations, refusal plan, token checks, debug).
/// LinearRefusalPlan + all plan_linear_* + cli_plan_linear_* + format + check + explain.
/// Delegates to linear_state, linear_mutation, checkpoint_stage.
/// Public surface preserved via thin facade in main.gleam. Zero behavior change.

import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import grkr/progress/checkpoint_plan
import grkr/progress/checkpoint_stage
import grkr/progress/linear_mutation
import grkr/progress/linear_state

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
  // Legacy 2-arg plan routes to scoped "update" stage for key (kept for CLI compat).
  // All production stage paths use plan_linear_state_mutation_scoped with explicit stage.
  let issue_id = linear_mutation.to_linear_issue_id(linear_issue_id)
  linear_mutation.update_state_mutation_scoped(issue_id, state_id, "update")
}

pub fn plan_linear_state_mutation_scoped(
  linear_issue_id: String,
  state_id: String,
  stage: String,
) -> linear_mutation.MutationRequest {
  let issue_id = linear_mutation.to_linear_issue_id(linear_issue_id)
  linear_mutation.update_state_mutation_scoped(issue_id, state_id, stage)
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
  let body = checkpoint_plan.plan_refusal_render(task_slug, reason_class, reasoning)
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
    sid -> Some(plan_linear_state_mutation_scoped(linear_issue_id, sid, "refusal"))
  }
  LinearRefusalPlan(
    body: body,
    comment_mutation: comment_mutation,
    target_state_name: target_state_name,
    state_mutation: state_mutation,
  )
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

pub fn cli_plan_linear_state(
  stage: String,
  env_getter: fn(String) -> String,
) -> Result(String, String) {
  use validated_stage <- result.try(checkpoint_plan.validate_checkpoint_stage(stage))
  plan_linear_state_update(validated_stage, env_getter)
}

pub fn cli_plan_linear_mutation(
  linear_issue_id: String,
  body: String,
  stage: String,
  task_slug: String,
) -> Result(linear_mutation.MutationRequest, String) {
  use validated_stage <- result.try(checkpoint_plan.validate_checkpoint_stage(stage))
  Ok(plan_linear_comment_mutation(linear_issue_id, body, validated_stage, task_slug))
}

pub fn cli_plan_linear_comment_mutation(
  linear_issue_id: String,
  body: String,
  stage: String,
  task_slug: String,
) -> Result(linear_mutation.MutationRequest, String) {
  use validated_stage <- result.try(checkpoint_plan.validate_checkpoint_stage(stage))
  Ok(plan_linear_comment_mutation(linear_issue_id, body, validated_stage, task_slug))
}

pub fn cli_plan_linear_state_mutation(
  linear_issue_id: String,
  state_id: String,
) -> Result(linear_mutation.MutationRequest, String) {
  // 2-arg CLI helper delegates to scoped update stage (stage-scoped keys only).
  Ok(plan_linear_state_mutation_scoped(linear_issue_id, state_id, "update"))
}

pub fn cli_plan_linear_state_mutation_scoped(
  linear_issue_id: String,
  state_id: String,
  stage: String,
) -> Result(linear_mutation.MutationRequest, String) {
  Ok(plan_linear_state_mutation_scoped(linear_issue_id, state_id, stage))
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
  use validated_stage <- result.try(checkpoint_plan.validate_checkpoint_stage(stage))
  let mutation = plan_linear_comment_mutation(linear_issue_id, body, validated_stage, task_slug)
  Ok(format_mutation_debug(mutation))
}
