import gleam/list
import gleam/option.{None, Some}
import gleam/string
import grkr/doctor/config_parse

type ExecResult {
  ExecResult(exit_code: Int, stdout: String, stderr: String)
}

@external(javascript, "../doctor/exec.mjs", "executable")
fn executable(command: String, args: List(String), input: String) -> ExecResult

@external(javascript, "../doctor/env.mjs", "get_env")
fn get_env(name: String) -> String

@external(javascript, "../doctor/fs.mjs", "read_text")
fn read_text(path: String) -> Result(String, String)

@external(javascript, "../doctor/fs.mjs", "write_text")
fn write_text(path: String, content: String) -> Result(Nil, String)

@external(javascript, "../doctor/fs.mjs", "exists")
fn path_exists(path: String) -> Bool

@external(javascript, "../doctor/fs.mjs", "mkdir_p")
fn mkdir_p(path: String) -> Bool

@external(javascript, "../doctor/fs.mjs", "probe_writable_dir")
fn probe_writable_dir(path: String) -> Bool

@external(javascript, "console", "log")
fn console_log(s: String) -> Nil

pub fn grkr_root() -> String {
  case get_env("GRKR_ROOT") {
    "" -> {
      case git_toplevel() {
        Ok(root) -> root
        Error(_) -> "."
      }
    }
    root -> root
  }
}

pub fn config_file_path() -> String {
  case get_env("GRKR_CONFIG_FILE") {
    "" -> grkr_root() <> "/.grkr/config.sh"
    path -> path
  }
}

fn git_toplevel() -> Result(String, Nil) {
  case executable("git", ["rev-parse", "--show-toplevel"], "") {
    ExecResult(0, stdout, _) -> Ok(string.trim(stdout))
    _ -> Error(Nil)
  }
}

fn fail(msg: String) -> Nil {
  console_log("❌ " <> msg)
}

fn tool_on_path(tool: String) -> Bool {
  case executable("command", ["-v", tool], "") {
    ExecResult(0, _, _) -> True
    _ -> False
  }
}

pub fn validate_tools() -> Bool {
  let tools = ["jq", "git", "gh", "timeout", "flock"]
  list.fold(tools, True, fn(ok, tool) {
    case ok {
      False -> False
      True ->
        case tool_on_path(tool) {
          True -> True
          False -> {
            fail(tool <> " is required but not installed.")
            False
          }
        }
    }
  })
}

pub fn validate_gh_auth() -> Bool {
  case executable("gh", ["auth", "status"], "") {
    ExecResult(0, _, _) -> True
    _ -> {
      fail("GitHub authentication failed. Run: gh auth login")
      False
    }
  }
}

pub fn validate_codex() -> Bool {
  case tool_on_path("codex") {
    False -> {
      fail("codex is required but not installed.")
      False
    }
    True ->
      case executable("codex", ["--help"], "") {
        ExecResult(0, _, _) -> True
        _ -> {
          fail("codex is installed but not runnable.")
          False
        }
      }
  }
}

pub fn validate_config_file() -> Bool {
  let path = config_file_path()
  case path_exists(path) {
    False -> {
      fail("Missing config file: " <> path)
      False
    }
    True ->
      case read_text(path) {
        Error(_) -> {
          fail("Unable to load config file: " <> path)
          False
        }
        Ok(content) -> {
          let assignments = config_parse.parse_config_assignments(content)
          let missing = config_parse.missing_required_keys(assignments)
          case missing {
            [] -> True
            _ -> {
              list.each(missing, fn(var) {
                fail("Missing required config value: " <> var)
              })
              False
            }
          }
        }
      }
  }
}

pub fn validate_repo_remote() -> Bool {
  let path = config_file_path()
  case read_text(path) {
    Error(_) -> False
    Ok(content) -> {
      let assignments = config_parse.parse_config_assignments(content)
      case config_parse.config_get(assignments, "REPO") {
        None -> False
        Some(repo_raw) -> {
          case executable("git", ["remote", "get-url", "origin"], "") {
            ExecResult(0, stdout, _) -> {
              let remote_url = string.trim(stdout)
              case config_parse.normalize_repo_slug(remote_url) {
                Error(_) -> {
                  fail("Unsupported origin remote URL: " <> remote_url)
                  False
                }
                Ok(remote_slug) -> {
                  let expected = case config_parse.normalize_repo_slug(repo_raw) {
                    Ok(normalized) -> normalized
                    Error(_) -> repo_raw
                  }
                  case remote_slug == expected {
                    True -> True
                    False -> {
                      fail(
                        "Origin remote "
                          <> remote_slug
                          <> " does not match configured repo "
                          <> expected
                          <> ".",
                      )
                      False
                    }
                  }
                }
              }
            }
            _ -> {
              fail("Unable to read git remote origin.")
              False
            }
          }
        }
      }
    }
  }
}

pub fn validate_grkr_dir() -> Bool {
  let grkr_dir = grkr_root() <> "/.grkr"
  case mkdir_p(grkr_dir) {
    False -> {
      fail("Unable to create " <> grkr_dir <> ".")
      False
    }
    True ->
      case probe_writable_dir(grkr_dir) {
        True -> True
        False -> {
          fail("Unable to write to " <> grkr_dir <> ".")
          False
        }
      }
  }
}

/// Full startup validation (parity with doctor_validate in shell).
pub fn run_validate() -> Int {
  let tools_ok = validate_tools()
  let gh_ok = validate_gh_auth()
  let codex_ok = validate_codex()

  let config_path = config_file_path()
  let config_ok = case path_exists(config_path) {
    False -> {
      fail("Missing config file: " <> config_path)
      False
    }
    True -> {
      let cfg_ok = validate_config_file()
      let remote_ok = validate_repo_remote()
      cfg_ok && remote_ok
    }
  }

  let grkr_ok = validate_grkr_dir()

  let all_ok = tools_ok && gh_ok && codex_ok && config_ok && grkr_ok
  case all_ok {
    True -> {
      console_log("✅ Startup validation passed.")
      0
    }
    False -> 1
  }
}

pub fn run_create_config(project_number: String) -> Int {
  let path = config_file_path()
  case path_exists(path) {
    True -> {
      fail("Config file already exists: " <> path)
      1
    }
    False -> write_default_config(project_number)
  }
}

fn write_default_config(project_number: String) -> Int {
  case string.trim(project_number) {
    "" -> {
      fail(
        "PROJECT_NUMBER is required to create "
          <> config_file_path()
          <> ".",
      )
      1
    }
    _ ->
      case executable("git", ["remote", "get-url", "origin"], "") {
        ExecResult(0, stdout, _) -> {
          let remote_url = string.trim(stdout)
          case config_parse.normalize_repo_slug(remote_url) {
            Error(_) -> {
              fail("Unsupported origin remote URL: " <> remote_url)
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
              case write_text(config_file_path(), content) {
                Error(_) -> {
                  fail("Unable to create " <> config_file_path() <> ".")
                  1
                }
                Ok(_) -> 0
              }
            }
          }
        }
        _ -> {
          fail("Unable to read git remote origin.")
          1
        }
      }
  }
}