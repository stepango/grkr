//// resolve_pr.gleam
//// Skeleton CLI entry + types for worker-resolve-pr.sh (GitHub-only v2) per t_f4d7a801 + spec/parts/14 + 39 item 11 (#20).
//// Thin delegation; no full conflict automation (worktree, git rebase/merge, codex, push, validation, cleanup) in this card.
//// Types included per card (subset of early resolve_pr/types.gleam); CLI entry only (stub success for wiring).
//// Supervisor detection still uses resolve_pr/github (separate); this is the execution worker entry.
//// Matches bin contract: <pr_number> arg, numeric validation, usage on bad, exit 0/1/2.
//// AGENTS.md: small explicit, <1000 LOC (this ~90), preserve bin/ sh conventions. Full port in follow-up slices.

import gleam/int

import grkr/workflow/ffi

@external(javascript, "./cli_ffi.mjs", "argv")
fn argv() -> List(String)

/// Types (skeleton; full fields/logic in later slices per spec/14)
pub type PullRequest {
  PullRequest(
    number: Int,
    title: String,
    author: String,
    head_ref: String,
    head_sha: String,
    base_ref: String,
    mergeable: Bool,
    conflicted: Bool,
    is_cross_repository: Bool,
  )
}

pub type ConflictFile {
  ConflictFile(path: String, our_content: String, their_content: String)
}

pub type ResolutionStrategy {
  Rebase
  Merge
}

pub type ResolutionResult {
  ResolutionSuccess(
    resolved_files: List(String),
    commit_sha: String,
    pushed: Bool,
  )
  ResolutionNoConflicts
  ResolutionFailed(error: String)
}

pub type WorktreeContext {
  WorktreeContext(
    pr_number: Int,
    worktree_path: String,
    branch_name: String,
    original_dir: String,
  )
}

pub type CodexResolution {
  CodexResolution(resolved_content: String, explanation: String)
  CodexSkipped(reason: String)
  CodexFailed(error: String)
}

pub fn main() {
  case argv() {
    ["help"] | [] -> emit_usage()
    [pr_number] -> do_resolve(pr_number)
    ["--", pr_number] -> do_resolve(pr_number)
    _ -> emit_usage()
  }
}

fn emit_usage() {
  ffi.console_error("Usage: worker-resolve-pr.sh <pr_number>")
  ffi.console_error("       gleam run -m grkr/resolve_pr/main -- <pr_number> (preferred; this skeleton is legacy ref)")
  ffi.console_error("Skeleton (types + CLI entry) for PR conflict resolution per spec/14 (GitHub-only v2, t_f4d7a801).")
  ffi.console_error("Full: fetch PR, worktree, rebase/merge, codex on conflicts, validate, commit/push, cleanup in follow-up.")
  ffi.exit(2)
}

fn do_resolve(pr_number: String) {
  case int.parse(pr_number) {
    Ok(n) if n > 0 -> {
      let _ =
        ffi.console_log(
          "Starting PR conflict resolution for #"
          <> int.to_string(n)
          <> " (GitHub-only v2 skeleton t_f4d7a801)",
        )
      let _ =
        ffi.console_log(
          "   (stub: no full worktree/git/codex/fetch/push yet; see resolve_pr/ for early impl + supervisor phases)",
        )
      let _ =
        ffi.console_log(
          "✅ resolve_pr complete for #" <> int.to_string(n) <> " (stub, exit=0)",
        )
      ffi.exit(0)
    }
    _ -> {
      ffi.console_error("Error: PR number must be a positive integer")
      ffi.exit(1)
    }
  }
}
