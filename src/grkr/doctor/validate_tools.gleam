//// validate_tools.gleam
//// Doctor tools + gh auth probes (LOC hygiene split, t_74a7a161).
//// Shared FFI/helpers for sibling validate_* modules. Zero intentional behavior change.

import gleam/list

pub type ExecResult {
  ExecResult(exit_code: Int, stdout: String, stderr: String)
}

@external(javascript, "../doctor/exec.mjs", "executable")
pub fn executable(command: String, args: List(String), input: String) -> ExecResult

@external(javascript, "../doctor/env.mjs", "get_env")
pub fn get_env(name: String) -> String

@external(javascript, "../doctor/fs.mjs", "read_text")
pub fn read_text(path: String) -> Result(String, String)

@external(javascript, "../doctor/fs.mjs", "write_text")
pub fn write_text(path: String, content: String) -> Result(Nil, String)

@external(javascript, "../doctor/fs.mjs", "exists")
pub fn path_exists(path: String) -> Bool

@external(javascript, "../doctor/fs.mjs", "mkdir_p")
pub fn mkdir_p(path: String) -> Bool

@external(javascript, "../doctor/fs.mjs", "probe_writable_dir")
pub fn probe_writable_dir(path: String) -> Bool

@external(javascript, "console", "log")
pub fn console_log(s: String) -> Nil

pub fn fail(msg: String) -> Nil {
  console_log("❌ " <> msg)
}

pub fn tool_on_path(tool: String) -> Bool {
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
