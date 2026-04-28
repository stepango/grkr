import gleam/int
import gleam/list
import gleam/string

type ExecResult {
  ExecResult(exit_code: Int, stdout: String, stderr: String)
}

const git_bin = "git"

pub fn create_worktree(
  branch_name: String,
  path: String,
) -> Result(String, String) {
  let cmd = [git_bin, "worktree", "add", "-b", branch_name, path]

  case execute_command(cmd, "") {
    Ok(output) -> Ok(output)
    Error(err) -> Error("Failed to create worktree: " <> err)
  }
}

pub fn create_worktree_from_commit(
  commit_sha: String,
  path: String,
) -> Result(String, String) {
  let cmd = [git_bin, "worktree", "add", path, commit_sha]

  case execute_command(cmd, "") {
    Ok(output) -> Ok(output)
    Error(err) -> Error("Failed to create worktree from commit: " <> err)
  }
}

pub fn create_worktree_from_branch(
  branch_name: String,
  path: String,
) -> Result(String, String) {
  let cmd = [git_bin, "worktree", "add", path, branch_name]

  case execute_command(cmd, "") {
    Ok(output) -> Ok(output)
    Error(err) -> Error("Failed to create worktree from branch: " <> err)
  }
}

pub fn remove_worktree(path: String) -> Result(Nil, String) {
  let cmd = [git_bin, "worktree", "remove", path]

  case execute_command(cmd, "") {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error("Failed to remove worktree: " <> err)
  }
}

pub fn fetch_origin(branch: String) -> Result(Nil, String) {
  let cmd = [git_bin, "fetch", "origin", branch]

  case execute_command(cmd, "") {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error("Failed to fetch origin: " <> err)
  }
}

pub fn fetch_pr_head(
  pr_number: Int,
  branch_name: String,
) -> Result(Nil, String) {
  let refspec =
    "pull/" <> int.to_string(pr_number) <> "/head:refs/heads/" <> branch_name
  let cmd = [git_bin, "fetch", "origin", refspec]

  case execute_command(cmd, "") {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error("Failed to fetch PR head: " <> err)
  }
}

pub fn rebase_branch(upstream: String) -> Result(Nil, String) {
  let cmd = [git_bin, "rebase", upstream]

  case execute_command(cmd, "") {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error("Rebase failed: " <> err)
  }
}

pub fn check_ref_name(branch_name: String) -> Result(Nil, String) {
  let cmd = [git_bin, "check-ref-format", "--branch", branch_name]

  case execute_command(cmd, "") {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error("Invalid branch name: " <> err)
  }
}

pub fn merge_branch(branch: String) -> Result(Nil, String) {
  let cmd = [git_bin, "merge", branch]

  case execute_command(cmd, "") {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error("Merge failed: " <> err)
  }
}

pub fn abort_merge_or_rebase() -> Result(Nil, String) {
  let cmd1 = [git_bin, "rebase", "--abort"]
  let cmd2 = [git_bin, "merge", "--abort"]

  let _result1 = execute_command(cmd1, "")
  let _result2 = execute_command(cmd2, "")

  Ok(Nil)
}

pub fn continue_rebase() -> Result(String, String) {
  let cmd = [git_bin, "-c", "core.editor=true", "rebase", "--continue"]

  case execute_command(cmd, "") {
    Ok(output) -> Ok(output)
    Error(err) -> Error("Failed to continue rebase: " <> err)
  }
}

pub fn get_conflicted_files() -> Result(List(String), String) {
  let cmd = [git_bin, "diff", "--name-only", "--diff-filter=U"]

  case execute_command(cmd, "") {
    Ok(output) -> {
      let files =
        output
        |> string.trim()
        |> string.split("\n")
        |> list.filter(fn(s) { s != "" })

      Ok(files)
    }
    Error(err) -> Error("Failed to get conflicted files: " <> err)
  }
}

pub fn commit_changes(message: String) -> Result(String, String) {
  let add_cmd = [git_bin, "add", "-A"]
  let commit_cmd = [git_bin, "commit", "-m", message]

  case execute_command(add_cmd, "") {
    Ok(_) -> {
      case execute_command(commit_cmd, "") {
        Ok(output) -> Ok(output)
        Error(err) -> Error("Failed to commit: " <> err)
      }
    }
    Error(err) -> Error("Failed to stage files: " <> err)
  }
}

pub fn stage_paths(paths: List(String)) -> Result(Nil, String) {
  let cmd = list.append([git_bin, "add", "--"], paths)

  case execute_command(cmd, "") {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error("Failed to stage files: " <> err)
  }
}

pub fn commit_staged(message: String) -> Result(String, String) {
  let cmd = [git_bin, "commit", "-m", message]

  case execute_command(cmd, "") {
    Ok(output) -> Ok(output)
    Error(err) -> Error("Failed to commit: " <> err)
  }
}

pub fn push_branch(branch_name: String) -> Result(String, String) {
  let cmd = [
    git_bin,
    "push",
    "--force-with-lease",
    "origin",
    "HEAD:" <> branch_name,
  ]

  case execute_command(cmd, "") {
    Ok(output) -> Ok(output)
    Error(err) -> Error("Failed to push: " <> err)
  }
}

pub fn get_current_head_sha() -> Result(String, String) {
  let cmd = [git_bin, "rev-parse", "HEAD"]

  case execute_command(cmd, "") {
    Ok(output) -> Ok(output |> string.trim())
    Error(err) -> Error("Failed to get HEAD sha: " <> err)
  }
}

pub fn in_conflict_state() -> Bool {
  case get_conflicted_files() {
    Ok(files) -> files != []
    Error(_) -> False
  }
}

pub fn checkout_branch(branch_name: String) -> Result(Nil, String) {
  let cmd = [git_bin, "checkout", branch_name]

  case execute_command(cmd, "") {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error("Failed to checkout branch: " <> err)
  }
}

fn execute_command(cmd: List(String), input: String) -> Result(String, String) {
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

@external(javascript, "../resolve_pr/exec.mjs", "executable")
fn javascript_executable(
  command: String,
  args: List(String),
  input: String,
) -> ExecResult
