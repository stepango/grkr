//// resolve_pr.gleam (workflow/)
//// Legacy reference stub. Canonical implementation is resolve_pr/main.gleam
//// (full run(): fetch, worktree, rebase/merge, codex, validate, push, cleanup).
////
//// bin/worker-resolve-pr.sh now delegates directly to grkr/resolve_pr/main
//// (per t_49932a05 + spec/parts/14). This file retained only for docs/history
//// (was t_f4d7a801 skeleton). No duplicate behavior or entry point.
////
//// See: src/grkr/resolve_pr/main.gleam, bin/worker-resolve-pr.sh, docs/gleam-migration.md

pub type PullRequest { PullRequest }  // legacy placeholder; full in resolve_pr/types
pub type ResolutionResult { ResolutionResult }  // see resolve_pr/main + types

pub fn main() { Nil }  // no-op; use gleam run -m grkr/resolve_pr/main instead
