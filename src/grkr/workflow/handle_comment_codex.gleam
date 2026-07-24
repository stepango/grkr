//// handle_comment_codex.gleam
//// Classify prompt + parse (CLASS/REPLY/CHANGES) for handle_comment (LOC hygiene).
//// Coding-agent exec via grkr/coding_agent (GRKR_CODING_AGENT / GRKR_AGENT_COMMENT).

import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/string

import grkr/coding_agent
import grkr/coding_agent_types as ca_types
import grkr/workflow/ffi.{ExecResult}
import grkr/workflow/handle_comment_types.{type CommentContext}

pub fn run_codex_classify(
  ctx: CommentContext,
  branch: String,
  workdir: String,
) -> String {
  let policy = "Follow AGENTS.md, spec/parts/*, and grkr v2 rules: minimal targeted changes only; always prefer answer/refuse over broad edits; respect 1000 LOC/file limit; use worktrees; post checkpoints for complex work; GitHub-only in this phase (no Linear mutations here). Be concise and professional."

  let prompt = "You are grkr, the autonomous repo robot.\n\nRAW COMMAND (from @:robot: comment #" <> ctx.id <> " by @" <> ctx.user_login <> "):\n" <> ctx.raw_cmd <> "\n\nCONTEXT:\n- Repo: " <> ctx.repo <> "\n- " <> case ctx.is_pr { True -> "PR " False -> "" } <> "Issue #" <> ctx.issue_number <> ": " <> ctx.issue_title <> "\n  State: " <> ctx.issue_state <> "\n  URL: " <> ctx.html_url <> "\n- Issue/PR body (truncated): " <> string.slice(ctx.issue_body, 0, 800) <> "\n- Recent thread comments (newest first, truncated): " <> ctx.recent_comments_json <> "\n- Current worktree branch: " <> branch <> "\n- Policy: " <> policy <> "\n\nTASK:\nClassify the intent of the RAW COMMAND and respond as one of:\n- answer-only: provide helpful reply, no code changes\n- code-change: describe + (if safe/minimal) note that edit would be made here\n- triage: suggest next step or label\n- refuse: politely decline with short reason (e.g. too vague, out of scope, needs more info)\n\nOUTPUT FORMAT (exact, parseable):\nCLASS: <answer-only|code-change|triage|refuse>\nREPLY: <1-6 sentence professional reply text for posting as GitHub comment. Include classification and any caveats. Do NOT include raw prompt.>\nCHANGES: <short description of any code intent or N/A>\n\nDo not execute external commands yourself; only describe. Keep REPLY under 1200 chars."

  let _ =
    ffi.console_log(
      "   building coding-agent prompt (len="
      <> int.to_string(string.length(prompt))
      <> ")",
    )

  let outcome =
    coding_agent.run_with_defaults(
      ca_types.Comment,
      ca_types.Classify,
      prompt,
      workdir,
      exec_adapter,
      fs_deps(),
    )

  let out = coding_agent.classify_output(outcome, ctx.raw_cmd)

  let _ =
    ffi.console_log(
      "   coding-agent raw output (truncated): "
      <> string.slice(out, 0, 300)
      <> "...",
    )
  out
}

fn exec_adapter(
  bin: String,
  args: List(String),
  input: Option(String),
) -> coding_agent.ExecOutcome {
  case ffi.executable(bin, args, input) {
    ExecResult(0, stdout, _) -> ca_types.ExecOk(stdout)
    ExecResult(code, stdout, stderr) ->
      ca_types.ExecFailed(code, stdout, stderr)
  }
}

fn fs_deps() -> coding_agent.FsDeps {
  ca_types.FsDeps(
    temp_path: ffi.tl_temp_path,
    write_text: ffi.tl_write_text,
    unlink: ffi.tl_unlink_file,
  )
}

pub fn parse_codex_output(out: String) -> #(String, String, String) {
  let class = case string.split(out, "\n") |> list.filter(fn(l) { string.starts_with(string.lowercase(l), "class:") }) |> list.reverse {
    [last, ..] -> last |> string.split(":") |> list.drop(1) |> string.join(":") |> string.trim |> string.lowercase |> normalize_class
    _ -> "answer-only"
  }
  // simple awk-like for REPLY capture until CHANGES
  let reply = extract_section(out, "REPLY:", "CHANGES:")
  let changes = case string.split(out, "\n") |> list.filter(fn(l) { string.starts_with(string.lowercase(l), "changes:") }) |> list.reverse {
    [last, ..] -> last |> string.split(":") |> list.drop(1) |> string.join(":") |> string.trim
    _ -> "N/A"
  }
  #(class, reply, changes)
}

fn normalize_class(c: String) -> String {
  case c {
    "code-change" | "answer-only" | "triage" | "refuse" -> c
    _ -> "answer-only"
  }
}

fn extract_section(text: String, start_marker: String, end_marker: String) -> String {
  // simple line based capture
  let lines = string.split(text, "\n")
  let lower_lines = list.map(lines, string.lowercase)
  let start_idx = case list.index_map(lower_lines, fn(l, i) { #(i, l) }) |> list.filter(fn(p) { string.starts_with(p.1, string.lowercase(start_marker)) }) |> list.map(fn(p) { p.0 }) |> list.first {
    Ok(i) -> i + 1
    _ -> 0
  }
  let end_idx = case list.index_map(lower_lines, fn(l, i) { #(i, l) }) |> list.filter(fn(p) { string.starts_with(p.1, string.lowercase(end_marker)) }) |> list.map(fn(p) { p.0 }) |> list.first {
    Ok(i) -> i
    _ -> list.length(lines)
  }
  lines
  |> list.drop(start_idx)
  |> list.take(end_idx - start_idx)
  |> string.join("\n")
  |> string.trim
  |> string.slice(0, 1800)
}
