write_research_checkpoint_file() {
  local file=$1
  local issue=$2
  local title=$3
  local body=$4
  local url=$5
  local task_slug=$6

  cat > "$file" <<EOF
$(checkpoint_marker research "$task_slug")

## Research checkpoint

### Problem statement

Issue #$issue requests the following work:

$title

Source issue: $url

$body

### Current system behavior

- \`grkr --issue $issue\` runs a staged workflow with checkpoint files under \`.grkr/tasks/$task_slug/\`, a dedicated issue worktree under \`.grkr/worktrees/$task_slug/\`, a decision gate, implementation, and the configured verification commands.
- The supervisor checkout stays separate from the issue worktree so repository mutations happen in isolated execution context.

### Relevant files/modules

- \`bin/grkr\`
- \`bin/grkr-issue-workflow.sh\`
- \`bin/grkr-project-status.sh\`
- \`README.md\`
- \`test/\`

### Assumptions

- The issue body is the primary product contract unless linked discussion adds stricter requirements.
- The implementation should preserve the existing shell-script conventions in \`bin/\` and \`test/\`.
- The final change must keep every touched file within the repository's 1000-line limit.

### Unknowns

- Whether the issue description contains enough detail for the decision gate to proceed without clarification.
- Which exact files will change until repository inspection confirms the implementation surface area.
- Whether unrelated repository health issues could block safe autonomous implementation.

### Risks

- Misreading the issue scope and changing a broader area than necessary.
- Regressing the existing staged workflow, worktree isolation, or GitHub project transitions.
- Passing local verification while still missing a workflow edge case or GitHub-side integration path.

### Inferred acceptance criteria

- Implement the requested behavior with a minimal, focused diff.
- Keep the issue workflow resumable through the checkpoint and progress files.
- Run the configured verification commands and record the results in \`test.md\` when implementation proceeds.
- Preserve worktree isolation and the repository's file-size policy.
EOF
}

write_plan_checkpoint_file() {
  local file=$1
  local issue=$2
  local title=$3
  local task_slug=$4

  cat > "$file" <<EOF
$(checkpoint_marker plan "$task_slug")

## Plan checkpoint

Issue #$issue: $title

### Implementation plan

1. Inspect the issue requirements and the repository files most likely to be affected.
2. Make the smallest focused change that satisfies the issue while preserving the existing shell-script conventions.
3. Re-run the configured verification commands and capture the resulting test checkpoint if implementation proceeds.
4. Publish only the relevant repository changes and keep project, checkpoint, and PR state in sync.

### Files likely to change

- \`bin/\`
- \`test/\`
- \`README.md\`

### Migration or data concerns

- Repository mutations should happen only inside the dedicated issue worktree, with runtime artifacts kept under \`.grkr/\`.
- Any user-facing workflow change must be reflected in \`README.md\` before the issue is considered complete.

### Test strategy

- Run the smallest relevant shell tests for the affected workflow area first.
- Run \`npm test\`.
- Validate any GitHub project or issue-state assumptions against the configured live project when that can be done safely.

### Rollback strategy

- Revert only the focused repository changes made for this issue.
- Keep the local task artifacts as execution history unless cleanup is explicitly needed.

### Out-of-scope items

- Unrelated refactors outside the issue scope.
- Manual GitHub cleanup that is not required to complete the issue workflow.
- Changes to runtime artifacts outside this issue's task directory unless required for resume safety.

## Refusal assessment

- Is the issue implementable now? Possibly, but the decision gate still needs to confirm that the scope is clear, bounded, and testable.
- If not, why not? The workflow should refuse if the issue remains underspecified, too large, blocked by dependencies, or unsafe for autonomous execution.
- Does the issue need clarification? Unknown until repository inspection confirms that the issue description is specific enough to implement.
- Does it need breakdown into smaller tasks? Possibly, if the implementation spans multiple systems or lacks a bounded test strategy.
- Are dependencies missing? Unknown until the affected code path and any upstream requirements are inspected.
- Is required design or product input absent? Unknown until the implementation path is clear and any ambiguous behavior is identified.
- Would implementation be too risky or too broad for an autonomous agent? Unknown until the decision gate evaluates repository health, scope, and safety.
EOF
}

write_decision_prompt_file() {
  local file=$1
  local issue=$2
  local title=$3
  local url=$4
  local body=$5
  local task_slug=$6
  local worktree_dir=$7

  cat > "$file" <<EOF
Decide whether the GitHub issue below should proceed to implementation now.

Reply with exactly one word on the first non-empty line: proceed or refuse.

Only reply with proceed when the issue is sufficiently specified, bounded, and ready for one autonomous implementation pass.

If you choose refuse:
- Put one refusal class on the second non-empty line.
- Put a short explanation after that.
- Allowed refusal classes: underspecified, too_large, missing_dependency, needs_design_decision, unsafe_autonomous_change, repo_not_ready, other.

**Issue #$issue: $title**
**URL:** $url

**Description:**
$body

**Checkpoint files:**
- $GRKR_ROOT/.grkr/tasks/$task_slug/research.md
- $GRKR_ROOT/.grkr/tasks/$task_slug/plan.md

**Repository context:**
- Issue worktree: $worktree_dir
- Repository root: $GRKR_ROOT
- Main repo policy: keep changed files at $MAX_FILE_LINES lines or fewer.

EOF
}

write_issue_prompt_file() {
  local file=$1
  local issue=$2
  local title=$3
  local url=$4
  local body=$5
  local task_slug=$6
  local worktree_dir=$7

  cat > "$file" <<EOF
Implement the GitHub issue described below using the Codex coding agent best practices.

**Issue #$issue: $title**
**URL:** $url

**Description:**
$body

**Execution context:**
- Issue worktree: $worktree_dir
- Repository root: $GRKR_ROOT
- Apply code changes in the issue worktree only.
- The shell runner records your terminal output in $GRKR_ROOT/.grkr/tasks/$task_slug/implementation.log and may shard large transcripts into $GRKR_ROOT/.grkr/tasks/$task_slug/codex/implementation.log.parts/.

**Checkpoint files:**
- $GRKR_ROOT/.grkr/tasks/$task_slug/research.md
- $GRKR_ROOT/.grkr/tasks/$task_slug/plan.md

**Repository constraints:**
- No file may exceed $MAX_FILE_LINES lines.
- If a file is approaching the limit, proactively split helpers or extract modules before finishing.

**Expected final response:**
## Detailed description of the task
## Implementation plan details
## Testing results
- Functional testing performed

---

**Instructions for you:**
1. First explore the codebase using available tools (grep, glob, read, etc.) to understand the current structure and conventions.
2. Follow the project's code style, naming conventions, and architecture.
3. Make minimal, focused changes.
4. Do not add comments unless specifically asked.
5. Follow the plan from the checkpoint files and minimize unrelated edits.
6. Run the configured build and test commands as part of the implementation work.
7. Stage only the files relevant to the issue.
8. Keep every changed file within the repository's per-file line limit.
9. After changes, run linting and tests if available (use the bash tool).
10. Be concise in your responses.
11. When done, the changes should fully address the issue.

Begin by analyzing the project.
EOF
}

write_line_limit_fix_prompt() {
  local file=$1
  local issue=$2
  local title=$3
  local task_slug=$4
  local violations=$5

  cat > "$file" <<EOF
The current implementation for issue #$issue still violates the repository file-size policy and must be refactored before publish.

**Issue #$issue: $title**

**Task context:**
- .grkr/tasks/$task_slug/research.md
- .grkr/tasks/$task_slug/plan.md

**Staged file line-limit violations:**
$violations

**Required outcome:**
1. Refactor the implementation so every changed file is $MAX_FILE_LINES lines or fewer.
2. Preserve the intended behavior of the issue implementation.
3. Prefer extracting focused helpers or support files over cramming more logic into an oversized file.
4. Keep the diff minimal and rerunnable by the existing shell tests.

Return a concise summary of the refactor and any tests you ran.
EOF
}

write_default_pr_body() {
  local pr_body_file=$1
  local body=$2
  local title=$3

  cat > "$pr_body_file" <<EOF
## Detailed description of the task

$title

$body

## Implementation plan details

- Review the issue and repository context.
- Make the smallest focused change needed.
- Verify the change with the available automated tests.

## Testing results

- Functional testing performed: the launcher completed the issue workflow and created this PR.
EOF
}

write_compact_pr_body() {
  local pr_body_file=$1
  local body=$2
  local title=$3
  local short_title
  local short_body

  short_title=$(summarize_text "$title" 200)
  short_body=$(summarize_text "$body" 4000)

  cat > "$pr_body_file" <<EOF
## Detailed description of the task

$short_title

$short_body

## Implementation plan details

- The full Codex-generated summary exceeded GitHub's PR body size limit and was replaced with this compact summary.
- See the issue discussion, commit history, and local grkr logs for the complete implementation details.

## Testing results

- Review the local grkr logs for the full Codex test output when needed.
EOF
}

append_issue_footer() {
  local pr_body_file=$1
  local issue=$2

  cat >> "$pr_body_file" <<EOF

Fixes #$issue
EOF
}
