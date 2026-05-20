//// recovery.gleam
//// Dead job recovery and stale lock purge for the GRKR supervisor (v2 Gleam port).
//// Port of recover_dead_jobs() + purge_stale_lock_files() from bin/robot-main.sh:185-259
//// Uses is_alive(PID), check_stale_lock (flock -n), atomic JSON state, structured logs.
//// Follows design-final.md, spec/parts/33+35, AGENTS.md (small file, exact contracts).

import gleam/dict
import gleam/int
import gleam/list
import gleam/string

import grkr/supervisor/ffi
import grkr/supervisor/lock
import grkr/supervisor/state
import grkr/supervisor/types as t

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
                False -> Ok(#(jk_str, aj))
              }
            })
          let count = list.length(stales)
          let stale_keys = list.map(stales, fn(p) {
            let #(k, _) = p
            k
          })
          let remaining =
            dict.filter(jobs, fn(k, _v) { !list.contains(stale_keys, k) })

          // Write state FIRST (atomic), only then unlink locks (prevents inconsistent state)
          case state.write_active_jobs_atomic(config.active_jobs_file, remaining) {
            Error(_) -> {
              log_error(config, context_phase, "-", entity, "active_jobs_update_failed=true")
              Error(t.Io("active_jobs_update_failed"))
            }
            Ok(_) -> {
              // Safe to unlink now
              list.each(stales, fn(pair) {
                let #(jk_str, aj) = pair
                let ln =
                  case aj.lock_name == "" {
                    True ->
                      case t.job_key_from_string(jk_str) {
                        Ok(k) -> t.job_key_lock_name(k)
                        Error(_) -> jk_str
                      }
                    False -> aj.lock_name
                  }
                let lp = lock.lock_path(config.locks_dir, ln)
                let _ = ffi.unlink_file(lp)
                let entity2 = aj.entity_type <> "/" <> aj.entity_id
                let msg = "stale_job pid=" <> int.to_string(aj.pid) <> " recovered=true"
                log_warn(config, context_phase, jk_str, entity2, msg)
                Nil
              })

              case count {
                0 -> log_info(config, context_phase, "-", entity, "stale_jobs=0")
                _ -> Nil
              }
              Ok(count)
            }
          }
        }
      }
    }
  }
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
