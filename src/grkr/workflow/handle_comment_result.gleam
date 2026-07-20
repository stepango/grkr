//// handle_comment_result.gleam
//// Result comment posting + optional commit/push for handle_comment (LOC hygiene).
//// Exact behavior preserved (best effort).

import gleam/option
import gleam/string

import grkr/workflow/ffi.{ExecResult}
import grkr/workflow/handle_comment_context as ctx
import grkr/workflow/handle_comment_types.{type CommentContext}

pub fn post_result_comment(ctx_in: CommentContext, comment_id: String, repo: String, class: String, reply: String, changes: String, branch: String) -> Nil {
  let result = "**grkr** processed your `@:robot: " <> ctx_in.raw_cmd <> "` (comment " <> comment_id <> ")\n\n**Classification:** " <> class <> "\n**Reply/Notes:** " <> reply <> "\n\n**Changes intent:** " <> changes <> "\n**Worktree:** " <> branch <> " (cleaned)\n**Context:** " <> case ctx_in.is_pr { True -> "PR " False -> "" } <> "#" <> ctx_in.issue_number <> " \"" <> ctx_in.issue_title <> "\"\n\n(Generated via Codex per spec/15; see job log for full prompt/output. This is GitHub-only v2 slice.)"
  let cmd = ["gh", "issue", "comment", ctx_in.issue_number, "--body", result, "--repo", repo]
  case ctx.run_gh(cmd) {
    ExecResult(0, _, _) -> ffi.console_log("   + posted result comment on #" <> ctx_in.issue_number)
    _ -> ffi.console_log("   ⚠️ failed to post result comment (best effort; continuing)")
  }
}

pub fn try_optional_commit_push(dir: String, comment_id: String, raw_cmd: String, reply: String, _repo: String, branch: String) -> Nil {
  // check status with -C
  case ffi.executable("git", ["-C", dir, "status", "--porcelain"], option.None) {
    ExecResult(0, out, _) -> {
      case string.trim(out) {
        "" -> Nil
        _ -> {
          let _ = ffi.executable("git", ["-C", dir, "add", "-A"], option.None)
          let commit_msg = "robot(comment-" <> comment_id <> "): code-change for " <> raw_cmd <> "\n\n" <> reply <> "\n\n[grkr v2 worker-handle-comment]"
          let _ = ffi.executable("git", ["-C", dir, "commit", "-m", commit_msg], option.None)
          case ffi.executable("git", ["-C", dir, "push", "--force-with-lease", "origin", branch], option.None) {
            ExecResult(0, _, _) -> ffi.console_log("   + pushed branch " <> branch <> " (code-change)")
            _ -> ffi.console_log("   ⚠️ push skipped (no perms or no changes)")
          }
        }
      }
    }
    _ -> Nil
  }
}
