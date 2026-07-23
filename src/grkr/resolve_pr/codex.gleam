//// resolve_pr/codex.gleam
//// Conflict-resolve via grkr/coding_agent (Resolve + ConflictResolve).
//// Env: GRKR_AGENT_RESOLVE → GRKR_CODING_AGENT_RESOLVE → GRKR_CODING_AGENT/CODING_AGENT → codex.
//// Public API names (resolve_conflicts / validate_resolution / CodexResolution) unchanged.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import grkr/coding_agent
import grkr/resolve_pr/types

type ExecResult {
  ExecResult(exit_code: Int, stdout: String, stderr: String)
}

pub fn resolve_conflicts(
  conflict_files: List(types.ConflictFile),
  workdir: String,
) -> Result(List(types.CodexResolution), String) {
  list.try_map(conflict_files, fn(c) { resolve_single_conflict(c, workdir) })
}

fn resolve_single_conflict(
  conflict: types.ConflictFile,
  workdir: String,
) -> Result(types.CodexResolution, String) {
  let prompt = build_conflict_prompt(conflict)

  let outcome =
    coding_agent.run_with_defaults(
      coding_agent.Resolve,
      coding_agent.ConflictResolve,
      prompt,
      workdir,
      exec_adapter,
      fs_deps(),
    )

  case outcome {
    coding_agent.ExecOk(output) ->
      case parse_codex_response(output) {
        Ok(resolution) -> Ok(resolution)
        Error(err) -> Error("Failed to parse coding agent response: " <> err)
      }
    coding_agent.ExecFailed(code, stdout, stderr) ->
      Error(
        "Coding agent command failed: "
        <> case string.trim(stderr) {
          "" -> "exit " <> int.to_string(code) <> " " <> string.trim(stdout)
          e -> e
        },
      )
  }
}

fn exec_adapter(
  bin: String,
  args: List(String),
  input: Option(String),
) -> coding_agent.ExecOutcome {
  let stdin = case input {
    Some(s) -> s
    None -> ""
  }
  case javascript_executable(bin, args, stdin) {
    ExecResult(0, stdout, _) -> coding_agent.ExecOk(stdout)
    ExecResult(code, stdout, stderr) ->
      coding_agent.ExecFailed(code, stdout, stderr)
  }
}

fn fs_deps() -> coding_agent.FsDeps {
  coding_agent.FsDeps(
    temp_path: javascript_temp_path,
    write_text: javascript_write_file,
    unlink: javascript_unlink_file,
  )
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

@external(javascript, "../resolve_pr/exec.mjs", "executable")
fn javascript_executable(
  command: String,
  args: List(String),
  input: String,
) -> ExecResult

@external(javascript, "../resolve_pr/fs.mjs", "write_file")
fn javascript_write_file(path: String, content: String) -> Result(Nil, String)

@external(javascript, "../resolve_pr/fs.mjs", "temp_path")
fn javascript_temp_path(prefix: String) -> String

@external(javascript, "../resolve_pr/fs.mjs", "unlink_file")
fn javascript_unlink_file(path: String) -> Bool
