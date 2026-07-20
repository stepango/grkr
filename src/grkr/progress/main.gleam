//// main.gleam
//// Thin public facade (t_8c7cd0a0). Delegates to checkpoint_plan/linear_plan/templates_cli/linear_apply.
//// Preserves 100% prior public API surface as main.<name> via 1-line bodies. Zero behavior change.

import grkr/progress/checkpoint_plan
import grkr/progress/checkpoint_stage
import grkr/progress/linear_apply
import grkr/progress/linear_mutation
import grkr/progress/linear_plan
import grkr/progress/templates_cli

pub type ProgressUpdate = checkpoint_plan.ProgressUpdate
pub type LinearRefusalPlan = linear_plan.LinearRefusalPlan

// Cluster A
pub fn plan_checkpoint_render(task_slug: String, stage: checkpoint_stage.CheckpointStage, body: String) -> String { checkpoint_plan.plan_checkpoint_render(task_slug, stage, body) }
pub fn plan_checkpoint_render_with_pr(task_slug: String, stage: checkpoint_stage.CheckpointStage, body: String, pr_url: String) -> String { checkpoint_plan.plan_checkpoint_render_with_pr(task_slug, stage, body, pr_url) }
pub fn plan_refusal_render(task_slug: String, reason_class: String, reasoning: String) -> String { checkpoint_plan.plan_refusal_render(task_slug, reason_class, reasoning) }
pub fn plan_pr_summary_render(task_slug: String, pr_url: String, branch_url: String) -> String { checkpoint_plan.plan_pr_summary_render(task_slug, pr_url, branch_url) }
pub fn validate_checkpoint_stage(stage_str: String) -> Result(checkpoint_stage.CheckpointStage, String) { checkpoint_plan.validate_checkpoint_stage(stage_str) }
pub fn extract_stage_from_existing_comment(comment: String) -> Result(checkpoint_stage.CheckpointStage, String) { checkpoint_plan.extract_stage_from_existing_comment(comment) }
pub fn has_checkpoint_marker(comment: String, stage_str: String, task_slug: String) -> Result(Bool, String) { checkpoint_plan.has_checkpoint_marker(comment, stage_str, task_slug) }
pub fn generate_idempotency_key(stage: checkpoint_stage.CheckpointStage, task_slug: String) -> String { checkpoint_plan.generate_idempotency_key(stage, task_slug) }
pub fn format_checkpoint_marker(stage: checkpoint_stage.CheckpointStage, task_slug: String) -> String { checkpoint_plan.format_checkpoint_marker(stage, task_slug) }
pub fn cli_render_checkpoint(stage: String, task_slug: String, body: String) -> Result(String, String) { checkpoint_plan.cli_render_checkpoint(stage, task_slug, body) }
pub fn cli_render_checkpoint_with_pr(stage: String, task_slug: String, body: String, pr_url: String) -> Result(String, String) { checkpoint_plan.cli_render_checkpoint_with_pr(stage, task_slug, body, pr_url) }
pub fn cli_render_refusal(task_slug: String, reason_class: String, reasoning: String) -> String { checkpoint_plan.cli_render_refusal(task_slug, reason_class, reasoning) }
pub fn cli_render_pr_summary(task_slug: String, pr_url: String, branch_url: String) -> String { checkpoint_plan.cli_render_pr_summary(task_slug, pr_url, branch_url) }

// Cluster B
pub fn plan_linear_state_update(stage: checkpoint_stage.CheckpointStage, env_getter: fn(String) -> String) -> Result(String, String) { linear_plan.plan_linear_state_update(stage, env_getter) }
pub fn plan_linear_comment_mutation(linear_issue_id: String, body: String, stage: checkpoint_stage.CheckpointStage, task_slug: String) -> linear_mutation.MutationRequest { linear_plan.plan_linear_comment_mutation(linear_issue_id, body, stage, task_slug) }
pub fn plan_linear_state_mutation(linear_issue_id: String, state_id: String) -> linear_mutation.MutationRequest { linear_plan.plan_linear_state_mutation(linear_issue_id, state_id) }
pub fn plan_linear_state_mutation_scoped(linear_issue_id: String, state_id: String, stage: String) -> linear_mutation.MutationRequest { linear_plan.plan_linear_state_mutation_scoped(linear_issue_id, state_id, stage) }
pub fn plan_linear_refusal(linear_issue_id: String, task_slug: String, reason_class: String, reasoning: String, state_id: String, env_getter: fn(String) -> String) -> LinearRefusalPlan { linear_plan.plan_linear_refusal(linear_issue_id, task_slug, reason_class, reasoning, state_id, env_getter) }
pub fn format_linear_refusal_plan(plan: LinearRefusalPlan) -> String { linear_plan.format_linear_refusal_plan(plan) }
pub fn check_linear_token_availability(token_getter: fn() -> Result(String, Nil)) -> linear_mutation.LinearTokenStatus { linear_plan.check_linear_token_availability(token_getter) }
pub fn explain_unavailable_token() -> String { linear_plan.explain_unavailable_token() }
pub fn format_mutation_debug(mutation: linear_mutation.MutationRequest) -> String { linear_plan.format_mutation_debug(mutation) }
pub fn cli_plan_linear_state(stage: String, env_getter: fn(String) -> String) -> Result(String, String) { linear_plan.cli_plan_linear_state(stage, env_getter) }
pub fn cli_plan_linear_mutation(linear_issue_id: String, body: String, stage: String, task_slug: String) -> Result(linear_mutation.MutationRequest, String) { linear_plan.cli_plan_linear_mutation(linear_issue_id, body, stage, task_slug) }
pub fn cli_plan_linear_comment_mutation(linear_issue_id: String, body: String, stage: String, task_slug: String) -> Result(linear_mutation.MutationRequest, String) { linear_plan.cli_plan_linear_comment_mutation(linear_issue_id, body, stage, task_slug) }
pub fn cli_plan_linear_state_mutation(linear_issue_id: String, state_id: String) -> Result(linear_mutation.MutationRequest, String) { linear_plan.cli_plan_linear_state_mutation(linear_issue_id, state_id) }
pub fn cli_plan_linear_state_mutation_scoped(linear_issue_id: String, state_id: String, stage: String) -> Result(linear_mutation.MutationRequest, String) { linear_plan.cli_plan_linear_state_mutation_scoped(linear_issue_id, state_id, stage) }
pub fn cli_plan_linear_refusal(linear_issue_id: String, task_slug: String, reason_class: String, reasoning: String, state_id: String, env_getter: fn(String) -> String) -> String { linear_plan.cli_plan_linear_refusal(linear_issue_id, task_slug, reason_class, reasoning, state_id, env_getter) }
pub fn cli_format_mutation_debug(linear_issue_id: String, body: String, stage: String, task_slug: String) -> Result(String, String) { linear_plan.cli_format_mutation_debug(linear_issue_id, body, stage, task_slug) }

// Cluster C
pub fn cli_render_research_checkpoint(issue: String, title: String, body: String, url: String, task_slug: String) -> String { templates_cli.cli_render_research_checkpoint(issue, title, body, url, task_slug) }
pub fn cli_render_plan_checkpoint(issue: String, title: String, task_slug: String) -> String { templates_cli.cli_render_plan_checkpoint(issue, title, task_slug) }
pub fn cli_render_decision_prompt(issue: String, title: String, url: String, body: String, task_slug: String, worktree_dir: String, grkr_root: String, max_file_lines: String) -> String { templates_cli.cli_render_decision_prompt(issue, title, url, body, task_slug, worktree_dir, grkr_root, max_file_lines) }
pub fn cli_render_issue_prompt(issue: String, title: String, url: String, body: String, task_slug: String, worktree_dir: String, grkr_root: String, max_file_lines: String) -> String { templates_cli.cli_render_issue_prompt(issue, title, url, body, task_slug, worktree_dir, grkr_root, max_file_lines) }
pub fn cli_render_line_limit_fix_prompt(issue: String, title: String, task_slug: String, violations: String, max_file_lines: String) -> String { templates_cli.cli_render_line_limit_fix_prompt(issue, title, task_slug, violations, max_file_lines) }
pub fn cli_render_default_pr_body(body: String, title: String) -> String { templates_cli.cli_render_default_pr_body(body, title) }
pub fn cli_render_compact_pr_body(short_body: String, short_title: String) -> String { templates_cli.cli_render_compact_pr_body(short_body, short_title) }
pub fn cli_render_issue_footer(issue: String) -> String { templates_cli.cli_render_issue_footer(issue) }
pub fn cli_select_codex_pr_section(content: String) -> String { templates_cli.cli_select_codex_pr_section(content) }
pub fn cli_ensure_github_pr_body(content: String, issue_body: String, title: String, issue: String, max_chars: Int) -> String { templates_cli.cli_ensure_github_pr_body(content, issue_body, title, issue, max_chars) }
pub fn cli_render_github_completion_summary(issue: String, title: String, branch_url: String, pr_url: String) -> String { templates_cli.cli_render_github_completion_summary(issue, title, branch_url, pr_url) }

// Cluster D
pub fn cli_apply_linear_mutation_from_path(dump_path: String, env_get: fn(String) -> String) -> Result(String, String) { linear_apply.cli_apply_linear_mutation_from_path(dump_path, env_get) }
pub fn cli_apply_linear_mutation_from_stdin(env_get: fn(String) -> String) -> Result(String, String) { linear_apply.cli_apply_linear_mutation_from_stdin(env_get) }
