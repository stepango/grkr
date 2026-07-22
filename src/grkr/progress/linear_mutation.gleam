//// linear_mutation.gleam
//// Thin public facade (LOC hygiene split, t_d0a2d481).
//// Stable module: grkr/progress/linear_mutation
//// Delegates to linear_mutation_{types,build,parse,policy}. Zero intentional behavior change.
//// Type aliases keep annotations as linear_mutation.X; constructors live on linear_mutation_types
//// (import that module for TokenAvailable / MutationSuccess / etc. pattern matches).

import grkr/progress/checkpoint_stage
import grkr/progress/linear_mutation_build as build
import grkr/progress/linear_mutation_parse as parse
import grkr/progress/linear_mutation_policy as policy
import grkr/progress/linear_mutation_types as types

pub type LinearIssueId = types.LinearIssueId
pub type LinearTokenStatus = types.LinearTokenStatus
pub type MutationRequest = types.MutationRequest
pub type MutationResult = types.MutationResult

// --- build ---
pub fn create_comment_mutation(issue_id: LinearIssueId, body: String, stage: checkpoint_stage.CheckpointStage, task_slug: String) -> MutationRequest { build.create_comment_mutation(issue_id, body, stage, task_slug) }
pub fn update_state_mutation_scoped(issue_id: LinearIssueId, state_id: String, stage: String) -> MutationRequest { build.update_state_mutation_scoped(issue_id, state_id, stage) }
pub fn update_state_mutation(issue_id: LinearIssueId, state_id: String) -> MutationRequest { build.update_state_mutation(issue_id, state_id) }
pub fn create_comment_with_pr_link(issue_id: LinearIssueId, body: String, pr_url: String, stage: checkpoint_stage.CheckpointStage, task_slug: String) -> MutationRequest { build.create_comment_with_pr_link(issue_id, body, pr_url, stage, task_slug) }
pub fn format_mutation_for_logging(request: MutationRequest) -> String { build.format_mutation_for_logging(request) }
pub fn to_linear_issue_id(issue_id: String) -> LinearIssueId { build.to_linear_issue_id(issue_id) }
pub fn extract_idempotency_key(request: MutationRequest) -> String { build.extract_idempotency_key(request) }

// --- parse ---
pub fn mutation_result_from_response(response: String) -> MutationResult { parse.mutation_result_from_response(response) }
pub fn parse_three_line_dump(content: String) -> Result(#(String, String, String), String) { parse.parse_three_line_dump(content) }
pub fn parse_mutation_dump(content: String) -> Result(#(String, String, String), String) { parse.parse_mutation_dump(content) }

// --- policy ---
pub fn check_token_status(token_getter: fn() -> Result(String, Nil)) -> LinearTokenStatus { policy.check_token_status(token_getter) }
pub fn safe_unavailable_token_result(token_status: LinearTokenStatus) -> MutationResult { policy.safe_unavailable_token_result(token_status) }
pub fn build_error_context(error: String) -> String { policy.build_error_context(error) }
pub fn is_idempotent_error(error: String) -> Bool { policy.is_idempotent_error(error) }
pub fn should_retry_mutation(result: MutationResult) -> Bool { policy.should_retry_mutation(result) }
pub fn should_apply_live(env_get: fn(String) -> String) -> Bool { policy.should_apply_live(env_get) }
pub fn should_strict_hard_fail(env_get: fn(String) -> String) -> Bool { policy.should_strict_hard_fail(env_get) }
pub fn dump_is_refuse_path(path: String) -> Bool { policy.dump_is_refuse_path(path) }
pub fn format_apply_sidecar(key: String, status: String, detail: String) -> String { policy.format_apply_sidecar(key, status, detail) }
pub fn classify_apply_outcome(result: MutationResult, had_token: Bool, already_sidecar: Bool) -> #(String, String) { policy.classify_apply_outcome(result, had_token, already_sidecar) }
pub fn sidecar_indicates_already_done(prior: String) -> Bool { policy.sidecar_indicates_already_done(prior) }
