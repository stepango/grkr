import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import grkr/progress/checkpoint_stage
import grkr/progress/checkpoint_render
import grkr/progress/checkpoint_id
import grkr/progress/linear_state
import grkr/progress/linear_mutation
import grkr/progress/templates
import grkr/issue_provider/client as issue_client
import grkr/issue_provider/types

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
    sid -> Some(plan_linear_state_mutation_scoped(linear_issue_id, sid, "refusal"))
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

pub fn cli_select_codex_pr_section(content: String) -> String {
  templates.select_codex_heading_section(content)
}

pub fn cli_ensure_github_pr_body(
  content: String,
  issue_body: String,
  title: String,
  issue: String,
  max_chars: Int,
) -> String {
  templates.ensure_github_pr_body(content, issue_body, title, issue, max_chars)
}

pub fn cli_render_github_completion_summary(
  issue: String,
  title: String,
  branch_url: String,
  pr_url: String,
) -> String {
  templates.render_github_completion_summary(issue, title, branch_url, pr_url)
}

/// Apply entry for CLI: reads dump from path, applies if gate allows, writes sidecar next to it.
/// Always returns Ok(marker line) for soft exit 0; caller prints it.
pub fn cli_apply_linear_mutation_from_path(
  dump_path: String,
  env_get: fn(String) -> String,
) -> Result(String, String) {
  case read_dump_file(dump_path) {
    Error(e) -> Error("cannot-read-dump:" <> e)
    Ok(content) -> apply_linear_mutation_dump(dump_path, content, env_get)
  }
}

/// Stdin variant (for piping dumps in tests or manual).
pub fn cli_apply_linear_mutation_from_stdin(
  _env_get: fn(String) -> String,
) -> Result(String, String) {
  // For stdin mode in this slice, we expect callers to use file path.
  // FFI stdin read can be added later; return guidance.
  Error("linear-apply-mutation stdin: provide explicit dump file path for now")
}

/// Core apply logic. Respects GRKR_LINEAR_MUTATE literal "1".
/// Writes sidecar <dump>.linear-apply-result.txt on attempt or skip-with-reason.
/// GRKR_LINEAR_APPLY_CMD (if set) short-circuits to the provided stub/cmd (hermetic tests);
/// mirrors bin/lib/linear_mutate.sh behavior. Stub controls output/sidecars.
fn apply_linear_mutation_dump(
  dump_path: String,
  content: String,
  env_get: fn(String) -> String,
) -> Result(String, String) {
  let apply_cmd = env_get("GRKR_LINEAR_APPLY_CMD")
  case string.trim(apply_cmd) {
    "" -> apply_with_gate(dump_path, content, env_get)
    cmd -> {
      case run_apply_override(cmd, dump_path) {
        Ok(out) -> {
          case out {
            "" -> Ok("LINEAR_MUTATE=dry-run key=" <> extract_key_or_unknown(content))
            m -> Ok(m)
          }
        }
        Error(_) -> Ok("LINEAR_MUTATE=dry-run key=" <> extract_key_or_unknown(content))
      }
    }
  }
}

fn apply_with_gate(
  dump_path: String,
  content: String,
  env_get: fn(String) -> String,
) -> Result(String, String) {
  let sidecar_path = dump_path <> ".linear-apply-result.txt"

  // 1. Gate
  case linear_mutation.should_apply_live(env_get) {
    False -> {
      let key = extract_key_or_unknown(content)
      let marker = "LINEAR_MUTATE=dry-run key=" <> key
      Ok(marker)
    }
    True -> {
      // 2. Check prior sidecar for idempotent skip
      case read_dump_file(sidecar_path) {
        Ok(prior) ->
          case linear_mutation.sidecar_indicates_already_done(prior) {
            True -> {
              let key = extract_key_or_unknown(content)
              let marker = "LINEAR_MUTATE=skipped-already key=" <> key
              Ok(marker)
            }
            False -> do_apply_or_skip(content, sidecar_path, env_get)
          }
        Error(_) -> do_apply_or_skip(content, sidecar_path, env_get)
      }
    }
  }
}

fn do_apply_or_skip(
  content: String,
  sidecar_path: String,
  _env_get: fn(String) -> String,
) -> Result(String, String) {
  // name-only check
  case linear_mutation.parse_mutation_dump(content) {
    Error(_name_only) -> {
      // name_only contains "name-only:..." or TARGET
      let target =
        content
        |> string.split("\n")
        |> list_first
        |> string.replace("TARGET_STATE=", "")
        |> string.trim
      let marker = "LINEAR_MUTATE=skipped-no-state-id target=" <> target
      let _ = write_sidecar(sidecar_path, linear_mutation.format_apply_sidecar("name-only", "skipped-no-state-id", "target=" <> target))
      Ok(marker)
    }
    Ok(#(query, vars_json, key)) -> {
      // 3. Token?  (soft skip: do not write sidecar so a later token run retries cleanly)
      case issue_client.resolve_access_token() {
        Error(_) -> {
          let marker = "LINEAR_MUTATE=skipped-no-token key=" <> key
          // Intentionally no sidecar write: skipped-no-token is soft/resume-safe.
          Ok(marker)
        }
        Ok(token) -> {
          // 4. Perform the POST via variables path
          case issue_client.run_graphql_with_variables(token, query, vars_json) {
            Ok(resp) -> {
              let res = linear_mutation.mutation_result_from_response(resp)
              let #(status, detail) = linear_mutation.classify_apply_outcome(res, True, False)
              let side = linear_mutation.format_apply_sidecar(key, status, detail)
              let _ = write_sidecar(sidecar_path, side)
              let marker = case status {
                "applied" -> "LINEAR_MUTATE=applied key=" <> key <> " " <> detail
                _ -> "LINEAR_MUTATE=" <> status <> " key=" <> key <> " " <> detail
              }
              Ok(marker)
            }
            Error(e) -> {
              let err_str = provider_error_message(e)
              let red = redact_apply_error(err_str)
              let side = linear_mutation.format_apply_sidecar(key, "failed", "error=" <> red)
              let _ = write_sidecar(sidecar_path, side)
              let marker = "LINEAR_MUTATE=failed key=" <> key <> " error=" <> red
              Ok(marker)
            }
          }
        }
      }
    }
  }
}

fn extract_key_or_unknown(content: String) -> String {
  let lines = string.split(string.trim(content), "\n")
  case lines {
    [_, _, k] -> k
    _ -> "unknown"
  }
}

fn list_first(l: List(String)) -> String {
  case l {
    [h, ..] -> h
    _ -> ""
  }
}

fn redact_apply_error(e: String) -> String {
  // Reuse client redact if possible, but simple here; token already redacted by client layer
  e
  |> string.replace("\n", " ")
  |> string.slice(0, 200)
}

fn provider_error_message(e: types.ProviderError) -> String {
  case e {
    types.QueryError(msg) -> msg
    types.ParseError(msg) -> msg
    types.ConfigError(_) -> "config error"
    types.NoMatchingIssue -> "no matching issue"
  }
}

// FFI declarations (implemented in cli_ffi.mjs)
@external(javascript, "../progress/cli_ffi.mjs", "readFileSync")
fn read_dump_file(path: String) -> Result(String, String)

@external(javascript, "../progress/cli_ffi.mjs", "writeFileSync")
fn write_sidecar(path: String, content: String) -> Result(String, String)

@external(javascript, "../progress/cli_ffi.mjs", "runApplyOverride")
fn run_apply_override(cmd: String, dump_path: String) -> Result(String, String)
