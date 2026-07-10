import gleam/int
import gleam/io
import gleam/result
import grkr/task_slug

pub fn main() -> Nil {
  case argv() {
    ["slugify", text] -> emit_slugify(text)
    ["task-slug", issue_str, title] -> emit_task_slug(issue_str, title)
    _ -> {
      io.println("Usage: gleam run -m grkr/task_slug/cli -- slugify <text>")
      io.println(
        "       gleam run -m grkr/task_slug/cli -- task-slug <issue-number> <title>",
      )
      exit(2)
    }
  }
}

fn emit_slugify(text: String) -> Nil {
  io.println(task_slug.slugify_text(text))
}

fn emit_task_slug(issue_str: String, title: String) -> Nil {
  case parse_issue_number(issue_str) {
    Ok(issue_number) ->
      io.println(task_slug.task_slug_for_issue(issue_number, title))
    Error(msg) -> {
      io.println("Error: " <> msg)
      exit(1)
    }
  }
}

fn parse_issue_number(s: String) -> Result(Int, String) {
  int.parse(s)
  |> result.map_error(fn(_) { "Invalid issue number: '" <> s <> "'" })
}

@external(javascript, "../task_slug/cli_ffi.mjs", "argv")
fn argv() -> List(String)

@external(javascript, "process", "exit")
fn exit(code: Int) -> Nil
