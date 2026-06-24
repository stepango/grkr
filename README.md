# grkr

AI-powered CLI that reads a GitHub issue and uses Codex to implement the changes.

Current implementation status: see [docs/gleam-migration.md](./docs/gleam-migration.md) for v2 Gleam migration progress and research notes (GitHub pick+schedule parity audit t_30fa61c7 @ 291 gleam tests; supervisor pick dispatch in `src/grkr/supervisor/pick.gleam` per t_73c1fbdf).

## Gleam v2 Migration Progress

**GitHub-only first, in progress on `v2` branch / PR #79 (https://github.com/stepango/grkr/pull/79).** Follows AGENTS.md: thick Gleam in `src/grkr/`, thin shell wrappers in `bin/` (preserve conventions), files <=1000 LOC, `spec/parts/` canonical. Large tasks decomposed into kanban slices to handle iteration budgets (90/90 max_iterations exhaustion on complex parents).

See the expanded [docs/gleam-migration.md](./docs/gleam-migration.md) for:
- Full file lists + LOC counts for github_picker/, refusal/, supervisor/, supporting modules
- What compiles/runs today (`gleam build`, targeted tests, picker/refusal/supervisor partial paths)
- Remaining work (Linear full execution path; ongoing PR #79 / e2e polish — spec/39 pipeline items 6–12 are implemented; see gleam-migration.md table)
- Traceability to specific kanban tasks (e.g. t_58ea0e02 scheduler impl, t_20695489 test+docs+sync, t_78a7818e cleanup prune, t_767a0b08 prior test+docs, t_65d650b7 review (supervisor slice), t_55147911 docs follow-up, t_e56d835b hygiene commit+push v2 uncommitted, t_2c94e927 (decision_gate + handle_comment wire/validate per spec/22+15 + t_1cca18ff), t_0843d707 (test_stage.gleam + wiring per spec/39 item 9 / #18 + spec/17), t_e2282d3f (gleam build 0 warnings fix in handle_comment WIP), PR#79 reviews t_2abfcacc/t_e1b63fc6/t_1ef6c1a8 etc)
- Design refs (supervisor-design-final.md, supervisor-synthesis.md, gleam-migration-patterns.md)
- Lock audit notes from this run

**High-level snapshot (post doctor Gleam thin t_630cd219: `bin/doctor.sh` 51 LOC → `grkr/doctor` validate+cli; **291/291** `gleam test` + npm test green on v2 / PR #79):**
- github_picker (client+main+picker + decoder_test 256/256 green post fixtures fix + hygiene M in client/decoder/field t_64f72de6 + t_077f26d0 (0 warnings fix for field/client/decoder.gleam)), refusal (flow/assessment/checkpoint + cli + config/ffi M in t_e56d835b), supervisor (main/loop/recovery/state/lock/config/phases + pick.gleam 152LOC dispatching `GRKR_ISSUE_PROVIDER` github|linear + scheduler 130 + FFI; loop M for sleep_remaining + error boundary + hygiene in t_e56d835b) implemented + reviewed in slices; phases.gleam pick phase calls `supervisor/pick` (fixture tests: `GITHUB_FIXTURE_PATH`, `LINEAR_FIXTURE_PATH`, `GRKR_ACTIVE_JOBS_PATH` under `test/fixtures/`); sync/pick (real scheduler wired)/scan_pr/scan_comment/reap/cleanup
- workflow/ (decision 264, decision_gate 155 (spec/22), implement_stage 36 + test, test_stage 66 LOC (run-tests + completion-marker per spec/26+39), handle_comment 456 (full post t_2c94e927 wiring + t_e2282d3f hygiene), resolve_pr/main 426 full + skeleton, task_log split, worktree split, main/ffi)
- Bin updates/hygiene (per AGENTS: preserve sh conv, small explicit changes, <1000 LOC): **doctor.sh (51 LOC thin: doctor_init + delegate to `grkr/doctor/cli`)**, grkr-project-status.sh (81 LOC thin), grkr-issue-workflow.sh (80 LOC thin wrapper delegating workflow/* CLIs incl decision_gate + test_completion_marker), worker-handle-comment.sh (29 LOC thin), worker-pick-issue.sh (46 LOC), worker-sync-main.sh (18 LOC), worker-resolve-pr.sh (39 LOC), worker-refuse-issue.sh (40 LOC thin calling refusal/cli), robot-main.sh (57 LOC), grkr (826 LOC post t_b5bd0fa8 task_progress extract), grkr-templates.sh (62 LOC thin), + bin/lib/{refusal_paths.sh,task_progress.sh} (176 LOC shared); new test_stage + implement_stage_test added
- Fully migrated: **doctor** (config_parse + validate + cli), sync_main, resolve_pr (PR conflicts), issue_provider (Linear), progress (checkpoints/Linear + templates 176), task_slug, project_status (full + 81 LOC thin bin/grkr-project-status.sh delegating to project_status_cli), linear e2e
- implement stage hook (Gleam src/grkr/workflow/implement_stage.gleam + test + thin delegate in grkr-issue-workflow.sh + wired in bin/grkr for commit msg per spec/25 + t_39ab1e08 / #17); test_stage hook + completion-marker (Gleam src/grkr/workflow/test_stage.gleam 66LOC + 24LOC test + delegate in grkr-issue-workflow.sh per spec/26 + t_6d2b458b / #18)
- Still thick: none in primary issue/PR paths (all core now thin Gleam delegates + full impls)
- Supervisor phases + scheduler (active_jobs record + detached spawn under flock for pick_and_schedule) landed (t_61c5af7b + t_58ea0e02) + wired in pick phase (t_20695489); pick now fully records+spawns real workflows; comment scan + worker full (t_13a8a733 + later); recent child cards (t_767a0b08, t_20695489 test+docs+sync, t_78a7818e cleanup, t_65d650b7 review + t_55147911 docs fix + t_e56d835b hygiene commit+push)
- All changes maintain 100% external contracts (logs, locks, JSON schemas, exit codes, env, gh/gh project behavior)

No changes to user-facing commands, config, or entrypoints (still `robot-main.sh`, `grkr --issue`, etc.). Workflow accuracy preserved.

## Usage

```bash
# Install globally
npm install -g .

# Create the config for this repo and project
grkr init 42

# Run the long-lived supervisor loop
robot-main.sh

# Run for an issue
grkr --issue 1

# Print CLI usage
grkr --help

# Run the smoke test
npm test

# Resolve PR conflicts (Gleam-based)
worker-resolve-pr.sh 123
```

## PR Conflict Resolution

The `worker-resolve-pr.sh` script implements automated PR conflict resolution using Gleam:

1. Fetches PR metadata and checks for conflicts
2. Creates a dedicated worktree at `.grkr/worktrees/pr-<number>/`
3. Attempts automatic rebase or merge with `origin/main` based on `CONFLICT_STRATEGY`
4. On conflicts, invokes Codex to resolve merge conflicts in affected files
5. Validates resolved content and commits changes
6. Pushes the resolved branch back to the PR
7. Cleans up the worktree

The implementation uses Gleam for the core logic with a thin shell wrapper that preserves shell conventions and integrates with the existing supervisor infrastructure.

## Progress Tracking and Linear Integration

grkr includes Gleam-owned progress tracking and Linear integration under `src/grkr/progress/`:

1. **Checkpoint stages**: Research, plan, refusal, implementation, test, and PR summary stages with validation and formatting
2. **Idempotency**: Stable machine markers and idempotency keys for checkpoint comments to prevent duplicates
3. **Markdown rendering**: Checkpoint comment formatting with optional PR links and refusal reasons
4. **Progress CLI**: `gleam run -m grkr/progress/cli -- marker <stage> <task-slug>` renders the checkpoint marker used by the shell workflow, so `bin/grkr` and `worker-refuse-issue.sh` now delegate marker production to Gleam. The same CLI also exposes safe Linear planning commands (`linear-state`, `linear-comment-mutation`, `linear-state-mutation`, `mutation-debug`, and `check-token`) that print planned mutations or token status without contacting Linear by default.
5. **Linear state mapping**: Configurable mapping from grkr phases to Linear workflow states via environment variables
6. **Linear mutations**: GraphQL mutation planning for comment creation and issue state updates with idempotency markers
7. **Token handling**: Safe failure when Linear access tokens are unavailable without treating OAuth app credentials as direct GraphQL tokens
8. **Safe diagnostics**: Linear mutation debug output includes the query and idempotency key while redacting variables that may contain checkpoint body text or secrets

The progress modules provide planning functions for checkpoint rendering and Linear mutations while preserving existing GitHub issue workflows. Linear support runs alongside GitHub, not as a replacement.

## Issue provider auth foundation

The v2 migration now includes a Gleam-owned issue-provider configuration foundation under `src/grkr/issue_provider/`. GitHub remains the default provider, while Linear can be configured alongside it for upcoming provider/query slices.

Linear credentials are treated as OAuth app credentials, not as a direct GraphQL token. Credential discovery reads `~/.linear/secret.txt` by default; for local automation, place the two app credential values there or point `LINEAR_CREDENTIALS_PATH` at an equivalent file. The supported OAuth app file shape is:

```text
client_id=<linear OAuth client id>
client_secret=<linear OAuth client secret>
```

These values are only enough to identify the OAuth app. Linear GraphQL calls still require a later OAuth installation/token exchange that produces an access token; until that exists, the Gleam validator returns a redacted, actionable `OAuthAppCredentialsWithoutToken` error instead of pretending the app credentials can query Linear directly. A single-line `token=...` or token-only file shape is parsed for future installed-token support, but OAuth app credentials are the expected local secret shape for the current Linear setup.

## How it works

1. `robot-main.sh` (now a thin ~58-line wrapper) sources doctor + config, runs validation, then `exec`s the Gleam supervisor at `src/grkr/supervisor/main` (v2, GitHub-only); the Gleam code creates the `.grkr` layout, validates, and runs the ordered phases on the configured interval
2. The first supervisor phase delegates to `worker-sync-main.sh`, a thin shell wrapper around `grkr/sync_main/main`, which takes `.grkr/locks/main.lock`, fetches `origin/$MAIN_BRANCH` with pruning, checks out the configured main branch, and hard-resets the supervisor checkout to `origin/$MAIN_BRANCH`
3. The supervisor writes structured loop logs to `.grkr/logs/main.log` and `.grkr/logs/loop.log`, keeps per-job logs under `.grkr/logs/jobs/`, recovers stale rows from `.grkr/state/active_jobs.json` on startup and each `reap_finished_jobs` tick (dead PIDs, entries past `ACTIVE_JOB_TTL_SECONDS` default 86400 while the PID still appears alive, and hung-lock orphans after a 5-minute grace — see `.grkr/supervisor-cleanup-policy.md` §6), and keeps later phases running when an earlier phase fails
4. Phase 4 delegates to `worker-pick-issue.sh`, which reads the configured GitHub Project live, filters Todo issues assigned to the authenticated bot in the configured repo, excludes active issue jobs, orders candidates by priority and age, and emits the stable `issue:<n>:execution` job key plus task slug for the top match
5. `grkr --issue <n>` remains the focused single-issue helper that fetches issue details using `gh issue view`
6. The issue helper creates or reuses `.grkr/tasks/<issue-slug>/`, writes `research.md`, `plan.md`, and `progress.json`, and posts the research and plan checkpoints back to the issue. The `<issue-slug>` task folder name is generated by the Gleam-backed `grkr/task_slug/cli` path, with `bin/grkr`, `worker-pick-issue.sh`, and `worker-refuse-issue.sh` using a thin shell delegator for naming compatibility.
7. If matching checkpoint comments already exist, the issue helper reuses those comments and resumes without reposting duplicate research or plan checkpoints
8. The issue helper also creates or reuses `.grkr/worktrees/<issue-slug>/` so issue execution happens in a dedicated git worktree instead of the supervisor checkout
9. After research and plan, a separate Codex decision gate runs in the issue worktree and implementation continues only when that gate returns `proceed`
10. When the decision is `refuse`, the issue helper writes `.grkr/tasks/<issue-slug>/refusal.md`, posts the refusal checkpoint, moves the project item back to `Backlog` when configured, marks `progress.json` as refused, skips test, and removes the issue worktree
11. When the decision is `proceed`, the issue helper moves the configured project item to the configured in-progress status when it can resolve that project item; GitHub Project status extraction, project id/field/option resolution, and status option normalization are Gleam-backed while the shell helper remains a thin `gh project` host adapter. Status option matching is case-insensitive and whitespace-normalized with exact match preference.
12. Codex implementation output is anchored at `.grkr/tasks/<issue-slug>/implementation.log`; when the transcript grows too large, `grkr` keeps that file as a manifest and shards the full log into `.grkr/tasks/<issue-slug>/codex/implementation.log.parts/` so every tracked file stays within the 1000-line limit
13. The configured build and test commands run in the same issue worktree, `grkr` writes `.grkr/tasks/<issue-slug>/test.md`, and posts the test checkpoint back to the issue
14. `grkr` stages only the relevant non-`.grkr` file changes from the issue worktree, commits, pushes the issue branch, creates or updates a PR that links the issue, records the branch and PR URLs in `progress.json`, and marks the issue workflow complete
15. On successful completion, the issue helper posts a short completion summary, optionally moves the project item to `Done`, and mirrors the local run log back to the issue inside a collapsed details block
16. If the generated PR description is too large for GitHub, `grkr` replaces it with a compact summary before creating the PR
17. In `grkr --project <id>` mode, a failed issue run is logged and the watcher continues with later issues and later loop iterations

## Install Notes

- `npm install -g .` installs the local `bin/grkr` launcher into your PATH.
- The installed `grkr` launcher resolves its real script path before loading helper files, so symlinked installs such as npm's global bin layout do not need `grkr-templates.sh` copied into the top-level bin directory.
- `robot-main.sh` uses `MAIN_BRANCH` and `LOOP_INTERVAL_SECS` from `.grkr/config.sh`; `grkr init <id>` now writes both defaults into the generated config.
- `worker-sync-main.sh` is the phase-1 supervisor worker; it delegates production sync logic to Gleam and always returns the main checkout to the configured `MAIN_BRANCH` before later phases run.
- `worker-pick-issue.sh` is the phase-4 selector; now a thin ~40-line wrapper that delegates to `gleam run -m grkr/github_picker/main` (config + gh GraphQL+paginate+decode+pick+emit). Supports `GITHUB_FIXTURE_PATH` and `items-query` subcmd. Assignee filtering uses `BOT_LOGIN` / `GITHUB_ACTOR` when set, otherwise `gh api user` (same as the legacy shell picker). Interface unchanged.
- `worker-refuse-issue.sh` handles the refusal flow for issues that should not be implemented yet; it generates `refusal.md` with class and reasoning, posts a refusal checkpoint comment exactly once without duplication on resume, moves the project item from `Todo` to `Backlog` when `ENABLE_PROJECT_STATUS_UPDATES` and `REFUSAL_REQUIRES_BACKLOG_MOVE` allow it, marks the workflow as refused, and treats refusal as a valid terminal state.
- `grkr init <id>` also writes `IN_PROGRESS_VALUE="In Progress"` so issue execution can move a project item out of Todo before branching; status option lookup tolerates casing differences such as `In progress`.
- `grkr init <id>` also writes `DONE_VALUE="Done"` plus default `TEST_COMMAND` and `BUILD_COMMAND` entries so the test stage has explicit verification commands.
- `grkr init <id>` also writes `BACKLOG_VALUE="Backlog"` so refusal can move unready issues back out of Todo.
- `npm test` refreshes the spec index from the split files under `spec/parts/` and runs the mocked shell tests without needing GitHub access.
- `grkr --issue <id>` automatically shrinks oversized Codex-generated PR bodies so `gh pr create` stays under GitHub's 65536-character body limit.
- `grkr --issue <id>` links the issue once in the PR body via `Fixes #<id>` to avoid duplicate issue mentions.
- `grkr --issue <id>` includes the per-file 1000-line rule in the Codex prompt and will trigger one immediate Codex refactor pass when staged changes still violate that limit.
- `grkr --issue <id>` now runs issue execution in `.grkr/worktrees/<issue-slug>/`, uses a dedicated Codex decision gate before implementation, and only proceeds when that gate returns `proceed`.
- `grkr --issue <id>` treats `refuse` as a valid terminal outcome: it writes `refusal.md`, posts a refusal checkpoint comment, moves the issue back to `Backlog` when configured, skips implementation and tests, and removes the issue worktree.
- During implementation, if Codex reports an explicit `grkr-refuse-implementation` blocker (missing dependencies, unsafe changes, or other issue-quality problems), the workflow converts from implementation to refusal, preserves the implementation log as `.grkr/tasks/<issue-slug>/codex/implementation-before-refusal.log`, and posts the refusal checkpoint with the discovered reason class.
- `grkr --issue <id>` stages only relevant non-`.grkr` files from the issue worktree and updates an existing branch PR when one is already open.
- `grkr --project <id>` treats per-issue failures as recoverable so the long-running watcher does not exit after one bad issue.
- `grkr --issue <id>` warns when the working directory is dirty, then continues so intentionally staged or unstaged local changes can be included.
- `grkr --issue <id>` now keeps per-issue checkpoint state under `.grkr/tasks/<issue-slug>/`, including `research.md`, `plan.md`, `implementation.log`, `test.md`, and `progress.json`; large implementation transcripts are sharded into `codex/implementation.log.parts/` with `implementation.log` left as the stable entrypoint.
- The issue helper posts the research, plan, and test checkpoint files as issue comments and reuses them on rerun when matching checkpoint markers already exist.
- The supervisor now records background issue jobs in `.grkr/state/active_jobs.json`, writes per-job logs under `.grkr/logs/jobs/`, and creates per-issue lock files when it schedules a selected Todo issue.
- On success, `progress.json` is updated to `complete` and records the branch URL plus PR URL for the finished issue workflow.
- During `cleanup_stale_worktrees`, the supervisor compacts processed comments, purges stale locks, and prunes old worktrees while skipping active jobs and task slugs with uncommitted refusal checkpoints (`refusal.md` or `progress.json` with `refuse`/`refused` before `implement_or_refuse.comment_id` is set); committed refusals may drop their worktrees per spec/parts/36.
- `grkr --issue <id>` mirrors its launcher log to the GitHub issue as a collapsed details block so the thread stays readable by default.
- Copy `.grkr/config.sh.example` to `.grkr/config.sh` and edit the values for your repo if you want to manage config manually.
- `grkr init <id>` will create `.grkr/config.sh` for the current `origin` remote and project id you pass in.
- `.grkr/tasks/`, `.grkr/state/`, `.grkr/locks/`, `.grkr/worktrees/`, `.grkr/logs/`, `.grkr/archive/` are local runtime state (populated by supervisor/workers per spec/parts/36-cleanup-policy.md) and ignored by git (see .gitignore); `.grkr/config.sh` and `.grkr/config.sh.example` stay tracked. Hygiene/audit in t_4f8b0fb5 + prior clean cards.

## Issue Providers

grkr supports multiple issue providers for selecting work:

### GitHub Projects (default)

The default provider uses GitHub Projects to select issues. Configure via `.grkr/config.sh`:

```bash
PROJECT_OWNER="owner-or-org"
PROJECT_NUMBER="12"
STATUS_FIELD_NAME="Status"
TODO_VALUE="Todo"
PRIORITY_FIELD_NAME="Priority"
PRIORITY_ORDER="P0,P1,P2,P3"
```

### Linear (experimental)

Set `GRKR_ISSUE_PROVIDER=linear` in your environment or `.grkr/config.sh` to use the Gleam-backed Linear issue selector. Fixture mode remains available for tests, and live Linear queries run only when an OAuth-derived access token is explicitly provided.

Configuration for Linear:

```bash
GRKR_ISSUE_PROVIDER="linear"
LINEAR_ASSIGNEE_ID="user-or-bot-id"
LINEAR_PROJECT_ID="optional-project-id"
LINEAR_TEAM_ID="optional-team-id"
LINEAR_TODO_STATE="Todo"
```

Linear credential setup:
1. Create or install a Linear OAuth app for grkr.
2. Store the OAuth app credentials in `~/.linear/secret.txt` as `client_id=...` and `client_secret=...` (`:` separators are also accepted).
3. Use the direct client_credentials grant (no browser interaction) to obtain an access token: curl -X POST https://api.linear.app/oauth/token -d "grant_type=client_credentials" -d "client_id=..." -d "client_secret=..." -d "scope=read write".
4. Store the access token at `~/.linear/token.txt` (or set `GRKR_LINEAR_TOKEN_PATH`), or set `GRKR_LINEAR_ACCESS_TOKEN` for the current run.
5. Do not use OAuth app credentials as a personal API key. grkr sends only the derived token with Linear's required bearer authorization header, never reads `~/.linear/secret.txt` as an API token, and redacts token values from client errors.

For fixture-backed selection, set `LINEAR_FIXTURE_PATH` to a JSON file containing Linear API response data. This slice returns shell-safe Linear issue metadata (`ISSUE_IDENTIFIER`, title, URL, state, priority, update time, job key, and task slug), but the supervisor only schedules executable work when a provider returns the GitHub `ISSUE_NUMBER` required by `grkr --issue`. Full Linear issue execution is still pending.

The Linear provider supports:
- Team and project-scoped issue queries
- Priority ordering (urgent, high, medium, low, none)
- State filtering (e.g., Todo, In Progress)
- Assignee filtering
- Live Linear GraphQL issue selection when `GRKR_LINEAR_ACCESS_TOKEN` contains an OAuth-derived access token
- Safe blocked output when no derived token is available, without treating OAuth app credentials as API tokens

### Linear Discovery Query CLI

The Linear issue provider includes safe, non-mutating discovery/query CLI subcommands for inspecting GraphQL queries without accessing Linear or using credentials:

```bash
# Print the viewer GraphQL query
gleam run -m grkr/issue_provider/main -- viewer-query

# Print the teams discovery query
gleam run -m grkr/issue_provider/main -- teams-query

# Print the project discovery query for a team
gleam run -m grkr/issue_provider/main -- team-projects-query <team-id>

# Print a single issue query by identifier
gleam run -m grkr/issue_provider/main -- issue-query <identifier>

# Print the assigned-issues query using current Linear config
gleam run -m grkr/issue_provider/main -- assigned-issues-query

# View usage by passing an invalid discovery subcommand
gleam run -m grkr/issue_provider/main -- help

# With no subcommand, keep the existing worker-pick-issue behavior:
# select a Linear issue and emit shell assignments.
gleam run -m grkr/issue_provider/main
```

These discovery commands:
- Print formatted GraphQL queries to stdout
- Never read or print credentials or tokens
- Never make HTTP requests to Linear
- Are safe for debugging, planning, and documentation
- Require minimal config (only `assigned-issues-query` needs `LINEAR_ASSIGNEE_ID` and `LINEAR_TODO_STATE`)

For example, to see what GraphQL would be generated for assigned issues:

```bash
LINEAR_ASSIGNEE_ID=user-123 LINEAR_TODO_STATE=Todo \
  gleam run -m grkr/issue_provider/main -- assigned-issues-query
```

## Linear E2E Tests

The project includes an opt-in Linear live e2e harness with its control flow implemented in Gleam under `src/grkr/linear/` and a thin shell wrapper at `test/e2e-linear-live.sh`.

### Features

- **OAuth credential parsing**: Reads Linear OAuth app credentials from `~/.linear/secret.txt` or `GRKR_LINEAR_SECRET_PATH`.
- **Credential redaction**: Never prints OAuth credentials or derived tokens in logs or test output.
- **GraphQL operation construction**: Builds viewer/project/team queries and mutation-backed temporary issue/comment/archive operations for the opt-in live e2e flow.
- **Opt-in testing**: Live tests are gated on `GRKR_LINEAR_E2E=1` and are not part of normal `npm test`, so the default suite never mutates Linear.
- **Clear blocker handling**: If only OAuth app credentials are available, the harness stops with an explicit access-token/OAuth-install blocker instead of treating app credentials as API tokens.

### Usage

```bash
# Run live Linear E2E tests (opt-in)
GRKR_LINEAR_E2E=1 bash test/e2e-linear-live.sh

# Run unit tests only (no Linear access required)
gleam test
# Includes refusal/cli_test + flow_test (GitHub-only v2) + 259 other modules
```

### Linear OAuth Setup

Live tests require Linear OAuth app credentials and an access token obtained through the OAuth flow.

#### Step 1: Create a Linear OAuth App

1. Go to your Linear workspace settings
2. Create a new OAuth application
3. Note the `client_id` and `client_secret`

#### Step 2: Store OAuth App Credentials

Store the OAuth app credentials in `~/.linear/secret.txt` (or set `GRKR_LINEAR_SECRET_PATH`):

```text
client_id=your_oauth_client_id
client_secret=your_oauth_client_secret
```

These are OAuth app credentials, not a personal API key. Never commit these values or use them directly as GraphQL tokens.

#### Step 3: Complete OAuth Installation and Token Exchange

3. Linear will redirect to your redirect URI with an authorization code
4. Exchange the authorization code for an access token

After completing the OAuth flow, store the access token in one of two ways:

**Option A: Store in default token location** (recommended):
```bash
# Store the token at ~/.linear/token.txt
mkdir -p ~/.linear
umask 077
printf '%s\n' "your_access_token_here" > ~/.linear/token.txt
```

**Option B: Store in custom location**:
```bash
# Set a custom token path
export GRKR_LINEAR_TOKEN_PATH=/path/to/your/token.txt
umask 077
printf '%s\n' "your_access_token_here" > /path/to/your/token.txt
```

**Option C: Use environment variable** (for one-off runs):
```bash
export GRKR_LINEAR_ACCESS_TOKEN=your_access_token_here
```

The harness checks locations in this order:
1. `GRKR_LINEAR_TOKEN_PATH` (or `~/.linear/token.txt` if not set)
2. `GRKR_LINEAR_ACCESS_TOKEN` environment variable

If no token is found, the harness exits with status 2 and reports the OAuth/access-token blocker without printing credential values.

Do not commit the token or put it in tracked config.

### E2E Test Behavior

When `GRKR_LINEAR_E2E=1` is set:
- The wrapper delegates to `gleam run -m grkr/linear/e2e_main`.
- The Gleam harness loads OAuth app credentials from `~/.linear/secret.txt` or `GRKR_LINEAR_SECRET_PATH`.
- If no token is available from `GRKR_LINEAR_TOKEN_PATH`, `~/.linear/token.txt`, or `GRKR_LINEAR_ACCESS_TOKEN`, the harness exits with status 2 and reports the OAuth/access-token blocker without printing credential values.
- If a derived token is provided, the harness performs live Linear checks through the Gleam Linear client path: it reads viewer/projects/teams, creates a clearly named temporary `grkr Linear live e2e temporary issue` in the first discovered team, reads that issue back, adds a `grkr:checkpoint:linear-live-e2e` checkpoint comment, and archives the temporary issue for cleanup. Output may include the temporary Linear issue URL and comment id, but never credentials or tokens.

When `GRKR_LINEAR_E2E` is not set or equals `0`:
- E2E tests are skipped entirely.
- Normal `npm test` runs without touching Linear.

## Requirements

- GitHub CLI (`gh`) installed and authenticated (`gh auth login`)
- Codex CLI available in PATH
- `jq` for JSON parsing
- Gleam compiler (for PR conflict resolution, Linear issue provider, and Linear E2E)
- Node.js (for global install and Gleam JavaScript target)
- Git repository with an `origin` remote configured
- Linear OAuth app credentials in `~/.linear/secret.txt` or `GRKR_LINEAR_SECRET_PATH` (optional, for Linear issue provider fixture/live-token setup and live E2E tests)

**Update for t_202da8aa (docs+sync after v2 phases + thin + review):**
- High-level snapshot refreshed with latest kanban cards: t_507df923 (robot-main thin 57LOC complete), t_35cbdf05 (supervisor/phases.gleam 284LOC), t_326501e8 (PR #79 review), t_e26dc010 (test fix), t_202da8aa (this docs+sync + lock clean)
- robot-main.sh now confirmed 57 LOC thin wrapper exec'ing Gleam supervisor
- Old build locks cleaned during this task
- Spec sync run, file size limit verified (<=1000 LOC)
- GitHub-only v2 workflow documented accurately for user (thin shells, Gleam supervisor run via robot-main.sh, GitHub project config)
- See docs/gleam-migration.md for full traceability

This keeps user-facing docs accurate per AGENTS.md after the recent functional slices.

**Update for t_9024ff95 (clean: audit + safe remove old .hermes/*.lock + build/*.lock + .grkr stale for GitHub-only v2):**
- Full audit of locks + .grkr (commands: ls -lT, stat, lsof, ps aux | grep, find, git status, grep in src/ for paths)
- Successfully removed (in workspace, no safety gate): .grkr/locks/ .grkr/logs/ .grkr/state/ .grkr/tasks/ .grkr/worktrees/ (stale May 21 untracked/empty runtime artifacts; v2 Gleam recreates as needed per config.gleam/lock.gleam; git status now clean for .grkr/)
- .gitignore updated: added .grkr/logs/ .grkr/state/ .grkr/locks/ .grkr/worktrees/ (alongside existing tasks/archive/)
- Proposed (safe, 0B unheld, verified no holders/processes): rm -f ~/.hermes/auth.lock ~/.hermes/memories/MEMORY.md.lock ~/.hermes/memories/USER.md.lock ~/.hermes/skills/.usage.json.lock
  (auth.lock for hermes auth.json; memory locks from memory_tool.py; usage lock; all confirmed stale/old via dates/lsof/code review)
- Left: gateway.lock (held by pid 859), cron/.tick.lock (recent active), build/gleam-*.lock + packages/gleam.lock (0B but touched at gleam lsp 8513 start 06:22, active), all package/yarn/uv locks, .grkr/archive/ + config* (historical, referenced in docs)
- Also noted legacy ~/.grkr/ (May 2 logs only) as candidate for manual clean
- Terminal safety gated the ~ deletes (pending_approval for home path); proposed commands + full verification (lsof/ps recheck, no breakage) recorded in kanban comments on this task (t_9024ff95)
- References: spec/parts/36-cleanup-policy.md (stale lock purge), AGENTS.md, prior cleanup cards (t_980b7473, t_4bb0bafc etc.), .grkr/audit-cleanup.md, docs/gleam-migration.md
- No impact on running gateway/kanban workers/gleam dev; fulfills cron "Clean any old locks" item
- README updated for user accuracy post-hygiene change

See kanban task t_9024ff95 comments for exact commands, output, and removed list.


**Update for t_32b4ad11 (cleanup: purge prep superseded kanban ws t_e2503a20 4.5M stale copy, GitHub-only v2):**
- Oriented via kanban_show(t_32b4ad11); read task body, AGENTS.md, spec/parts/36-cleanup-policy.md, .grkr/audit-cleanup.md (full recent entries incl t_78a7818e)
- Verified safety for purge of /Users/claw/.hermes/kanban/workspaces/t_e2503a20 (ls/du/lsof/ps/sqlite3 on kanban.db/git worktree/diff state.gleam): 4.5M, no procs, only historical db ref by its own blocked task, divergent stale snapshot (state.gleam older), active ws /work/grkr-v2-cron unaffected at same commit base
- Ran `gleam build` (clean 0.08s) + /bin/bash scripts/sync-spec.sh (no spec change, index 50 lines)
- Appended rich prep note with before/after commands, post-steps, metadata template to .grkr/audit-cleanup.md
- Added hygiene notes to docs/gleam-migration.md and this README.md per AGENTS.md + task acceptance (no functional change, just kanban hygiene reclaim prep)
- Per kanban-worker skill: terminal safety blocks rm -rf (as in t_980b7473); documented ready-to-run purge command in audit; will block this task with review-required
- No impact on active workspace, .git, builds, gateway, or other ws (t_7a26300d/t_d3a4d148 0B empties out of scope)
- ~4.5M reclaim targeted; part of GitHub-only v2 board cleanup (see t_075882be audit for full ~14MB plan)
- References: .grkr/audit-cleanup.md (detailed), kanban task t_32b4ad11, spec/parts/36 + 39, prior clean cards
- This keeps README accurate for user post-hygiene prep (no user-facing workflow change)

See .grkr/audit-cleanup.md for exact verification output, purge command, and handoff.

**Update for t_b45212c0 (e2e: validate github_picker thin wrapper + Gleam main; fixed wiring + title decode):**
- Full e2e validation of bin/worker-pick-issue.sh (thin 46 LOC) + gleam run -m grkr/github_picker/main (all modules: config/types/query/decoder/selector/field/priority/client + ffis)
- `gleam build` clean 0w (0.06s), `gleam test test/grkr/github_picker/` 258/258 pass
- test/worker-pick-issue.sh (3 scenarios) + GITHUB_FIXTURE_PATH runs now emit correct SELECTED/ISSUE_*/JOB_KEY/TASK_SLUG/PROJECT_ITEM_ID + full ISSUE_TITLE (with title words in slug)
- Fixed 2 small issues found in validation: 
  1. bin/worker-pick-issue.sh now exports config vars (set -a re-source after .grkr/config.sh) so Gleam FFI process.env gets REPO etc (was "Missing required" error in thin mode)
  2. decoder.gleam: title now direct decode_string (not field_text on primitive .title value) -- title was silently "", slugs fell back to "task"; now correct
- No contract changes, no README behavior update needed beyond this note; AGENTS.md followed (small, docs updated, <1000, explicit)
- See docs/gleam-migration.md for full e2e details + traceability to t_1c2663ae / t_f8eab5d9
- This keeps user-facing docs accurate per AGENTS.md after the functional fixes in v2 picker slice.

**Update for t_e2282d3f (fix: gleam build 0 warnings (workflow handle_comment WIP)):**

- Fixed last 2 warnings blocking clean `gleam build` (unused Option type import + unused WIP case value in handle_comment.gleam)
- `gleam build` now 0 warnings; 258 tests still pass
- Updated this README (traceability + stale LOC) + docs/gleam-migration.md; ran sync-spec (noop)
- No user-facing or functional changes (hygiene only, per AGENTS after edit)
- See docs/gleam-migration.md for full details

**Hygiene note for t_35a3cfc0 (2026-05-30 cleanup prep: auth.lock + 4 stale kanban ws + 18 .claude + git wt reg + new kanban.db.init.lock; review-required):**
- Re-audited current state (fresh ls/lsof/ps/git/gleam/sqlite per task steps 1-2; state evolved from May25 task body with new ws from later blocked tasks + init.lock).
- Appended full section to .grkr/audit-cleanup.md with 2026-05-30 outputs, prior blocked rm history (t_1c3c4a70 etc), updated proposed commands, verifs, handoff metadata.
- Ran scripts/sync-spec.sh (noop).
- Verified gleam build clean (0.06s), no LOC impact.
- Per AGENTS + task: docs + README updated for traceability (hygiene only); no user-facing impact.
- Prep complete; destructive exec blocked for human review (terminal safety precedent on rm in ~/.hermes/.claude paths).
- See .grkr/audit-cleanup.md (new t_35a3cfc0 section) + kanban comment for commands + evidence. GitHub-only v2 board hygiene.

This keeps README accurate per AGENTS for the cleanup lane hygiene card.
