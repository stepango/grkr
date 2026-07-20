//// runtime.gleam
//// Exec, validation, FFI helpers, and result_try for resolve_pr (LOC hygiene).
//// Extracted from monolithic main without behavior change.

import gleam/int
import gleam/io
import gleam/list
import gleam/string

pub type ExecResult {
  ExecResult(exit_code: Int, stdout: String, stderr: String)
}

pub fn execute_command(cmd: List(String), input: String) -> Result(String, String) {
  case cmd {
    [] -> Error("Empty command")
    [command, ..args] -> {
      let result = javascript_executable(command, args, input)
      case result {
        ExecResult(exit_code, stdout, _stderr) -> {
          case exit_code {
            0 -> Ok(stdout)
            _ ->
              Error(
                "Command failed with exit code " <> int.to_string(exit_code),
              )
          }
        }
      }
    }
  }
}

pub fn result_try(
  result: Result(a, String),
  next: fn(a) -> Result(b, String),
) -> Result(b, String) {
  case result {
    Ok(value) -> next(value)
    Error(err) -> Error(err)
  }
}

pub fn run_validation_commands() -> Result(Nil, String) {
  let commands =
    [get_env("BUILD_COMMAND"), get_env("TEST_COMMAND")]
    |> list.map(string.trim)
    |> list.filter(fn(command) { command != "" })

  list.try_each(commands, fn(command) {
    io.println("Running validation command: " <> command)
    case execute_command(["bash", "-lc", command], "") {
      Ok(_) -> Ok(Nil)
      Error(err) -> Error(command <> ": " <> err)
    }
  })
}

// --- Thin FFI wrappers (stable names used by workflow/apply/main) ---

pub fn get_env(name: String) -> String {
  javascript_get_env(name)
}

pub fn argv() -> List(String) {
  javascript_argv()
}

pub fn exit(code: Int) -> Nil {
  javascript_exit(code)
}

pub fn cwd() -> String {
  javascript_cwd()
}

pub fn chdir(path: String) -> Nil {
  javascript_chdir(path)
}

pub fn write_file(path: String, content: String) -> Result(Nil, String) {
  javascript_write_file(path, content)
}

@external(javascript, "../resolve_pr/exec.mjs", "executable")
fn javascript_executable(
  command: String,
  args: List(String),
  input: String,
) -> ExecResult

@external(javascript, "../resolve_pr/fs.mjs", "write_file")
fn javascript_write_file(path: String, content: String) -> Result(Nil, String)

@external(javascript, "../resolve_pr/env.mjs", "argv")
fn javascript_argv() -> List(String)

@external(javascript, "../resolve_pr/env.mjs", "get_env")
fn javascript_get_env(name: String) -> String

@external(javascript, "process", "chdir")
fn javascript_chdir(path: String) -> Nil

@external(javascript, "process", "cwd")
fn javascript_cwd() -> String

@external(javascript, "process", "exit")
fn javascript_exit(code: Int) -> Nil
