import grkr/workflow/ffi
import grkr/workflow/worktree_ops as ops
import grkr/workflow/worktree_stage as stage
import gleam/string

/// CLI entry for workflow (GitHub-only v2).
/// Subcommands:
///   prepare <branch> <task-slug>   Prepare/reuse issue worktree (prints msgs to stderr, bare dir to stdout for $(capture))
///   cleanup <worktree-dir>         Force remove worktree
///   collect-relevant
///   stage-relevant
///   help
/// Mirrors bash grkr-issue-workflow.sh prepare_issue_worktree / cleanup_issue_worktree + collect/stage parity.
/// Invoked as: gleam run -m grkr/workflow/main -- prepare issue-123 my-task-slug
/// Updated for worktree split (t_d704484d): direct imports from ops/stage submodules.
pub fn main() {
  case ffi.argv() {
    ["prepare", branch, slug] -> do_prepare(branch, slug)
    ["cleanup", dir] -> do_cleanup(dir)
    ["collect-relevant"] -> do_collect()
    ["stage-relevant"] -> do_stage()
    ["help"] | [] -> emit_usage()
    _ -> emit_usage()
  }
}

fn emit_usage() {
  ffi.console_error("Usage: gleam run -m grkr/workflow/main -- prepare <branch> <task-slug>")
  ffi.console_error("       gleam run -m grkr/workflow/main -- cleanup <worktree-dir>")
  ffi.console_error("       gleam run -m grkr/workflow/main -- collect-relevant")
  ffi.console_error("       gleam run -m grkr/workflow/main -- stage-relevant")
  ffi.console_error("       gleam run -m grkr/workflow/main -- help")
  ffi.console_error("")
  ffi.console_error("Prepares isolated git worktree under $GRKR_ROOT/.grkr/worktrees/<slug>")
  ffi.console_error("for issue workflows. Reuses existing branch/worktree when possible.")
  ffi.console_error("Emits human msgs (♻️ ⚠️ 🌿 🧹) to stderr; success path to stdout (for shell var capture).")
  ffi.console_error("Respects CURRENT_ISSUE_WORKTREE for context git ops (collect/stage).")
  ffi.exit(2)
}

fn do_collect() {
  let paths = stage.collect_relevant_issue_paths()
  case paths {
    [] -> Nil
    _ -> ffi.console_log(string.join(paths, "\n"))
  }
  ffi.exit(0)
}

fn do_stage() {
  stage.stage_relevant_issue_files()
  ffi.exit(0)
}

fn do_prepare(branch: String, slug: String) {
  case ops.prepare_issue_worktree(branch, slug) {
    Ok(dir) -> {
      // bare path to stdout for var=$(...) capture, exactly like old bash printf
      ffi.console_log(dir)
      ffi.exit(0)
    }
    Error(e) -> {
      ffi.console_error("❌ prepare_issue_worktree failed: " <> e)
      ffi.exit(1)
    }
  }
}

fn do_cleanup(dir: String) {
  case ops.cleanup_issue_worktree(dir) {
    Ok(_) -> ffi.exit(0)
    Error(e) -> {
      ffi.console_error("❌ cleanup_issue_worktree failed: " <> e)
      ffi.exit(1)
    }
  }
}
