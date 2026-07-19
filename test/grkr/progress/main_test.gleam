import gleeunit
import gleam/option
import gleam/string
import gleeunit/should
import grkr/progress/checkpoint_stage
import grkr/progress/main as progress
import grkr/progress/linear_mutation

pub fn main() {
  gleeunit.main()
}

pub fn plan_checkpoint_render_test() {
  let result =
    progress.plan_checkpoint_render(
      "issue-123-test",
      checkpoint_stage.Research,
      "Research findings here",
    )

  string.contains(result, "Research checkpoint")
  |> should.be_true()

  string.contains(result, "Research findings here")
  |> should.be_true()

  string.contains(result, "grkr:checkpoint")
  |> should.be_true()
}

pub fn plan_checkpoint_render_with_pr_test() {
  let result =
    progress.plan_checkpoint_render_with_pr(
      "issue-456-impl",
      checkpoint_stage.Implementation,
      "Implementation complete",
      "https://github.com/test/repo/pull/123",
    )

  string.contains(result, "Implementation checkpoint")
  |> should.be_true()

  string.contains(result, "Implementation complete")
  |> should.be_true()

  string.contains(result, "### PR")
  |> should.be_true()

  string.contains(result, "https://github.com/test/repo/pull/123")
  |> should.be_true()
}

pub fn plan_refusal_render_test() {
  let result =
    progress.plan_refusal_render(
      "issue-789-refuse",
      "underspecified",
      "This issue needs more details",
    )

  string.contains(result, "Implementation refused")
  |> should.be_true()

  string.contains(result, "underspecified")
  |> should.be_true()

  string.contains(result, "This issue needs more details")
  |> should.be_true()
}

pub fn plan_pr_summary_render_test() {
  let result =
    progress.plan_pr_summary_render(
      "issue-999-summary",
      "https://github.com/test/repo/pull/456",
      "https://github.com/test/repo/tree/feature",
    )

  string.contains(result, "PR summary")
  |> should.be_true()

  string.contains(result, "https://github.com/test/repo/pull/456")
  |> should.be_true()
}

pub fn plan_linear_state_update_test() {
  let mock_env = fn(_key) { "Custom State" }
  let result = progress.plan_linear_state_update(checkpoint_stage.Research, mock_env)

  result
  |> should.equal(Ok("Custom State"))
}

pub fn validate_checkpoint_stage_test() {
  progress.validate_checkpoint_stage("research")
  |> should.equal(Ok(checkpoint_stage.Research))

  progress.validate_checkpoint_stage("invalid")
  |> should.be_error()
}

pub fn generate_idempotency_key_test() {
  let result =
    progress.generate_idempotency_key(checkpoint_stage.Plan, "issue-777-key")

  result
  |> should.equal("grkr-checkpoint-plan-issue-777-key")
}

pub fn format_checkpoint_marker_test() {
  let result =
    progress.format_checkpoint_marker(checkpoint_stage.Test, "issue-888-marker")

  string.contains(result, "grkr:checkpoint")
  |> should.be_true()

  string.contains(result, "stage=test")
  |> should.be_true()

  string.contains(result, "task=issue-888-marker")
  |> should.be_true()
}

pub fn check_linear_token_availability_test() {
  let mock_getter = fn() { Ok("test-token") }
  let result = progress.check_linear_token_availability(mock_getter)

  result
  |> should.equal(linear_mutation.TokenAvailable)
}

pub fn explain_unavailable_token_test() {
  let result = progress.explain_unavailable_token()

  string.contains(result, "OAuth")
  |> should.be_true()
}

pub fn cli_render_checkpoint_test() {
  let result = progress.cli_render_checkpoint("research", "issue-111-cli", "CLI test")

  result
  |> should.equal(Ok("<!-- grkr:checkpoint stage=research task=issue-111-cli version=1 -->\n\n## Research checkpoint\n\nCLI test"))
}

pub fn cli_render_checkpoint_with_pr_test() {
  let result =
    progress.cli_render_checkpoint_with_pr(
      "implementation",
      "issue-222-cli",
      "CLI impl",
      "https://github.com/test/repo/pull/222",
    )

  case result {
    Ok(content) -> {
  string.contains(content, "https://github.com/test/repo/pull/222")
  |> should.be_true()
    }
    Error(_) -> should.fail()
  }
}

pub fn cli_render_refusal_test() {
  let result = progress.cli_render_refusal("issue-333-cli", "blocked", "CLI refusal")

  string.contains(result, "blocked")
  |> should.be_true()
}

pub fn cli_render_pr_summary_test() {
  let result =
    progress.cli_render_pr_summary(
      "issue-444-cli",
      "https://github.com/test/repo/pull/444",
      "https://github.com/test/repo/tree/branch",
    )

  string.contains(result, "PR summary")
  |> should.be_true()
}

pub fn cli_plan_linear_state_test() {
  let mock_env = fn(_key) { "Test State" }
  let result = progress.cli_plan_linear_state("plan", mock_env)

  result
  |> should.equal(Ok("Test State"))
}

pub fn cli_plan_linear_mutation_test() {
  let result =
    progress.cli_plan_linear_mutation(
      "LIN-555",
      "Test body",
      "test",
      "issue-555-mutation",
    )

  case result {
    Ok(mutation) -> {
      string.contains(mutation.query, "commentCreate")
      |> should.be_true()
    }
    Error(_) -> should.fail()
  }
}

pub fn cli_plan_linear_comment_mutation_alias_test() {
  let result =
    progress.cli_plan_linear_comment_mutation(
      "LIN-556",
      "Alias body",
      "implementation",
      "issue-556-mutation",
    )

  case result {
    Ok(mutation) -> {
      string.contains(mutation.variables_json, "grkr:checkpoint")
      |> should.be_true()

      mutation.idempotency_key
      |> should.equal("grkr-checkpoint-implementation-issue-556-mutation")
    }
    Error(_) -> should.fail()
  }
}

pub fn cli_plan_linear_state_mutation_test() {
  let result = progress.cli_plan_linear_state_mutation("LIN-557", "state-123")

  case result {
    Ok(mutation) -> {
      string.contains(mutation.query, "issueUpdate")
      |> should.be_true()

      string.contains(mutation.variables_json, "state-123")
      |> should.be_true()
    }
    Error(_) -> should.fail()
  }
}

pub fn cli_format_mutation_debug_redacts_variables_test() {
  let result =
    progress.cli_format_mutation_debug(
      "LIN-558",
      "checkpoint body that should not be echoed",
      "plan",
      "issue-558-debug",
    )

  case result {
    Ok(debug) -> {
      string.contains(debug, "[redacted]")
      |> should.be_true()

      string.contains(debug, "checkpoint body that should not be echoed")
      |> should.be_false()
    }
    Error(_) -> should.fail()
  }
}

pub fn plan_linear_refusal_without_state_id_test() {
  let mock_env = fn(key) {
    case key {
      "LINEAR_STATE_BACKLOG" -> "Icebox"
      _ -> ""
    }
  }
  let plan =
    progress.plan_linear_refusal(
      "LIN-001",
      "eng-123",
      "underspecified",
      "Needs clearer AC",
      "",
      mock_env,
    )

  string.contains(plan.body, "underspecified")
  |> should.be_true()

  string.contains(plan.body, "grkr:checkpoint stage=refusal")
  |> should.be_true()

  plan.comment_mutation.idempotency_key
  |> should.equal("grkr-checkpoint-refusal-eng-123")

  string.contains(plan.comment_mutation.query, "commentCreate")
  |> should.be_true()

  plan.target_state_name
  |> should.equal("Icebox")

  plan.state_mutation
  |> should.equal(option.None)
}

pub fn plan_linear_refusal_with_state_id_test() {
  let mock_env = fn(_key) { "" }
  let plan =
    progress.plan_linear_refusal(
      "LIN-001",
      "eng-123",
      "too_large",
      "Split into smaller issues",
      "STATE-BACKLOG-1",
      mock_env,
    )

  plan.target_state_name
  |> should.equal("Backlog")

  case plan.state_mutation {
    option.Some(req) -> {
      string.contains(req.query, "issueUpdate")
      |> should.be_true()

      string.contains(req.variables_json, "STATE-BACKLOG-1")
      |> should.be_true()

      req.idempotency_key
      |> should.equal("grkr-state-refusal-LIN-001")
    }
    option.None -> should.fail()
  }
}

pub fn format_linear_refusal_plan_test() {
  let mock_env = fn(_key) { "" }
  let plan =
    progress.plan_linear_refusal(
      "LIN-9",
      "eng-9",
      "other",
      "reason",
      "sid-1",
      mock_env,
    )
  let formatted = progress.format_linear_refusal_plan(plan)

  string.contains(formatted, "TARGET_STATE=Backlog")
  |> should.be_true()

  string.contains(formatted, "COMMENT_IDEMPOTENCY_KEY=grkr-checkpoint-refusal-eng-9")
  |> should.be_true()

  string.contains(formatted, "STATE_MUTATION_PLANNED=1")
  |> should.be_true()

  string.contains(formatted, "---BODY---")
  |> should.be_true()

  string.contains(formatted, "commentCreate")
  |> should.be_true()
}

pub fn select_codex_pr_section_test() {
  // no heading -> empty (caller will default)
  progress.cli_select_codex_pr_section("some plain text\nno headings")
  |> should.equal("")

  // starts with heading -> all
  let starts = "## Detailed\nfoo\n\n## Plan\nbar"
  progress.cli_select_codex_pr_section(starts)
  |> should.equal(starts)

  // heading in middle -> from first ## onward
  let mid = "intro text\n\n## Detailed description of the task\ncontent here\n## more"
  let expected = "## Detailed description of the task\ncontent here\n## more"
  progress.cli_select_codex_pr_section(mid)
  |> should.equal(expected)

  // subheading ### not matched (only ^## )
  progress.cli_select_codex_pr_section("text\n### sub\n## Real")
  |> should.equal("## Real")
}

pub fn ensure_github_pr_body_test() {
  let body = "issue body text"
  let title = "Issue title"
  let issue = "42"
  let max = 10

  // oversized -> compact + footer (compact render is short)
  let long = "0123456789ABCDEF"  // >10
  let ensured = progress.cli_ensure_github_pr_body(long, body, title, issue, max)
  string.contains(ensured, "exceeded GitHub's PR body size limit")
  |> should.be_true()
  string.contains(ensured, "Fixes #42")
  |> should.be_true()
  // footer appears once
  string.contains(ensured, "Fixes #42\nFixes")
  |> should.be_false()

  // normal short, no fixes -> append footer once
  let short = "## Detailed\nok"
  let with_footer = progress.cli_ensure_github_pr_body(short, body, title, issue, 1000)
  string.contains(with_footer, "Fixes #42")
  |> should.be_true()
  string.ends_with(with_footer, "Fixes #42\n")
  |> should.be_true()

  // already contains Fixes -> no duplicate footer appended
  let has_fixes = "## Detailed\nFixes #42\nmore"
  let kept = progress.cli_ensure_github_pr_body(has_fixes, body, title, issue, 1000)
  string.contains(kept, "Fixes #42\nFixes")
  |> should.be_false()
  string.contains(kept, "more")
  |> should.be_true()
}

pub fn cli_render_github_completion_summary_test() {
  let result =
    progress.cli_render_github_completion_summary(
      "123",
      "Polish GitHub completion surface",
      "https://github.com/stepango/grkr/tree/issue-123",
      "https://github.com/stepango/grkr/pull/147",
    )

  let expected =
    "## Completion summary\n\nIssue #123: Polish GitHub completion surface\n\n- Recommendation: ready\n- Branch: https://github.com/stepango/grkr/tree/issue-123\n- PR: https://github.com/stepango/grkr/pull/147\n"

  result
  |> should.equal(expected)
}

pub fn cli_render_github_completion_summary_empty_urls_test() {
  let result =
    progress.cli_render_github_completion_summary("99", "Edge case", "", "")

  let expected =
    "## Completion summary\n\nIssue #99: Edge case\n\n- Recommendation: ready\n- Branch: \n- PR: \n"

  result
  |> should.equal(expected)
}
