import gleam/int
import gleam/list
import gleam/string
import grkr/resolve_pr/types

type ExecResult {
  ExecResult(exit_code: Int, stdout: String, stderr: String)
}

const codex_bin = "codex"

pub fn resolve_conflicts(
  conflict_files: List(types.ConflictFile),
) -> Result(List(types.CodexResolution), String) {
  list.try_map(conflict_files, resolve_single_conflict)
}

fn resolve_single_conflict(
  conflict: types.ConflictFile,
) -> Result(types.CodexResolution, String) {
  let prompt = build_conflict_prompt(conflict)

  let cmd = [codex_bin, "exec", "--full-auto", prompt]

  case execute_command(cmd, "") {
    Ok(output) -> {
      case parse_codex_response(output) {
        Ok(resolution) -> Ok(resolution)
        Error(err) -> Error("Failed to parse Codex response: " <> err)
      }
    }
    Error(err) -> Error("Codex command failed: " <> err)
  }
}

fn build_conflict_prompt(conflict: types.ConflictFile) -> String {
  "Resolve the merge conflict in file: "
  <> conflict.path
  <> "\n\n"
  <> "Our changes (current branch):\n"
  <> conflict.our_content
  <> "\n\n"
  <> "Their changes (incoming branch):\n"
  <> conflict.their_content
  <> "\n\n"
  <> "Instructions:\n"
  <> "- Resolve merge conflicts only\n"
  <> "- Preserve the intent of both changes\n"
  <> "- Avoid unrelated refactors\n"
  <> "- Avoid formatting unrelated files\n"
  <> "- Run only minimal validation\n"
  <> "- Provide only the final resolved content\n"
  <> "- Explain your resolution briefly\n\n"
  <> "Respond with the resolved content followed by an explanation."
}

fn parse_codex_response(
  output: String,
) -> Result(types.CodexResolution, String) {
  let parts = string.split(output, "\n\n")

  case parts {
    [resolved_content, explanation] -> {
      Ok(types.CodexResolution(
        resolved_content: string.trim(resolved_content),
        explanation: string.trim(explanation),
      ))
    }
    _ -> {
      case string.split(output, "\n---\n") {
        [resolved_content, explanation] -> {
          Ok(types.CodexResolution(
            resolved_content: string.trim(resolved_content),
            explanation: string.trim(explanation),
          ))
        }
        _ -> {
          Ok(types.CodexResolution(
            resolved_content: string.trim(output),
            explanation: "No explanation provided",
          ))
        }
      }
    }
  }
}

pub fn validate_resolution(
  _conflict: types.ConflictFile,
  resolution: types.CodexResolution,
) -> Result(Nil, String) {
  case resolution {
    types.CodexResolution(resolved_content, _) -> {
      case string.trim(resolved_content) {
        "" -> Error("Resolved content is empty")
        _ -> {
          case string.contains(resolved_content, "<<<<<<<") {
            True -> Error("Resolved content still contains conflict markers")
            False -> Ok(Nil)
          }
        }
      }
    }
    types.CodexSkipped(_) -> Ok(Nil)
    types.CodexFailed(_) -> Ok(Nil)
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
