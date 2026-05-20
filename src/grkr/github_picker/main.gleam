import gleam/int
import gleam/string
import grkr/github_picker/config
import grkr/github_picker/decoder
import grkr/github_picker/selector
import grkr/github_picker/types
@external(javascript, "../github_picker/cli_ffi.mjs", "argv")
fn argv() -> List(String)

@external(javascript, "console", "log")
fn console_log(s: String) -> Nil

@external(javascript, "process", "exit")
fn exit(code: Int) -> Nil

fn shell_quote(value: String) -> String {
  "\""
    <> {
    value
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
    |> string.replace("$", "\\$")
    |> string.replace("`", "\\`")
  }
    <> "\""
}

fn emit(key: String, value: String) {
  console_log(key <> "=" <> shell_quote(value))
}

fn emit_error(msg: String) {
  console_log("ERROR=" <> shell_quote(msg))
}

pub fn main() {
  let args = argv()
  let json_string = case args {
    [first, ..] -> first
    _ -> ""
  }

  case config.load() {
    Error(e) -> {
      emit_error(types.provider_error_to_string(types.Config(e)))
      exit(1)
    }
    Ok(cfg) -> {
      case decoder.decode_project_items(json_string, cfg) {
        Error(de) -> {
          emit_error("Decode failed: " <> de)
          exit(1)
        }
        Ok(items) -> {
          case selector.pick(items, cfg) {
            Error(_) -> {
              emit("SELECTED", "0")
              exit(0)
            }
            Ok(sel) -> {
              emit("SELECTED", "1")
              emit("ISSUE_NUMBER", int.to_string(sel.issue_number))
              emit("ISSUE_TITLE", sel.issue_title)
              emit("ISSUE_UPDATED_AT", sel.issue_updated_at)
              emit("PRIORITY_NAME", sel.priority_name)
              emit("PRIORITY_NUMBER", sel.priority_number)
              emit("JOB_KEY", sel.job_key)
              emit("TASK_SLUG", sel.task_slug)
              emit("PROJECT_ITEM_ID", sel.project_item_id)
              exit(0)
            }
          }
        }
      }
    }
  }
}
