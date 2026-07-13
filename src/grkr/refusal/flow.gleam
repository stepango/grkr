import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import grkr/refusal/checkpoint
import grkr/refusal/config
import grkr/refusal/ffi
import grkr/refusal/types.{
  type RefusalConfig, type RefusalError, type RefusalResult,
  OtherError, Other, normalize_refusal_class, to_string, RefusalResult,
}
import grkr/task_slug

/// Run the full refusal flow for a GitHub issue (GitHub-only, no Linear).
/// - Fetches issue (title, projectItems, comments)
/// - Computes stable task_slug
/// - Ensures refusal checkpoint (writes refusal.md + posts comment once)
/// - Updates progress.json via FFI (status=refused, test=skipped)
/// - Optionally moves project item to Backlog via gh project item-edit
/// Returns structured result for caller (e.g. main or tests).
pub fn run_refusal(
  issue_number: Int,
  class_raw: String,
  reasoning_raw: String,
) -> Result(RefusalResult, RefusalError) {
  use cfg <- result.try(config.load_runtime_config())

  // fetch issue json (title + comments + projectItems)
  use issue_json <- result.try(
    case checkpoint.fetch_issue_json(cfg.repo, issue_number) {
      Ok(j) -> Ok(j)
      Error(e) -> Error(OtherError("fetch_issue_failed: " <> e))
    }
  )

  let title = extract_title_from_issue_json(issue_json)
  let task_slug = task_slug.task_slug_for_issue(issue_number, title)

  let progress_file = checkpoint.progress_file_for_task(cfg.tasks_dir, task_slug)

  // normalize class/reasoning (empty -> sensible defaults)
  let class = case class_raw {
    "" -> Other("no-class-provided")
    c -> normalize_refusal_class(c)
  }
  let reasoning = case reasoning_raw {
    "" -> "No reasoning provided via CLI or decision gate."
    r -> r
  }

  // ensure checkpoint (idempotent resume)
  use chk <- result.try(
    checkpoint.ensure_refusal_checkpoint(
      cfg,
      issue_number,
      issue_json,
      task_slug,
      title,
      class,
      reasoning,
    )
  )

  let comment_id_str = case chk.comment_id {
    Some(id) -> id
    None -> ""
  }
  let class_str = to_string(class)

  // atomic progress update (sets refused + skipped test)
  // best-effort (non-fatal after checkpoint); errors are console.logged in FFI
  // (previously ignored Result via let _ = ; now explicitly handled)
  let _ = case ffi.update_progress_for_refusal(progress_file, class_str, comment_id_str) {
    Ok(_) -> Nil
    Error(_) -> Nil
  }

  // project status move (optional, GitHub Projects v2 via gh cli)
  let moved = case move_to_backlog_if_needed(cfg, issue_number, issue_json) {
    Ok(b) -> b
    Error(_) -> False
  }

  Ok(RefusalResult(
    provider: "github",
    issue_number: Some(issue_number),
    issue_identifier: None,
    task_slug: task_slug,
    class: class,
    comment_id: comment_id_str,
    progress_file: progress_file,
    moved_to_backlog: moved,
  ))
}

fn extract_title_from_issue_json(issue_json: String) -> String {
  case ffi.parse(issue_json) {
    Error(_) -> ""
    Ok(v) -> ffi.get_field_path_string(v, ["title"])
  }
}

fn id_from_item(it: ffi.JsonValue) -> Option(String) {
  let id = ffi.get_field_string(it, "id")
  case id {
    "" -> None
    s -> Some(s)
  }
}

fn extract_project_item_id(issue_json: String, project_number: Int) -> Option(String) {
  case ffi.parse(issue_json) {
    Error(_) -> None
    Ok(v) -> {
      let items_v = ffi.get_field_path(v, ["projectItems"])
      case ffi.decode_array(items_v) {
        Error(_) -> None
        Ok(items) -> {
          let pnum_str = int.to_string(project_number)
          // try matching project number first
          let match = list.find(items, fn(it) {
            let pnum = ffi.get_field_path_string(it, ["project", "number"])
            pnum == pnum_str
            || ffi.get_field_path_string(it, ["number"]) == pnum_str
          })
          case match {
            Ok(it) -> id_from_item(it)
            Error(_) -> case list.first(items) {
              Ok(it) -> id_from_item(it)
              Error(_) -> None
            }
          }
        }
      }
    }
  }
}

fn fetch_project_item_id_via_list(cfg: RefusalConfig, issue: Int) -> Option(String) {
  let args = [
    "project", "item-list",
    int.to_string(cfg.project_number),
    "--owner", cfg.project_owner,
    "--limit", "200",
    "--format", "json",
  ]
  let res = ffi.execute_command("gh", args)
  case res.exit_code {
    0 -> {
      case ffi.parse(res.stdout) {
        Ok(v) -> {
          let items_v = case ffi.get_field(v, "items") {
            _ -> v
          }
          case ffi.decode_array(items_v) {
            Ok(items) -> {
              let found = list.find(items, fn(it) {
                let n1 = ffi.get_field_path_string(it, ["content", "number"])
                let n2 = ffi.get_field_path_string(it, ["content", "issue", "number"])
                let n3 = ffi.get_field_path_string(it, ["number"])
                n1 == int.to_string(issue) || n2 == int.to_string(issue) || n3 == int.to_string(issue)
              })
              case found {
                Ok(it) -> id_from_item(it)
                Error(_) -> None
              }
            }
            Error(_) -> None
          }
        }
        Error(_) -> None
      }
    }
    _ -> None
  }
}

fn extract_project_status_name(issue_json: String, project_number: Int) -> String {
  case ffi.parse(issue_json) {
    Error(_) -> ""
    Ok(v) -> {
      let items_v = ffi.get_field_path(v, ["projectItems"])
      case ffi.decode_array(items_v) {
        Error(_) -> ""
        Ok(items) -> {
          let pnum_str = int.to_string(project_number)
          let match = list.find(items, fn(it) {
            ffi.get_field_path_string(it, ["project", "number"]) == pnum_str
            || ffi.get_field_path_string(it, ["number"]) == pnum_str
          })
          case match {
            Ok(it) -> ffi.get_field_path_string(it, ["status", "name"])
            Error(_) -> case list.first(items) {
              Ok(it) -> ffi.get_field_path_string(it, ["status", "name"])
              Error(_) -> ""
            }
          }
        }
      }
    }
  }
}

fn move_to_backlog_if_needed(
  cfg: RefusalConfig,
  issue: Int,
  issue_json: String,
) -> Result(Bool, String) {
  case cfg.updates_enabled && cfg.requires_backlog {
    False -> Ok(False)
    True -> {
      let target = cfg.backlog_value
      let item_id_opt = case extract_project_item_id(issue_json, cfg.project_number) {
        Some(id) -> Some(id)
        None -> fetch_project_item_id_via_list(cfg, issue)
      }
      case item_id_opt {
        None -> Ok(False)
        Some(item_id) -> {
          let current = extract_project_status_name(issue_json, cfg.project_number)
          case normalize_option_name(current) == normalize_option_name(target) {
            True -> Ok(False)
            False -> {
              case fetch_project_id(cfg.project_owner, cfg.project_number) {
                Error(e) -> Error(e)
                Ok(project_id) -> {
                  case fetch_status_field_and_backlog_option(
                    cfg.project_owner,
                    cfg.project_number,
                    cfg.status_field_name,
                    target,
                  ) {
                    Error(e) -> Error(e)
                    Ok(#(field_id, option_id)) -> {
                      let edit_args = [
                        "project", "item-edit",
                        "--id", item_id,
                        "--field-id", field_id,
                        "--project-id", project_id,
                        "--single-select-option-id", option_id,
                      ]
                      let edit = ffi.execute_command("gh", edit_args)
                      case edit.exit_code {
                        0 -> Ok(True)
                        _ -> Error("gh project item-edit failed: " <> edit.stderr)
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

fn fetch_project_id(owner: String, num: Int) -> Result(String, String) {
  let args = ["project", "view", int.to_string(num), "--owner", owner, "--format", "json"]
  let res = ffi.execute_command("gh", args)
  case res.exit_code {
    0 -> {
      case ffi.parse(res.stdout) {
        Ok(v) -> {
          let id = ffi.get_field_path_string(v, ["id"])
          case id {
            "" -> {
              let pid = ffi.get_field_path_string(v, ["project", "id"])
              case pid {
                "" -> Error("no project id in json")
                s -> Ok(s)
              }
            }
            s -> Ok(s)
          }
        }
        Error(_) -> Error("parse project view json failed")
      }
    }
    _ -> Error("gh project view failed: " <> res.stderr)
  }
}

fn fetch_status_field_and_backlog_option(
  owner: String,
  num: Int,
  field_name: String,
  option_name: String,
) -> Result(#(String, String), String) {
  let args = ["project", "field-list", int.to_string(num), "--owner", owner, "--format", "json"]
  let res = ffi.execute_command("gh", args)
  case res.exit_code {
    0 -> {
      case ffi.parse(res.stdout) {
        Ok(v) -> {
          let fields_v = case ffi.decode_array(v) {
            Ok(_) -> v
            Error(_) -> ffi.get_field(v, "fields")
          }
          case ffi.decode_array(fields_v) {
            Error(_) -> Error("fields not array")
            Ok(fields) -> {
              let field_opt = list.find(fields, fn(f) {
                ffi.get_field_string(f, "name") == field_name
              })
              case field_opt {
                Error(_) -> Error("status field not found: " <> field_name)
                Ok(f) -> {
                  let field_id = ffi.get_field_string(f, "id")
                  let opts_v = ffi.get_field(f, "options")
                  case ffi.decode_array(opts_v) {
                    Error(_) -> Error("options not array for field")
                    Ok(opts) -> {
                      let opt_opt = list.find(opts, fn(o) {
                        ffi.get_field_string(o, "name") == option_name
                      })
                      let opt_opt2 = case opt_opt {
                        Ok(_) -> opt_opt
                        Error(_) -> list.find(opts, fn(o) {
                          normalize_option_name(ffi.get_field_string(o, "name")) == normalize_option_name(option_name)
                        })
                      }
                      case opt_opt2 {
                        Error(_) -> Error("backlog option not found: " <> option_name)
                        Ok(o) -> {
                          let oid = ffi.get_field_string(o, "id")
                          case oid {
                            "" -> Error("option id empty")
                            _ -> Ok(#(field_id, oid))
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        Error(_) -> Error("parse field-list json failed")
      }
    }
    _ -> Error("gh project field-list failed: " <> res.stderr)
  }
}

fn normalize_option_name(s: String) -> String {
  s
  |> string.trim
  |> string.lowercase
}
