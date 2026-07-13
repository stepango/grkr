import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import grkr/issue_provider/types as ltypes
import grkr/progress/main as pmain
import grkr/refusal/assessment
import grkr/refusal/ffi
import grkr/refusal/types.{
  type RefusalError, type RefusalResult, OtherError, Other,
  normalize_refusal_class, to_string, RefusalResult,
}

/// Linear refuse path (progress-layer mutations, dry-run by default).
/// - Resolves title/linear_id via issue_provider fetch-issue (LINEAR_FIXTURE_PATH or live)
///   or falls back to env/meta (ISSUE_TITLE, ISSUE_ID) or identifier.
/// - Writes refusal.md (assessment body + checkpoint marker)
/// - Updates progress.json refused via shared ffi
/// - Plans Linear commentCreate + optional Backlog state mutation via progress helpers
/// - Does NOT call gh project APIs
/// - Dry-run succeeds without GRKR_LINEAR_ACCESS_TOKEN (matches MVP)
pub fn run_refusal_linear(
  identifier: String,
  class_raw: String,
  reasoning_raw: String,
) -> Result(RefusalResult, RefusalError) {
  let task_slug = ltypes.task_slug_for_identifier(identifier)

  let tasks_dir = ffi.get_env_with_default("TASKS_DIR", ".grkr/tasks")
  let task_dir = tasks_dir <> "/" <> task_slug
  let progress_file = task_dir <> "/progress.json"
  let refusal_md = task_dir <> "/refusal.md"

  let #(title, linear_id, _url) = resolve_linear_issue(identifier, task_dir)

  let class = case class_raw {
    "" -> Other("no-class-provided")
    c -> normalize_refusal_class(c)
  }
  let reasoning = case reasoning_raw {
    "" -> "No reasoning provided via CLI or decision gate."
    r -> r
  }
  let class_str = to_string(class)

  let body =
    assessment.format_full_refusal_md(
      task_slug,
      None,
      title,
      class,
      reasoning,
    )

  case ffi.write_file(refusal_md, body) {
    Error(e) -> Error(OtherError("write refusal.md failed: " <> e))
    Ok(_) -> {
      let _ = case ffi.update_progress_for_refusal(progress_file, class_str, "") {
        Ok(_) -> Nil
        Error(_) -> Nil
      }

      let state_id = ffi.get_env_with_default("LINEAR_BACKLOG_STATE_ID", "")
      let state_id2 = case string.trim(state_id) {
        "" -> ffi.get_env_with_default("TARGET_STATE_ID", "")
        s -> s
      }

      let env_getter = fn(key: String) { ffi.get_env_with_default(key, "") }
      let plan =
        pmain.plan_linear_refusal(
          linear_id,
          task_slug,
          class_str,
          reasoning,
          state_id2,
          env_getter,
        )

      let plan_path = task_dir <> "/refusal.linear-plan.txt"
      let _ = ffi.write_file(plan_path, pmain.format_linear_refusal_plan(plan))

      let mutation_path = task_dir <> "/refusal.linear-mutation.txt"
      let comment_dump =
        plan.comment_mutation.query
        <> "\n"
        <> plan.comment_mutation.variables_json
        <> "\n"
        <> plan.comment_mutation.idempotency_key
        <> "\n"
      let _ = ffi.write_file(mutation_path, comment_dump)

      let state_name_path = task_dir <> "/refusal.linear-state.txt"
      let _ =
        ffi.write_file(
          state_name_path,
          "intended_state="
            <> plan.target_state_name
            <> "\nprovider=linear\n",
        )

      case plan.state_mutation {
        Some(state_mut) -> {
          let sm_path = task_dir <> "/refusal.linear-state-mutation.txt"
          let sm_dump =
            state_mut.query
            <> "\n"
            <> state_mut.variables_json
            <> "\n"
            <> state_mut.idempotency_key
            <> "\n"
          let _ = ffi.write_file(sm_path, sm_dump)
          Nil
        }
        None -> Nil
      }

      // Record idempotency key as comment_id until live mutate lands
      let comment_key = plan.comment_mutation.idempotency_key
      let _ =
        case ffi.update_progress_for_refusal(progress_file, class_str, comment_key) {
          Ok(_) -> Nil
          Error(_) -> Nil
        }

      Ok(
        RefusalResult(
          provider: "linear",
          issue_number: None,
          issue_identifier: Some(identifier),
          task_slug: task_slug,
          class: class,
          comment_id: comment_key,
          progress_file: progress_file,
          moved_to_backlog: False,
        ),
      )
    }
  }
}

fn resolve_linear_issue(
  identifier: String,
  task_dir: String,
) -> #(String, String, String) {
  let env_title = ffi.get_env_with_default("ISSUE_TITLE", "")
  let env_id = ffi.get_env_with_default("ISSUE_ID", "")
  let env_url = ffi.get_env_with_default("ISSUE_URL", "")
  case env_title != "" {
    True -> {
      let use_id = case env_id {
        "" -> identifier
        s -> s
      }
      #(env_title, use_id, env_url)
    }
    False -> {
      case try_read_context_title(task_dir) {
        Some(t) -> {
          let ctx_id =
            try_read_context_id(task_dir)
            |> option_unwrap(identifier)
          let ctx_url =
            try_read_context_url(task_dir)
            |> option_unwrap("")
          #(t, ctx_id, ctx_url)
        }
        None -> {
          case fetch_via_provider_cli(identifier) {
            Ok(#(t, i, u)) -> #(t, i, u)
            Error(_) -> #(identifier, identifier, "")
          }
        }
      }
    }
  }
}

fn option_unwrap(opt: Option(String), default: String) -> String {
  case opt {
    Some(s) -> s
    None -> default
  }
}

fn try_read_context_title(task_dir: String) -> Option(String) {
  let ctx = task_dir <> "/issue-context.json"
  case ffi.exists_file(ctx) {
    False -> None
    True -> {
      case ffi.parse(ffi.read_text_or_empty(ctx)) {
        Error(_) -> None
        Ok(v) -> {
          let t = ffi.get_field_path_string(v, ["title"])
          case t {
            "" -> None
            s -> Some(s)
          }
        }
      }
    }
  }
}

fn try_read_context_id(task_dir: String) -> Option(String) {
  let ctx = task_dir <> "/issue-context.json"
  case ffi.exists_file(ctx) {
    False -> None
    True -> {
      case ffi.parse(ffi.read_text_or_empty(ctx)) {
        Error(_) -> None
        Ok(v) -> {
          let i = ffi.get_field_path_string(v, ["id"])
          case i {
            "" -> None
            s -> Some(s)
          }
        }
      }
    }
  }
}

fn try_read_context_url(task_dir: String) -> Option(String) {
  let ctx = task_dir <> "/issue-context.json"
  case ffi.exists_file(ctx) {
    False -> None
    True -> {
      case ffi.parse(ffi.read_text_or_empty(ctx)) {
        Error(_) -> None
        Ok(v) -> {
          let u = ffi.get_field_path_string(v, ["url"])
          case u {
            "" -> None
            s -> Some(s)
          }
        }
      }
    }
  }
}

fn fetch_via_provider_cli(
  identifier: String,
) -> Result(#(String, String, String), String) {
  let args = [
    "run",
    "--no-print-progress",
    "-m",
    "grkr/issue_provider/main",
    "--",
    "fetch-issue",
    identifier,
  ]
  let res = ffi.execute_command("gleam", args)
  case res.exit_code {
    0 -> {
      let #(title, id, url) = parse_fetch_assignments(res.stdout, identifier)
      Ok(#(title, id, url))
    }
    _ -> Error("fetch-issue non-zero")
  }
}

fn parse_fetch_assignments(
  output: String,
  fallback_id: String,
) -> #(String, String, String) {
  let lines = string.split(output, "\n")
  let title = find_value(lines, "ISSUE_TITLE") |> option_unwrap(fallback_id)
  let id = find_value(lines, "ISSUE_ID") |> option_unwrap(fallback_id)
  let url = find_value(lines, "ISSUE_URL") |> option_unwrap("")
  #(title, id, url)
}

fn find_value(lines: List(String), key: String) -> Option(String) {
  case list.find(lines, fn(l) { string.starts_with(l, key <> "=") }) {
    Ok(line) -> {
      let val = case string.split_once(line, "=") {
        Ok(#(_, v)) -> v
        Error(_) -> ""
      }
      Some(strip_shell_quotes(val))
    }
    Error(_) -> None
  }
}

fn strip_shell_quotes(v: String) -> String {
  let t = string.trim(v)
  let no_outer = case string.starts_with(t, "\"") && string.ends_with(t, "\"") {
    True -> string.drop_start(string.drop_end(t, 1), 1)
    False -> t
  }
  no_outer
  |> string.replace("\\n", "\n")
  |> string.replace("\\\"", "\"")
  |> string.replace("\\\\", "\\")
}
