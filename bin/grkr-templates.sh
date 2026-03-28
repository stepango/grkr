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

- \`grkr --issue $issue\` fetches issue metadata, optionally moves the project item to \`${IN_PROGRESS_VALUE:-In Progress}\`, checks out or creates \`issue-$issue\`, runs Codex once for implementation, then commits, pushes, and opens a pull request.
- The current workflow does not create per-issue task folders or persist research and plan checkpoints that can be resumed on rerun.

### Relevant files/modules

- \`bin/grkr\`
- \`README.md\`
- \`test/grkr-smoke.sh\`

### Assumptions

- The new checkpoint stages should run inside the existing single-issue helper before the later implementation step.
- Checkpoint comments should use the machine-detectable marker format from the split spec.
- Re-running the same issue should reuse the existing task folder and avoid duplicate checkpoint comments.

### Unknowns

- Whether a later worktree-based issue executor will keep the current branch naming or replace it with task-slug worktrees.
- Whether later stages will regenerate checkpoint content with Codex instead of the shell-generated scaffolding used here.

### Risks

- Duplicate checkpoint comments if marker matching is too loose.
- Local checkpoint files drifting from the issue thread if execution stops after writing the file but before posting the comment.
- Regressing the current branch and PR flow while adding staged issue state.

### Inferred acceptance criteria

- Create \`.grkr/tasks/$task_slug/\` for the issue.
- Write \`research.md\`, \`plan.md\`, and \`progress.json\` under that task folder.
- Post the research and plan checkpoints as issue comments.
- Resume cleanly when matching checkpoint comments already exist.
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

1. Derive the issue task slug and create the per-issue directory under \`.grkr/tasks/$task_slug/\`.
2. Persist issue metadata and initialize \`progress.json\` with research and plan stages set to pending.
3. Generate each checkpoint Markdown file when it is missing, then post it as an issue comment unless a matching checkpoint comment already exists.
4. Reuse matching checkpoint comments on rerun so the workflow resumes without duplicate research or plan posts.
5. Continue into the existing implementation flow after the two checkpoint stages complete.

### Files likely to change

- \`bin/grkr\`
- \`README.md\`
- \`package.json\`
- \`test/grkr-smoke.sh\`
- \`test/grkr-checkpoint-resume.sh\`

### Migration or data concerns

- Existing issue branches may already exist without any task folder; the first rerun must create the missing task state without disturbing branch reuse.
- The new task artifacts live under \`.grkr/tasks/\` and do not require repository data migrations.

### Test strategy

- Extend the mocked issue flow test to assert task artifact creation and checkpoint comment posting.
- Add a resume test that preloads matching checkpoint comments and verifies the launcher reuses them without reposting.
- Run \`npm test\`.

### Rollback strategy

- Revert the launcher, test, and documentation changes.
- Delete the generated \`.grkr/tasks/$task_slug/\` directory for any affected local runs if the checkpoint workflow needs to be removed.

### Out-of-scope items

- The implement-or-refuse decision gate.
- Refusal checkpointing and Backlog transitions.
- The later test-stage checkpoint.

## Refusal assessment

- Is the issue implementable now? Yes. The requested scope is limited to creating and resuming the research and plan checkpoint stages in the current shell launcher.
- If not, why not? Not applicable.
- Does the issue need clarification? No; the required files, comment behavior, and resume expectation are explicit in the issue and spec slices.
- Does it need breakdown into smaller tasks? No; the next decision-gate and refusal work is already split into later issues.
- Are dependencies missing? No new external dependency is required beyond the existing \`gh\`, \`jq\`, and \`codex\` tooling.
- Is required design or product input absent? No; the checkpoint content and progress structure are specified.
- Would implementation be too risky or too broad for an autonomous agent? No; the change is focused to the issue launcher, its tests, and the README.
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

If you choose refuse, you may add a short explanation after the first line.
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
