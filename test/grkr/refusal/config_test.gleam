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
      // (int_from_env returns None -> 88)
    }
    Error(_) -> should.fail()  // in real env with doctor it succeeds
  }
}
