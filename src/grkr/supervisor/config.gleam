//// config.gleam
//// Load SupervisorConfig from env (set by doctor.sh + .grkr/config.sh)
//// or test overrides. Mirrors load_runtime_config + paths in robot-main.sh

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import grkr/supervisor/ffi
import grkr/supervisor/types as types

pub fn load() -> Result(types.SupervisorConfig, types.SupervisorError) {
  load_with_overrides(dict.new())
}

/// For tests: provide env overrides (e.g. for MAX_TICKS, FAIL_PHASES, dirs)
pub fn load_for_test(overrides: Dict(String, String)) -> Result(types.SupervisorConfig, types.SupervisorError) {
  load_with_overrides(overrides)
}

fn load_with_overrides(overrides: Dict(String, String)) -> Result(types.SupervisorConfig, types.SupervisorError) {
  let get = fn(key: String, default: String) {
    case dict.get(overrides, key) {
      Ok(v) -> v
      Error(_) -> ffi.get_env_with_default(key, default)
    }
  }

    let get_required = fn(key: String) -> Result(String, types.SupervisorError) {
    let v = case dict.get(overrides, key) {
      Ok(v) -> v
      Error(_) -> ffi.get_env(key)
    }
    case v {
      "" -> Error(types.MissingRequiredEnv(key))
      val -> Ok(val)
    }
  }

  let repo = get("REPO", "unknown/unknown")
  let main_branch = get("MAIN_BRANCH", "main")
  let loop_interval_secs =
    get("LOOP_INTERVAL_SECS", "20")
    |> int.parse
    |> result.unwrap(20)

  let grkr_root = case get_required("GRKR_ROOT") {
    Ok(r) -> r
    Error(e) -> {
      // fallback for direct runs / tests
      let home = get("HOME", ".")
      home <> "/.grkr"
    }
  }

  let grkr_dir = grkr_root <> "/.grkr"
  let state_dir = grkr_dir <> "/state"
  let locks_dir = grkr_dir <> "/locks"
  let logs_dir = grkr_dir <> "/logs"
  let job_logs_dir = logs_dir <> "/jobs"
  let worktrees_dir = grkr_dir <> "/worktrees"
  let tasks_dir = grkr_dir <> "/tasks"

  let active_jobs_file = state_dir <> "/active_jobs.json"
  let processed_comments_file = state_dir <> "/processed_comments.json"
  let project_cache_file = state_dir <> "/project_cache.json"
  let pr_cache_file = state_dir <> "/pr_cache.json"
  let last_comment_scan_file = state_dir <> "/last_comment_scan_at"
  let main_log_file = logs_dir <> "/main.log"
  let loop_log_file = logs_dir <> "/loop.log"

  let validation_ok =
    get("VALIDATION_OK", "0")
    |> int.parse
    |> result.unwrap(0)
    |> fn(n) { n == 1 }

  let max_ticks =
    case get("GRKR_MAX_TICKS", "") {
      "" -> None
      s ->
        case int.parse(s) {
          Ok(n) if n > 0 -> Some(n)
          _ -> None
        }
    }

  let fail_phases =
    get("GRKR_FAIL_PHASES", "")
    |> string.split(on: ",")
    |> list.map(string.trim)
    |> list.filter(fn(s) { s != "" })

  // Project V2 config (for picker integration)
  let project_v2_owner = get("PROJECT_V2_OWNER", "")
  let project_v2_number =
    get("PROJECT_V2_NUMBER", "0")
    |> int.parse
    |> result.unwrap(0)
  let config =
    types.SupervisorConfig(
      repo: repo,
      main_branch: main_branch,
      loop_interval_secs: loop_interval_secs,
      grkr_root: grkr_root,
      grkr_dir: grkr_dir,
      state_dir: state_dir,
      locks_dir: locks_dir,
      logs_dir: logs_dir,
      job_logs_dir: job_logs_dir,
      worktrees_dir: worktrees_dir,
      tasks_dir: tasks_dir,
      active_jobs_file: active_jobs_file,
      processed_comments_file: processed_comments_file,
      project_cache_file: project_cache_file,
      pr_cache_file: pr_cache_file,
      last_comment_scan_file: last_comment_scan_file,
      main_log_file: main_log_file,
      loop_log_file: loop_log_file,
      validation_ok: validation_ok,
      max_ticks: max_ticks,
      fail_phases: fail_phases,
      project_v2_owner: project_v2_owner,
      project_v2_number: project_v2_number,
    )
  Ok(config)
}
/// Ensure dirs and initial files exist (like ensure_runtime_layout)
pub fn ensure_layout(cfg: types.SupervisorConfig) -> Result(Nil, types.SupervisorError) {
  let _ = ffi.mkdir_p(cfg.state_dir)
  let _ = ffi.mkdir_p(cfg.locks_dir)
  let _ = ffi.mkdir_p(cfg.logs_dir)
  let _ = ffi.mkdir_p(cfg.job_logs_dir)
  let _ = ffi.mkdir_p(cfg.worktrees_dir)
  let _ = ffi.mkdir_p(cfg.tasks_dir)

  // touch logs
  let _ = ffi.append_log(cfg.main_log_file, "")
  let _ = ffi.append_log(cfg.loop_log_file, "")

  // init json if missing
  case ffi.exists(cfg.active_jobs_file) {
    True -> Nil
    False ->
      case ffi.atomic_write_json(cfg.active_jobs_file, "{}") {
        Ok(_) -> Nil
        Error(_) -> Nil
      }
  }
  case ffi.exists(cfg.processed_comments_file) {
    True -> Nil
    False ->
      case ffi.atomic_write_json(cfg.processed_comments_file, "[]") {
        Ok(_) -> Nil
        Error(_) -> Nil
      }
  }
  // other caches similar, but for now skip detailed init

  Ok(Nil)
}
