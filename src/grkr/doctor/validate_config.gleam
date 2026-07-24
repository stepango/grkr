//// validate_config.gleam
//// Doctor config + remote + grkr-dir probes (LOC hygiene split, t_74a7a161).
//// Zero intentional behavior change.

import gleam/list
import gleam/option.{None, Some}
import gleam/string
import grkr/doctor/config_parse
import grkr/doctor/validate_tools as tools

pub fn grkr_root() -> String {
  case tools.get_env("GRKR_ROOT") {
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
  case tools.get_env("GRKR_CONFIG_FILE") {
    "" -> grkr_root() <> "/.grkr/config.sh"
    path -> path
  }
}

fn git_toplevel() -> Result(String, Nil) {
  case tools.executable("git", ["rev-parse", "--show-toplevel"], "") {
    tools.ExecResult(0, stdout, _) -> Ok(string.trim(stdout))
    _ -> Error(Nil)
  }
}

pub fn validate_config_file() -> Bool {
  let path = config_file_path()
  case tools.path_exists(path) {
    False -> {
      tools.fail("Missing config file: " <> path)
      False
    }
    True ->
      case tools.read_text(path) {
        Error(_) -> {
          tools.fail("Unable to load config file: " <> path)
          False
        }
        Ok(content) -> {
          let assignments = config_parse.parse_config_assignments(content)
          let missing = config_parse.missing_required_keys(assignments)
          case missing {
            [] -> True
            _ -> {
              list.each(missing, fn(var) {
                tools.fail("Missing required config value: " <> var)
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
  case tools.read_text(path) {
    Error(_) -> False
    Ok(content) -> {
      let assignments = config_parse.parse_config_assignments(content)
      case config_parse.config_get(assignments, "REPO") {
        None -> False
        Some(repo_raw) -> {
          case tools.executable("git", ["remote", "get-url", "origin"], "") {
            tools.ExecResult(0, stdout, _) -> {
              let remote_url = string.trim(stdout)
              case config_parse.normalize_repo_slug(remote_url) {
                Error(_) -> {
                  tools.fail("Unsupported origin remote URL: " <> remote_url)
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
                      tools.fail(
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
              tools.fail("Unable to read git remote origin.")
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
  case tools.mkdir_p(grkr_dir) {
    False -> {
      tools.fail("Unable to create " <> grkr_dir <> ".")
      False
    }
    True ->
      case tools.probe_writable_dir(grkr_dir) {
        True -> True
        False -> {
          tools.fail("Unable to write to " <> grkr_dir <> ".")
          False
        }
      }
  }
}
