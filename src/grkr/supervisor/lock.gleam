//// lock.gleam
//// Locking primitives for the GRKR supervisor (v2 Gleam port).
//// Thin typed wrapper around the flock-based FFI in fs.mjs (acquire_lock / release_lock).
////
//// - acquire_lock(path) returns LockResult (Acquired | Busy)
//// - release_lock(path) -> Bool
//// - check_stale_lock(path) for recovery / purge_stale_lock_files
//// - convenience helpers for JobKey-based per-job locks (pr-N, issue-N, comment-ID)
////
//// Matches shell semantics from bin/robot-main.sh:
////   - flock -n 9 || exit 75  (Busy treated as non-fatal skip in phases)
////   - purge only for job locks not present in active_jobs.json
////   - cross-tick recovery via PID checks (in recovery.gleam, not here)
////
//// Phases (future) will do manual:
////   use _ <- result.try(...)
////   ... critical work ...
////   let _ = release...
////
//// The JS side holds fds in a Map for lifetime of the supervisor process;
//// workers themselves hold their own per-job locks via the bash wrapper spawn.

import grkr/supervisor/ffi
import grkr/supervisor/types.{
  type JobKey, type LockResult, type SupervisorError, Acquired, Busy,
  job_key_lock_name,
}

/// Acquire non-blocking exclusive lock on the .lock file at `lock_path`.
/// Returns Acquired if we now hold it (fd open in JS until release),
/// Busy if another process holds it.
pub fn acquire_lock(lock_path: String) -> Result(LockResult, SupervisorError) {
  case ffi.acquire_lock(lock_path) {
    Ok(_) -> Ok(Acquired)
    Error(_) -> Ok(Busy)
  }
}

/// Release a lock we previously acquired for this exact path.
/// Returns true if the fd was held by this process and successfully closed.
pub fn release_lock(lock_path: String) -> Bool {
  ffi.release_lock(lock_path)
}

/// Return true if `lock_path` has no live holder (stale .lock file left by dead process).
///
/// Does a try-acquire; if successful we briefly hold then release and return true.
/// If contended, returns false.
/// Does not delete the file (caller in recovery decides + unlinks after checking active_jobs).
pub fn check_stale_lock(lock_path: String) -> Bool {
  case acquire_lock(lock_path) {
    Ok(Acquired) -> {
      let _ = release_lock(lock_path)
      True
    }
    _ -> False
  }
}

/// Construct the full lock file path under the configured locks directory.
/// Example: lock_path("~/.grkr/locks", "issue-42") == "~/.grkr/locks/issue-42.lock"
pub fn lock_path(locks_dir: String, lock_name: String) -> String {
  locks_dir <> "/" <> lock_name <> ".lock"
}

/// Acquire a per-job lock derived from JobKey (uses job_key_lock_name: "pr-42", "issue-7", "comment-abc123").
pub fn acquire_lock_for_job_key(
  locks_dir: String,
  job_key: JobKey,
) -> Result(LockResult, SupervisorError) {
  let name = job_key_lock_name(job_key)
  let path = lock_path(locks_dir, name)
  acquire_lock(path)
}

/// Release the per-job lock for the given JobKey.
pub fn release_lock_for_job_key(locks_dir: String, job_key: JobKey) -> Bool {
  let name = job_key_lock_name(job_key)
  let path = lock_path(locks_dir, name)
  release_lock(path)
}

/// Check if the per-job lock for the given JobKey is stale.
pub fn check_stale_lock_for_job_key(locks_dir: String, job_key: JobKey) -> Bool {
  let name = job_key_lock_name(job_key)
  let path = lock_path(locks_dir, name)
  check_stale_lock(path)
}
