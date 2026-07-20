//// workflow.gleam
//// Worktree orchestration and resolution workflow for resolve_pr (LOC hygiene).
//// Extracted: resolve_with_workflow, attempt_resolution, complete_resolution,
//// cleanup_worktree, build_* paths, configured_strategy, strategy_name.
//// Zero intentional behavior change; delegates to apply for codex path.

import gleam/int
import gleam/io
import gleam/string

import grkr/resolve_pr/apply
import grkr/resolve_pr/git
import grkr/resolve_pr/runtime
import grkr/resolve_pr/types

pub fn resolve_with_workflow(
  pr: types.PullRequest,
) -> Result(types.ResolutionResult, String) {
  let worktree_path = build_worktree_path(pr.number)
  let local_branch = build_worktree_branch(pr.number)
  let original_dir = runtime.cwd()
  let strategy = configured_strategy()

  io.println("Creating worktree at: " <> worktree_path)

  let setup_result = case pr.is_cross_repository {
    True -> Error("Cross-repository PR conflict resolution is not supported")
    False -> {
      use _ <- runtime.result_try(git.check_ref_name(pr.head_ref))
      use _ <- runtime.result_try(git.fetch_origin("main"))
      use _ <- runtime.result_try(git.fetch_pr_head(pr.number, local_branch))
      git.create_worktree_from_branch(local_branch, worktree_path)
    }
  }

  case setup_result {
    Error(err) -> {
      io.println("Setup failed: " <> err)
      Error("Worktree setup failed: " <> err)
    }
    Ok(_) -> {
      let resolution_result = attempt_resolution(pr, worktree_path, strategy)

      let _cleanup = cleanup_worktree(worktree_path, original_dir)

      resolution_result
    }
  }
}

pub fn attempt_resolution(
  pr: types.PullRequest,
  worktree_path: String,
  strategy: types.ResolutionStrategy,
) -> Result(types.ResolutionResult, String) {
  let _ = runtime.chdir(worktree_path)

  io.println("Attempting " <> strategy_name(strategy) <> "...")
  let integration_result = case strategy {
    types.Rebase -> git.rebase_branch("origin/main")
    types.Merge -> git.merge_branch("origin/main")
  }

  case integration_result {
    Ok(_) -> {
      io.println(strategy_name(strategy) <> " successful")
      complete_resolution(pr, worktree_path)
    }
    Error(err) -> {
      io.println(strategy_name(strategy) <> " failed: " <> err)

      case git.in_conflict_state() {
        True -> {
          io.println("Conflicts detected, invoking Codex...")
          apply.resolve_with_codex(pr, worktree_path, strategy)
        }
        False -> {
          let _result = git.abort_merge_or_rebase()
          Error(strategy_name(strategy) <> " failed without conflicts: " <> err)
        }
      }
    }
  }
}

fn complete_resolution(
  pr: types.PullRequest,
  _worktree_path: String,
) -> Result(types.ResolutionResult, String) {
  let sha = case git.get_current_head_sha() {
    Ok(s) -> s
    Error(_) -> "unknown"
  }

  case runtime.run_validation_commands() {
    Ok(_) -> {
      case git.push_branch(pr.head_ref) {
        Ok(_) -> {
          io.println("Successfully pushed")
          Ok(types.ResolutionSuccess(
            resolved_files: [],
            commit_sha: sha,
            pushed: True,
          ))
        }
        Error(err) -> Error("Push failed: " <> err)
      }
    }
    Error(err) -> Error("Validation failed: " <> err)
  }
}

pub fn cleanup_worktree(
  worktree_path: String,
  original_dir: String,
) -> Result(Nil, String) {
  let _ = runtime.chdir(original_dir)
  git.remove_worktree(worktree_path)
}

pub fn build_worktree_path(pr_number: Int) -> String {
  ".grkr/worktrees/pr-" <> int.to_string(pr_number)
}

pub fn build_worktree_branch(pr_number: Int) -> String {
  "robot/pr-" <> int.to_string(pr_number) <> "-conflict"
}

pub fn configured_strategy() -> types.ResolutionStrategy {
  case runtime.get_env("CONFLICT_STRATEGY") |> string.lowercase {
    "rebase" -> types.Rebase
    _ -> types.Merge
  }
}

pub fn strategy_name(strategy: types.ResolutionStrategy) -> String {
  case strategy {
    types.Rebase -> "rebase"
    types.Merge -> "merge"
  }
}
