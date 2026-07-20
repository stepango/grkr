//// main.gleam
//// Thin public facade for resolve_pr (LOC hygiene split).
//// Stable entry: `gleam run -m grkr/resolve_pr/main` (see bin/worker-resolve-pr.sh).
//// Delegates to workflow/apply/runtime; zero intentional behavior change.
/// Preserves: argv patterns, exit codes (usage=2, fail=1), GLEAM_ENV=test short-circuit,
/// exact log strings, worktree/branch names, CONFLICT_STRATEGY, Resolution* results,
/// push-fail-is-still-Ok on codex path.

import gleam/int
import gleam/io

import grkr/resolve_pr/github
import grkr/resolve_pr/runtime
import grkr/resolve_pr/types
import grkr/resolve_pr/workflow

pub fn main() {
  case runtime.get_env("GLEAM_ENV") {
    "test" -> Nil
    _ -> run_cli()
  }
}

fn run_cli() {
  case runtime.argv() {
    ["help"] | [] -> emit_usage()
    [pr_number] -> run_cli_pr(pr_number)
    ["--", pr_number] -> run_cli_pr(pr_number)
    _ -> emit_usage()
  }
}

fn emit_usage() {
  io.println_error("Usage: worker-resolve-pr.sh <pr_number>")
  io.println_error("       gleam run -m grkr/resolve_pr/main -- <pr_number>")
  io.println_error("PR conflict resolution (full logic: worktree/git/codex/push per spec/parts/14, GitHub-only v2, t_49932a05).")
  io.println_error("Supports CONFLICT_STRATEGY=merge|rebase, BUILD_COMMAND, TEST_COMMAND env.")
  runtime.exit(2)
}

fn run_cli_pr(pr_number: String) {
  case int.parse(pr_number) {
    Ok(number) if number > 0 -> {
      case run(number) {
        Ok(_) -> Nil
        Error(err) -> fail_cli(err)
      }
    }
    _ -> fail_cli("Error: PR number must be a positive integer")
  }
}

fn fail_cli(message: String) {
  io.println_error(message)
  runtime.exit(1)
}

pub fn run(pr_number: Int) -> Result(types.ResolutionResult, String) {
  io.println(
    "Starting PR conflict resolution for #" <> int.to_string(pr_number),
  )

  case github.fetch_pr(pr_number) {
    Ok(pr) -> {
      io.println("Processing PR: " <> pr.title)

      case pr.base_ref == "main", github.is_pr_conflicting(pr) {
        False, _ -> Error("PR base is not main: " <> pr.base_ref)
        _, False -> {
          io.println("PR has no conflicts")
          Ok(types.ResolutionNoConflicts)
        }
        True, True -> workflow.resolve_with_workflow(pr)
      }
    }
    Error(err) -> {
      io.println("Error fetching PR: " <> err)
      Error("Failed to fetch PR: " <> err)
    }
  }
}
