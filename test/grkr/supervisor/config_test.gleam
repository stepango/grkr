import gleam/dict
import grkr/supervisor/config
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn load_for_test_returns_config_test() {
  let overrides =
    dict.new()
    |> dict.insert("REPO", "stepango/grkr")
    |> dict.insert("MAIN_BRANCH", "main")
    |> dict.insert("LOOP_INTERVAL_SECS", "30")
    |> dict.insert("GRKR_ROOT", "/tmp/grkr-test")
    |> dict.insert("PROJECT_OWNER", "stepango")
    |> dict.insert("PROJECT_NUMBER", "1")

  case config.load_for_test(overrides) {
    Ok(cfg) -> {
      cfg.repo |> should.equal("stepango/grkr")
      cfg.main_branch |> should.equal("main")
      cfg.loop_interval_secs |> should.equal(30)
      cfg.grkr_root |> should.equal("/tmp/grkr-test")
      cfg.grkr_dir |> should.equal("/tmp/grkr-test/.grkr")
      cfg.state_dir |> should.equal("/tmp/grkr-test/.grkr/state")
      cfg.locks_dir |> should.equal("/tmp/grkr-test/.grkr/locks")
      cfg.logs_dir |> should.equal("/tmp/grkr-test/.grkr/logs")
      cfg.job_logs_dir |> should.equal("/tmp/grkr-test/.grkr/logs/jobs")
      cfg.worktrees_dir |> should.equal("/tmp/grkr-test/.grkr/worktrees")
      cfg.tasks_dir |> should.equal("/tmp/grkr-test/.grkr/tasks")
      cfg.active_jobs_file |> should.equal("/tmp/grkr-test/.grkr/state/active_jobs.json")
      cfg.project_owner |> should.equal("stepango")
      cfg.project_number |> should.equal(1)
    }
    Error(_) -> should.fail()
  }
}

pub fn load_for_test_defaults_when_repo_missing_test() {
  let overrides =
    dict.new()
    |> dict.insert("GRKR_ROOT", "/tmp/grkr-test2")

  case config.load_for_test(overrides) {
    Ok(cfg) -> {
      cfg.repo |> should.equal("unknown/unknown")
      cfg.grkr_root |> should.equal("/tmp/grkr-test2")
      // note: REPO no longer required (defaults), GRKR_ROOT required path but with fallback in impl
      Nil
    }
    Error(_) -> should.fail()
  }
}

pub fn ensure_layout_does_not_crash_test() {
  let overrides =
    dict.new()
    |> dict.insert("REPO", "test/repo")
    |> dict.insert("GRKR_ROOT", "/tmp/grkr-test-layout")
    |> dict.insert("PROJECT_OWNER", "test")
    |> dict.insert("PROJECT_NUMBER", "1")

  case config.load_for_test(overrides) {
    Ok(cfg) -> {
      // ensure_layout should succeed (creates dirs/files via ffi)
      case config.ensure_layout(cfg) {
        Ok(_) -> Nil
        Error(_) -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}
