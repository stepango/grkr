import gleam/int
import gleam/io
import gleam/list
import gleam/string
import grkr/resolve_pr/codex
import grkr/resolve_pr/git
import grkr/resolve_pr/github
import grkr/resolve_pr/types

type ExecResult {
  ExecResult(exit_code: Int, stdout: String, stderr: String)
}

pub fn main() {
  case javascript_get_env("GLEAM_ENV") {
    "test" -> Nil
    _ -> run_cli()
  }
}

fn run_cli() {
  case javascript_argv() {
    [pr_number] -> run_cli_pr(pr_number)
    _ -> fail_cli("Usage: worker-resolve-pr.sh <pr_number>")
  }
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
  javascript_exit(1)
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
        True, True -> resolve_with_workflow(pr)
      }
    }
    Error(err) -> {
      io.println("Error fetching PR: " <> err)
      Error("Failed to fetch PR: " <> err)
    }
  }
}

fn resolve_with_workflow(
  pr: types.PullRequest,
) -> Result(types.ResolutionResult, String) {
  let worktree_path = build_worktree_path(pr.number)
  let local_branch = build_worktree_branch(pr.number)
  let original_dir = javascript_cwd()
  let strategy = configured_strategy()

  io.println("Creating worktree at: " <> worktree_path)

  let setup_result = case pr.is_cross_repository {
    True -> Error("Cross-repository PR conflict resolution is not supported")
    False -> {
      use _ <- result_try(git.check_ref_name(pr.head_ref))
      use _ <- result_try(git.fetch_origin("main"))
      use _ <- result_try(git.fetch_pr_head(pr.number, local_branch))
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

fn attempt_resolution(
  pr: types.PullRequest,
  worktree_path: String,
  strategy: types.ResolutionStrategy,
) -> Result(types.ResolutionResult, String) {
  let _ = javascript_chdir(worktree_path)

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
          resolve_with_codex(pr, worktree_path, strategy)
        }
        False -> {
          let _result = git.abort_merge_or_rebase()
          Error(strategy_name(strategy) <> " failed without conflicts: " <> err)
        }
      }
    }
  }
}

fn resolve_with_codex(
  pr: types.PullRequest,
  _worktree_path: String,
  strategy: types.ResolutionStrategy,
) -> Result(types.ResolutionResult, String) {
  case git.get_conflicted_files() {
    Ok(conflict_paths) -> {
      io.println(
        "Found "
        <> int.to_string(list.length(conflict_paths))
        <> " conflicted files",
      )

      let conflicts =
        list.map(conflict_paths, fn(path) {
          types.ConflictFile(
            path: path,
            our_content: get_file_conflict_content(path, "ours"),
            their_content: get_file_conflict_content(path, "theirs"),
          )
        })

      case codex.resolve_conflicts(conflicts) {
        Ok(resolutions) -> {
          case
            validate_and_apply_resolutions(
              conflicts,
              conflict_paths,
              resolutions,
            )
          {
            Ok(_) -> {
              case git.stage_paths(conflict_paths) {
                Ok(_commit_output) -> {
                  case run_validation_commands() {
                    Ok(_) -> {
                      case finish_integration(strategy) {
                        Ok(_) -> {
                          let sha = case git.get_current_head_sha() {
                            Ok(s) -> s
                            Error(_) -> "unknown"
                          }

                          case git.push_branch(pr.head_ref) {
                            Ok(_) -> {
                              io.println("Successfully pushed resolved changes")
                              Ok(types.ResolutionSuccess(
                                resolved_files: conflict_paths,
                                commit_sha: sha,
                                pushed: True,
                              ))
                            }
                            Error(err) -> {
                              io.println("Push failed: " <> err)
                              Ok(types.ResolutionSuccess(
                                resolved_files: conflict_paths,
                                commit_sha: sha,
                                pushed: False,
                              ))
                            }
                          }
                        }
                        Error(err) -> {
                          let _result = git.abort_merge_or_rebase()
                          Error("Failed to finish integration: " <> err)
                        }
                      }
                    }
                    Error(err) -> {
                      let _result = git.abort_merge_or_rebase()
                      Error("Validation failed: " <> err)
                    }
                  }
                }
                Error(err) -> {
                  let _result = git.abort_merge_or_rebase()
                  Error("Failed to stage resolutions: " <> err)
                }
              }
            }
            Error(err) -> {
              let _result = git.abort_merge_or_rebase()
              Error("Failed to apply resolutions: " <> err)
            }
          }
        }
        Error(err) -> {
          let _result = git.abort_merge_or_rebase()
          Error("Codex resolution failed: " <> err)
        }
      }
    }
    Error(err) -> {
      let _result = git.abort_merge_or_rebase()
      Error("Failed to get conflicted files: " <> err)
    }
  }
}

fn finish_integration(
  strategy: types.ResolutionStrategy,
) -> Result(String, String) {
  case strategy {
    types.Rebase -> git.continue_rebase()
    types.Merge -> git.commit_staged("Resolve merge conflicts via Codex")
  }
}

fn validate_and_apply_resolutions(
  conflicts: List(types.ConflictFile),
  paths: List(String),
  resolutions: List(types.CodexResolution),
) -> Result(Nil, String) {
  case conflicts, paths, resolutions {
    [], [], [] -> Ok(Nil)
    [conflict, ..rest_conflicts],
      [path, ..rest_paths],
      [resolution, ..rest_resolutions]
    -> {
      use _ <- result_try(codex.validate_resolution(conflict, resolution))
      use _ <- result_try(apply_single_resolution(path, resolution))
      validate_and_apply_resolutions(
        rest_conflicts,
        rest_paths,
        rest_resolutions,
      )
    }
    _, _, _ -> Error("Mismatch between conflicts, paths, and resolutions")
  }
}

fn apply_single_resolution(
  path: String,
  resolution: types.CodexResolution,
) -> Result(Nil, String) {
  case resolution {
    types.CodexResolution(resolved_content, _) ->
      write_file_content(path, resolved_content)
    types.CodexSkipped(reason) -> Error("Resolution skipped: " <> reason)
    types.CodexFailed(err) -> Error("Resolution failed: " <> err)
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

  case run_validation_commands() {
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

fn cleanup_worktree(
  worktree_path: String,
  original_dir: String,
) -> Result(Nil, String) {
  let _ = javascript_chdir(original_dir)
  git.remove_worktree(worktree_path)
}

fn build_worktree_path(pr_number: Int) -> String {
  ".grkr/worktrees/pr-" <> int.to_string(pr_number)
}

fn build_worktree_branch(pr_number: Int) -> String {
  "robot/pr-" <> int.to_string(pr_number) <> "-conflict"
}

fn configured_strategy() -> types.ResolutionStrategy {
  case javascript_get_env("CONFLICT_STRATEGY") |> string.lowercase {
    "rebase" -> types.Rebase
    _ -> types.Merge
  }
}

fn strategy_name(strategy: types.ResolutionStrategy) -> String {
  case strategy {
    types.Rebase -> "rebase"
    types.Merge -> "merge"
  }
}

fn get_file_conflict_content(path: String, side: String) -> String {
  let stage = case side {
    "ours" -> "2"
    "theirs" -> "3"
    _ -> side
  }
  let cmd = ["git", "show", ":" <> stage <> ":" <> path]

  case execute_command(cmd, "") {
    Ok(content) -> content
    Error(_) -> ""
  }
}

fn write_file_content(path: String, content: String) -> Result(Nil, String) {
  javascript_write_file(path, content)
}

fn run_validation_commands() -> Result(Nil, String) {
  let commands =
    [javascript_get_env("BUILD_COMMAND"), javascript_get_env("TEST_COMMAND")]
    |> list.map(string.trim)
    |> list.filter(fn(command) { command != "" })

  list.try_each(commands, fn(command) {
    io.println("Running validation command: " <> command)
    case execute_command(["bash", "-lc", command], "") {
      Ok(_) -> Ok(Nil)
      Error(err) -> Error(command <> ": " <> err)
    }
  })
}

fn result_try(
  result: Result(a, String),
  next: fn(a) -> Result(b, String),
) -> Result(b, String) {
  case result {
    Ok(value) -> next(value)
    Error(err) -> Error(err)
  }
}

fn execute_command(cmd: List(String), input: String) -> Result(String, String) {
  case cmd {
    [] -> Error("Empty command")
    [command, ..args] -> {
      let result = javascript_executable(command, args, input)
      case result {
        ExecResult(exit_code, stdout, _stderr) -> {
          case exit_code {
            0 -> Ok(stdout)
            _ ->
              Error(
                "Command failed with exit code " <> int.to_string(exit_code),
              )
          }
        }
      }
    }
  }
}

@external(javascript, "../resolve_pr/exec.mjs", "executable")
fn javascript_executable(
  command: String,
  args: List(String),
  input: String,
) -> ExecResult

@external(javascript, "../resolve_pr/fs.mjs", "write_file")
fn javascript_write_file(path: String, content: String) -> Result(Nil, String)

@external(javascript, "../resolve_pr/env.mjs", "argv")
fn javascript_argv() -> List(String)

@external(javascript, "../resolve_pr/env.mjs", "get_env")
fn javascript_get_env(name: String) -> String

@external(javascript, "process", "chdir")
fn javascript_chdir(path: String) -> Nil

@external(javascript, "process", "cwd")
fn javascript_cwd() -> String

@external(javascript, "process", "exit")
fn javascript_exit(code: Int) -> Nil
