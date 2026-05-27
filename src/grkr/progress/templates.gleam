import grkr/progress/checkpoint_id
import grkr/progress/checkpoint_stage

/// Template renderers for the legacy grkr-templates.sh contract (GitHub-only v2).
/// All outputs must match the original shell heredocs byte-for-byte (after var expansion + marker).
/// See t_23a1c5ae, docs/plans/2026-05-26-grkr-templates-thinning.md, AGENTS.md

pub fn render_research_checkpoint(
  issue: String,
  title: String,
  body: String,
  url: String,
  task_slug: String,
) -> String {
  let marker =
    checkpoint_id.marker(checkpoint_stage.Research, task_slug)
    |> checkpoint_id.to_html_comment

  marker
  <> "\n\n## Research checkpoint\n\n### Problem statement\n\nIssue #"
  <> issue
  <> " requests the following work:\n\n"
  <> title
  <> "\n\nSource issue: "
  <> url
  <> "\n\n"
  <> body
  <> "\n\n### Current system behavior\n\n- `grkr --issue "
  <> issue
  <> "` runs a staged workflow with checkpoint files under `.grkr/tasks/"
  <> task_slug
  <> "/`, a dedicated issue worktree under `.grkr/worktrees/"
  <> task_slug
  <> "/`, a decision gate, implementation, and the configured verification commands.\n- The supervisor checkout stays separate from the issue worktree so repository mutations happen in isolated execution context.\n\n### Relevant files/modules\n\n- `bin/grkr`\n- `bin/grkr-issue-workflow.sh`\n- `bin/grkr-project-status.sh`\n- `README.md`\n- `test/`\n\n### Assumptions\n\n- The issue body is the primary product contract unless linked discussion adds stricter requirements.\n- The implementation should preserve the existing shell-script conventions in `bin/` and `test/`.\n- The final change must keep every touched file within the repository's 1000-line limit.\n\n### Unknowns\n\n- Whether the issue description contains enough detail for the decision gate to proceed without clarification.\n- Which exact files will change until repository inspection confirms the implementation surface area.\n- Whether unrelated repository health issues could block safe autonomous implementation.\n\n### Risks\n\n- Misreading the issue scope and changing a broader area than necessary.\n- Regressing the existing staged workflow, worktree isolation, or GitHub project transitions.\n- Passing local verification while still missing a workflow edge case or GitHub-side integration path.\n\n### Inferred acceptance criteria\n\n- Implement the requested behavior with a minimal, focused diff.\n- Keep the issue workflow resumable through the checkpoint and progress files.\n- Run the configured verification commands and record the results in `test.md` when implementation proceeds.\n- Preserve worktree isolation and the repository's file-size policy.\n"
}

pub fn render_plan_checkpoint(
  issue: String,
  title: String,
  task_slug: String,
) -> String {
  let marker =
    checkpoint_id.marker(checkpoint_stage.Plan, task_slug)
    |> checkpoint_id.to_html_comment

  marker
  <> "\n\n## Plan checkpoint\n\nIssue #"
  <> issue
  <> ": "
  <> title
  <> "\n\n### Implementation plan\n\n1. Inspect the issue requirements and the repository files most likely to be affected.\n2. Make the smallest focused change that satisfies the issue while preserving the existing shell-script conventions.\n3. Re-run the configured verification commands and capture the resulting test checkpoint if implementation proceeds.\n4. Publish only the relevant repository changes and keep project, checkpoint, and PR state in sync.\n\n### Files likely to change\n\n- `bin/`\n- `test/`\n- `README.md`\n\n### Migration or data concerns\n\n- Repository mutations should happen only inside the dedicated issue worktree, with runtime artifacts kept under `.grkr/`.\n- Any user-facing workflow change must be reflected in `README.md` before the issue is considered complete.\n\n### Test strategy\n\n- Run the smallest relevant shell tests for the affected workflow area first.\n- Run `npm test`.\n- Validate any GitHub project or issue-state assumptions against the configured live project when that can be done safely.\n\n### Rollback strategy\n\n- Revert only the focused repository changes made for this issue.\n- Keep the local task artifacts as execution history unless cleanup is explicitly needed.\n\n### Out-of-scope items\n\n- Unrelated refactors outside the issue scope.\n- Manual GitHub cleanup that is not required to complete the issue workflow.\n- Changes to runtime artifacts outside this issue's task directory unless required for resume safety.\n\n## Refusal assessment\n\n- Is the issue implementable now? Possibly, but the decision gate still needs to confirm that the scope is clear, bounded, and testable.\n- If not, why not? The workflow should refuse if the issue remains underspecified, too large, blocked by dependencies, or unsafe for autonomous execution.\n- Does the issue need clarification? Unknown until repository inspection confirms that the issue description is specific enough to implement.\n- Does it need breakdown into smaller tasks? Possibly, if the implementation spans multiple systems or lacks a bounded test strategy.\n- Are dependencies missing? Unknown until the affected code path and any upstream requirements are inspected.\n- Is required design or product input absent? Unknown until the implementation path is clear and any ambiguous behavior is identified.\n- Would implementation be too risky or too broad for an autonomous agent? Unknown until the decision gate evaluates repository health, scope, and safety.\n"
}

pub fn render_decision_prompt(
  issue: String,
  title: String,
  url: String,
  body: String,
  task_slug: String,
  worktree_dir: String,
  grkr_root: String,
  max_file_lines: String,
) -> String {
  "Decide whether the GitHub issue below should proceed to implementation now.\n\nReply with exactly one word on the first non-empty line: proceed or refuse.\n\nOnly reply with proceed when the issue is sufficiently specified, bounded, and ready for one autonomous implementation pass.\n\nIf you choose refuse:\n- Put one refusal class on the second non-empty line.\n- Put a short explanation after that.\n- Allowed refusal classes: underspecified, too_large, missing_dependency, needs_design_decision, unsafe_autonomous_change, repo_not_ready, other.\n\n**Issue #"
  <> issue
  <> ": "
  <> title
  <> "**\n**URL:** "
  <> url
  <> "\n\n**Description:**\n"
  <> body
  <> "\n\n**Checkpoint files:**\n- "
  <> grkr_root
  <> "/.grkr/tasks/"
  <> task_slug
  <> "/research.md\n- "
  <> grkr_root
  <> "/.grkr/tasks/"
  <> task_slug
  <> "/plan.md\n\n**Repository context:**\n- Issue worktree: "
  <> worktree_dir
  <> "\n- Repository root: "
  <> grkr_root
  <> "\n- Main repo policy: keep changed files at "
  <> max_file_lines
  <> " lines or fewer.\n\n"
}

pub fn render_issue_prompt(
  issue: String,
  title: String,
  url: String,
  body: String,
  task_slug: String,
  worktree_dir: String,
  grkr_root: String,
  max_file_lines: String,
) -> String {
  "Implement the GitHub issue described below using the Codex coding agent best practices.\n\n**Issue #"
  <> issue
  <> ": "
  <> title
  <> "**\n**URL:** "
  <> url
  <> "\n\n**Description:**\n"
  <> body
  <> "\n\n**Execution context:**\n- Issue worktree: "
  <> worktree_dir
  <> "\n- Repository root: "
  <> grkr_root
  <> "\n- Apply code changes in the issue worktree only.\n- The shell runner records your terminal output in "
  <> grkr_root
  <> "/.grkr/tasks/"
  <> task_slug
  <> "/implementation.log and may shard large transcripts into "
  <> grkr_root
  <> "/.grkr/tasks/"
  <> task_slug
  <> "/codex/implementation.log.parts/.\n\n**Checkpoint files:**\n- "
  <> grkr_root
  <> "/.grkr/tasks/"
  <> task_slug
  <> "/research.md\n- "
  <> grkr_root
  <> "/.grkr/tasks/"
  <> task_slug
  <> "/plan.md\n\n**Repository constraints:**\n- No file may exceed "
  <> max_file_lines
  <> " lines.\n- If a file is approaching the limit, proactively split helpers or extract modules before finishing.\n\n**Expected final response:**\n## Detailed description of the task\n## Implementation plan details\n## Testing results\n- Functional testing performed\n\nIf you discover an issue-quality blocker during implementation that requires refusal instead of completion, end your final response with exactly this block:\n\ngrkr-refuse-implementation\n<one allowed refusal class>\n<short explanation>\n\nAllowed refusal classes: underspecified, too_large, missing_dependency, needs_design_decision, unsafe_autonomous_change, repo_not_ready, other.\n\n---\n\n**Instructions for you:**\n1. First explore the codebase using available tools (grep, glob, read, etc.) to understand the current structure and conventions.\n2. Follow the project's code style, naming conventions, and architecture.\n3. Make minimal, focused changes.\n4. Do not add comments unless specifically asked.\n5. Follow the plan from the checkpoint files and minimize unrelated edits.\n6. Run the configured build and test commands as part of the implementation work.\n7. Stage only the files relevant to the issue.\n8. Keep every changed file within the repository's per-file line limit.\n9. After changes, run linting and tests if available (use the bash tool).\n10. Be concise in your responses.\n11. When done, the changes should fully address the issue.\n\nBegin by analyzing the project.\n"
}

pub fn render_line_limit_fix_prompt(
  issue: String,
  title: String,
  task_slug: String,
  violations: String,
  max_file_lines: String,
) -> String {
  "The current implementation for issue #"
  <> issue
  <> " still violates the repository file-size policy and must be refactored before publish.\n\n**Issue #"
  <> issue
  <> ": "
  <> title
  <> "**\n\n**Task context:**\n- .grkr/tasks/"
  <> task_slug
  <> "/research.md\n- .grkr/tasks/"
  <> task_slug
  <> "/plan.md\n\n**Staged file line-limit violations:**\n"
  <> violations
  <> "\n\n**Required outcome:**\n1. Refactor the implementation so every changed file is "
  <> max_file_lines
  <> " lines or fewer.\n2. Preserve the intended behavior of the issue implementation.\n3. Prefer extracting focused helpers or support files over cramming more logic into an oversized file.\n4. Keep the diff minimal and rerunnable by the existing shell tests.\n\nReturn a concise summary of the refactor and any tests you ran.\n"
}

pub fn render_default_pr_body(body: String, title: String) -> String {
  "## Detailed description of the task\n\n"
  <> title
  <> "\n\n"
  <> body
  <> "\n\n## Implementation plan details\n\n- Review the issue and repository context.\n- Make the smallest focused change needed.\n- Verify the change with the available automated tests.\n\n## Testing results\n\n- Functional testing performed: the launcher completed the issue workflow and created this PR.\n"
}

pub fn render_compact_pr_body(short_body: String, short_title: String) -> String {
  "## Detailed description of the task\n\n"
  <> short_title
  <> "\n\n"
  <> short_body
  <> "\n\n## Implementation plan details\n\n- The full Codex-generated summary exceeded GitHub's PR body size limit and was replaced with this compact summary.\n- See the issue discussion, commit history, and local grkr logs for the complete implementation details.\n\n## Testing results\n\n- Review the local grkr logs for the full Codex test output when needed.\n"
}

pub fn render_issue_footer(issue: String) -> String {
  "\nFixes #"
  <> issue
  <> "\n"
}
