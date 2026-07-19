import gleam/int
import gleam/io
import gleam/result
import gleam/string
import grkr/progress/main
import grkr/progress/linear_mutation

pub fn main() -> Nil {
  case argv() {
    ["marker", stage, task_slug] -> emit_marker(stage, task_slug)
    ["render-checkpoint", stage, task_slug, body] ->
      emit_result(main.cli_render_checkpoint(stage, task_slug, body))
    ["render-checkpoint-with-pr", stage, task_slug, body, pr_url] ->
      emit_result(main.cli_render_checkpoint_with_pr(stage, task_slug, body, pr_url))
    ["render-refusal", task_slug, reason_class, reasoning] ->
      io.print(main.cli_render_refusal(task_slug, reason_class, reasoning))
    ["render-pr-summary", task_slug, pr_url, branch_url] ->
      io.print(main.cli_render_pr_summary(task_slug, pr_url, branch_url))
    ["render-research-checkpoint", issue, title, body, url, slug] ->
      io.print(main.cli_render_research_checkpoint(issue, title, body, url, slug))
    ["render-plan-checkpoint", issue, title, slug] ->
      io.print(main.cli_render_plan_checkpoint(issue, title, slug))
    ["render-decision-prompt", issue, title, url, body, slug, worktree, root, max] ->
      io.print(main.cli_render_decision_prompt(issue, title, url, body, slug, worktree, root, max))
    ["render-issue-prompt", issue, title, url, body, slug, worktree, root, max] ->
      io.print(main.cli_render_issue_prompt(issue, title, url, body, slug, worktree, root, max))
    ["render-line-limit-fix-prompt", issue, title, slug, violations, max] ->
      io.print(main.cli_render_line_limit_fix_prompt(issue, title, slug, violations, max))
    ["render-default-pr-body", body, title] ->
      io.print(main.cli_render_default_pr_body(body, title))
    ["render-compact-pr-body", short_body, short_title] ->
      io.print(main.cli_render_compact_pr_body(short_body, short_title))
    ["render-issue-footer", issue] ->
      io.print(main.cli_render_issue_footer(issue))
    ["select-codex-pr-section", path] ->
      emit_result(read_file(path) |> result.map(main.cli_select_codex_pr_section))
    ["ensure-github-pr-body", pr_body_path, body, title, issue, max_str] -> {
      let max = case int.parse(max_str) {
        Ok(n) -> n
        Error(_) -> 60000
      }
      case read_file(pr_body_path) {
        Ok(curr) ->
          io.print(main.cli_ensure_github_pr_body(curr, body, title, issue, max))
        Error(msg) -> {
          io.println("progress cli error: " <> msg)
          exit(1)
        }
      }
    }
    ["render-github-completion-summary", issue, title, branch_url, pr_url] ->
      io.print(main.cli_render_github_completion_summary(issue, title, branch_url, pr_url))
    ["linear-state", stage] -> emit_linear_state(stage)
    ["linear-comment-mutation", issue_id, body, stage, task_slug] ->
      emit_mutation(main.cli_plan_linear_comment_mutation(issue_id, body, stage, task_slug))
    ["linear-state-mutation", issue_id, state_id] ->
      // Legacy 2-arg CLI routes via scoped "update" (no unscoped key emitted).
      emit_mutation(main.cli_plan_linear_state_mutation_scoped(issue_id, state_id, "update"))
    ["linear-state-mutation", issue_id, state_id, stage] ->
      emit_mutation(main.cli_plan_linear_state_mutation_scoped(issue_id, state_id, stage))
    ["plan-linear-refusal", issue_id, task_slug, reason_class, reasoning] ->
      io.print(
        main.cli_plan_linear_refusal(
          issue_id,
          task_slug,
          reason_class,
          reasoning,
          "",
          env_get,
        ),
      )
    ["plan-linear-refusal", issue_id, task_slug, reason_class, reasoning, state_id] ->
      io.print(
        main.cli_plan_linear_refusal(
          issue_id,
          task_slug,
          reason_class,
          reasoning,
          state_id,
          env_get,
        ),
      )
    ["check-token"] -> emit_token_status()
    ["mutation-debug", issue_id, body, stage, task_slug] ->
      emit_debug(main.cli_format_mutation_debug(issue_id, body, stage, task_slug))
    ["linear-apply-mutation", path] ->
      emit_apply_result(path, main.cli_apply_linear_mutation_from_path(path, env_get))
    ["linear-apply-mutation"] ->
      // stdin mode: read all from stdin; treat as non-refuse for STRICT decision
      emit_apply_result("-", main.cli_apply_linear_mutation_from_stdin(env_get))
    _ -> {
      io.println("Usage: gleam run -m grkr/progress/cli -- <command> [args...]")
      io.println("")
      io.println("Checkpoint commands:")
      io.println("  marker <stage> <task-slug>                                    Generate checkpoint marker")
      io.println("  render-checkpoint <stage> <task-slug> <body>                  Render checkpoint")
      io.println("  render-checkpoint-with-pr <stage> <task-slug> <body> <pr-url> Render checkpoint with PR")
      io.println("  render-refusal <task-slug> <reason-class> <reasoning>         Render refusal checkpoint")
      io.println("  render-pr-summary <task-slug> <pr-url> <branch-url>           Render PR summary")
      io.println("")
      io.println("GitHub PR body helpers (internal; path-based for large bodies):")
      io.println("  select-codex-pr-section <codex-log-file>                      Extract ## section (first heading to end)")
      io.println("  ensure-github-pr-body <pr-body-file> <body> <title> <issue> <max>  Size limit + exactly one Fixes #N")
      io.println("  render-github-completion-summary <issue> <title> <branch-url> <pr-url>  Completion summary body")
      io.println("")
      io.println("Linear integration commands:")
      io.println("  linear-state <stage>                                          Show Linear state for stage")
      io.println("  linear-comment-mutation <issue-id> <body> <stage> <task-slug> Show Linear comment mutation")
      io.println("  linear-state-mutation <issue-id> <state-id>                   Show Linear state mutation")
      io.println("  plan-linear-refusal <issue-id> <task-slug> <class> <reason> [state-id]")
      io.println("                                                                Plan refuse comment+Backlog mutations (dry-run)")
      io.println("  check-token                                                   Check Linear token availability")
      io.println("  mutation-debug <issue-id> <body> <stage> <task-slug>          Show mutation debug info")
      io.println("  linear-apply-mutation <dump-file>                             Apply planned mutation (guarded by GRKR_LINEAR_MUTATE=1)")
      io.println("  linear-apply-mutation                                         Same, reading dump from stdin")
      exit(2)
    }
  }
}

fn emit_marker(stage: String, task_slug: String) -> Nil {
  case main.validate_checkpoint_stage(stage) {
    Ok(validated_stage) -> io.print(main.format_checkpoint_marker(validated_stage, task_slug))
    Error(message) -> {
      io.println("progress cli error: " <> message)
      exit(1)
    }
  }
}

fn emit_result(result: Result(String, String)) -> Nil {
  case result {
    Ok(value) -> io.print(value)
    Error(message) -> {
      io.println("progress cli error: " <> message)
      exit(1)
    }
  }
}

fn emit_linear_state(stage: String) -> Nil {
  emit_result(main.cli_plan_linear_state(stage, env_get))
}

fn emit_mutation(result: Result(linear_mutation.MutationRequest, String)) -> Nil {
  case result {
    Ok(request) -> {
      io.println(request.query)
      io.println(request.variables_json)
      io.println(request.idempotency_key)
    }
    Error(message) -> {
      io.println("progress cli error: " <> message)
      exit(1)
    }
  }
}

fn emit_token_status() -> Nil {
  let status = main.check_linear_token_availability(fn() {
    case env_get("GRKR_LINEAR_ACCESS_TOKEN") {
      "" -> Error(Nil)
      token -> Ok(token)
    }
  })
  case status {
    linear_mutation.TokenAvailable -> io.println("Token available")
    linear_mutation.TokenUnavailable -> io.println("Token unavailable")
    linear_mutation.TokenInvalid -> io.println("Token invalid")
  }
}

fn emit_debug(result: Result(String, String)) -> Nil {
  emit_result(result)
}

fn emit_apply_result(dump_path: String, result: Result(String, String)) -> Nil {
  let line = case result {
    Ok(l) -> l
    Error(message) -> "LINEAR_MUTATE=failed error=" <> message
  }
  io.println(line)

  // STRICT=1 (literal) makes non-refuse failed applies exit non-zero.
  // Refuse dumps (basename refusal.*) stay soft even under STRICT.
  // All other outcomes (dry, skipped-*, applied) stay soft.
  let strict = linear_mutation.should_strict_hard_fail(env_get)
  let is_refuse = linear_mutation.dump_is_refuse_path(dump_path)
  let is_failed = string.contains(line, "LINEAR_MUTATE=failed")
  case strict && !is_refuse && is_failed {
    True -> exit(1)
    False -> Nil
  }
}

@external(javascript, "../progress/cli_ffi.mjs", "readFileSync")
fn read_file(path: String) -> Result(String, String)

@external(javascript, "../progress/cli_ffi.mjs", "argv")
fn argv() -> List(String)

@external(javascript, "../progress/cli_ffi.mjs", "env_get")
fn env_get(key: String) -> String

@external(javascript, "process", "exit")
fn exit(code: Int) -> Nil
