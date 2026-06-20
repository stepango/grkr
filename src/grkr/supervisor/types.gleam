import gleam/option.{type Option}
import gleam/string
import gleam/int

/// Job key variants for active jobs (GitHub-only for this slice)
pub type JobKey {
  PrConflict(number: Int)
  IssueExecution(number: Int)
  Comment(id: String)
  // Future: IssueRefusal(number: Int)
}

/// Parse job key string e.g. "pr:123:conflict-resolution" or "issue:42:execution" or "comment:123"
pub fn job_key_from_string(s: String) -> Result(JobKey, String) {
  let parts = string.split(s, ":")
  case parts {
    ["pr", num_str, _task] -> {
      case int.parse(num_str) {
        Ok(n) -> Ok(PrConflict(n))
        Error(_) -> Error("invalid pr number in key: " <> s)
      }
    }
    ["issue", num_str, "execution"] -> {
      case int.parse(num_str) {
        Ok(n) -> Ok(IssueExecution(n))
        Error(_) -> Error("invalid issue number in key: " <> s)
      }
    }
    ["comment", id] -> Ok(Comment(id))
    _ -> Error("unknown job key format: " <> s)
  }
}

pub fn job_key_to_string(key: JobKey) -> String {
  case key {
    PrConflict(n) -> "pr:" <> int.to_string(n) <> ":conflict-resolution"
    IssueExecution(n) -> "issue:" <> int.to_string(n) <> ":execution"
    Comment(id) -> "comment:" <> id
  }
}

pub fn job_key_lock_name(key: JobKey) -> String {
  case key {
    PrConflict(n) -> "pr-" <> int.to_string(n)
    IssueExecution(n) -> "issue-" <> int.to_string(n)
    Comment(id) -> "comment-" <> id
  }
}

pub fn job_key_log_basename(key: JobKey) -> String {
  job_key_to_string(key)
  |> string.replace(":", "-")
  |> string.replace("/", "-")
}

/// Minimal GitHub comment record for scan_comment_commands (from REST /repos/.../issues/comments)
/// Per spec/parts/15-phase-3, 11-state-model (id + updated_at for idempotency)
pub type GitHubComment {
  GitHubComment(
    id: String,
    body: String,
    created_at: String,
    updated_at: String,
    user_login: String,
    html_url: String,
  )
}

/// Active job record (matches active_jobs.json schema + shell)
pub type ActiveJob {
  ActiveJob(
    pid: Int,
    entity_type: String,
    entity_id: String,
    lock_name: String,
    task_slug: String,
    started_at: String,
    project_item_id: Option(String),
  )
}

/// Supervisor phases (order matches spec 09-main-loop-contract and shell)
pub type Phase {
  SyncMain
  ScanPrConflicts
  ScanCommentCommands
  PickAndScheduleIssueExecution
  ReapFinishedJobs
  CleanupStaleWorktrees
  SleepUntilNextTick
  // Internal markers for logging only
  StartupValidation
  Supervisor
}

/// Convert phase to the exact string used in logs and GRKR_FAIL_PHASES
pub fn phase_to_string(p: Phase) -> String {
  case p {
    SyncMain -> "sync_main"
    ScanPrConflicts -> "scan_pr_conflicts"
    ScanCommentCommands -> "scan_comment_commands"
    PickAndScheduleIssueExecution -> "pick_and_schedule_issue_execution"
    ReapFinishedJobs -> "reap_finished_jobs"
    CleanupStaleWorktrees -> "cleanup_stale_worktrees"
    SleepUntilNextTick -> "sleep_until_next_tick"
    StartupValidation -> "startup_validation"
    Supervisor -> "supervisor"
  }
}

/// Runtime config loaded from env (after shell doctor+config source)
pub type SupervisorConfig {
  SupervisorConfig(
    repo: String,
    main_branch: String,
    loop_interval_secs: Int,
    grkr_root: String,
    grkr_dir: String,
    state_dir: String,
    locks_dir: String,
    logs_dir: String,
    job_logs_dir: String,
    worktrees_dir: String,
    worktree_ttl_seconds: Int,
    active_job_ttl_seconds: Int,
    tasks_dir: String,
    active_jobs_file: String,
    processed_comments_file: String,
    project_cache_file: String,
    pr_cache_file: String,
    last_comment_scan_file: String,
    main_log_file: String,
    loop_log_file: String,
    validation_ok: Bool,
    max_ticks: Option(Int),
    fail_phases: List(String),
    project_owner: String,
    project_number: Int,
  )
}

/// Errors for supervisor (Result everywhere per design)
pub type SupervisorError {
  ConfigLoad(String)
  MissingRequiredEnv(String)
  Io(String)
  ValidationFailed
  LockBusy
  PhaseFailed(phase: String, code: Int)
  Parse(String)
  SpawnFailed(String)
  InvalidPhaseName(String)
  Other(String)
}

pub fn supervisor_error_to_string(e: SupervisorError) -> String {
  case e {
    ConfigLoad(msg) -> "config_load:" <> msg
    MissingRequiredEnv(name) -> "missing_required_env:" <> name
    Io(msg) -> "io:" <> msg
    ValidationFailed -> "validation_failed"
    LockBusy -> "lock_busy"
    PhaseFailed(p, c) -> "phase_failed:" <> p <> ":" <> int.to_string(c)
    Parse(msg) -> "parse:" <> msg
    SpawnFailed(msg) -> "spawn_failed:" <> msg
    InvalidPhaseName(name) -> "invalid phase name: " <> name
    Other(msg) -> "other:" <> msg
  }
}

/// Lock acquire result
pub type LockResult {
  Acquired
  Busy
  LockError(String)
}

/// Per-phase result (never let phase kill supervisor)
pub type PhaseResult {
  Success
  Skipped(reason: String)
  Failed(err: SupervisorError)
}
