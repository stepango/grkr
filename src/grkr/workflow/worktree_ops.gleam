import gleam/list
import gleam/option
import gleam/string

import grkr/workflow/ffi.{type ExecResult, ExecResult}

/// Compute the worktree dir under $GRKR_ROOT/.grkr/worktrees/<slug> (or ./ if unset)
pub fn issue_worktree_dir(task_slug: String) -> String {
  let root = case ffi.get_env("GRKR_ROOT") {
    "" -> "."
    r -> r
  }
  root <> "/.grkr/worktrees/" <> task_slug
}

pub fn issue_worktree_ready(worktree_dir: String) -> Bool {
  let git_marker = worktree_dir <> "/.git"
  ffi.path_exists(git_marker)
}

pub fn issue_worktree_base_ref() -> String {
  let main_branch = case ffi.get_env("MAIN_BRANCH") {
    "" -> "main"
    b -> b
  }
  let origin_ref = "refs/remotes/origin/" <> main_branch
  let local_ref = "refs/heads/" <> main_branch
  case git_check_ref(origin_ref) {
    True -> "origin/" <> main_branch
    False ->
      case git_check_ref(local_ref) {
        True -> main_branch
        False -> "HEAD"
      }
  }
}

fn git_check_ref(ref: String) -> Bool {
  let args = ["show-ref", "--verify", "--quiet", ref]
  let res = ffi.git_exec(args, option.None)
  res.exit_code == 0
}

fn git_ls_remote_has_branch(branch: String) -> Bool {
  let args = ["ls-remote", "--heads", "origin", branch]
  let res = ffi.git_exec(args, option.None)
  case res.exit_code {
    0 -> string.contains(res.stdout, branch)
    _ -> False
  }
}

fn dirname(path: String) -> String {
  let parts = string.split(path, "/")
  case list.reverse(parts) {
    [] -> "."
    [_] -> "."
    [_, ..rest] ->
      case list.reverse(rest) {
        [] -> "."
        ps -> string.join(ps, "/")
      }
  }
}

/// Core: prepare (or reuse) issue worktree. Mirrors bash exactly for msgs + side effects.
/// Prints ♻️ / ⚠️ / 🌿 msgs to stderr via console_error.
/// Returns Ok(dir) on success (dir also echoed to stdout by caller/CLI).
pub fn prepare_issue_worktree(branch: String, task_slug: String) -> Result(String, String) {
  let worktree_dir = issue_worktree_dir(task_slug)
  let parent = dirname(worktree_dir)
  let _ = ffi.mkdir_p(parent)

  case issue_worktree_ready(worktree_dir) {
    True -> {
      ffi.console_error("♻️ Reusing issue worktree: " <> worktree_dir)
      Ok(worktree_dir)
    }
    False -> {
      let local_ref = "refs/heads/" <> branch
      case git_check_ref(local_ref) {
        True -> {
          ffi.console_error(
            "⚠️ Branch " <> branch <> " already exists locally. Reusing it in an issue worktree...",
          )
          let args = ["worktree", "add", worktree_dir, branch]
          case ffi.git_exec(args, option.None) {
            ExecResult(0, _, _) -> Ok(worktree_dir)
            ExecResult(_, _, e) -> Error("Failed to add worktree for existing local branch: " <> e)
          }
        }
        False ->
          case git_ls_remote_has_branch(branch) {
            True -> {
              ffi.console_error(
                "⚠️ Branch " <> branch <> " already exists remotely. Reusing it in an issue worktree...",
              )
              let args = ["worktree", "add", "-b", branch, worktree_dir, "origin/" <> branch]
              case ffi.git_exec(args, option.None) {
                ExecResult(0, _, _) -> Ok(worktree_dir)
                ExecResult(_, _, e) ->
                  Error("Failed to add worktree from remote branch: " <> e)
              }
            }
            False -> {
              let base = issue_worktree_base_ref()
              let args = ["worktree", "add", "-b", branch, worktree_dir, base]
              case ffi.git_exec(args, option.None) {
                ExecResult(0, _, _) -> {
                  ffi.console_error("🌿 Created issue worktree for branch: " <> branch)
                  Ok(worktree_dir)
                }
                ExecResult(_, _, e) -> Error("Failed to create worktree: " <> e)
              }
            }
          }
      }
    }
  }
}

/// git_in_issue_context equiv (for use by other Gleam code in context)
pub fn git_in_issue_context(args: List(String)) -> ExecResult {
  ffi.git_exec_in_context(args, option.None)
}

/// cleanup (force remove worktree). Prints 🧹 msg on success. Host git context.
pub fn cleanup_issue_worktree(worktree_dir: String) -> Result(Nil, String) {
  case worktree_dir {
    "" -> Ok(Nil)
    _ ->
      case ffi.path_exists(worktree_dir) {
        False -> Ok(Nil)
        True -> {
          let args = ["worktree", "remove", "--force", worktree_dir]
          case ffi.git_exec(args, option.None) {
            ExecResult(0, _, _) -> {
              ffi.console_error("🧹 Removed issue worktree: " <> worktree_dir)
              Ok(Nil)
            }
            ExecResult(_, _, e) -> Error("worktree remove failed: " <> e)
          }
        }
      }
  }
}
