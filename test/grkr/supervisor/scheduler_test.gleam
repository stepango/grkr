import gleam/dict
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import grkr/supervisor/config
import grkr/supervisor/ffi
import grkr/supervisor/scheduler
import grkr/supervisor/state
import grkr/supervisor/types

@external(javascript, "./test_helper.mjs", "set_env")
fn set_env(name: String, value: String) -> Nil

@external(javascript, "./scheduler_fixture.mjs", "prepare_issue_spawn_fixture")
fn prepare_issue_spawn_fixture() -> #(String, String)

@external(javascript, "./scheduler_fixture.mjs", "write_bin_grkr_mock")
fn write_bin_grkr_mock(root: String, runner_log: String) -> Nil

@external(javascript, "./scheduler_fixture.mjs", "read_runner_log")
fn read_runner_log(path: String) -> String

@external(javascript, "./scheduler_fixture.mjs", "cleanup_fixture")
fn cleanup_fixture(root: String) -> Nil

@external(javascript, "./scheduler_fixture.mjs", "pause_for_spawn")
fn pause_for_spawn() -> Nil

pub fn main() {
  gleeunit.main()
}

fn load_test_config(root: String) -> types.SupervisorConfig {
  let overrides =
    dict.new()
    |> dict.insert("REPO", "stepango/grkr")
    |> dict.insert("GRKR_ROOT", root)
    |> dict.insert("PROJECT_OWNER", "stepango")
    |> dict.insert("PROJECT_NUMBER", "1")

  let assert Ok(cfg) = config.load_for_test(overrides)
  cfg
}

pub fn spawn_issue_execution_records_active_job_test() {
  let #(root, _runner_log) = prepare_issue_spawn_fixture()
  set_env("GRKR_ROOT", root)

  let cfg = load_test_config(root)
  let assert Ok(_) = config.ensure_layout(cfg)

  let task_slug = "issue-42-fixture-pick-issue"
  let project_id = Some("PVTI_pick1")

  let assert Ok(pid) =
    scheduler.spawn_issue_execution(cfg, 42, task_slug, project_id)
  case pid > 0 {
    True -> Nil
    False -> should.fail()
  }

  pause_for_spawn()

  let assert Ok(jobs) = state.read_active_jobs(cfg.active_jobs_file)
  let assert Ok(aj) = dict.get(jobs, "issue:42:execution")
  let types.ActiveJob(_, et, eid, ln, ts, _, proj) = aj
  et |> should.equal("issue")
  eid |> should.equal("42")
  ln |> should.equal("issue-42")
  ts |> should.equal(task_slug)
  proj |> should.equal(project_id)

  let job_log = cfg.job_logs_dir <> "/issue-42-execution.log"
  ffi.exists(job_log) |> should.be_true()

  let lock_file = cfg.locks_dir <> "/issue-42.lock"
  ffi.exists(lock_file) |> should.be_true()

  cleanup_fixture(root)
}

pub fn spawn_issue_execution_runs_grkr_issue_argv_test() {
  let #(root, runner_log) = prepare_issue_spawn_fixture()
  set_env("GRKR_ROOT", root)

  let cfg = load_test_config(root)
  let assert Ok(_) = config.ensure_layout(cfg)

  let assert Ok(_) =
    scheduler.spawn_issue_execution(cfg, 42, "issue-42-fixture-pick-issue", None)

  pause_for_spawn()

  let log = read_runner_log(runner_log)
  string.contains(log, "--issue") |> should.be_true()
  string.contains(log, "42") |> should.be_true()

  cleanup_fixture(root)
}

pub fn spawn_issue_execution_uses_bin_grkr_when_root_grkr_missing_test() {
  let #(root, runner_log) = prepare_issue_spawn_fixture()
  write_bin_grkr_mock(root, runner_log)
  set_env("GRKR_ROOT", root)

  let cfg = load_test_config(root)
  let assert Ok(_) = config.ensure_layout(cfg)

  let assert Ok(pid) = scheduler.spawn_issue_execution(cfg, 7, "issue-7-test", None)
  case pid > 0 {
    True -> Nil
    False -> should.fail()
  }

  pause_for_spawn()

  let log = read_runner_log(runner_log)
  string.contains(log, "--issue") |> should.be_true()
  string.contains(log, "7") |> should.be_true()

  cleanup_fixture(root)
}

pub fn spawn_issue_execution_returns_positive_pid_test() {
  let #(root, _runner_log) = prepare_issue_spawn_fixture()
  set_env("GRKR_ROOT", root)

  let cfg = load_test_config(root)
  let assert Ok(_) = config.ensure_layout(cfg)

  let assert Ok(pid) = scheduler.spawn_issue_execution(cfg, 99, "issue-99", None)
  case pid > 0 {
    True -> Nil
    False -> should.fail()
  }
  ffi.is_alive(pid) |> should.be_true()
  let _ = ffi.kill(pid, "SIGTERM")

  cleanup_fixture(root)
}