//// validate_run.gleam
//// Doctor validate / create-config orchestrator (LOC hygiene split, t_74a7a161).
//// Zero intentional behavior change.

import gleam/string
import grkr/doctor/config_parse
import grkr/doctor/validate_agent as agent
import grkr/doctor/validate_config as config
import grkr/doctor/validate_tools as tools

/// Full startup validation (parity with doctor_validate in shell).
pub fn run_validate() -> Int {
  let tools_ok = tools.validate_tools()
  let gh_ok = tools.validate_gh_auth()
  let agent_ok = agent.validate_coding_agent()

  let config_path = config.config_file_path()
  let config_ok = case tools.path_exists(config_path) {
    False -> {
      tools.fail("Missing config file: " <> config_path)
      False
    }
    True -> {
      let cfg_ok = config.validate_config_file()
      let remote_ok = config.validate_repo_remote()
      cfg_ok && remote_ok
    }
  }

  let grkr_ok = config.validate_grkr_dir()

  let all_ok = tools_ok && gh_ok && agent_ok && config_ok && grkr_ok
  case all_ok {
    True -> {
      tools.console_log(
        "✅ Startup validation passed (coding agent: "
          <> agent.coding_agent_name()
          <> ").",
      )
      0
    }
    False -> 1
  }
}

pub fn run_create_config(project_number: String) -> Int {
  let path = config.config_file_path()
  case tools.path_exists(path) {
    True -> {
      tools.fail("Config file already exists: " <> path)
      1
    }
    False -> write_default_config(project_number)
  }
}

fn write_default_config(project_number: String) -> Int {
  case string.trim(project_number) {
    "" -> {
      tools.fail(
        "PROJECT_NUMBER is required to create "
          <> config.config_file_path()
          <> ".",
      )
      1
    }
    _ ->
      case tools.executable("git", ["remote", "get-url", "origin"], "") {
        tools.ExecResult(0, stdout, _) -> {
          let remote_url = string.trim(stdout)
          case config_parse.normalize_repo_slug(remote_url) {
            Error(_) -> {
              tools.fail("Unsupported origin remote URL: " <> remote_url)
              1
            }
            Ok(remote_slug) -> {
              let owner = case string.split(remote_slug, "/") {
                [o, ..] -> o
                _ -> remote_slug
              }
              let content =
                config_parse.default_config_template(
                  remote_slug,
                  owner,
                  string.trim(project_number),
                )
              case tools.write_text(config.config_file_path(), content) {
                Error(_) -> {
                  tools.fail("Unable to create " <> config.config_file_path() <> ".")
                  1
                }
                Ok(_) -> 0
              }
            }
          }
        }
        _ -> {
          tools.fail("Unable to read git remote origin.")
          1
        }
      }
  }
}
