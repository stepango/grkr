import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import grkr/progress/checkpoint_id
import grkr/progress/checkpoint_stage

import grkr/refusal/assessment
import grkr/refusal/ffi
import grkr/refusal/types.{type RefusalClass, type RefusalConfig, type RefusalError, OtherError}

/// Refusal checkpoint result (comment id for progress.json)
pub type RefusalCheckpoint {
  RefusalCheckpoint(
    comment_id: Option(String),
  )
}

/// Returns the full issue JSON via gh (used by flow and ensure for comment scan)
pub fn fetch_issue_json(repo: String, issue_number: Int) -> Result(String, String) {
  let args = [
    "issue", "view", int.to_string(issue_number),
    "--repo", repo,
    "--comments",
    "--json", "title,body,url,number,projectItems,comments",
  ]
  let res = ffi.execute_command("gh", args)
  case res.exit_code {
    0 -> Ok(res.stdout)
    _ -> Error("gh issue view failed: " <> res.stderr)
  }
}

/// Find the id (string) of the last comment whose body contains the marker
fn find_comment_id_with_marker(issue_json: String, marker: String) -> Option(String) {
  case ffi.parse(issue_json) {
    Error(_) -> None
    Ok(v) -> {
      let comments_v = ffi.get_field_path(v, ["comments"])
      case ffi.decode_array(comments_v) {
        Error(_) -> None
        Ok(comments) -> {
          // filter those containing marker in body, take last (most recent)
          let matching =
            list.filter(comments, fn(c) {
              let body = ffi.get_field_path_string(c, ["body"])
              string.contains(body, marker)
            })
          case list.last(matching) {
            Ok(c) -> Some(ffi.get_field_string(c, "id"))
            Error(_) -> None
          }
        }
      }
    }
  }
}

/// Extract the body of the comment containing the marker (for restore)
fn extract_comment_body_with_marker(issue_json: String, marker: String) -> Option(String) {
  case ffi.parse(issue_json) {
    Error(_) -> None
    Ok(v) -> {
      let comments_v = ffi.get_field_path(v, ["comments"])
      case ffi.decode_array(comments_v) {
        Error(_) -> None
        Ok(comments) -> {
          let matching =
            list.filter(comments, fn(c) {
              let body = ffi.get_field_path_string(c, ["body"])
              string.contains(body, marker)
            })
          case list.last(matching) {
            Ok(c) -> Some(ffi.get_field_path_string(c, ["body"]))
            Error(_) -> None
          }
        }
      }
    }
  }
}

/// Write the refusal.md and post as comment (idempotent via caller), return the new comment id
fn write_and_post_checkpoint(
  cfg: RefusalConfig,
  issue_number: Int,
  checkpoint_file: String,
  task_slug: String,
  title: String,
  class: RefusalClass,
  reasoning: String,
) -> Result(Option(String), RefusalError) {
  let body =
    assessment.format_full_refusal_md(
      task_slug,
      Some(issue_number),
      title,
      class,
      reasoning,
    )

  case ffi.write_file(checkpoint_file, body) {
    Error(e) -> Error(OtherError("write refusal.md failed: " <> e))
    Ok(_) -> {
      // post the comment
      let post_args = [
        "issue", "comment", int.to_string(issue_number),
        "--repo", cfg.repo,
        "--body-file", checkpoint_file,
      ]
      let post = ffi.execute_command("gh", post_args)
      case post.exit_code {
        0 -> {
          // refetch to get the new comment id
          case fetch_issue_json(cfg.repo, issue_number) {
            Error(e) -> Error(OtherError("refetch after post failed: " <> e))
            Ok(new_json) -> {
              let marker =
                checkpoint_id.marker(checkpoint_stage.Refusal, task_slug)
                |> checkpoint_id.to_html_comment()
              let new_id = find_comment_id_with_marker(new_json, marker)
              Ok(new_id)
            }
          }
        }
        _ -> Error(OtherError("gh issue comment failed: " <> post.stderr))
      }
    }
  }
}

/// Idempotent ensure: writes refusal.md + posts GH comment exactly once.
/// Ports shell ensure_refusal_checkpoint + write + comment json scan.
/// GitHub-only v2.
pub fn ensure_refusal_checkpoint(
  cfg: RefusalConfig,
  issue_number: Int,
  issue_json: String,
  task_slug: String,
  title: String,
  class: RefusalClass,
  reasoning: String,
) -> Result(RefusalCheckpoint, RefusalError) {
  let marker =
    checkpoint_id.marker(checkpoint_stage.Refusal, task_slug)
    |> checkpoint_id.to_html_comment()

  let checkpoint_file = cfg.tasks_dir <> "/" <> task_slug <> "/refusal.md"

  let comment_id = find_comment_id_with_marker(issue_json, marker)
  let file_exists = ffi.exists_file(checkpoint_file)

  case file_exists, comment_id {
    True, Some(id) -> {
      // reuse existing
      Ok(RefusalCheckpoint(comment_id: Some(id)))
    }
    False, Some(id) -> {
      // restore file from existing comment body
      case extract_comment_body_with_marker(issue_json, marker) {
        Some(body) -> {
          // best-effort restore from comment (non-fatal)
          let _ = case ffi.write_file(checkpoint_file, body) {
            Ok(_) -> Nil
            Error(_) -> Nil
          }
          Ok(RefusalCheckpoint(comment_id: Some(id)))
        }
        None -> {
          // fallback to write+post
          case write_and_post_checkpoint(cfg, issue_number, checkpoint_file, task_slug, title, class, reasoning) {
            Ok(new_id) -> Ok(RefusalCheckpoint(comment_id: new_id))
            Error(e) -> Error(e)
          }
        }
      }
    }
    _, _ -> {
      // no prior, write file and post comment
      case write_and_post_checkpoint(cfg, issue_number, checkpoint_file, task_slug, title, class, reasoning) {
        Ok(new_id) -> Ok(RefusalCheckpoint(comment_id: new_id))
        Error(e) -> Error(e)
      }
    }
  }
}