//// comment_handler_worktree.gleam
//// Worktree create + cleanup for supervisor/comment_handler (spec/12) (LOC hygiene).
//// Exact bodies moved; PR vs issue base selection and fallback unchanged.

import gleam/option.{None}
import gleam/string

import grkr/workflow/ffi.{ExecResult}
import grkr/supervisor/comment_handler_context as ctx
import grkr/supervisor/comment_handler_types.{type CommentContext, type WorktreeInfo, WorktreeInfo}

pub fn create_comment_worktree(comment_id: String, ctx_in: CommentContext, repo: String, main_branch: String) -> WorktreeInfo {
  let grkr_dir = case ffi.get_env("GRKR_DIR") {
    "" -> ".grkr"
    d -> d
  }
  let worktrees_dir = grkr_dir <> "/worktrees"
  let _ = ffi.mkdir_p(worktrees_dir)
  let worktree_dir = worktrees_dir <> "/comment-" <> comment_id
  let branch_name = "robot/comment-" <> comment_id

  // determine base
  let base_ref = case ctx_in.is_pr {
    True -> {
      // fetch pr head
      let pr_cmd = ["gh", "api", "repos/" <> repo <> "/pulls/" <> ctx_in.issue_number, "--jq", ".head.ref // \"main\""]
      let pr_ref = case ctx.run_gh(pr_cmd) {
        ExecResult(0, out, _) -> {
          let r = string.trim(out)
          case r {
            "" -> main_branch
            _ -> r
          }
        }
        _ -> main_branch
      }
      "origin/" <> pr_ref
    }
    False -> "origin/" <> main_branch
  }

  let _ = ffi.console_log("   worktree: " <> case ctx_in.is_pr { True -> "PR comment" False -> "issue comment" } <> " base=" <> base_ref)

  // force clean prior
  let _ = ffi.git_exec(["worktree", "remove", worktree_dir, "--force"], None)
  let _ = ffi.git_exec(["branch", "-D", branch_name], None)

  // fetch
  let _ = ffi.git_exec(["fetch", "origin", main_branch, "--quiet"], None)
  let _ = case ctx_in.is_pr {
    True -> {
      // try fetch pr head ref? skip details
      Nil
    }
    False -> Nil
  }

  // add worktree
  let add_args = ["worktree", "add", "-b", branch_name, worktree_dir, base_ref]
  case ffi.git_exec(add_args, None) {
    ExecResult(0, _, _) -> {
      let _ = ffi.console_log("   + worktree created at " <> worktree_dir <> " (branch " <> branch_name <> ")")
      // configure author (best effort, host git may suffice)
      let _ = ffi.git_exec(["-C", worktree_dir, "config", "user.name", "grkr-bot"], None)
      let _ = ffi.git_exec(["-C", worktree_dir, "config", "user.email", "grkr@noreply.github.com"], None)
      let _ = ffi.git_exec(["-C", worktree_dir, "config", "commit.gpgsign", "false"], None)
      WorktreeInfo(dir: worktree_dir, branch: branch_name)
    }
    _ -> {
      let _ = ffi.console_log("   ⚠️ worktree create failed; falling back to temp dir (no git ops)")
      // fallback temp (no git)
      let tmp = worktrees_dir <> "/comment-" <> comment_id <> ".tmp"
      let _ = ffi.mkdir_p(tmp)
      WorktreeInfo(dir: tmp, branch: branch_name)
    }
  }
}

pub fn cleanup_worktree(dir: String) -> Nil {
  case dir {
    "" -> Nil
    d -> {
      let _ = ffi.git_exec(["worktree", "remove", d, "--force"], None)
      let _ = ffi.executable("rm", ["-rf", d], None)
      ffi.console_log("   + worktree removed")
    }
  }
}
