# Gleam Migration Patterns: Extracted from sync_main/resolve_pr/github_picker/issue_provider/progress/task_slug/refusal for Supervisor v2 (GitHub-only)

**Task:** t_619dc89f research: Gleam migration patterns from sync_main/resolve_pr/ for supervisor v2 (GitHub-only)
**Date:** 2026-05-17
**Status:** Research complete; patterns doc created; detailed handoff in kanban comment + file; ready for synthesize child t_1ec1ab1c and design.

This extracts concrete, reusable patterns observed in the existing Gleam v2 modules (and their thin JS FFI + shell wrappers) to inform the Gleam reimplementation of supervisor scheduling, recovery, locking, state, bg orchestration, and phases (currently in bin/robot-main.sh ~519 LOC + worker-pick-issue.sh 425 LOC etc.).

Follows AGENTS.md: GitHub priority, split specs canonical (but this is impl patterns), files <=1000 LOC, preserve shell conventions for bin/.

Sources analyzed:
- src/grkr/sync_main/{main.gleam,exec.mjs,fs.mjs}
- src/grkr/resolve_pr/{main.gleam,types.gleam,git.gleam,github.gleam,codex.gleam,*.mjs}
- src/grkr/github_picker/{main.gleam,types.gleam,config.gleam,decoder.gleam,selector.gleam,ffi.gleam,*.mjs}
- src/grkr/issue_provider/{main.gleam,config.gleam,decoder.gleam,selector.gleam,client.gleam,query.gleam,*.mjs}
- src/grkr/progress/{cli.gleam,main.gleam,checkpoint_*.gleam,linear_*.gleam,cli_ffi.mjs}
- src/grkr/task_slug/{task_slug.gleam,cli.gleam,cli_ffi.mjs}
- src/grkr/refusal/{assessment.gleam,types.gleam,*.mjs} (recent)
- Corresponding bin/worker-*.sh (sync-main, resolve-pr, pick-issue, refuse-issue), bin/grkr, doctor.sh, test/*.sh, README.md, supervisor-research-summary.md (archived)

## 1. Module Split Patterns (Canonical Structure)

Every feature follows a consistent, testable split (keeps files small, logic pure where possible):

- **types.gleam** (required): All domain types + error variants as Gleam custom types.
  - Examples: PullRequest, ResolutionResult, ProjectItem, SelectedIssue, ProviderError, RefusalClass, CheckpointStage, TaskSlug, etc.
  - Often include to_string helpers, from_string parsers, validators.
  - No side effects.

- **config.gleam** (common): load() -> Result(Config, Error)
  - Reads env vars (REPO, PROJECT_*, TODO_VALUE, GRKR_*, LINEAR_*, etc.)
  - Optional file loads (e.g. credentials ~/.linear/secret.txt via FFI)
  - Fixture support for tests (LINEAR_FIXTURE_PATH or similar)
  - Validation + defaults.
  - Example: github_picker/config.gleam, issue_provider/config.gleam

- **main.gleam** (or cli.gleam): Entrypoint + orchestration.
  - pub fn main() -> Nil
  - Skips side-effects if GLEAM_ENV=test
  - Parses argv (via FFI), dispatches to subcommands or default run()
  - Calls into domain modules, handles results -> emit or error exit
  - Public run() for direct invocation from other Gleam (e.g. tests or higher modules)

- **Domain submodules** (split by concern):
  - decoder.gleam / selector.gleam (for pickers/providers): JSON walk + typed decode, pure filter/sort/pick logic
  - github.gleam / git.gleam / codex.gleam / client.gleam / query.gleam / assessment.gleam: specific ops (gh exec, git worktree, LLM calls, GraphQL, refusal rules)
  - checkpoint_render.gleam, linear_mutation.gleam etc for shared

- **ffi.gleam** (in some, e.g. github_picker): Re-exports all @external declarations for the feature's JS interop. Clean import surface.
  - Other modules declare @external inline at bottom of .gleam files.

- **<feature>_ffi.mjs / env.mjs / exec.mjs / fs.mjs / json_ffi.mjs / cli_ffi.mjs / file.mjs** (per module or shared later):
  - Thin JS glue. See FFI section.

- **Shared cross-cutting**:
  - grkr/task_slug.gleam (core slugify + task_slug_for_issue)
  - grkr/progress/* (checkpoint markers, progress.json, Linear mutations)
  - Future: grkr/ffi/* consolidated (env, fs, exec, process, json, logging)

**Supervisor application**:
- Proposed (from prior research): src/grkr/supervisor/
  - types.gleam (JobKey, ActiveJob, Phase, SupervisorState, LockResult, ...)
  - config.gleam (load from env + .grkr/config.sh derived)
  - main.gleam (loop entry, CLI for test/MAX_TICKS)
  - loop.gleam (the while true tick logic)
  - recovery.gleam (recover_dead_jobs, purge_stale_locks)
  - locking.gleam (acquire/release per entity, is_held)
  - phases.gleam (sync_main, pick_issue, schedule_*, reap, cleanup, pr_scan, comment_scan)
  - state.gleam (read/write active_jobs.json atomically, count active issues)
  - logging.gleam (structured log_event to multiple files)
  - scheduler.gleam (bg spawn + record)
- Each < ~400 LOC. Use result.try / use for error boundaries.
- Import grkr/progress , grkr/task_slug , grkr/github_picker (once wired), grkr/resolve_pr etc.

**Pitfall observed**: Duplication of nearly-identical FFI (env/exec/fs/json) across 5+ modules. Plan: after supervisor, consolidate to grkr/ffi/ and update callers (non-breaking for now).

## 2. CLI Dispatch Patterns

Consistent, shell-friendly CLI:

```gleam
// in main.gleam
pub fn main() {
  case javascript_get_env("GLEAM_ENV") {
    "test" -> Nil
    _ -> run_cli()
  }
}

fn run_cli() {
  case javascript_argv() {
    ["subcmd", arg] -> handle_sub(arg)
    [] -> case run() { Ok(_) -> emit_success(); Error(e) -> fail_cli(e) }
    _ -> { usage(); javascript_exit(2) }
  }
}

fn fail_cli(msg: String) {
  io.println_error(msg)
  javascript_exit(1)
}
```

- **Arg access**: @external(javascript, "../mod/env.mjs" or "cli_ffi.mjs", "argv") fn javascript_argv() -> List(String)
  - JS: `toList(process.argv.slice(2))`  (slice(2) skips node + script)
  - When invoked as `gleam run -m foo -- $ARGS` the -- passes $ARGS cleanly.

- **Output for shell sourcing** (critical for pickers, task-slug, etc.):
  - Emit lines like `KEY="value with spaces"\n`
  - Use custom `shell_quote` in Gleam:
    ```gleam
    fn shell_quote(v: String) -> String {
      "\"" <> (v |> replace("\\","\\\\") |> replace("\"","\\\"") |> replace("$","\\$") |> replace("`","\\`") ) <> "\""
    }
    ```
  - Then `console_log(key <> "=" <> shell_quote(val))`  or io.println
  - Examples: github_picker/main emits SELECTED, ISSUE_NUMBER, JOB_KEY, TASK_SLUG, PROJECT_ITEM_ID, ...
  - Shell then does `source <(gleam ...)` or captures and evals.

- **Subcommands**: Supported in issue_provider/main (viewer-query, teams-query, ... assigned-issues-query), task_slug/cli (slugify, task-slug)
  - Useful for debug / query introspection without full run.

- **Exit codes**: 0 success, 1 error, 2 usage, special 75=lock held (treated as non-fatal skip in supervisor), 64=forced fail for tests.

- **Test friendliness**: GLEAM_ENV=test bypasses main() side effects; tests call pure run() or sub fns directly.

**For supervisor**:
- main.gleam will support `gleam run -m grkr/supervisor/main` (long running) or with MAX_TICKS=5 for tests.
- Emit nothing normally (or structured logs to stderr/stdout); logs go to files via FFI.
- Thin robot-main.sh will be ~15 LOC: doctor + config + exec gleam ...

## 3. FFI Usage Patterns (JS <-> Gleam)

**Gleam side declaration** (bottom of .gleam or in ffi.gleam):
```gleam
@external(javascript, "../sync_main/exec.mjs", "executable")
fn javascript_executable(cmd: String, args: List(String), input: String) -> ExecResult

@external(javascript, "../mod/fs.mjs", "acquire_lock")
fn javascript_acquire_lock(path: String) -> Result(Nil, Nil)
```

**JS side** (always):
```js
import { Ok, Error, toList } from "../../gleam.mjs";

export function executable(command, args, input) {
  try {
    const opts = { input, encoding: "utf-8", stdio: ["pipe","pipe","pipe"] };
    if (process.env.GRKR_ROOT) opts.cwd = process.env.GRKR_ROOT;
    const out = execFileSync(command, args.toArray(), opts);
    return { exit_code: 0, stdout: out, stderr: "" };
  } catch (e) {
    return { exit_code: e.status || 1, stdout: e.stdout || "", stderr: e.stderr || e.message };
  }
}
```

**Common FFI files per module** (patterns to copy/extend):
- **env.mjs**: get_env(name) -> "" | val ; argv() -> List
- **exec.mjs**: executable(...) -> {exit_code, stdout, stderr}  (used for git, gh, codex, flock indirect)
- **fs.mjs**: mkdir_p, acquire_lock (flock -n on fd hack + Map< path, fd >), release_lock, exit_process, sometimes read/write_file, append
  - Lock impl critical for supervisor: replicates shell flock usage exactly.
- **json_ffi.mjs** (github_picker, issue_provider, refusal): 
  - parse(s) -> Result(JsonValue, err)
  - get_field(obj, "key") -> JsonValue (null safe)
  - get_keys(obj) -> Result(List(String))
  - decode_string / decode_int / decode_array / is_null -> Result or Bool
  - Used with Gleam walk_path to handle GraphQL nested shapes flexibly (user vs org, fallback paths)
- **cli_ffi.mjs**: argv, sometimes console_log wrapper, exit
- **github_ffi.mjs** (resolve_pr): parse_pr_json, parse_pr_list_json -> Result(PullRequest or List, err)  (uses JS JSON + field mapping)
- **file.mjs** (some): read_text, write_text, exists?
- **linear_http.mjs**, credential_ffi.mjs, oauth_ffi etc for provider specifics.
- **parse.mjs** (resolve_pr): perhaps custom parsers.

**Gleam JSON handling pattern** (github_picker/decoder.gleam):
- walk_path(json, ["data","user","projectV2",...]) |> ffi.decode_array
- Fallbacks for org vs user, string vs int number, etc.
- Build typed structs only after full decode.

**Supervisor FFI needs** (new or extend):
- process_ffi.mjs: spawn_detached(cmd: List(String), opts) -> Int (pid) ; is_alive(pid: Int) -> Bool ; kill(pid, signal?)
  - JS: const child = spawn(cmd[0], cmd.slice(1), {detached:true, stdio:'ignore', ...}); child.unref(); return child.pid;
  - is_alive: try{process.kill(pid,0); return true}catch{return false}
- sleep_ffi: sleep(ms: Int)
- log_append(path, line)
- atomic_write_json(tmp, final, content) : write tmp, renameSync
- Or keep using exec for some (git, gh, rm -rf guarded)

**Pitfalls**:
- cwd must be set to GRKR_ROOT for git ops in workers.
- flock fd must stay open in the JS process that holds it (Map in fs.mjs).
- Cross platform: kill(0) works on mac/linux; Windows different (but macOS dev).
- JSON numbers vs strings in gh output (handle both in decoder).
- Large outputs: resolve_pr/codex handles sharded logs.

## 4. Thin Main + Shell Wrapper Patterns (Preserve Conventions)

**Gleam side is the "thick" logic**; shell is glue + conventions.

**Typical bin/worker-foo.sh** (15-50 LOC, set -euo pipefail):
```bash
#!/bin/bash
set -euo pipefail
SCRIPT_DIR=...
. "$SCRIPT_DIR/doctor.sh"
doctor_init
if [ -f "$GRKR_CONFIG_FILE" ]; then . "$GRKR_CONFIG_FILE"; fi
export GRKR_ROOT MAIN_BRANCH ...
cd "$PROJECT_ROOT"
# optional arg validation, mkdir
exec gleam run -m grkr/foo/main -- "$@"
```

- **Special cases**:
  - worker-sync-main.sh: sets GRKR_SYNC_MAIN_LOCK_HELD=1 bypass, uses flock in Gleam too.
  - worker-pick-issue.sh: long (425LOC) because still has full github selection + GraphQL in bash + jq; once github_picker wired, it will shrink to ~60LOC + call to gleam for decode+select or full.
  - worker-resolve-pr.sh: ~43 LOC, passes PR_NUMBER.
- **bin/grkr** (the main CLI entry, ~984? LOC): more complex, uses templates, calls into progress/cli via gleam, handles issue workflow, worktrees, etc. Delegates marker gen to Gleam now.
- **doctor.sh**: prereq checks + validate (gh auth, git, codex, config keys, project fields, linear creds). Outputs lines; supervisor parses for VALIDATION_OK.

**For supervisor v2**:
- New thin bin/robot-main.sh (or keep/enhance existing, delegate loop to Gleam):
  - doctor_init
  - source config
  - exec gleam run -m grkr/supervisor/main
- Gleam supervisor will replicate exact phase order, recovery at top of tick, error boundaries (never die on worker fail), MAX_TICKS, GRKR_FAIL_PHASES, %10 cleanup, etc.
- Workers (sync, pick, resolve, refuse, future pr-scan, comment) stay as thin + their Gleam.

**Test integration**:
- test/worker-*.sh : setup fixtures, run wrapper, assert exit, logs, state, branches, etc.
- Gleam tests: `gleam test` (via scripts/bootstrap-gleam.sh)
- package.json has "test:gleam"

## 5. Logging, State, Locking, Recovery, Scheduling Patterns

**Logging** (from robot-main.sh):
- Structured: `log_event phase job entity msg` -> appends TIMESTAMP LEVEL ... to .grkr/logs/{main,loop,jobs/*.log}
- Escape values for safe k=v
- In Gleam: either FFI append or build line + exec "echo ... >> file"

**State (active_jobs.json)**:
- Atomic: write tmp, jq or mv
- Schema: { "issue:42:execution": { "pid":123, "type":"issue_execution", "id":42, "lock":"issue-42", "task_slug":"42-foo", "started_at":..., "project_item_id"?:... } , ... }
- Ops: record, remove, count by prefix (for active_issue_execution_count), filter dead
- Gleam: json_ffi + fs read/write + pure transform fns

**Locking**:
- .grkr/locks/{main.lock, issue-N.lock, pr-N.lock, comment-*.lock}
- acquire: flock -n (nonblock), 75 exit = held (supervisor treats as skip for some phases)
- Held by the bg worker process (flock in subshell or in Gleam FFI)
- Stale purge: if not in active_jobs and flockable -> rm

**Recovery** (every tick start + reap phase):
- For each in active_jobs: if ! pid or ! kill -0 pid -> remove job, rm lock, log "recovered=true"
- Also prune_stale_worktrees sometimes

**Scheduling / bg jobs**:
- `schedule_issue_execution`: prep lock+log, bg `(flock -n9 || exit75; bin/grkr --issue N >>joblog 2>&1 & ) 9>lock` ; pid=$!; record_active_job(key, pid, ...)
- Similar for PR conflict resolve, comment cmds
- Only 1 active issue execution at a time (serialize long runs)
- Gleam equiv: FFI spawn_bg that returns pid immediately, record, let it run detached

**Cleanup** (every 10 ticks):
- purge orphan locks
- (future) prune old worktrees/tasks per policy in 36-cleanup-policy.md

**Error/phase handling**:
- run_phase_with_lock: flock guard, map 75->success-skip, propagate others
- phase_should_fail via GRKR_FAIL_PHASES csv for tests
- Supervisor never exits; logs ERROR but continues to next phase/tick

**Supervisor specific to replicate exactly** (from T1 extraction in archived summary):
- refresh_validation, ensure_runtime_layout, job_key_lock_name, purge every 10, sleep_remaining_time calc, etc.

## 6. Handoff to Design / Implementation

**Concrete proposal for supervisor/** (refine in synthesize t_1ec1ab1c):
- 8-10 modules as listed in section 1
- FFI first (new process + json + log FFI) or extend existing fs/exec
- Wire github_picker into worker-pick-issue.sh (replace jq selection block with gleam call that takes the raw GraphQL json)
- Keep all external behavior, exit codes, log formats, file layouts identical so existing tests + robot-main.sh (thin) pass unchanged
- GitHub-first: PR scan, comment scan, issue pick, conflict resolve, all via gh + Gleam parsers
- Linear via issue_provider (already partial)

**Next steps after patterns**:
- Synthesize (t_1ec1ab1c) will combine T1+T2+T3 into full proposal + structure
- Then design card: exact APIs, file list, test plan, FFI spec
- Impl: start with FFI + types + state/locking/recovery (core for supervisor to boot)
- Update README, run spec sync if spec/parts touched, keep <=1000 LOC

**Risks / Gotchas for supervisor** (from patterns + T1):
- Replicating flock fd + detached spawn exactly in JS (test on macOS)
- PID lifecycle across ticks (supervisor long lived, workers short)
- Atomic state under concurrent? (but single threaded Gleam + shell bg)
- Time/sleep precision for interval
- Preserving 75/64 codes, structured logs, worktree isolation
- Gradual migration: keep shell supervisor running while Gleam version matures (or replace in one go after tests)

This completes the T3 patterns research. File is the durable artifact.

See also: supervisor-research-summary.md (in .grkr/archive/), refusal-synthesis.md (example of synthesis output), spec/parts/07-supervisor.md and related.
