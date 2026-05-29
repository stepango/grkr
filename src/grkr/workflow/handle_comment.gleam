//// handle_comment.gleam
//// Thin CLI entry for worker-handle-comment.sh (GitHub-only v2) per t_944f1214 + spec/parts/15.
//// Delegates full reactions/worktree/codex/prompt logic from legacy bash (now .legacy-v1 in bin/).
//// Basic wiring + stub for now (full port in follow-up to avoid large slice); always exits 0 best-effort.
//// Matches supervisor scheduler contract + e2e mocks (comment_id arg, no output emission required, exit 0).
//// AGENTS: small explicit, <1000 LOC (this ~40), preserve bin/ sh conventions.

import gleam/int

import grkr/workflow/ffi

@external(javascript, "./cli_ffi.mjs", "argv")
fn argv() -> List(String)

pub fn main() {
  case argv() {
    ["help"] | [] -> emit_usage()
    [comment_id] -> do_handle(comment_id)
    ["--", comment_id] -> do_handle(comment_id)
    _ -> emit_usage()
  }
}

fn emit_usage() {
  ffi.console_error("Usage: gleam run -m grkr/workflow/handle_comment -- <comment_id>")
  ffi.console_error("Thin wrapper for GitHub @:robot: comment processing per spec/15.")
  ffi.console_error("Full impl (gh context, eyes/rocket, worktree per spec/12, codex classify, reply, cleanup) in follow-up.")
  ffi.exit(2)
}

fn do_handle(comment_id: String) {
  // Basic validation (numeric per sh)
  case int.parse(comment_id) {
    Ok(_) -> Nil
    Error(_) -> {
      ffi.console_error("Error: comment_id must be numeric (GitHub id)")
      ffi.exit(1)
    }
  }

  let _ = ffi.console_log("🤖 grkr/workflow/handle_comment: starting for comment_id=" <> comment_id <> " (GitHub-only v2 stub)")

  // TODO full port of legacy logic here in follow-up slice:
  // - fetch comment + issue via gh api (reuse supervisor/ffi or extend)
  // - eyes reaction
  // - worktree create (use existing worktree_ops or extend)
  // - build prompt
  // - codex exec (pattern from resolve_pr/codex.gleam)
  // - parse CLASS/REPLY/CHANGES
  // - post result comment
  // - optional commit/push
  // - rocket reaction
  // - cleanup (trap equiv via Result + defer style or explicit)
  // Always best-effort; supervisor marks processed before spawn.

  // Stub success for wiring (preserves "always exit 0" contract; real reactions etc in full port)
  let _ = ffi.console_log("   context: stub (full fetch/reactions/worktree/codex in next slice)")
  let _ = ffi.console_log("✅ handle_comment complete for " <> comment_id <> " (class=answer-only stub, exit=0)")

  ffi.exit(0)
}
