import gleam/dict
import gleeunit
import gleeunit/should
import grkr/refusal/config

pub fn main() {
  gleeunit.main()
}

pub fn load_runtime_config_test() {
  // runtime load should succeed with defaults (even if some env missing)
  case config.load_runtime_config() {
    Ok(cfg) -> {
      cfg.repo |> should.not_equal("")
      cfg.tasks_dir |> should.equal(".grkr/tasks")  // default
      // project_number defaults to 88 if not set in env
    }
    Error(_) -> should.fail()  // in real env with doctor it succeeds
  }
}

pub fn load_for_test_overrides_test() {
  let overrides =
    dict.new()
    |> dict.insert("GITHUB_REPOSITORY", "test/repo")
    |> dict.insert("TASKS_DIR", "/tmp/test-tasks")
    |> dict.insert("PROJECT_NUMBER", "42")
    |> dict.insert("ENABLE_PROJECT_STATUS_UPDATES", "false")
    |> dict.insert("REFUSAL_REQUIRES_BACKLOG_MOVE", "0")
    |> dict.insert("BACKLOG_VALUE", "MyBacklog")
    |> dict.insert("PROJECT_OWNER", "testowner")
    |> dict.insert("STATUS_FIELD_NAME", "State")

  case config.load_for_test(overrides) {
    Ok(cfg) -> {
      cfg.repo |> should.equal("test/repo")
      cfg.tasks_dir |> should.equal("/tmp/test-tasks")
      cfg.project_number |> should.equal(42)
      cfg.updates_enabled |> should.be_false()
      cfg.requires_backlog |> should.be_false()
      cfg.backlog_value |> should.equal("MyBacklog")
      cfg.project_owner |> should.equal("testowner")
      cfg.status_field_name |> should.equal("State")
    }
    Error(_) -> should.fail()
  }
}

pub fn load_for_test_defaults_test() {
  let overrides = dict.new()
  case config.load_for_test(overrides) {
    Ok(cfg) -> {
      cfg.repo |> should.equal("stepango/grkr")
      cfg.tasks_dir |> should.equal(".grkr/tasks")
      cfg.project_number |> should.equal(88)
      cfg.updates_enabled |> should.be_true()
      cfg.requires_backlog |> should.be_true()
      cfg.backlog_value |> should.equal("Backlog")
    }
    Error(_) -> should.fail()
  }
}
