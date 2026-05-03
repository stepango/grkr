import gleam/int
import gleam/list
import gleam/string

pub type ExitCode {
  ExitCode(i: Int)
}

pub type SyncError {
  LockAlreadyHeld
  CommandFailed(code: Int, msg: String)
  FsError(msg: String)
}

pub type SyncCommand {
  SyncCommand(program: String, args: List(String))
}

const lock_already_held_code = 75

pub fn get_repo_root() -> Result(String, String) {
  case javascript_executable("git", ["rev-parse", "--show-toplevel"], "") {
    ExecResult(0, stdout, _) -> Ok(string.trim(stdout))
    ExecResult(code, _, stderr) -> {
      let msg =
        "git rev-parse failed with code "
        <> int.to_string(code)
        <> ": "
        <> stderr
      Error(msg)
    }
  }
}

pub fn get_grkr_root() -> Result(String, String) {
  case javascript_get_env("GRKR_ROOT") {
    "" -> get_repo_root()
    root -> Ok(root)
  }
}

pub fn get_main_branch() -> String {
  case javascript_get_env("MAIN_BRANCH") {
    "" -> "main"
    branch -> branch
  }
}

pub fn sync_commands(main_branch: String) -> List(SyncCommand) {
  [
    SyncCommand("git", ["fetch", "origin", main_branch, "--prune"]),
    SyncCommand("git", ["checkout", main_branch]),
    SyncCommand("git", ["reset", "--hard", "origin/" <> main_branch]),
  ]
}

pub fn command_to_string(command: SyncCommand) -> String {
  let SyncCommand(program, args) = command
  string.join([program, ..args], " ")
}

pub fn planned_command_strings(main_branch: String) -> List(String) {
  sync_commands(main_branch)
  |> list.map(command_to_string)
}

pub fn ensure_locks_dir(grkr_root: String) -> Result(Nil, SyncError) {
  let locks_dir = grkr_root <> "/.grkr/locks"
  case javascript_mkdir_p(locks_dir) {
    True -> Ok(Nil)
    False -> Error(FsError("Failed to create locks directory: " <> locks_dir))
  }
}

pub fn acquire_main_lock(grkr_root: String) -> Result(Nil, SyncError) {
  case javascript_get_env("GRKR_SYNC_MAIN_LOCK_HELD") {
    "1" -> Ok(Nil)
    _ -> {
      let lock_path = grkr_root <> "/.grkr/locks/main.lock"
      case javascript_acquire_lock(lock_path) {
        Ok(_) -> Ok(Nil)
        Error(Nil) -> Error(LockAlreadyHeld)
      }
    }
  }
}

pub fn release_main_lock(grkr_root: String) -> Nil {
  case javascript_get_env("GRKR_SYNC_MAIN_LOCK_HELD") {
    "1" -> Nil
    _ -> {
      let lock_path = grkr_root <> "/.grkr/locks/main.lock"
      let _ = javascript_release_lock(lock_path)
      Nil
    }
  }
}

pub fn git_fetch(main_branch: String) -> Result(Nil, SyncError) {
  case execute_git_command(SyncCommand("git", ["fetch", "origin", main_branch, "--prune"])) {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error(err)
  }
}

pub fn git_checkout(main_branch: String) -> Result(Nil, SyncError) {
  case execute_git_command(SyncCommand("git", ["checkout", main_branch])) {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error(err)
  }
}

pub fn git_reset_hard(main_branch: String) -> Result(Nil, SyncError) {
  case execute_git_command(SyncCommand("git", ["reset", "--hard", "origin/" <> main_branch])) {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error(err)
  }
}

pub fn run() -> ExitCode {
  case get_grkr_root() {
    Error(_) -> ExitCode(1)
    Ok(grkr_root) -> {
      let main_branch = get_main_branch()

      case ensure_locks_dir(grkr_root) {
        Error(_) -> ExitCode(1)
        Ok(_) -> {
          case acquire_main_lock(grkr_root) {
            Error(LockAlreadyHeld) -> ExitCode(lock_already_held_code)
            Error(_) -> ExitCode(1)
            Ok(_) -> {
              let sync_result = run_sync_sequence(main_branch)
              release_main_lock(grkr_root)

              case sync_result {
                Ok(_) -> ExitCode(0)
                Error(CommandFailed(code, _)) -> ExitCode(code)
                Error(_) -> ExitCode(1)
              }
            }
          }
        }
      }
    }
  }
}

pub fn main() {
  let ExitCode(code) = run()
  javascript_exit(code)
}

fn run_sync_sequence(main_branch: String) -> Result(Nil, SyncError) {
  case git_fetch(main_branch) {
    Error(error) -> Error(error)
    Ok(_) -> {
      case git_checkout(main_branch) {
        Error(error) -> Error(error)
        Ok(_) -> git_reset_hard(main_branch)
      }
    }
  }
}

fn execute_git_command(command: SyncCommand) -> Result(Nil, SyncError) {
  let SyncCommand(program, args) = command
  case javascript_executable(program, args, "") {
    ExecResult(0, _, _) -> Ok(Nil)
    ExecResult(code, _, stderr) -> {
      let msg =
        "Command failed with exit code "
        <> int.to_string(code)
        <> ": "
        <> stderr
      Error(CommandFailed(code, msg))
    }
  }
}

type ExecResult {
  ExecResult(exit_code: Int, stdout: String, stderr: String)
}

@external(javascript, "../sync_main/exec.mjs", "executable")
fn javascript_executable(
  command: String,
  args: List(String),
  input: String,
) -> ExecResult

@external(javascript, "../sync_main/fs.mjs", "get_env")
fn javascript_get_env(name: String) -> String

@external(javascript, "../sync_main/fs.mjs", "mkdir_p")
fn javascript_mkdir_p(path: String) -> Bool

@external(javascript, "../sync_main/fs.mjs", "acquire_lock")
fn javascript_acquire_lock(lock_path: String) -> Result(Nil, Nil)

@external(javascript, "../sync_main/fs.mjs", "release_lock")
fn javascript_release_lock(lock_path: String) -> Bool

@external(javascript, "../sync_main/fs.mjs", "exit_process")
fn javascript_exit(code: Int) -> Nil
