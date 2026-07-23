//// apply.gleam
//// Codex conflict resolution application path for resolve_pr (LOC hygiene).
//// Extracted verbatim behavior from main: resolve_with_codex, finish_integration,
//// validate_and_apply_resolutions, apply_single_resolution, get_file_conflict_content,
//// write_file_content. Zero intentional behavior change.

import gleam/int
import gleam/io
import gleam/list

import grkr/resolve_pr/codex
import grkr/resolve_pr/git
import grkr/resolve_pr/runtime
import grkr/resolve_pr/types

pub fn resolve_with_codex(
  pr: types.PullRequest,
  worktree_path: String,
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

      case codex.resolve_conflicts(conflicts, worktree_path) {
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
                  case runtime.run_validation_commands() {
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
          Error("Coding agent resolution failed: " <> err)
        }
      }
    }
    Error(err) -> {
      let _result = git.abort_merge_or_rebase()
      Error("Failed to get conflicted files: " <> err)
    }
  }
}

pub fn finish_integration(
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
      use _ <- runtime.result_try(codex.validate_resolution(conflict, resolution))
      use _ <- runtime.result_try(apply_single_resolution(path, resolution))
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

fn get_file_conflict_content(path: String, side: String) -> String {
  let stage = case side {
    "ours" -> "2"
    "theirs" -> "3"
    _ -> side
  }
  let cmd = ["git", "show", ":" <> stage <> ":" <> path]

  case runtime.execute_command(cmd, "") {
    Ok(content) -> content
    Error(_) -> ""
  }
}

fn write_file_content(path: String, content: String) -> Result(Nil, String) {
  runtime.write_file(path, content)
}
