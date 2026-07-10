//// recovery.gleam
//// Dead job recovery, stale active_jobs TTL/hung-lock purge, and stale lock file purge.
//// Port of recover_dead_jobs() + purge_stale_lock_files() from bin/robot-main.sh:185-259
//// Uses is_alive(PID), check_stale_lock (flock -n), atomic JSON state, structured logs.
//// Follows design-final.md, spec/parts/33+35+36, .grkr/supervisor-cleanup-policy.md §6, AGENTS.md.
////
//// GAPS vs spec (deferred):
//// - No retry backoff / max_retries in scheduler (deferred).
//// - No per-10-tick enforcement (caller in phases decides frequency).
//// - Refusal job TTL handling stub (worktree side: refusal-protected slugs wired in worktree_cleanup).

import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import grkr/supervisor/ffi
import grkr/supervisor/lock
import grkr/supervisor/state
import grkr/supervisor/types as t

/// Grace after started_at before hung-lock purge may apply (policy §6.3).
pub const hung_lock_grace_seconds = 300

/// Age in seconds from UTC ISO started_at; Error if invalid/empty (no TTL purge).
pub fn active_job_age_seconds(started_at: String, now_unix: Int) -> Result(Int, Nil) {
  let ts = ffi.parse_utc_iso_to_unix(started_at)
  case ts < 0 {
    True -> Error(Nil)
    False -> Ok(now_unix - ts)
  }
}

/// Purge reason for a live job, if any. Prefers stale_ttl when TTL expired (policy §6.3).
pub fn stale_purge_reason(
  age_seconds: Int,
  ttl_seconds: Int,
  lock_is_stale: Bool,
) -> Option(String) {
  let ttl_expired = age_seconds > ttl_seconds
  let hung =
    lock_is_stale && age_seconds >= hung_lock_grace_seconds
  case ttl_expired, hung {
    True, _ -> Some("stale_ttl")
    False, True -> Some("stale_hung_lock")
    False, False -> None
  }
}

/// Recover dead PIDs from active_jobs.json, unlink their locks, remove from state (atomic write first).
/// Logs per-stale "stale_job pid=... recovered=true" (WARN) + zero case (INFO).
/// Returns recovered count or Error on state read/write fail.
/// Matches shell exactly (kill -0 equiv via is_alive, mktemp+mv atomic, jq del).
pub fn recover_dead_jobs(
  config: t.SupervisorConfig,
  context_phase: String,
) -> Result(Int, t.SupervisorError) {
  let entity = "repo/" <> config.repo
  case state.read_active_jobs(config.active_jobs_file) {
    Error(_) -> {
      log_error(config, context_phase, "-", entity, "active_jobs_state_invalid=true")
      Error(t.Io("active_jobs_state_invalid"))
    }
    Ok(jobs) -> {
      let entries = dict.to_list(jobs)
      case entries {
        [] -> Ok(0)
        _ -> {
          let stales =
            list.filter_map(entries, fn(pair) {
              let #(jk_str, aj) = pair
              case ffi.is_alive(aj.pid) {
                True -> Error(Nil)
                False -> Ok(#(jk_str, aj, "dead_pid"))
              }
            })
          purge_active_job_entries(config, context_phase, jobs, stales)
        }
      }
    }
  }
}

/// Purge live-PID active_jobs rows past TTL or with stale uncontended locks (policy §6).
/// Skips dead PIDs (recover_dead_jobs). Does not signal the worker process.
pub fn recover_stale_active_jobs(
  config: t.SupervisorConfig,
  context_phase: String,
) -> Result(Int, t.SupervisorError) {
  let entity = "repo/" <> config.repo
  let now = ffi.unix_seconds()
  let ttl = config.active_job_ttl_seconds

  case state.read_active_jobs(config.active_jobs_file) {
    Error(_) -> {
      log_error(config, context_phase, "-", entity, "active_jobs_state_invalid=true")
      Error(t.Io("active_jobs_state_invalid"))
    }
    Ok(jobs) -> {
      let entries = dict.to_list(jobs)
      let stales =
        list.filter_map(entries, fn(pair) {
          let #(jk_str, aj) = pair
          case ffi.is_alive(aj.pid) {
            False -> Error(Nil)
            True -> {
              case active_job_age_seconds(aj.started_at, now) {
                Error(Nil) -> {
                  log_warn(
                    config,
                    context_phase,
                    jk_str,
                    aj.entity_type <> "/" <> aj.entity_id,
                    "active_job_started_at_invalid=true job="
                      <> jk_str,
                  )
                  Error(Nil)
                }
                Ok(age) -> {
                  let lp = job_lock_path(config, jk_str, aj)
                  let lock_stale = lock.check_stale_lock(lp)
                  case stale_purge_reason(age, ttl, lock_stale) {
                    None -> Error(Nil)
                    Some(reason) -> Ok(#(jk_str, aj, reason))
                  }
                }
              }
            }
          }
        })

      case list.length(stales) {
        0 -> {
          log_info(
            config,
            context_phase,
            "-",
            entity,
            "stale_ttl_jobs=0",
          )
          Ok(0)
        }
        _ -> purge_active_job_entries(config, context_phase, jobs, stales)
      }
    }
  }
}

fn purge_active_job_entries(
  config: t.SupervisorConfig,
  context_phase: String,
  jobs: dict.Dict(String, t.ActiveJob),
  stales: List(#(String, t.ActiveJob, String)),
) -> Result(Int, t.SupervisorError) {
  let count = list.length(stales)
  let stale_keys =
    list.map(stales, fn(p) {
      let #(k, _, _) = p
      k
    })
  let remaining =
    dict.filter(jobs, fn(k, _v) { !list.contains(stale_keys, k) })

  case state.write_active_jobs_atomic(config.active_jobs_file, remaining) {
    Error(_) -> {
      let entity = "repo/" <> config.repo
      log_error(config, context_phase, "-", entity, "active_jobs_update_failed=true")
      Error(t.Io("active_jobs_update_failed"))
    }
    Ok(_) -> {
      list.each(stales, fn(triple) {
        let #(jk_str, aj, reason) = triple
        let lp = job_lock_path(config, jk_str, aj)
        let _ = ffi.unlink_file(lp)
        let entity2 = aj.entity_type <> "/" <> aj.entity_id
        let msg =
          "stale_job pid="
            <> int.to_string(aj.pid)
            <> " recovered=true reason="
            <> reason
        log_warn(config, context_phase, jk_str, entity2, msg)
        Nil
      })

      case count {
        0 -> {
          let entity = "repo/" <> config.repo
          log_info(config, context_phase, "-", entity, "stale_jobs=0")
        }
        _ -> Nil
      }
      Ok(count)
    }
  }
}

fn job_lock_path(
  config: t.SupervisorConfig,
  jk_str: String,
  aj: t.ActiveJob,
) -> String {
  let ln =
    case aj.lock_name == "" {
      True ->
        case t.job_key_from_string(jk_str) {
          Ok(k) -> t.job_key_lock_name(k)
          Error(_) -> jk_str
        }
      False -> aj.lock_name
    }
  lock.lock_path(config.locks_dir, ln)
}

/// Purge unreferenced pr-*.lock / issue-*.lock / comment-*.lock under locks_dir.
/// Uses check_stale_lock (flock -n) before rm. Always logs "purged_stale_locks=N".
/// Errors only on active_jobs read or list dir fail. (shell: flock -n + find + rm)
pub fn purge_stale_lock_files(config: t.SupervisorConfig) -> Result(Int, t.SupervisorError) {
  let entity = "repo/" <> config.repo
  let phase = "cleanup_stale_worktrees"
  case state.read_active_jobs(config.active_jobs_file) {
    Error(_) -> {
      log_error(config, phase, "-", entity, "active_jobs_state_invalid=true")
      Error(t.Io("active_jobs_state_invalid"))
    }
    Ok(jobs) -> {
      case ffi.list_files(config.locks_dir) {
        Error(e) -> Error(t.Io("list locks dir: " <> e))
        Ok(all_files) -> {
          let candidates =
            list.filter(all_files, fn(f) {
              let has_prefix =
                string.starts_with(f, "pr-")
                || string.starts_with(f, "issue-")
                || string.starts_with(f, "comment-")
              string.ends_with(f, ".lock") && has_prefix
            })

          let purged =
            list.fold(candidates, 0, fn(acc, f) {
              let lock_name = string.drop_end(f, 5)
              let used =
                list.any(dict.values(jobs), fn(aj) { aj.lock_name == lock_name })
              case used {
                True -> acc
                False -> {
                  let full = lock.lock_path(config.locks_dir, lock_name)
                  case lock.check_stale_lock(full) {
                    True -> {
                      let _ = ffi.unlink_file(full)
                      acc + 1
                    }
                    False -> acc
                  }
                }
              }
            })

          log_info(
            config,
            phase,
            "-",
            entity,
            "purged_stale_locks=" <> int.to_string(purged),
          )
          Ok(purged)
        }
      }
    }
  }
}

// --- internal logging (dupe ok until logging.gleam extracted; matches shell 51-79) ---

fn escape_log_value(value: String) -> String {
  value
  |> string.replace("\n", " ")
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
}

fn log_event(
  config: t.SupervisorConfig,
  level: String,
  phase: String,
  job_key: String,
  entity: String,
  message: String,
) -> Nil {
  let ts = ffi.utc_timestamp()
  let msg_esc = escape_log_value(message)
  let line =
    ts
    <> " "
    <> level
    <> " phase="
    <> phase
    <> " job="
    <> job_key
    <> " entity="
    <> entity
    <> " msg=\""
    <> msg_esc
    <> "\""

  let _ = ffi.append_log(config.main_log_file, line)
  let _ = ffi.append_log(config.loop_log_file, line)

  case job_key == "-" {
    True -> Nil
    False -> {
      let base =
        case t.job_key_from_string(job_key) {
          Ok(jk) -> t.job_key_log_basename(jk)
          Error(_) ->
            job_key
            |> string.replace(":", "-")
            |> string.replace("/", "-")
        }
      let jpath = config.job_logs_dir <> "/" <> base <> ".log"
      let _ = ffi.append_log(jpath, line)
      Nil
    }
  }
}

fn log_info(config: t.SupervisorConfig, phase: String, job: String, entity: String, msg: String) -> Nil {
  log_event(config, "INFO", phase, job, entity, msg)
}

fn log_warn(config: t.SupervisorConfig, phase: String, job: String, entity: String, msg: String) -> Nil {
  log_event(config, "WARN", phase, job, entity, msg)
}

fn log_error(config: t.SupervisorConfig, phase: String, job: String, entity: String, msg: String) -> Nil {
  log_event(config, "ERROR", phase, job, entity, msg)
}