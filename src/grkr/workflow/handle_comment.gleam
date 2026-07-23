//// handle_comment.gleam
//// Thin public facade (LOC hygiene split). Stable CLI entry for bin/worker-handle-comment.sh.
/// Delegates to concern modules while preserving 100% prior behavior + public surface.
/// Zero intentional behavior change.

import gleam/int

import grkr/workflow/handle_comment_codex as codex
import grkr/workflow/handle_comment_context as context
import grkr/workflow/handle_comment_reactions as reactions
import grkr/workflow/handle_comment_result as result
import grkr/workflow/handle_comment_worktree as worktree

import grkr/workflow/ffi

pub fn main() {
  case ffi.argv() {
    ["help"] | [] -> emit_usage()
    [comment_id] -> do_handle(comment_id)
    ["--", comment_id] -> do_handle(comment_id)
    _ -> emit_usage()
  }
}

fn emit_usage() {
  ffi.console_error("Usage: gleam run -m grkr/workflow/handle_comment -- <comment_id>")
  ffi.console_error("Full @robot: comment handler (GitHub-only v2) per spec/15.")
  ffi.console_error("gh context, eyes/rocket, worktree (spec/12), codex classify, reply, cleanup.")
  ffi.exit(2)
}

fn do_handle(comment_id: String) {
  case int.parse(comment_id) {
    Ok(_) -> Nil
    Error(_) -> {
      ffi.console_error("Error: comment_id must be numeric (GitHub id)")
      ffi.exit(1)
    }
  }

  let _ = ffi.console_log("🤖 grkr/workflow/handle_comment: starting for comment_id=" <> comment_id <> " (GitHub-only v2 full)")

  // 1. Fetch context (best effort; no-op if fail)
  let repo = case ffi.get_env("REPO") {
    "" -> "stepango/grkr"
    r -> r
  }
  let main_branch = case ffi.get_env("MAIN_BRANCH") {
    "" -> "main"
    b -> b
  }

  case context.fetch_context(comment_id, repo, main_branch) {
    Ok(ctx) -> {
      let _ = ffi.console_log("   context: comment by @" <> ctx.user_login <> " on " <> case ctx.is_pr { True -> "PR " False -> "" } <> "#" <> ctx.issue_number <> " \"" <> ctx.issue_title <> "\" cmd=\"" <> ctx.raw_cmd <> "\"")

      // 2. eyes reaction (capture id for cleanup)
      let eyes_id = reactions.add_eyes_reaction(comment_id, repo)

      // 3. worktree (per spec/12)
      let worktree_info = worktree.create_comment_worktree(comment_id, ctx, repo, main_branch)

      // 4+5. prompt + codex
      let codex_out =
        codex.run_codex_classify(ctx, worktree_info.branch, worktree_info.dir)

      let #(class, reply, changes) = codex.parse_codex_output(codex_out)

      let _ = ffi.console_log("   parsed: class=" <> class <> " changes=" <> changes)

      // 6+7. post result + optional commit/push
      let _ = result.post_result_comment(ctx, comment_id, repo, class, reply, changes, worktree_info.branch)

      case class {
        "code-change" -> result.try_optional_commit_push(worktree_info.dir, comment_id, ctx.raw_cmd, reply, repo, worktree_info.branch)
        _ -> Nil
      }

      // 8. success reactions: remove eyes + rocket (best effort)
      reactions.remove_eyes_and_add_rocket(comment_id, repo, eyes_id)

      // 9. cleanup
      worktree.cleanup_worktree(worktree_info.dir)

      let _ = ffi.console_log("✅ handle_comment complete for " <> comment_id <> " (class=" <> class <> ", exit=0)")
      ffi.exit(0)
    }
    Error(e) -> {
      ffi.console_error("⚠️ handle_comment fetch failed (best-effort no-op): " <> e)
      ffi.exit(0)
    }
  }
}
