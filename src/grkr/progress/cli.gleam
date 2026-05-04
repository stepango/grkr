import gleam/io
import grkr/progress/main

pub fn main() -> Nil {
  case argv() {
    ["marker", stage, task_slug] -> emit_marker(stage, task_slug)
    ["render-checkpoint", stage, task_slug, body] ->
      emit_result(main.cli_render_checkpoint(stage, task_slug, body))
    ["render-checkpoint-with-pr", stage, task_slug, body, pr_url] ->
      emit_result(main.cli_render_checkpoint_with_pr(stage, task_slug, body, pr_url))
    ["render-refusal", task_slug, reason_class, reasoning] ->
      io.print(main.cli_render_refusal(task_slug, reason_class, reasoning))
    ["render-pr-summary", task_slug, pr_url, branch_url] ->
      io.print(main.cli_render_pr_summary(task_slug, pr_url, branch_url))
    _ -> {
      io.println("Usage: gleam run -m grkr/progress/cli -- marker <stage> <task-slug>")
      io.println("       gleam run -m grkr/progress/cli -- render-checkpoint <stage> <task-slug> <body>")
      io.println("       gleam run -m grkr/progress/cli -- render-checkpoint-with-pr <stage> <task-slug> <body> <pr-url>")
      io.println("       gleam run -m grkr/progress/cli -- render-refusal <task-slug> <reason-class> <reasoning>")
      io.println("       gleam run -m grkr/progress/cli -- render-pr-summary <task-slug> <pr-url> <branch-url>")
      exit(2)
    }
  }
}

fn emit_marker(stage: String, task_slug: String) -> Nil {
  case main.validate_checkpoint_stage(stage) {
    Ok(validated_stage) -> io.print(main.format_checkpoint_marker(validated_stage, task_slug))
    Error(message) -> {
      io.println("progress cli error: " <> message)
      exit(1)
    }
  }
}

fn emit_result(result: Result(String, String)) -> Nil {
  case result {
    Ok(value) -> io.print(value)
    Error(message) -> {
      io.println("progress cli error: " <> message)
      exit(1)
    }
  }
}

@external(javascript, "../progress/cli_ffi.mjs", "argv")
fn argv() -> List(String)

@external(javascript, "process", "exit")
fn exit(code: Int) -> Nil
