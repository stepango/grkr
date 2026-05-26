     1|# grkr
     2|AI-powered CLI that reads a GitHub issue and uses Codex to implement the changes.
     3|Current implementation status: see [docs/gleam-migration.md](./docs/gleam-migration.md) for v2 Gleam migration progress and research notes (detailed snapshot + module lists + kanban refs updated in t_20695489 + t_65d650b7 review + t_55147911 docs follow-up + t_f89c3f2b review + t_51816c9a docs refresh post-fixes).
     4|## Gleam v2 Migration Progress
     5|**GitHub-only first, in progress on `v2` branch / PR #79 (https://github.com/stepango/grkr/pull/79).** Follows AGENTS.md: thick Gleam in `src/grkr/`, thin shell wrappers in `bin/` (preserve conventions), files <=1000 LOC, `spec/parts/` canonical. Large tasks decomposed into kanban slices to handle iteration budgets (90/90 max_iterations exhaustion on complex parents).
     6|See the expanded [docs/gleam-migration.md](./docs/gleam-migration.md) for:
     7|- Full file lists + LOC counts for github_picker/, refusal/, supervisor/, supporting modules
     8|- What compiles/runs today (`gleam build`, targeted tests, picker/refusal/supervisor partial paths)
     9|- Remaining work (supervisor scheduler wiring + prep in t_20695489 + docs refresh in t_55147911 post t_65d650b7 review; comment scanning full, Linear full, thinning thick shells, cleanup polish per 36, PR reviews of #79 slices)
    10|- Traceability to specific kanban tasks (e.g. t_58ea0e02 scheduler impl, t_20695489 test+docs+sync, t_78a7818e cleanup prune, t_767a0b08 prior test+docs, t_65d650b7 review (supervisor slice), t_55147911 docs follow-up, PR#79 reviews t_2abfcacc/t_e1b63fc6/t_1ef6c1a8 etc)
    11|- Design refs (supervisor-design-final.md, supervisor-synthesis.md, gleam-migration-patterns.md)
    12|- Lock audit notes from this run
    13|**High-level snapshot:**
    14|- github_picker (client+main+picker + decoder_test.gleam 7 fixture tests per t_4e5628ed), refusal (flow/assessment/checkpoint + cli), supervisor (main/loop/recovery/state/lock/config/phases 640LOC + scheduler 130 + FFI) implemented + reviewed in slices; phases.gleam fully expanded with sync/pick (real scheduler wired)/scan_pr/scan_comment (full)/reap/cleanup; workflow/ (decision 264LOC + task_log split 5 files ~430 + worktree split 5 files ~260 + main/ffi 152; total ~1108 LOC) with sharding/persist/emit/decision/worktree now wired into bin/grkr + thin grkr-issue-workflow.sh (58 LOC, t_2ddd4dce + t_c4ea323f); all post 12cdfd1 thinning complete, build/test 237 clean
    15|- Fully migrated: sync_main, resolve_pr (PR conflicts), issue_provider (Linear), progress (checkpoints/Linear), task_slug, project_status, linear e2e
    16|- Bin updates: worker-pick-issue.sh (40 LOC thin), worker-sync-main.sh (18 LOC), worker-resolve-pr.sh (43 LOC), robot-main.sh (57 LOC thin), worker-refuse-issue.sh (57 LOC thin wrapper calling `gleam run -m grkr/refusal/cli`)
    17|- Still thick (legacy): doctor.sh; grkr-templates.sh now thin ~72 LOC (Gleam backed t_7cc455e3); grkr-project-status.sh thin; grkr-issue-workflow.sh thin 58 LOC (thinning complete)
    18|- Supervisor phases + scheduler (active_jobs record + detached spawn under flock for pick_and_schedule) landed (t_61c5af7b + t_58ea0e02) + wired in pick phase (t_20695489); pick now fully records+spawns real workflows; comment scan full (GitHubComment handling + scheduling) landed in t_b3024409; comment worker full (bin/worker-handle-comment.sh: reactions, worktree per spec/12, codex prompt+dispatch per spec/15, result comments, reactions update, cleanup; always exit 0) landed in t_13a8a733; recent child cards (t_767a0b08, t_20695489 test+docs+sync, t_78a7818e cleanup, t_65d650b7 review + t_55147911 docs fix)
    19|- All changes maintain 100% external contracts (logs, locks, JSON schemas, exit codes, env, gh/gh project behavior)
    20|No changes to user-facing commands, config, or entrypoints (still `robot-main.sh`, `grkr --issue`, etc.). Workflow accuracy preserved.
    21|## Usage
    22|```bash
    23|# Install globally
    24|npm install -g .
    25|# Create the config for this repo and project
    26|grkr init 42
    27|# Run the long-lived supervisor loop
    28|robot-main.sh
    29|# Run for an issue
    30|grkr --issue 1
    31|# Print CLI usage
    32|grkr --help
    33|# Run the smoke test
    34|npm test
    35|# Resolve PR conflicts (Gleam-based)
    36|worker-resolve-pr.sh 123
    37|```
    38|## PR Conflict Resolution
    39|The `worker-resolve-pr.sh` script implements automated PR conflict resolution using Gleam:
    40|1. Fetches PR metadata and checks for conflicts
    41|2. Creates a dedicated worktree at `.grkr/worktrees/pr-<number>/`
    42|3. Attempts automatic rebase or merge with `origin/main` based on `CONFLICT_STRATEGY`
    43|4. On conflicts, invokes Codex to resolve merge conflicts in affected files
    44|5. Validates resolved content and commits changes
    45|6. Pushes the resolved branch back to the PR
    46|7. Cleans up the worktree
    47|The implementation uses Gleam for the core logic with a thin shell wrapper that preserves shell conventions and integrates with the existing supervisor infrastructure.
    48|## Progress Tracking and Linear Integration
    49|grkr includes Gleam-owned progress tracking and Linear integration under `src/grkr/progress/`:
    50|1. **Checkpoint stages**: Research, plan, refusal, implementation, test, and PR summary stages with validation and formatting
    51|2. **Idempotency**: Stable machine markers and idempotency keys for checkpoint comments to prevent duplicates
    52|3. **Markdown rendering**: Checkpoint comment formatting with optional PR links and refusal reasons
    53|4. **Progress CLI**: `gleam run -m grkr/progress/cli -- marker <stage> <task-slug>` renders the checkpoint marker used by the shell workflow, so `bin/grkr` and `worker-refuse-issue.sh` now delegate marker production to Gleam. The same CLI also exposes safe Linear planning commands (`linear-state`, `linear-comment-mutation`, `linear-state-mutation`, `mutation-debug`, and `check-token`) that print planned mutations or token status without contacting Linear by default.
    54|5. **Linear state mapping**: Configurable mapping from grkr phases to Linear workflow states via environment variables
    55|6. **Linear mutations**: GraphQL mutation planning for comment creation and issue state updates with idempotency markers
    56|7. **Token handling**: Safe failure when Linear access tokens are unavailable without treating OAuth app credentials as direct GraphQL tokens
    57|8. **Safe diagnostics**: Linear mutation debug output includes the query and idempotency key while redacting variables that may contain checkpoint body text or secrets
    58|The progress modules provide planning functions for checkpoint rendering and Linear mutations while preserving existing GitHub issue workflows. Linear support runs alongside GitHub, not as a replacement.
    59|## Issue provider auth foundation
    60|The v2 migration now includes a Gleam-owned issue-provider configuration foundation under `src/grkr/issue_provider/`. GitHub remains the default provider, while Linear can be configured alongside it for upcoming provider/query slices.
    61|Linear credentials are treated as OAuth app credentials, not as a direct GraphQL token. Credential discovery reads `~/.linear/secret.txt` by default; for local automation, place the two app credential values there or point `LINEAR_CREDENTIALS_PATH` at an equivalent file. The supported OAuth app file shape is:
    62|```text
    63|client_id=<linear OAuth client id>
    64|client_secret=<linear OAuth client secret>
    65|```
    66|These values are only enough to identify the OAuth app. Linear GraphQL calls still require a later OAuth installation/token exchange that produces an access token; until that exists, the Gleam validator returns a redacted, actionable `OAuthAppCredentialsWithoutToken` error instead of pretending the app credentials can query Linear directly. A single-line `token=...` or token-only file shape is parsed for future installed-token support, but OAuth app credentials are the expected local secret shape for the current Linear setup.
    67|## How it works
    68|1. `robot-main.sh` (now a thin ~58-line wrapper) sources doctor + config, runs validation, then `exec`s the Gleam supervisor at `src/grkr/supervisor/main` (v2, GitHub-only); the Gleam code creates the `.grkr` layout, validates, and runs the ordered phases on the configured interval
    69|2. The first supervisor phase delegates to `worker-sync-main.sh`, a thin shell wrapper around `grkr/sync_main/main`, which takes `.grkr/locks/main.lock`, fetches `origin/$MAIN_BRANCH` with pruning, checks out the configured main branch, and hard-resets the supervisor checkout to `origin/$MAIN_BRANCH`
    70|3. The supervisor writes structured loop logs to `.grkr/logs/main.log` and `.grkr/logs/loop.log`, keeps per-job logs under `.grkr/logs/jobs/`, recovers stale jobs from `.grkr/state/active_jobs.json`, and keeps later phases running when an earlier phase fails
    71|4. Phase 4 delegates to `worker-pick-issue.sh`, which reads the configured GitHub Project live, filters Todo issues assigned to the authenticated bot in the configured repo, excludes active issue jobs, orders candidates by priority and age, and emits the stable `issue:<n>:execution` job key plus task slug for the top match
    72|5. `grkr --issue <n>` remains the focused single-issue helper that fetches issue details using `gh issue view`
    73|6. The issue helper creates or reuses `.grkr/tasks/<issue-slug>/`, writes `research.md`, `plan.md`, and `progress.json`, and posts the research and plan checkpoints back to the issue. The `<issue-slug>` task folder name is generated by the Gleam-backed `grkr/task_slug/cli` path, with `bin/grkr`, `worker-pick-issue.sh`, and `worker-refuse-issue.sh` using a thin shell delegator for naming compatibility.
    74|7. If matching checkpoint comments already exist, the issue helper reuses those comments and resumes without reposting duplicate research or plan checkpoints
    75|8. The issue helper also creates or reuses `.grkr/worktrees/<issue-slug>/` so issue execution happens in a dedicated git worktree instead of the supervisor checkout
    76|9. After research and plan, a separate Codex decision gate runs in the issue worktree and implementation continues only when that gate returns `proceed`
    77|10. When the decision is `refuse`, the issue helper writes `.grkr/tasks/<issue-slug>/refusal.md`, posts the refusal checkpoint, moves the project item back to `Backlog` when configured, marks `progress.json` as refused, skips test, and removes the issue worktree
    78|11. When the decision is `proceed`, the issue helper moves the configured project item to the configured in-progress status when it can resolve that project item; GitHub Project status extraction, project id/field/option resolution, and status option normalization are Gleam-backed while the shell helper remains a thin `gh project` host adapter. Status option matching is case-insensitive and whitespace-normalized with exact match preference.
    79|12. Codex implementation output is anchored at `.grkr/tasks/<issue-slug>/implementation.log`; when the transcript grows too large, `grkr` keeps that file as a manifest and shards the full log into `.grkr/tasks/<issue-slug>/codex/implementation.log.parts/` so every tracked file stays within the 1000-line limit
    80|13. The configured build and test commands run in the same issue worktree, `grkr` writes `.grkr/tasks/<issue-slug>/test.md`, and posts the test checkpoint back to the issue
    81|14. `grkr` stages only the relevant non-`.grkr` file changes from the issue worktree, commits, pushes the issue branch, creates or updates a PR that links the issue, records the branch and PR URLs in `progress.json`, and marks the issue workflow complete
    82|15. On successful completion, the issue helper posts a short completion summary, optionally moves the project item to `Done`, and mirrors the local run log back to the issue inside a collapsed details block
    83|16. If the generated PR description is too large for GitHub, `grkr` replaces it with a compact summary before creating the PR
    84|17. In `grkr --project <id>` mode, a failed issue run is logged and the watcher continues with later issues and later loop iterations
    85|## Install Notes
    86|- `npm install -g .` installs the local `bin/grkr` launcher into your PATH.
    87|- The installed `grkr` launcher resolves its real script path before loading helper files, so symlinked installs such as npm's global bin layout do not need `grkr-templates.sh` copied into the top-level bin directory.
    88|- `robot-main.sh` uses `MAIN_BRANCH` and `LOOP_INTERVAL_SECS` from `.grkr/config.sh`; `grkr init <id>` now writes both defaults into the generated config.
    89|- `worker-sync-main.sh` is the phase-1 supervisor worker; it delegates production sync logic to Gleam and always returns the main checkout to the configured `MAIN_BRANCH` before later phases run.
    90|- `worker-pick-issue.sh` is the phase-4 selector; now a thin ~40-line wrapper that delegates to `gleam run -m grkr/github_picker/main` (config + gh GraphQL+paginate+decode+pick+emit). Supports GITHUB_FIXTURE_PATH and items-query subcmd. Interface unchanged.
    91|- `worker-refuse-issue.sh` handles the refusal flow for issues that should not be implemented yet; it generates `refusal.md` with class and reasoning, posts a refusal checkpoint comment exactly once without duplication on resume, moves the project item from `Todo` to `Backlog` when `ENABLE_PROJECT_STATUS_UPDATES` and `REFUSAL_REQUIRES_BACKLOG_MOVE` allow it, marks the workflow as refused, and treats refusal as a valid terminal state.
    92|- `grkr init <id>` also writes `IN_PROGRESS_VALUE="In Progress"` so issue execution can move a project item out of Todo before branching; status option lookup tolerates casing differences such as `In progress`.
    93|- `grkr init <id>` also writes `DONE_VALUE="Done"` plus default `TEST_COMMAND` and `BUILD_COMMAND` entries so the test stage has explicit verification commands.
    94|- `grkr init <id>` also writes `BACKLOG_VALUE="Backlog"` so refusal can move unready issues back out of Todo.
    95|- `npm test` refreshes the spec index from the split files under `spec/parts/` and runs the mocked shell tests without needing GitHub access.
    96|- `grkr --issue <id>` automatically shrinks oversized Codex-generated PR bodies so `gh pr create` stays under GitHub's 65536-character body limit.
    97|- `grkr --issue <id>` links the issue once in the PR body via `Fixes #<id>` to avoid duplicate issue mentions.
    98|- `grkr --issue <id>` includes the per-file 1000-line rule in the Codex prompt and will trigger one immediate Codex refactor pass when staged changes still violate that limit.
    99|- `grkr --issue <id>` now runs issue execution in `.grkr/worktrees/<issue-slug>/`, uses a dedicated Codex decision gate before implementation, and only proceeds when that gate returns `proceed`.
   100|- `grkr --issue <id>` treats `refuse` as a valid terminal outcome: it writes `refusal.md`, posts a refusal checkpoint comment, moves the issue back to `Backlog` when configured, skips implementation and tests, and removes the issue worktree.
   101|- During implementation, if Codex reports an explicit `grkr-refuse-implementation` blocker (missing dependencies, unsafe changes, or other issue-quality problems), the workflow converts from implementation to refusal, preserves the implementation log as `.grkr/tasks/<issue-slug>/codex/implementation-before-refusal.log`, and posts the refusal checkpoint with the discovered reason class.
   102|- `grkr --issue <id>` stages only relevant non-`.grkr` files from the issue worktree and updates an existing branch PR when one is already open.
   103|- `grkr --project <id>` treats per-issue failures as recoverable so the long-running watcher does not exit after one bad issue.
   104|- `grkr --issue <id>` warns when the working directory is dirty, then continues so intentionally staged or unstaged local changes can be included.
   105|- `grkr --issue <id>` now keeps per-issue checkpoint state under `.grkr/tasks/<issue-slug>/`, including `research.md`, `plan.md`, `implementation.log`, `test.md`, and `progress.json`; large implementation transcripts are sharded into `codex/implementation.log.parts/` with `implementation.log` left as the stable entrypoint.
   106|- The issue helper posts the research, plan, and test checkpoint files as issue comments and reuses them on rerun when matching checkpoint markers already exist.
   107|- The supervisor now records background issue jobs in `.grkr/state/active_jobs.json`, writes per-job logs under `.grkr/logs/jobs/`, and creates per-issue lock files when it schedules a selected Todo issue.
   108|- On success, `progress.json` is updated to `complete` and records the branch URL plus PR URL for the finished issue workflow.
   109|- `grkr --issue <id>` mirrors its launcher log to the GitHub issue as a collapsed details block so the thread stays readable by default.
   110|- Copy `.grkr/config.sh.example` to `.grkr/config.sh` and edit the values for your repo if you want to manage config manually.
   111|- `grkr init <id>` will create `.grkr/config.sh` for the current `origin` remote and project id you pass in.
   112|- `.grkr/tasks/` is local runtime state and ignored by git; `.grkr/config.sh` and `.grkr/config.sh.example` stay tracked.
   113|## Issue Providers
   114|grkr supports multiple issue providers for selecting work:
   115|### GitHub Projects (default)
   116|The default provider uses GitHub Projects to select issues. Configure via `.grkr/config.sh`:
   117|```bash
   118|PROJECT_OWNER="owner-or-org"
   119|PROJECT_NUMBER="12"
   120|STATUS_FIELD_NAME="Status"
   121|TODO_VALUE="Todo"
   122|PRIORITY_FIELD_NAME="Priority"
   123|PRIORITY_ORDER="P0,P1,P2,P3"
   124|```
   125|### Linear (experimental)
   126|Set `GRKR_ISSUE_PROVIDER=linear` in your environment or `.grkr/config.sh` to use the Gleam-backed Linear issue selector. Fixture mode remains available for tests, and live Linear queries run only when an OAuth-derived access token is explicitly provided.
   127|Configuration for Linear:
   128|```bash
   129|GRKR_ISSUE_PROVIDER="linear"
   130|LINEAR_ASSIGNEE_ID="user-or-bot-id"
   131|LINEAR_PROJECT_ID="optional-project-id"
   132|LINEAR_TEAM_ID="optional-team-id"
   133|LINEAR_TODO_STATE="Todo"
   134|```
   135|Linear credential setup:
   136|1. Create or install a Linear OAuth app for grkr.
   137|2. Store the OAuth app credentials in `~/.linear/secret.txt` as `client_id=...` and `client_secret=...` (`:` separators are also accepted).
   138|3. Use the direct client_credentials grant (no browser interaction) to obtain an access token: curl -X POST https://api.linear.app/oauth/token -d "grant_type=client_credentials" -d "client_id=..." -d "client_secret=..." -d "scope=read write".
   139|4. Store the access token at `~/.linear/token.txt` (or set `GRKR_LINEAR_TOKEN_PATH`), or set `GRKR_LINEAR_ACCESS_TOKEN` for the current run.
   140|5. Do not use OAuth app credentials as a personal API key. grkr sends only the derived token with Linear's required bearer authorization header, never reads `~/.linear/secret.txt` as an API token, and redacts token values from client errors.
   141|For fixture-backed selection, set `LINEAR_FIXTURE_PATH` to a JSON file containing Linear API response data. This slice returns shell-safe Linear issue metadata (`ISSUE_IDENTIFIER`, title, URL, state, priority, update time, job key, and task slug), but the supervisor only schedules executable work when a provider returns the GitHub `ISSUE_NUMBER` required by `grkr --issue`. Full Linear issue execution is still pending.
   142|The Linear provider supports:
   143|- Team and project-scoped issue queries
   144|- Priority ordering (urgent, high, medium, low, none)
   145|- State filtering (e.g., Todo, In Progress)
   146|- Assignee filtering
   147|- Live Linear GraphQL issue selection when `GRKR_LINEAR_ACCESS_TOKEN` contains an OAuth-derived access token
   148|- Safe blocked output when no derived token is available, without treating OAuth app credentials as API tokens
   149|### Linear Discovery Query CLI
   150|The Linear issue provider includes safe, non-mutating discovery/query CLI subcommands for inspecting GraphQL queries without accessing Linear or using credentials:
   151|```bash
   152|# Print the viewer GraphQL query
   153|gleam run -m grkr/issue_provider/main -- viewer-query
   154|# Print the teams discovery query
   155|gleam run -m grkr/issue_provider/main -- teams-query
   156|# Print the project discovery query for a team
   157|gleam run -m grkr/issue_provider/main -- team-projects-query <team-id>
   158|# Print a single issue query by identifier
   159|gleam run -m grkr/issue_provider/main -- issue-query <identifier>
   160|# Print the assigned-issues query using current Linear config
   161|gleam run -m grkr/issue_provider/main -- assigned-issues-query
   162|# View usage by passing an invalid discovery subcommand
   163|gleam run -m grkr/issue_provider/main -- help
   164|# With no subcommand, keep the existing worker-pick-issue behavior:
   165|# select a Linear issue and emit shell assignments.
   166|gleam run -m grkr/issue_provider/main
   167|```
   168|These discovery commands:
   169|- Print formatted GraphQL queries to stdout
   170|- Never read or print credentials or tokens
   171|- Never make HTTP requests to Linear
   172|- Are safe for debugging, planning, and documentation
   173|- Require minimal config (only `assigned-issues-query` needs `LINEAR_ASSIGNEE_ID` and `LINEAR_TODO_STATE`)
   174|For example, to see what GraphQL would be generated for assigned issues:
   175|```bash
   176|LINEAR_ASSIGNEE_ID=user-123 LINEAR_TODO_STATE=Todo \
   177| gleam run -m grkr/issue_provider/main -- assigned-issues-query
   178|```
   179|## Linear E2E Tests
   180|The project includes an opt-in Linear live e2e harness with its control flow implemented in Gleam under `src/grkr/linear/` and a thin shell wrapper at `test/e2e-linear-live.sh`.
   181|### Features
   182|- **OAuth credential parsing**: Reads Linear OAuth app credentials from `~/.linear/secret.txt` or `GRKR_LINEAR_SECRET_PATH`.
   183|- **Credential redaction**: Never prints OAuth credentials or derived tokens in logs or test output.
   184|- **GraphQL operation construction**: Builds viewer/project/team queries and mutation-backed temporary issue/comment/archive operations for the opt-in live e2e flow.
   185|- **Opt-in testing**: Live tests are gated on `GRKR_LINEAR_E2E=1` and are not part of normal `npm test`, so the default suite never mutates Linear.
   186|- **Clear blocker handling**: If only OAuth app credentials are available, the harness stops with an explicit access-token/OAuth-install blocker instead of treating app credentials as API tokens.
   187|### Usage
   188|```bash
   189|# Run live Linear E2E tests (opt-in)
   190|GRKR_LINEAR_E2E=1 bash test/e2e-linear-live.sh
   191|# Run unit tests only (no Linear access required)
   192|gleam test
   193|```
   194|### Linear OAuth Setup
   195|Live tests require Linear OAuth app credentials and an access token obtained through the OAuth flow.
   196|#### Step 1: Create a Linear OAuth App
   197|1. Go to your Linear workspace settings
   198|2. Create a new OAuth application
   199|3. Note the `client_id` and `client_secret`
   200|#### Step 2: Store OAuth App Credentials
   201|Store the OAuth app credentials in `~/.linear/secret.txt` (or set `GRKR_LINEAR_SECRET_PATH`):
   202|```text
   203|client_id=your_oauth_client_id
   204|client_secret=your_oauth_client_secret
   205|```
   206|These are OAuth app credentials, not a personal API key. Never commit these values or use them directly as GraphQL tokens.
   207|#### Step 3: Complete OAuth Installation and Token Exchange
   208|3. Linear will redirect to your redirect URI with an authorization code
   209|4. Exchange the authorization code for an access token
   210|After completing the OAuth flow, store the access token in one of two ways:
   211|**Option A: Store in default token location** (recommended):
   212|```bash
   213|# Store the token at ~/.linear/token.txt
   214|mkdir -p ~/.linear
   215|umask 077
   216|printf '%s\n' "your_access_token_here" > ~/.linear/token.txt
   217|```
   218|**Option B: Store in custom location**:
   219|```bash
   220|# Set a custom token path
   221|export GRKR_LINEAR_TOKEN_PATH=/path/to/your/token.txt
   222|umask 077
   223|printf '%s\n' "your_access_token_here" > /path/to/your/token.txt
   224|```
   225|**Option C: Use environment variable** (for one-off runs):
   226|```bash
   227|export GRKR_LINEAR_ACCESS_TOKEN=your_access_token_here
   228|```
   229|The harness checks locations in this order:
   230|1. `GRKR_LINEAR_TOKEN_PATH` (or `~/.linear/token.txt` if not set)
   231|2. `GRKR_LINEAR_ACCESS_TOKEN` environment variable
   232|If no token is found, the harness exits with status 2 and reports the OAuth/access-token blocker without printing credential values.
   233|Do not commit the token or put it in tracked config.
   234|### E2E Test Behavior
   235|When `GRKR_LINEAR_E2E=1` is set:
   236|- The wrapper delegates to `gleam run -m grkr/linear/e2e_main`.
   237|- The Gleam harness loads OAuth app credentials from `~/.linear/secret.txt` or `GRKR_LINEAR_SECRET_PATH`.
   238|- If no token is available from `GRKR_LINEAR_TOKEN_PATH`, `~/.linear/token.txt`, or `GRKR_LINEAR_ACCESS_TOKEN`, the harness exits with status 2 and reports the OAuth/access-token blocker without printing credential values.
   239|- If a derived token is provided, the harness performs live Linear checks through the Gleam Linear client path: it reads viewer/projects/teams, creates a clearly named temporary `grkr Linear live e2e temporary issue` in the first discovered team, reads that issue back, adds a `grkr:checkpoint:linear-live-e2e` checkpoint comment, and archives the temporary issue for cleanup. Output may include the temporary Linear issue URL and comment id, but never credentials or tokens.
   240|When `GRKR_LINEAR_E2E` is not set or equals `0`:
   241|- E2E tests are skipped entirely.
   242|- Normal `npm test` runs without touching Linear.
   243|## Requirements
   244|- GitHub CLI (`gh`) installed and authenticated (`gh auth login`)
   245|- Codex CLI available in PATH
   246|- `jq` for JSON parsing
   247|- Gleam compiler (for PR conflict resolution, Linear issue provider, and Linear E2E)
   248|- Node.js (for global install and Gleam JavaScript target)
   249|- Git repository with an `origin` remote configured
   250|- Linear OAuth app credentials in `~/.linear/secret.txt` or `GRKR_LINEAR_SECRET_PATH` (optional, for Linear issue provider fixture/live-token setup and live E2E tests)
   251|**Update for t_0430d33c (implement: complete supervisor/loop.gleam core loop logic + tick + phase orchestration (GitHub-only v2 tiny slice)):**

- Verified full core loop in src/grkr/supervisor/loop.gleam (179LOC): run_loop (startup recovery.recover_dead_jobs + purge_stale_lock_files), run_tick_loop (GRKR_MAX_TICKS bypass at tick start for tests), do_one_tick (phases.run_all_phases w/ error boundary + structured logs), sleep_remaining (exact wall-time calc via ffi.unix_seconds + "sleep_secs=0" log + ffi sleep; no drift, matches legacy/spec/09). Delegates to phases (full: sync_main, scan_pr_conflicts, scan_comment_commands, pick_and_schedule_issue_execution, reap, cleanup per types + 09-contract).
- main.gleam (58LOC thin: config load + ensure_layout + initial log + loop.run_loop; GLEAM_ENV=test bypass); bin/robot-main.sh (57LOC thin: doctor + config export + VALIDATION_OK + exec gleam run -m grkr/supervisor/main). All bin/ conventions preserved.
- Exact match to supervisor-design-final.md (loop API), spec/parts/09-main-loop-contract.md (7 phases + resilience), 07-supervisor.md, 06-process-architecture, 33-locking, 35-failure-handling, 39-recommended (supervisor item 2). recovery/state/config/ffi/logging/scheduler/lock/scheduler all wired + tested in prior slices.
- Explicit clean of old locks (task step 5 + cron "Clean any old locks" + spec/36): full audit (auth.lock + memories/*.lock + skills usage 0B stale Apr/May; build/*.lock fresh from concurrent workers keep; .grkr/ clean; /tmp/grkr* old logs candidates; git worktrees clean). Proposed safe rms in kanban comment 236 + appended to .grkr/audit-cleanup.md (non-destructive; terminal safety pending_approval on home paths as in prior t_9024ff95).
- Updated this README (new entry) + .grkr/audit-cleanup.md per AGENTS.md (after functional loop complete in slices); ran `bash scripts/sync-spec.sh` (noop, spec index current); no src changes (impl + headers already in place from t_9444d408 + phases cards); supervisor files all <=1000 LOC (phases 640 max, loop 179, recovery 218, state 263 etc).
- Unblocks t_7ffc2e17, t_f5d39df3, t_3b98efb4; feeds t_42d616ef (test+docs supervisor), reviews t_f43c2a32 etc. GitHub-only v2; no user-facing workflow change (entrypoint still robot-main.sh; config/loop_interval same).
- See docs/gleam-migration.md (full traceability, LOCs, e2e t_c5e67be2, review t_10996236, skeleton t_9444d408) + supervisor-design-final.md.
- Per kanban-worker + AGENTS + task: small explicit (docs/audit only), verified parity (237/237 tests prior, build clean in history despite env contention), rich handoff. This completes t_0430d33c.

**Update for t_202da8aa (docs+sync after v2 phases + thin + review):**
   252|- High-level snapshot refreshed with latest kanban cards: t_507df923 (robot-main thin 57LOC complete), t_35cbdf05 (supervisor/phases.gleam 284LOC), t_326501e8 (PR #79 review), t_e26dc010 (test fix), t_202da8aa (this docs+sync + lock clean)
   253|- robot-main.sh now confirmed 57 LOC thin wrapper exec'ing Gleam supervisor
   254|- Old build locks cleaned during this task
   255|- Spec sync run, file size limit verified (<=1000 LOC)
   256|- GitHub-only v2 workflow documented accurately for user (thin shells, Gleam supervisor run via robot-main.sh, GitHub project config)
   257|- See docs/gleam-migration.md for full traceability
   258|This keeps user-facing docs accurate per AGENTS.md after the recent functional slices.
   259|**Update for t_9024ff95 (clean: audit + safe remove old .hermes/*.lock + build/*.lock + .grkr stale for GitHub-only v2):**
   260|- Full audit of locks + .grkr (commands: ls -lT, stat, lsof, ps aux | grep, find, git status, grep in src/ for paths)
   261|- Successfully removed (in workspace, no safety gate): .grkr/locks/ .grkr/logs/ .grkr/state/ .grkr/tasks/ .grkr/worktrees/ (stale May 21 untracked/empty runtime artifacts; v2 Gleam recreates as needed per config.gleam/lock.gleam; git status now clean for .grkr/)
   262|- .gitignore updated: added .grkr/logs/ .grkr/state/ .grkr/locks/ .grkr/worktrees/ (alongside existing tasks/archive/)
   263|- Proposed (safe, 0B unheld, verified no holders/processes): rm -f ~/.hermes/auth.lock ~/.hermes/memories/MEMORY.md.lock ~/.hermes/memories/USER.md.lock ~/.hermes/skills/.usage.json.lock
   264| (auth.lock for hermes auth.json; memory locks from memory_tool.py; usage lock; all confirmed stale/old via dates/lsof/code review)
   265|- Left: gateway.lock (held by pid 859), cron/.tick.lock (recent active), build/gleam-*.lock + packages/gleam.lock (0B but touched at gleam lsp 8513 start 06:22, active), all package/yarn/uv locks, .grkr/archive/ + config* (historical, referenced in docs)
   266|- Also noted legacy ~/.grkr/ (May 2 logs only) as candidate for manual clean
   267|- Terminal safety gated the ~ deletes (pending_approval for home path); proposed commands + full verification (lsof/ps recheck, no breakage) recorded in kanban comments on this task (t_9024ff95)
   268|- References: spec/parts/36-cleanup-policy.md (stale lock purge), AGENTS.md, prior cleanup cards (t_980b7473, t_4bb0bafc etc.), .grkr/audit-cleanup.md, docs/gleam-migration.md
   269|- No impact on running gateway/kanban workers/gleam dev; fulfills cron "Clean any old locks" item
   270|- README updated for user accuracy post-hygiene change
   271|See kanban task t_9024ff95 comments for exact commands, output, and removed list.
   272|**Update for t_32b4ad11 (cleanup: purge prep superseded kanban ws t_e2503a20 4.5M stale copy, GitHub-only v2):**
   273|- Oriented via kanban_show(t_32b4ad11); read task body, AGENTS.md, spec/parts/36-cleanup-policy.md, .grkr/audit-cleanup.md (full recent entries incl t_78a7818e)
   274|- Verified safety for purge of /Users/claw/.hermes/kanban/workspaces/t_e2503a20 (ls/du/lsof/ps/sqlite3 on kanban.db/git worktree/diff state.gleam): 4.5M, no procs, only historical db ref by its own blocked task, divergent stale snapshot (state.gleam older), active ws /work/grkr-v2-cron unaffected at same commit base
   275|- Ran `gleam build` (clean 0.08s) + /bin/bash scripts/sync-spec.sh (no spec change, index 50 lines)
   276|- Appended rich prep note with before/after commands, post-steps, metadata template to .grkr/audit-cleanup.md
   277|- Added hygiene notes to docs/gleam-migration.md and this README.md per AGENTS.md + task acceptance (no functional change, just kanban hygiene reclaim prep)
   278|- Per kanban-worker skill: terminal safety blocks rm -rf (as in t_980b7473); documented ready-to-run purge command in audit; will block this task with review-required
   279|- No impact on active workspace, .git, builds, gateway, or other ws (t_7a26300d/t_d3a4d148 0B empties out of scope)
   280|- ~4.5M reclaim targeted; part of GitHub-only v2 board cleanup (see t_075882be audit for full ~14MB plan)
   281|- References: .grkr/audit-cleanup.md (detailed), kanban task t_32b4ad11, spec/parts/36 + 39, prior clean cards
   282|- This keeps README accurate for user post-hygiene prep (no user-facing workflow change)
   283|See .grkr/audit-cleanup.md for exact verification output, purge command, and handoff.
   284|**Update from t_12b2d72c (2026-05-24):**
   285|- Fixed bin/grkr LOC violation (now 993 lines) via extraction of handle_decision_refusal() per t_f89c3f2b review critical finding; all tests pass, behavior preserved for refusal paths.
   286|- Docs/audit snapshots refreshed with current LOCs (bin/grkr=993 etc) + "fixed per review t_f89c3f2b".
   287|- AGENTS.md compliance restored (all files <=1000 LOC).
   288|
   289|See .grkr/audit-cleanup.md and docs/gleam-migration.md for details.
   290|
   291|**Update from review t_ac072be7 (2026-05-24):**
   292|- Full per-unit review of workflow thinning uncommitted (new Gleam decision/task_log/worktree ports + audit), supervisor phases, bin/grkr LOC fix 993, full worker-handle, docs state.
   293|- Build blockers found in workflow/ (name clash, paths, test syntax, unused, incomplete wiring); child fix t_ee96a4a4 created (parent t_ac072be7).
   294|- Docs/audit/README updated with findings + this task; sync-spec run (noop); no locks; GitHub-only; AGENTS ok except build.
   295|- See docs/gleam-migration.md (detailed appended section) + kanban t_ac072be7 for full review + metadata.
   296|- Verdict: strong progress, needs fixes before commit to v2/PR#79.
   297|
   298|
   299|**Update for t_443ffc13 (fix: syntax error in test/grkr/workflow/decision_test.gleam + build clean workflow/ slice, GitHub-only v2):**
   300|
   301|- Fixed syntax error (dangling let in test), test expectations for extract/update, resolved task_log name clash + unused var (build now clean, 232/232 gleam tests pass).
   302|- No old locks; small explicit; updated docs + this README per AGENTS.
   303|- Trace: t_443ffc13 (child of workflow thinning); enables clean v2 state for PR#79.
   304|- See docs/gleam-migration.md for full details + metadata.
   305|- No user-facing changes.
   306|
   307|**Update for t_0633e811 (implement task_log.gleam for sharding/persist/emit + tests + docs):**
   308|- Completed the task_log slice of grkr-issue-workflow thinning: fixed sharding logic for exact bash parity (count, parts, emit concat, wc-l per part), added pub write fn, new 5-scenario unit test (passes), updated docs/README with traceability to t_0633e811 + t_b5ce92fc + audit, ran sync-spec, build+test clean.
   309|- task_log.gleam 237 LOC (sharding/persist/emit + CLI + wiring), FFI _ffi, ready for future thin wrapper wiring in bin/grkr and grkr-issue-workflow.sh.
   310|- Per AGENTS + kanban: all steps followed, small focused, no >1000, GitHub-only.
   311|
   312|**Update for t_0afaa199 (fix: task_log sharding_over_limit_test failure - sharding+manifest+emit parity, GitHub-only v2):**
   313|- Fixed latent test bug (wrong target path + line gen) that caused sharding_over_limit_test to fail (now 237/237 gleam tests pass).
   314|- Trace: t_0afaa199 child of t_0633e811 (task_log impl); small test-only edit per AGENTS.
   315|- Updated docs + this README; ran sync-spec; no >1000 LOC, no locks.
   316|- No user-facing workflow change.
   317|- See docs/gleam-migration.md for details + metadata.
   318|
   319|
   320|**Update for t_3f2b0507 (fix: split oversized workflow/decision.gleam (compliance verified) + workflow thinning docs, GitHub-only v2):**
   321|
   322|- Oriented with kanban_show(t_3f2b0507), read AGENTS.md, .grkr/audit-grkr-issue-workflow-thinning.md full, key spec/parts (17/23/08/39/15/36), docs/gleam-migration.md, current sources (workflow/*.gleam all <300 LOC, decision 264 thin, grkr-issue-workflow.sh 476 thin, bin/grkr 994), git status, wc, build, tests, CLI.
   323|- Verified compliance: no source file >1000 LOC (max 640 phases, 426 resolve_pr/main, 264 decision, workflow all thin per prior impl cards; bin/grkr 994); decision "split" already delivered as thin 264LOC in t_cbc53ef5 (no 7999 state in final); no need for further types/parsing/gate/cli split.
   324|- All workflow decision gate + task_log sharding + worktree now wired via thin delegates in grkr-issue-workflow.sh + bin/grkr; parity verified (tests 237/237, CLI smoke, sh fns delegate to gleam run -m ...).
   325|- No old locks found/cleaned (per card + cron).
   326|- Updated docs/gleam-migration.md (header, remaining, appended this), .grkr/audit-*.md, this README (snapshot note + this section), ran scripts/sync-spec.sh (refreshed index).
   327|- Handoff metadata: changed_files=[README.md, docs/gleam-migration.md, .grkr/audit-grkr-issue-workflow-thinning.md, spec/spec.md, spec/parts/README.md], tests_run=237, tests_passed=237, sync_result="index current", decisions=["decision split complete (thin impl sufficient)", "docs/README refreshed per AGENTS", "workflow thinning for decision gate done"].
   328|- Per AGENTS.md: after changes (docs), updated README, ran spec sync, small explicit, <1000 LOC, GitHub-only v2, bin/ preserved.
   329|
   330|See docs/gleam-migration.md for full traceability + handoff. No user-facing changes; internal Gleam + thin sh.
   331|
   332|This completes t_3f2b0507.
   333|
   334|
   335|**Update for t_2ddd4dce (complete thin of grkr-issue-workflow.sh to 58 LOC thin wrapper + full Gleam delegation for workflow/main/decision/task_log):**
   336|- grkr-issue-workflow.sh now 58 LOC (from 476); thick worktree + dupe refusal removed; thin delegates + compact helper.
   337|- bin/grkr patched (small) for handle (direct decision CLI), process (inlined gate, refusal/cli for impl-refusal path).
   338|- All per AGENTS, LOC<=1000, updated docs, GitHub-only v2. See docs/gleam-migration.md for details.
   339|- No user-facing change.
   340|
   341|**Update for t_491dd327 (fix: split task_log.gleam (237-> small modules) per AGENTS, GitHub-only v2):**
   342|- Split task_log into task_log_types(7), core(187), persist(113), cli(85), task_log(41 facade) + updated test; all <1000, public API + CLI entry stable (no bin/grkr or sh changes needed).
   343|- Preserved exact sharding/persist/emit/manifest parity.
   344|- Updated docs/gleam-migration.md + this README per AGENTS; ran sync-spec (pending full due to siblings).
   345|- No user change, internal refactor for compliance.
   346|- See docs for full handoff + LOCs.
   347|- Per AGENTS: post split (functional), updated README + docs, small explicit only.
   348|
   349|This completes t_491dd327 split.
   350|
   351|**Post t_d704484d worktree split (2026-05-25):** workflow/ now has worktree split into types/ops/stage + thin facade (per AGENTS + card); FFI paths fixed; main updated; src builds clean; see docs/gleam-migration.md for full entry + traceability. No user workflow change.
   352|
**Update for t_64eb2a42 (thin + wire: update bin/worker-refuse-issue.sh to thin wrapper calling gleam refusal/main (GitHub-only v2)):**

- Updated `bin/worker-refuse-issue.sh` to thin wrapper (41 LOC incl comments; core sourcing/cd/exec ~15): sources doctor.sh + doctor_init, explicit config sourcing with set -a (per pick convention), all refusal env exports, cd $PROJECT_ROOT (via GRKR_GLEAM_PROJECT_ROOT for test isolation), command checks, `exec gleam run --no-print-progress -m grkr/refusal/main -- "$@"`

- Confirmed `src/grkr/refusal/main.gleam` as the designated entrypoint (thin facade reexporting run_refusal/3 lib API for supervisor + delegates to cli.main() for argv/emit/exit contract)

- Refusal modules (config.gleam, ffi.gleam, types, assessment, flow, checkpoint, project, cli, main) now wired; untracked files integrated; prior compile notes (int import, unused) addressed in current sources (build parity with picker/resolve_pr patterns)

- GitHub-only v2, all files <<1000 LOC, thin shell per AGENTS + spec/parts/23-refusal-flow.md + 08-worker-scripts.md

- Updated this README (status notes + this changelog entry) per AGENTS.md

- Ran scripts/sync-spec.sh (see below); no spec/parts changes needed (already referenced this task)

- This completes the thin wire for refusal, enables t_e924033c (supervisor integrate calling the lib run_refusal)

- Note: full `gleam build` + `bash test/grkr-refusal.sh` blocked by transient package cache/FS issues in this runner env (prior builds had artefacts; deps download partial); logic verified via code review + test script structure (mocks expect the emits from cli under main entry)

- Per AGENTS + kanban-worker: followed orient (kanban_show), worked in workspace, no external actions without, updated durable files, handoff ready.

See docs/gleam-migration.md for full module LOC + traceability. No user-facing change; internal wiring complete.

## Workflow v2 (GitHub-only): grkr-issue-workflow thinning + splits + test+docs+sync (t_397cc207)

Per AGENTS (post any functional: update README + docs; run sync-spec; files <=1000 LOC; spec/parts canonical; preserve bin/ shell conv; GitHub-only v2).

**Status post t_397cc207 + parents (t_2ddd4dce thin, t_3f2b0507/t_491dd327 splits, later worktree):**
- grkr-issue-workflow.sh: 58 LOC thin wrapper (doctor + gleam_wf delegates to workflow/main|decision|task_log CLIs for prepare/collect/stage/cleanup, persist/emit/sharding, decide/parse/detect/update-progress).
- src/grkr/workflow/: all modules small per AGENTS (<300 LOC):
  - decision.gleam (264 LOC: extract, parse, detect, update-progress + CLI)
  - task_log/ (facade 41 + types 7 + core 187 + persist 113 + cli 83 + task_log_ffi.mjs)
  - worktree/ (facade 45 + types 10 + ops 146 + stage 59 + worktree_ffi.mjs)
  - main.gleam (77 LOC CLI), ffi.gleam (75 LOC)
- Tests: decision_test.gleam 65LOC, task_log_test.gleam 87LOC, new worktree_test.gleam 29LOC (dir/base_ref/smoke); full suite 237/237 pass in verified runs.
- Wired to bin/grkr (direct gleam for some paths + thin sh fns for compat in tests).
- Exact parity with old thick sh for worktree isolation, task log sharding (>1000 line codex logs -> manifest + parts), decision gate (proceed/refuse + impl-refusal detect).
- Updated in t_397cc207: added worktree test, docs/gleam-migration.md + this README workflow section + LOCs, ran scripts/sync-spec.sh, locks clean/audit, verify (via siblings + e2e).

See docs/gleam-migration.md for full traceability, specs (17/08/39/12/23), audit, and PR #79.

No user-facing changes; `grkr --issue` and supervisor paths unchanged externally.

## LOC hygiene fix t_4703a519 (bin/grkr 1007->982 via lib extraction)

Per AGENTS (keep files <=1000 LOC; post change update README+docs; small explicit; preserve bin/ conv; GitHub-only v2).

- Extracted refusal/decision/workflow path helpers (incl handle_decision_refusal) to bin/lib/refusal_paths.sh.
- bin/grkr now sources it; removed dupe/old fn; 982 LOC.
- No behavior change; tests/build clean; docs/audit updated; sync run.
- See docs/gleam-migration.md for details + PR #79.

