//// comment_handler.gleam
//// Thin CLI entrypoint for worker-handle-comment (GitHub-only v2).
//// Per spec/parts/15-phase-3-detect-and-process-robot-comments.md, AGENTS.md, t_058fa950.
//// Currently stub (full reactions, worktree, codex prompt+dispatch, gh mutations ported from
//// bin/worker-handle-comment.sh.legacy-v1 in future dedicated slice; matches original stub TODO).
//// For now: logs, best-effort no-op success (exit 0), supports the scheduler spawn contract.
//// Later: port full logic here using supervisor/ffi for gh/git/codex + json decode + worktree helpers.
//// Emits nothing special (supervisor does not parse; always 0 on completion).

@external(javascript, "../supervisor/cli_ffi.mjs", "argv")
fn argv() -> List(String)

@external(javascript, "console", "error")
fn console_error(s: String) -> Nil

@external(javascript, "process", "exit")
fn exit(code: Int) -> Nil

pub fn main() {
  let args = argv()
  case args {
    [] -> {
      console_error("Usage: gleam run -m grkr/supervisor/comment_handler -- <comment_id>")
      exit(1)
    }
    [comment_id, ..] -> run_handle(comment_id)
  }
}

fn run_handle(comment_id: String) {
  console_error("🤖 grkr/supervisor/comment_handler: starting for comment_id=" <> comment_id <> " (GitHub-only v2 stub)")
  console_error("   (full impl: eyes reaction, worktree per spec/12, codex prompt from cmd+context+policy, action dispatch, result comment, reactions update, cleanup)")
  console_error("   See bin/worker-handle-comment.sh.legacy-v1 for current full shell parity.")
  console_error("   Stub per t_058fa950 + original TODO in stub; thin sh finalized.")
  console_error("✅ worker-handle-comment complete for " <> comment_id <> " (stub, exit=0)")
  exit(0)
}
