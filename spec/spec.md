# AI Agent Specification for Codex + GitHub CLI Shell Automation

## 1. Goal

Build a long-running shell-based AI agent that uses **Codex CLI** and **GitHub CLI (`gh`)** to continuously triage repository work, resolve PR conflicts, react to `@:robot:` comments, and execute assigned issues from a GitHub Project.

The agent runs inside a local clone of a single GitHub repository and loops every **20 seconds**. In each iteration it:

1. syncs local `main` to the latest remote commit,
2. scans open PRs for merge conflicts with `main` and resolves them using Codex,
3. scans GitHub comments for commands starting with `@:robot:` and processes them using Codex,
4. scans a specified GitHub Project for issues assigned to the agent in **Todo** state, chooses the highest-priority candidate, and executes it through a staged pipeline,
5. remains resilient to internal errors so the main loop continues even when any individual action fails.

The implementation must use **shell scripts** as the primary implementation language.

---

## 2. Core requirements

### 2.1 Technology

Implementation must use:

- `bash` as the main language
- `git`
- `gh`
- `jq`
- `sed`
- `awk`
- `timeout`
- `flock`
- `mktemp`
- `find`
- standard POSIX utilities
- `codex` CLI

### 2.2 Main loop

The agent loops every **20 seconds** and performs, in order:

1. checkout latest commit from `main`,
2. check opened PRs for merge conflicts with `main` and resolve them,
3. check comments starting with `@:robot:` and process them,
4. check assigned issues in **Todo** state from the configured GitHub Project,
5. pick the highest-priority issue,
6. run issue execution flow or refusal flow as appropriate.

### 2.3 Comment reactions

When the agent starts processing a qualifying GitHub comment:

- add `eyes` reaction.

When the agent finishes processing successfully:

- remove `eyes`,
- add `rocket`.

If processing fails:

- best effort remove `eyes`,
- optionally add a failure comment,
- do **not** add `rocket`.

### 2.4 Checkpoints for issue execution

For issue execution:

- `research`, `plan`, and `test` stages must each write a Markdown file locally under `.grkr/<task-name>/`
- those Markdown files must also be posted to the issue as comments
- the local artifacts must allow execution to resume from checkpoints after interruption or failure

### 2.5 Worktree isolation

For all mutating or parallel work, use separate `git worktree`s:

- PR conflict resolution
- `@:robot:` comment processing
- issue execution
- issue refusal flow if it needs repository context or generated local artifacts

The main checkout is used only by the supervisor and never for implementation work.

### 2.6 Error resilience

The main loop must survive:

- Codex failures,
- GitHub API failures,
- Git failures,
- project field lookup failures,
- worktree creation failures,
- shell script runtime errors in worker scripts.

A failed worker must not terminate the supervisor loop.

---

## 3. Resolved behavior and assumptions

To make the system implementable, the following behaviors are defined explicitly.

### 3.1 Comment trigger grammar

A GitHub comment is actionable if its trimmed body begins with:

```text
@:robot:
```

Everything after that prefix is treated as the instruction for Codex.

### 3.2 Comment types covered

The base version supports:

- issue comments on issues,
- issue comments on pull requests.

Review comments may be added later but are out of scope for the first version.

### 3.3 Project Todo state

“Todo” means the project item is currently in the configured project field value:

- field: `Status`
- value: `Todo`

Field names and option IDs are loaded dynamically from the project.

### 3.4 Project Backlog state

To support refusal, the project must also define a configured **Backlog** state:

- field: `Status`
- value: `Backlog`

If refusal occurs, the issue is moved from `Todo` to `Backlog`.

### 3.5 Priority field

The project priority field may be either:

- numeric, where larger numbers are higher priority, or
- single-select, with configured ordering such as `P0 > P1 > P2 > P3`.

### 3.6 Single active issue execution

By default, the agent executes only **one issue pipeline at a time per repository**.

PR conflict resolution and comment processing may run in parallel up to configured limits.

### 3.7 PR conflict strategy

Conflict resolution uses one configured strategy:

- `rebase` onto `origin/main`, or
- `merge` `origin/main` into the PR branch.

Default: `rebase`.

### 3.8 Issue execution outcome categories

The issue workflow can end in one of these states:

- `complete`
- `failed`
- `blocked`
- `refused`

`refused` is a first-class outcome and is **not** treated as an execution failure.

---

## 4. Repository layout

Recommended layout:

```text
repo/
  .grkr/
    config.sh
    state/
      last_comment_scan_at
      processed_comments.json
      active_jobs.json
      project_cache.json
      pr_cache.json
    locks/
      main.lock
      comments.lock
      issues.lock
      prs.lock
      pr-456.lock
      issue-123.lock
      comment-789.lock
    logs/
      main.log
      loop.log
      jobs/
        pr-456.log
        issue-123.log
        comment-789.log
    worktrees/
      pr-456/
      issue-123/
      comment-789/
    tasks/
      issue-123-add-search-index/
        meta.env
        issue-context.json
        progress.json
        research.md
        plan.md
        refusal.md
        implementation.log
        test.md
        codex/
          research.prompt.md
          plan.prompt.md
          implement.prompt.md
          refuse.prompt.md
          test.prompt.md
```

---

## 5. Configuration

All runtime settings live in:

```bash
.grkr/config.sh
```

Example:

```bash
REPO="owner/repo"
MAIN_BRANCH="main"

PROJECT_OWNER="owner-or-org"
PROJECT_NUMBER="12"

STATUS_FIELD_NAME="Status"
TODO_VALUE="Todo"
IN_PROGRESS_VALUE="In Progress"
DONE_VALUE="Done"
BACKLOG_VALUE="Backlog"

PRIORITY_FIELD_NAME="Priority"
PRIORITY_MODE="single_select"   # or number
PRIORITY_ORDER="P0,P1,P2,P3"

LOOP_INTERVAL_SECS="20"

COMMENT_PREFIX="@:robot:"

MAX_PARALLEL_COMMENT_JOBS="4"
MAX_PARALLEL_PR_JOBS="2"
ISSUE_EXECUTION_CONCURRENCY="1"

CONFLICT_STRATEGY="rebase"      # or merge

TEST_COMMAND="./scripts/test.sh"
BUILD_COMMAND="./scripts/build.sh"

BOT_GIT_NAME="robot"
BOT_GIT_EMAIL="robot@example.com"

CODEX_MODEL="gpt-5-codex"
CODEX_ARGS="-c model=$CODEX_MODEL"

ENABLE_AUTO_PUSH="true"
ENABLE_PROJECT_STATUS_UPDATES="true"
ENABLE_PR_COMMENTS="true"
ENABLE_ISSUE_COMMENTS="true"

KEEP_FAILED_WORKTREES="false"
ALLOW_ISSUE_REFUSAL="true"
REFUSAL_REQUIRES_BACKLOG_MOVE="true"
```

Optional recommended settings:

```bash
MAX_IMPLEMENTATION_ATTEMPTS="1"
MAX_REFUSAL_COMMENT_UPDATES="3"
```

---

## 6. Process architecture

## 6.1 Supervisor

One long-running process:

```text
robot-main.sh
```

It loops forever and spawns short-lived workers.

## 6.2 Worker scripts

Recommended scripts:

```text
doctor.sh
worker-sync-main.sh
worker-scan-pr-conflicts.sh
worker-resolve-pr.sh
worker-scan-comments.sh
worker-handle-comment.sh
worker-pick-issue.sh
worker-exec-issue.sh
worker-refuse-issue.sh

lib/common.sh
lib/log.sh
lib/lock.sh
lib/state.sh
lib/github.sh
lib/git.sh
lib/worktree.sh
lib/codex.sh
lib/project.sh
```

### Responsibilities

- `doctor.sh`: validate tools, auth, repo, config
- `worker-sync-main.sh`: sync main checkout
- `worker-scan-pr-conflicts.sh`: discover conflicting PRs and schedule jobs
- `worker-resolve-pr.sh`: resolve conflicts in a dedicated worktree
- `worker-scan-comments.sh`: discover new `@:robot:` comments
- `worker-handle-comment.sh`: process one comment in a dedicated worktree
- `worker-pick-issue.sh`: find the highest-priority eligible Todo issue
- `worker-exec-issue.sh`: run the issue workflow
- `worker-refuse-issue.sh`: generate refusal reasoning, post comment, and move item to Backlog

---

## 7. Main loop contract

Each iteration performs these phases in order:

1. `sync_main`
2. `scan_and_schedule_pr_conflicts`
3. `scan_and_schedule_comment_commands`
4. `pick_and_schedule_issue_execution`
5. `reap_finished_jobs`
6. `cleanup_stale_worktrees`
7. `sleep_until_next_tick`

Pseudo-code:

```bash
while true; do
  tick_started_at=$(date +%s)

  run_phase sync_main || log_phase_error sync_main
  run_phase scan_prs || log_phase_error scan_prs
  run_phase scan_comments || log_phase_error scan_comments
  run_phase pick_issue || log_phase_error pick_issue
  run_phase reap || log_phase_error reap
  run_phase cleanup || log_phase_error cleanup

  sleep_remaining_time "$tick_started_at" "$LOOP_INTERVAL_SECS"
done
```

### 7.1 Resilience rules

- each phase must be wrapped in an error boundary,
- the supervisor must never exit just because a worker fails,
- workers may use `set -euo pipefail`,
- the supervisor must catch worker exit codes and continue.

---

## 8. Startup validation

At startup the supervisor must verify:

1. `gh auth status` succeeds,
2. GitHub token has the required scopes,
3. `git remote get-url origin` matches configured repo,
4. `codex` is installed and runnable,
5. required tools exist: `jq`, `timeout`, `flock`, `git`, `gh`,
6. local `.grkr` directory can be created and written,
7. the configured project contains the required fields and values:
   - `Status`
   - `Todo`
   - `Backlog`
   - `Priority`

If validation fails, the supervisor remains alive but only logs errors and skips mutating operations.

---

## 9. State model

### 9.1 Durable state

Persist in `.grkr/state/`:

- `processed_comments.json`
- `active_jobs.json`
- `project_cache.json`
- `last_comment_scan_at`
- `pr_cache.json`

### 9.2 Job keys

Use stable job keys:

- `pr:<number>:conflict-resolution`
- `comment:<comment_id>`
- `issue:<number>:execution`
- `issue:<number>:refusal`

### 9.3 Idempotency

Do not schedule a duplicate job if:

- the same job is already active, or
- the same entity version has already been completed successfully.

For comment jobs, the version key must include:

- `comment_id`
- `updated_at`
- `sha256(body)`

For issue refusal, the version key should include:

- `issue_number`
- latest issue body/comment digest
- relevant project field values

This prevents duplicate refusal comments on unchanged issue state.

---

## 10. Worktree model

### 10.1 Naming

Worktree path examples:

- `.grkr/worktrees/pr-456`
- `.grkr/worktrees/comment-789`
- `.grkr/worktrees/issue-123-add-search-index`

Branches:

- `robot/pr-456-conflict`
- `robot/comment-789`
- `robot/issue-123-add-search-index`

### 10.2 Lifecycle

For each worker:

1. create worktree,
2. configure git author,
3. fetch needed refs,
4. perform work,
5. commit and push if needed,
6. update job state,
7. remove worktree,
8. periodically prune stale worktrees.

### 10.3 Base refs

- PR conflict job base: PR head branch
- PR comment job base: PR head branch
- issue comment job base: latest `main`
- issue execution base: latest `origin/main`
- issue refusal base: latest `origin/main` if repo context is needed, otherwise no worktree required

---

## 11. Phase 1: sync latest `main`

### 11.1 Behavior

The first step in every loop updates the supervisor checkout to latest `origin/main`.

Commands:

```bash
git fetch origin "$MAIN_BRANCH" --prune
git checkout "$MAIN_BRANCH"
git reset --hard "origin/$MAIN_BRANCH"
```

Run under `.grkr/locks/main.lock`.

### 11.2 Restriction

No feature work happens in the supervisor checkout.

---

## 12. Phase 2: detect and resolve PR conflicts

### 12.1 Discovery

List open PRs and determine mergeability.

Schedule a resolution job when all are true:

- PR is open,
- PR base is `main`,
- PR is conflicting with `main`,
- no active PR conflict job exists for that PR.

### 12.2 Worker flow

`worker-resolve-pr.sh <pr_number>`

1. fetch PR metadata,
2. create worktree from PR head,
3. fetch latest `origin/main`,
4. attempt rebase or merge,
5. if conflicts appear:
   - collect conflict files,
   - invoke Codex to resolve only those conflicts,
6. rerun integration command,
7. run validation commands,
8. commit resolved changes,
9. push to the PR branch,
10. optionally post PR summary comment,
11. cleanup.

### 12.3 Constraints

The Codex prompt must instruct:

- resolve merge conflicts only,
- preserve PR intent,
- avoid unrelated refactors,
- avoid formatting unrelated files,
- run minimal validation.

### 12.4 Failure handling

On failure:

- log failure,
- optionally comment on the PR,
- retain the worktree only if configured,
- keep the supervisor alive.

---

## 13. Phase 3: detect and process `@:robot:` comments

### 13.1 Discovery

Scan issue comments on:

- issues
- pull requests

A comment is actionable only if it starts with `@:robot:`.

### 13.2 Reaction flow

Before processing:

- add `eyes`.

On successful completion:

- best effort remove `eyes`,
- add `rocket`.

On failure:

- best effort remove `eyes`,
- optionally add a failure comment,
- do not add `rocket`.

### 13.3 Worker flow

`worker-handle-comment.sh <comment_id>`

1. fetch comment context,
2. add `eyes`,
3. create worktree,
4. build Codex prompt from:
   - raw command,
   - issue/PR title and body,
   - recent comments,
   - current branch context,
   - repo policy,
5. execute chosen action,
6. comment with result if needed,
7. commit and push if needed,
8. update reactions,
9. cleanup.

### 13.4 Supported action classes

Codex may choose one of:

- **answer-only**
- **code-change**
- **triage**
- **refuse**

A refusal in comment handling only affects the comment response. It does not automatically move project items unless explicitly configured.

---

## 14. Phase 4: choose assigned issue from project Todo

### 14.1 Candidate selection

The agent queries the configured project and selects issues that satisfy:

- item type = issue,
- assigned to the bot/authenticated user,
- `Status = Todo`,
- issue is open,
- issue belongs to the configured repo,
- issue is not already active.

### 14.2 Priority ordering

Order by:

1. highest configured priority,
2. oldest update time,
3. lowest issue number.

### 14.3 Scheduling

If no issue execution is already active, schedule the top candidate.

---

## 15. Issue workflow overview

The issue workflow is a staged pipeline executed in one dedicated worktree.

Stages:

1. `research`
2. `plan`
3. `implement_or_refuse`
4. `test` (only if implementation proceeds)

The key change is that **implementation is optional**. After research and plan, the agent may decide to:

- continue into implementation, or
- refuse implementation and move the issue back to **Backlog** with a reasoned comment.

### 15.1 High-level outcomes

Possible issue workflow outcomes:

- **implemented**: code changes produced and tested
- **refused**: issue intentionally not implemented
- **blocked**: execution interrupted by transient or external problem
- **failed**: workflow bug or unrecoverable execution failure

### 15.2 Refusal is not failure

A refusal is a valid and expected result when the issue should not be implemented yet.

It must be recorded clearly, commented publicly, checkpointed locally, and reflected in project state.

---

## 16. Task folder and progress tracking

Task slug example:

```text
issue-123-add-search-index
```

Task folder:

```text
.grkr/tasks/issue-123-add-search-index/
```

Files:

- `meta.env`
- `issue-context.json`
- `research.md`
- `plan.md`
- `refusal.md`
- `implementation.log`
- `test.md`
- `progress.json`

Example `progress.json`:

```json
{
  "issue_number": 123,
  "project_item_id": "PVTI_xxx",
  "task_slug": "issue-123-add-search-index",
  "branch": "robot/issue-123-add-search-index",
  "status": "planning",
  "decision": "undecided",
  "stages": {
    "research": {"status": "done", "comment_id": 1111},
    "plan": {"status": "done", "comment_id": 1112},
    "implement_or_refuse": {"status": "pending"},
    "test": {"status": "pending"}
  },
  "started_at": "...",
  "updated_at": "..."
}
```

If refusal happens:

```json
{
  "status": "refused",
  "decision": "refuse",
  "stages": {
    "research": {"status": "done", "comment_id": 1111},
    "plan": {"status": "done", "comment_id": 1112},
    "implement_or_refuse": {"status": "done", "comment_id": 1113, "reason_class": "underspecified"},
    "test": {"status": "skipped"}
  }
}
```

---

## 17. Stage 1: research

### 17.1 Inputs

- issue title and body
- project metadata
- relevant repository files
- related comments
- related linked issues/PRs if cheaply available

### 17.2 Output

Write:

```text
.grkr/tasks/<slug>/research.md
```

It must contain:

- problem statement
- current system behavior
- relevant files/modules
- assumptions
- unknowns
- risks
- inferred acceptance criteria

### 17.3 Issue checkpoint comment

Post `research.md` as an issue comment.

### 17.4 Resume rule

If `research.md` exists and matching checkpoint comment exists, skip this stage unless forced.

---

## 18. Stage 2: plan

### 18.1 Inputs

- `research.md`
- issue body/comments
- repository context

### 18.2 Output

Write:

```text
.grkr/tasks/<slug>/plan.md
```

It must contain:

- implementation plan
- files likely to change
- migration or data concerns
- test strategy
- rollback strategy
- out-of-scope items
- refusal assessment section

### 18.3 Required refusal assessment section

`plan.md` must include a section:

```markdown
## Refusal assessment
```

This section must explicitly answer:

- Is the issue implementable now?
- If not, why not?
- Does the issue need clarification?
- Does it need breakdown into smaller tasks?
- Are dependencies missing?
- Is required design or product input absent?
- Would implementation be too risky or too broad for an autonomous agent?

### 18.4 Issue checkpoint comment

Post `plan.md` as an issue comment.

### 18.5 Resume rule

If `plan.md` exists and matching checkpoint comment exists, skip this stage unless forced.

---

## 19. Stage 3: implement-or-refuse decision gate

This is the new required decision stage.

After `research` and `plan`, the agent must decide whether to:

- proceed to implementation, or
- refuse implementation.

This decision must be made before any implementation attempt.

### 19.1 Decision authority

The decision is delegated to a separate Codex invocation with a tightly-scoped prompt using:

- issue description,
- relevant comments,
- `research.md`,
- `plan.md`,
- repository context,
- project policy.

### 19.2 Possible decisions

- `proceed`
- `refuse`

### 19.3 Default decision policy

The agent should **refuse** if any of the following hold:

1. **underspecified issue**
   - acceptance criteria are unclear
   - expected behavior is ambiguous
   - important implementation details are missing

2. **issue too large or high complexity**
   - task spans multiple systems
   - requires major design decisions
   - should be decomposed into smaller issues

3. **missing dependencies**
   - required upstream issue or PR is not implemented
   - required API or schema does not exist
   - external service or infra dependency is unavailable

4. **blocked by product or design decision**
   - user experience or product requirements are unresolved
   - conflicting approaches are possible and no choice is specified

5. **unsafe or inappropriate for autonomous implementation**
   - high-risk migration
   - irreversible data changes
   - security-sensitive or policy-sensitive changes needing human review

6. **repository state not suitable**
   - tests or build are fundamentally broken in a way unrelated to the issue
   - required branch context is missing

### 19.4 Proceed criteria

The agent should proceed only if:

- the issue is sufficiently specified,
- the implementation is bounded enough for one autonomous change,
- dependencies appear ready,
- risks are acceptable,
- a test strategy exists.

### 19.5 Implementation attempt cap

The agent must not loop forever on the same issue. If implementation repeatedly fails due to issue quality rather than transient execution problems, it may convert the workflow from `implement` to `refuse`.

---

## 20. Refusal flow

If the decision is `refuse`, the agent must enter the refusal flow.

### 20.1 Required actions

1. generate `refusal.md`
2. post `refusal.md` as an issue comment
3. move the project item from `Todo` to `Backlog`
4. mark workflow status as `refused`
5. skip implementation
6. skip test
7. cleanup the worktree

### 20.2 Refusal markdown file

Write:

```text
.grkr/tasks/<slug>/refusal.md
```

The file must contain:

- refusal summary
- refusal class
- detailed reasoning
- what information or prerequisite is missing
- explicit next step recommendations
- whether the issue should be split
- whether follow-up issues are recommended

### 20.3 Refusal classes

Allowed refusal classes:

- `underspecified`
- `too_large`
- `missing_dependency`
- `needs_design_decision`
- `unsafe_autonomous_change`
- `repo_not_ready`
- `other`

### 20.4 Required refusal comment format

Example:

```markdown
<!-- grkr:checkpoint stage=refusal task=issue-123-add-search-index version=1 -->
## Implementation refused

### Reason class
underspecified

### Why this issue was not implemented
The issue does not define acceptance criteria for the search ranking behavior, and it is unclear whether relevance should prefer title matches, semantic matches, or exact tags.

### What is needed before implementation
- Define expected ranking behavior
- Provide at least 2-3 concrete examples
- Confirm whether search should index archived items

### Suggested next actions
- Update this issue with explicit acceptance criteria, or
- Split the issue into:
  1. define ranking rules
  2. add indexing support
  3. add search UI behavior
```

### 20.5 Project status update

If refusal occurs and `ENABLE_PROJECT_STATUS_UPDATES=true`, the agent must move the project item to:

```text
Backlog
```

If `REFUSAL_REQUIRES_BACKLOG_MOVE=true` and no Backlog state is found, refusal should still be commented, but the worker should log a project-state update failure and mark the result as `refused_with_project_update_error`.

### 20.6 Refusal is resumable

The refusal flow must be resumable. If `refusal.md` already exists and the matching checkpoint comment exists:

- do not repost duplicate comments,
- do not move project status repeatedly if already in Backlog,
- mark issue workflow as refused and complete cleanup.

---

## 21. Stage 4: implement

This stage runs only if the decision gate returns `proceed`.

### 21.1 Inputs

- `research.md`
- `plan.md`
- issue context
- repository worktree

### 21.2 Output

Codex modifies files in the issue worktree and implementation logs are stored in:

```text
.grkr/tasks/<slug>/implementation.log
```

### 21.3 Constraints

The implementation prompt must instruct Codex to:

- follow the plan,
- minimize unrelated edits,
- avoid large opportunistic refactors,
- run configured build and test commands,
- stage only relevant files.

### 21.4 Commit strategy

Commit message example:

```text
feat(robot): implement #123 add search index
```

or

```text
fix(robot): implement #123 stabilize cache invalidation
```

### 21.5 Branch strategy

Default behavior:

- push issue branch
- create or update a PR for that branch
- link the issue in the PR body

### 21.6 Escalation from implement to refuse

If implementation begins but the agent discovers issue-quality blockers that should have caused refusal, it may still switch to refusal **before** posting final success.

When that happens:

- preserve `implementation.log`
- generate `refusal.md`
- post refusal comment
- move issue to Backlog
- mark workflow as `refused`

This prevents half-finished silent failures.

---

## 22. Stage 5: test

This stage runs only if implementation succeeded.

### 22.1 Inputs

- final implementation worktree
- configured commands

### 22.2 Output

Write:

```text
.grkr/tasks/<slug>/test.md
```

It must include:

- commands run
- pass/fail summary
- output excerpts
- remaining risks
- recommendation: ready or needs follow-up

### 22.3 Issue checkpoint comment

Post `test.md` as issue comment.

### 22.4 Completion actions

On success:

- optionally move project item to `In Progress` or `Done`
- comment final summary
- record branch and PR URL
- mark `progress.json.status = complete`

---

## 23. Checkpoint comment format

All checkpoint comments must be machine-detectable.

### 23.1 Research

```markdown
<!-- grkr:checkpoint stage=research task=issue-123-add-search-index version=1 -->
## Research checkpoint
...
```

### 23.2 Plan

```markdown
<!-- grkr:checkpoint stage=plan task=issue-123-add-search-index version=1 -->
## Plan checkpoint
...
```

### 23.3 Refusal

```markdown
<!-- grkr:checkpoint stage=refusal task=issue-123-add-search-index version=1 -->
## Implementation refused
...
```

### 23.4 Test

```markdown
<!-- grkr:checkpoint stage=test task=issue-123-add-search-index version=1 -->
## Test checkpoint
...
```

---

## 24. Detailed issue workflow pseudocode

```bash
worker-exec-issue.sh() {
  load_issue_context "$ISSUE_NUMBER"
  create_or_attach_worktree "$TASK_SLUG"

  ensure_research_checkpoint
  ensure_plan_checkpoint

  decision=$(decide_implement_or_refuse)

  if [ "$decision" = "refuse" ]; then
    worker-refuse-issue.sh "$ISSUE_NUMBER" "$PROJECT_ITEM_ID" "$TASK_SLUG"
    mark_issue_workflow_refused
    cleanup_issue_worktree
    return 0
  fi

  run_implementation || {
    if should_convert_failure_to_refusal; then
      worker-refuse-issue.sh "$ISSUE_NUMBER" "$PROJECT_ITEM_ID" "$TASK_SLUG"
      mark_issue_workflow_refused
      cleanup_issue_worktree
      return 0
    fi
    mark_issue_workflow_failed
    cleanup_issue_worktree
    return 1
  }

  ensure_test_checkpoint
  mark_issue_workflow_complete
  cleanup_issue_worktree
}
```

Refusal worker example:

```bash
worker-refuse-issue.sh() {
  local issue_number="$1"
  local project_item_id="$2"
  local task_slug="$3"

  generate_refusal_md "$issue_number" "$task_slug"
  post_refusal_comment_if_missing "$issue_number" "$task_slug"
  move_project_item_to_backlog "$project_item_id"
  update_progress_refused "$issue_number" "$task_slug"
}
```

---

## 25. Locking and concurrency

### 25.1 Locks

Use `flock` on:

- `main.lock`
- `comments.lock`
- `prs.lock`
- `issues.lock`
- `pr-<n>.lock`
- `issue-<n>.lock`
- `comment-<id>.lock`

### 25.2 Rules

- only one sync-main at a time
- only one worker per PR
- only one worker per comment version
- only one workflow per issue
- only one active issue execution by default

### 25.3 Dead process recovery

At the beginning of each loop:

- inspect `active_jobs.json`
- if recorded PID no longer exists:
  - mark job stale
  - release lock
  - optionally requeue the job

---

## 26. Logging and observability

### 26.1 Structured logging

Each log line should include:

- timestamp
- level
- phase
- job key
- entity type/id
- message

Example:

```text
2026-03-27T15:22:00Z INFO phase=issue_execute job=issue:123:execution entity=issue/123 msg="decision=refuse reason_class=underspecified"
```

### 26.2 Worker logs

Each worker writes to:

```text
.grkr/logs/jobs/<job-key>.log
```

### 26.3 Refusal visibility

Refusal must be visible in logs, state, and issue comments. It must never be silently collapsed into generic failure.

---

## 27. Failure handling

### 27.1 Retry classes

Retry automatically:

- GitHub API 5xx
- transient network failures
- `git fetch` failures
- temporary Codex invocation failures

Do not hot-loop retry:

- malformed config
- missing project field configuration
- repeated policy refusal
- persistent project item edit failure due to missing Backlog state
- deterministic repository permission errors

### 27.2 Backoff

Use per-job backoff:

- 1 loop
- 3 loops
- 10 loops
- cap at 1 hour

### 27.3 Refusal vs failure

Important distinction:

- **failure** means the system could not perform its intended workflow
- **refusal** means the system intentionally decided not to implement

Refusal should not consume repeated retry budget unless issue state changes.

---

## 28. Cleanup policy

At least every 10 loops:

- remove completed worktrees older than 1 hour,
- remove failed worktrees older than configured TTL,
- prune stale worktrees,
- purge stale locks,
- compact processed comment state.

For refused issues:

- task folders must remain,
- refusal checkpoints must remain,
- worktrees may be removed immediately after refusal is committed to state and comments.

---

## 29. Security and policy constraints

The shell wrapper is the real policy boundary.

Mandatory safeguards:

- never execute arbitrary shell fragments from comments,
- only allow predefined command execution paths,
- no writes outside repo/worktree except `.grkr`,
- no force-push to protected branches by default,
- no secret exfiltration,
- redact secrets in logs,
- no automatic implementation when the issue is too ambiguous or risky.

The new refusal path is a safety feature, not just a workflow feature.

---

## 30. Acceptance criteria

The system is complete when all are true:

1. the supervisor runs continuously and survives worker failures,
2. each 20-second loop continues even when one phase fails,
3. actionable comments get `eyes` at start and `rocket` on success,
4. assigned Todo issues can be discovered and prioritized,
5. research, plan, and test generate local Markdown checkpoints and post them to the issue,
6. PR merge conflicts against `main` can be resolved in isolated worktrees,
7. issue execution can resume from checkpoint files,
8. issue execution may validly end in **refusal**,
9. refusal posts a reasoned comment,
10. refusal moves the issue from **Todo** to **Backlog**,
11. refusal is checkpointed locally in `refusal.md`,
12. refusal is treated as a valid terminal state rather than a worker failure.

---

## 31. Recommended implementation order

1. `doctor.sh`
2. supervisor loop + logging + locks
3. sync-main worker
4. project issue picker
5. issue workflow with research and plan checkpoints
6. implement-or-refuse decision gate
7. refusal worker and Backlog transition
8. implement stage
9. test stage
10. comment scanning + reactions
11. PR conflict resolution
12. cleanup and retry polish

Tracked issues for this implementation order:

1. [#10 - Add doctor.sh validation for tools, auth, repo, and config](https://github.com/stepango/grkr/issues/10)
2. [#11 - Add supervisor loop, logging, and lock orchestration](https://github.com/stepango/grkr/issues/11)
3. [#12 - Add worker-sync-main.sh to fast-forward the supervisor checkout to origin/main](https://github.com/stepango/grkr/issues/12)
4. [#13 - Add worker-pick-issue.sh for project Todo selection and prioritization](https://github.com/stepango/grkr/issues/13)
5. [#14 - Add research and plan checkpoints to the issue workflow](https://github.com/stepango/grkr/issues/14)
6. [#15 - Add implement-or-refuse decision gate for issue execution](https://github.com/stepango/grkr/issues/15)
7. [#16 - Add worker-refuse-issue.sh and Backlog transition handling](https://github.com/stepango/grkr/issues/16)
8. [#17 - Add the implementation stage for issue workflows](https://github.com/stepango/grkr/issues/17)
9. [#18 - Add the test stage and completion flow for issues](https://github.com/stepango/grkr/issues/18)
10. [#19 - Add worker-scan-comments.sh and worker-handle-comment.sh for @:robot: commands](https://github.com/stepango/grkr/issues/19)
11. [#20 - Add worker-resolve-pr.sh for merge-conflict resolution in isolated worktrees](https://github.com/stepango/grkr/issues/20)
12. [#21 - Add cleanup, retry, and stale-job recovery polish](https://github.com/stepango/grkr/issues/21)

This order gets the refusal-aware issue pipeline working early, which is important for safe autonomous operation.

---
