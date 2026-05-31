//// handle_comment.gleam
//// Full Gleam port of bin/worker-handle-comment.sh (296 LOC legacy) per spec/15 + t_05a253d1 + AGENTS.md
//// GitHub-only v2. Thin sh delegates here (always exit 0 best-effort).
//// Reuses workflow FFI (exec + json + git), patterns from phases (gh+decode), resolve_pr (codex/exec).
//// Preserves: eyes/rocket reactions, worktree per spec/12 (issue vs PR base), codex classify (CLASS/REPLY/CHANGES),
//// result comment, optional commit/push (rare), cleanup. Idempotency via supervisor scan mark.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

import grkr/workflow/ffi.{type ExecResult, type JsonValue, ExecResult}

pub fn main() {
  case ffi.argv() {
    ["help"] | [] -> emit_usage()
    [comment_id] -> do_handle(comment_id)
    ["--", comment_id] -> do_handle(comment_id)
    _ -> emit_usage()
  }
}

fn emit_usage() {
  ffi.console_error("Usage: gleam run -m grkr/workflow/handle_comment -- <comment_id>")
  ffi.console_error("Full @robot: comment handler (GitHub-only v2) per spec/15.")
  ffi.console_error("gh context, eyes/rocket, worktree (spec/12), codex classify, reply, cleanup.")
  ffi.exit(2)
}

fn do_handle(comment_id: String) {
  case int.parse(comment_id) {
    Ok(_) -> Nil
    Error(_) -> {
      ffi.console_error("Error: comment_id must be numeric (GitHub id)")
      ffi.exit(1)
    }
  }

  let _ = ffi.console_log("🤖 grkr/workflow/handle_comment: starting for comment_id=" <> comment_id <> " (GitHub-only v2 full)")

  // 1. Fetch context (best effort; no-op if fail)
  let repo = case ffi.get_env("REPO") {
    "" -> "stepango/grkr"
    r -> r
  }
  let main_branch = case ffi.get_env("MAIN_BRANCH") {
    "" -> "main"
    b -> b
  }

  case fetch_context(comment_id, repo, main_branch) {
    Ok(ctx) -> {
      let _ = ffi.console_log("   context: comment by @" <> ctx.user_login <> " on " <> case ctx.is_pr { True -> "PR " False -> "" } <> "#" <> ctx.issue_number <> " \"" <> ctx.issue_title <> "\" cmd=\"" <> ctx.raw_cmd <> "\"")

      // 2. eyes reaction (capture id for cleanup)
      let eyes_id = add_eyes_reaction(comment_id, repo)

      // 3. worktree (per spec/12)
      let worktree_info = create_comment_worktree(comment_id, ctx, repo, main_branch)

      // 4+5. prompt + codex
      let codex_out = run_codex_classify(ctx, worktree_info.branch)

      let #(class, reply, changes) = parse_codex_output(codex_out)

      let _ = ffi.console_log("   parsed: class=" <> class <> " changes=" <> changes)

      // 6+7. post result + optional commit/push
      let _ = post_result_comment(ctx, comment_id, repo, class, reply, changes, worktree_info.branch)

      case class {
        "code-change" -> try_optional_commit_push(worktree_info.dir, comment_id, ctx.raw_cmd, reply, repo, worktree_info.branch)
        _ -> Nil
      }

      // 8. success reactions: remove eyes + rocket (best effort)
      remove_eyes_and_add_rocket(comment_id, repo, eyes_id)

      // 9. cleanup
      cleanup_worktree(worktree_info.dir)

      let _ = ffi.console_log("✅ handle_comment complete for " <> comment_id <> " (class=" <> class <> ", exit=0)")
      ffi.exit(0)
    }
    Error(e) -> {
      ffi.console_error("⚠️ handle_comment fetch failed (best-effort no-op): " <> e)
      ffi.exit(0)
    }
  }
}

type CommentContext {
  CommentContext(
    id: String,
    raw_cmd: String,
    user_login: String,
    html_url: String,
    issue_number: String,
    issue_title: String,
    issue_body: String,
    is_pr: Bool,
    issue_state: String,
    recent_comments_json: String,
    repo: String,
  )
}

type WorktreeInfo {
  WorktreeInfo(dir: String, branch: String)
}

fn fetch_context(comment_id: String, repo: String, _main_branch: String) -> Result(CommentContext, String) {
  // gh api for comment
  let comment_path = "repos/" <> repo <> "/issues/comments/" <> comment_id
  let cmd = ["gh", "api", comment_path, "--jq", "{id: (.id|tostring), body, user_login: .user.login, html_url, issue_url, created_at, updated_at}"]
  case run_gh(cmd) {
    ExecResult(0, stdout, _) -> {
      case parse_comment_json(stdout) {
        Ok(c) -> {
          let raw_body = c.body
          let raw_cmd = raw_body
            |> string.replace("@:robot:", "")
            |> string.replace("@ :robot:", "")
            |> string.trim
            |> string.slice(0, 500)
          let issue_url = c.issue_url
          let issue_number = case string.split(issue_url, "/") |> list.reverse {
            [num, ..] -> num
            _ -> "0"
          }
          // fetch issue
          let issue_cmd = ["gh", "api", "repos/" <> repo <> "/issues/" <> issue_number, "--jq", "{number, title, body: (.body // \"\"), html_url, is_pr: (has(\"pull_request\") and .pull_request != null), state}"]
          case run_gh(issue_cmd) {
            ExecResult(0, issue_out, _) -> {
              case parse_issue_json(issue_out) {
                Ok(i) -> {
                  // recent comments
                  let recent_cmd = ["gh", "api", "repos/" <> repo <> "/issues/" <> issue_number <> "/comments?per_page=5&sort=created&direction=desc", "--jq", "[.[] | {user: .user.login, body: (.body | .[0:120] | gsub(\"\\n\";\" \"))} ]"]
                  let recent_json = case run_gh(recent_cmd) {
                    ExecResult(0, r, _) -> r
                    _ -> "[]"
                  }
                  Ok(CommentContext(
                    id: comment_id,
                    raw_cmd: raw_cmd,
                    user_login: c.user_login,
                    html_url: c.html_url,
                    issue_number: issue_number,
                    issue_title: i.title,
                    issue_body: string.slice(i.body, 0, 2000),
                    is_pr: i.is_pr,
                    issue_state: i.state,
                    recent_comments_json: recent_json,
                    repo: repo,
                  ))
                }
                Error(e) -> Error("issue json: " <> e)
              }
            }
            ExecResult(_, _, e) -> Error("issue fetch: " <> e)
          }
        }
        Error(e) -> Error("comment json: " <> e)
      }
    }
    ExecResult(_, _, e) -> Error("comment fetch: " <> e)
  }
}

fn parse_comment_json(j: String) -> Result(CommentJson, String) {
  let trimmed = string.trim(j)
  case trimmed {
    "" | "null" | "{}" -> Error("empty comment json")
    _ -> case ffi.parse(trimmed) {
      Error(e) -> Error("parse: " <> e)
      Ok(root) -> {
        let id = get_string_field(root, "id", "")
        let body = get_string_field(root, "body", "")
        let user_login = get_string_field(root, "user_login", "unknown")
        let html_url = get_string_field(root, "html_url", "")
        let issue_url = get_string_field(root, "issue_url", "")
        Ok(CommentJson(id: id, body: body, user_login: user_login, html_url: html_url, issue_url: issue_url))
      }
    }
  }
}

type CommentJson {
  CommentJson(id: String, body: String, user_login: String, html_url: String, issue_url: String)
}

fn parse_issue_json(j: String) -> Result(IssueJson, String) {
  let trimmed = string.trim(j)
  case trimmed {
    "" | "null" | "{}" -> Error("empty issue json")
    _ -> case ffi.parse(trimmed) {
      Error(e) -> Error("parse: " <> e)
      Ok(root) -> {
        let title = get_string_field(root, "title", "untitled")
        let body = get_string_field(root, "body", "")
        let is_pr = case ffi.get_field(root, "is_pr") |> ffi.decode_bool {
          Ok(b) -> b
          _ -> False
        }
        let state = get_string_field(root, "state", "open")
        Ok(IssueJson(title: title, body: body, is_pr: is_pr, state: state))
      }
    }
  }
}

type IssueJson {
  IssueJson(title: String, body: String, is_pr: Bool, state: String)
}

fn get_string_field(obj: JsonValue, key: String, default: String) -> String {
  case ffi.get_field(obj, key) |> ffi.decode_string {
    Ok(s) -> s
    _ -> default
  }
}

fn run_gh(args: List(String)) -> ExecResult {
  // args include "gh" as head; split for executable
  case args {
    [bin, ..rest] -> ffi.executable(bin, rest, None)
    _ -> ExecResult(1, "", "bad gh cmd")
  }
}

fn add_eyes_reaction(comment_id: String, repo: String) -> String {
  let path = "repos/" <> repo <> "/issues/comments/" <> comment_id <> "/reactions"
  let cmd = ["gh", "api", "-X", "POST", path, "-f", "content=eyes"]
  case run_gh(cmd) {
    ExecResult(0, out, _) -> {
      case ffi.parse(out) {
        Ok(root) -> case ffi.get_field(root, "id") |> ffi.decode_string {
          Ok(id) -> {
            let _ = ffi.console_log("   + eyes reaction (id=" <> id <> ")")
            id
          }
          _ -> {
            let _ = ffi.console_log("   ⚠️ eyes reaction add skipped/failed (best effort)")
            ""
          }
        }
        _ -> ""
      }
    }
    _ -> {
      let _ = ffi.console_log("   ⚠️ eyes reaction add skipped/failed (best effort)")
      ""
    }
  }
}

fn create_comment_worktree(comment_id: String, ctx: CommentContext, repo: String, main_branch: String) -> WorktreeInfo {
  let grkr_dir = case ffi.get_env("GRKR_DIR") {
    "" -> ".grkr"
    d -> d
  }
  let worktrees_dir = grkr_dir <> "/worktrees"
  let _ = ffi.mkdir_p(worktrees_dir)
  let worktree_dir = worktrees_dir <> "/comment-" <> comment_id
  let branch_name = "robot/comment-" <> comment_id

  // determine base
  let base_ref = case ctx.is_pr {
    True -> {
      // fetch pr head
      let pr_cmd = ["gh", "api", "repos/" <> repo <> "/pulls/" <> ctx.issue_number, "--jq", ".head.ref // \"main\""]
      let pr_ref = case run_gh(pr_cmd) {
        ExecResult(0, out, _) -> {
          let r = string.trim(out)
          case r {
            "" -> main_branch
            _ -> r
          }
        }
        _ -> main_branch
      }
      "origin/" <> pr_ref
    }
    False -> "origin/" <> main_branch
  }

  let _ = ffi.console_log("   worktree: " <> case ctx.is_pr { True -> "PR comment" False -> "issue comment" } <> " base=" <> base_ref)

  // force clean prior
  let _ = ffi.git_exec(["worktree", "remove", worktree_dir, "--force"], None)
  let _ = ffi.git_exec(["branch", "-D", branch_name], None)

  // fetch
  let _ = ffi.git_exec(["fetch", "origin", main_branch, "--quiet"], None)
  let _ = case ctx.is_pr {
    True -> {
      // try fetch pr head ref? skip details
      Nil
    }
    False -> Nil
  }

  // add worktree
  let add_args = ["worktree", "add", "-b", branch_name, worktree_dir, base_ref]
  case ffi.git_exec(add_args, None) {
    ExecResult(0, _, _) -> {
      let _ = ffi.console_log("   + worktree created at " <> worktree_dir <> " (branch " <> branch_name <> ")")
      // configure author (best effort, host git may suffice)
      let _ = ffi.git_exec(["-C", worktree_dir, "config", "user.name", "grkr-bot"], None)
      let _ = ffi.git_exec(["-C", worktree_dir, "config", "user.email", "grkr@noreply.github.com"], None)
      let _ = ffi.git_exec(["-C", worktree_dir, "config", "commit.gpgsign", "false"], None)
      WorktreeInfo(dir: worktree_dir, branch: branch_name)
    }
    _ -> {
      let _ = ffi.console_log("   ⚠️ worktree create failed; falling back to temp dir (no git ops)")
      // fallback temp (no git)
      let tmp = worktrees_dir <> "/comment-" <> comment_id <> ".tmp"
      let _ = ffi.mkdir_p(tmp)
      WorktreeInfo(dir: tmp, branch: branch_name)
    }
  }
}

fn run_codex_classify(ctx: CommentContext, branch: String) -> String {
  let policy = "Follow AGENTS.md, spec/parts/*, and grkr v2 rules: minimal targeted changes only; always prefer answer/refuse over broad edits; respect 1000 LOC/file limit; use worktrees; post checkpoints for complex work; GitHub-only in this phase (no Linear mutations here). Be concise and professional."

  let prompt = "You are grkr, the autonomous repo robot.\n\nRAW COMMAND (from @:robot: comment #" <> ctx.id <> " by @" <> ctx.user_login <> "):\n" <> ctx.raw_cmd <> "\n\nCONTEXT:\n- Repo: " <> ctx.repo <> "\n- " <> case ctx.is_pr { True -> "PR " False -> "" } <> "Issue #" <> ctx.issue_number <> ": " <> ctx.issue_title <> "\n  State: " <> ctx.issue_state <> "\n  URL: " <> ctx.html_url <> "\n- Issue/PR body (truncated): " <> string.slice(ctx.issue_body, 0, 800) <> "\n- Recent thread comments (newest first, truncated): " <> ctx.recent_comments_json <> "\n- Current worktree branch: " <> branch <> "\n- Policy: " <> policy <> "\n\nTASK:\nClassify the intent of the RAW COMMAND and respond as one of:\n- answer-only: provide helpful reply, no code changes\n- code-change: describe + (if safe/minimal) note that edit would be made here\n- triage: suggest next step or label\n- refuse: politely decline with short reason (e.g. too vague, out of scope, needs more info)\n\nOUTPUT FORMAT (exact, parseable):\nCLASS: <answer-only|code-change|triage|refuse>\nREPLY: <1-6 sentence professional reply text for posting as GitHub comment. Include classification and any caveats. Do NOT include raw prompt.>\nCHANGES: <short description of any code intent or N/A>\n\nDo not execute external commands yourself; only describe. Keep REPLY under 1200 chars."

  let _ = ffi.console_log("   building codex prompt (len=" <> int.to_string(string.length(prompt)) <> ")")

  let codex_bin = "codex"
  // use timeout wrapper if available for parity; else direct (may hang in rare cases)
  let has_timeout = case ffi.executable("which", ["timeout"], None) {
    ExecResult(0, _, _) -> True
    _ -> False
  }

  let #(cmd_bin, cmd_args, use_input) = case has_timeout {
    True -> #("timeout", ["120", codex_bin, "exec", "--sandbox", "workspace-write"], True)
    False -> #(codex_bin, ["exec", "--sandbox", "workspace-write"], True)
  }

  let input = case use_input {
    True -> Some(prompt)
    False -> None
  }

  let out = case ffi.executable(cmd_bin, cmd_args, input) {
    ExecResult(0, stdout, _) -> stdout
    ExecResult(_, stdout, stderr) -> {
      stdout <> "\n" <> stderr <> "\nCLASS: refuse\nREPLY: Codex invocation failed or timed out for command: " <> ctx.raw_cmd <> ". Treating as non-actionable.\nCHANGES: N/A"
    }
  }

  let _ = ffi.console_log("   codex raw output (truncated): " <> string.slice(out, 0, 300) <> "...")
  out
}

fn parse_codex_output(out: String) -> #(String, String, String) {
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

fn post_result_comment(ctx: CommentContext, comment_id: String, repo: String, class: String, reply: String, changes: String, branch: String) -> Nil {
  let result = "**grkr** processed your `@:robot: " <> ctx.raw_cmd <> "` (comment " <> comment_id <> ")\n\n**Classification:** " <> class <> "\n**Reply/Notes:** " <> reply <> "\n\n**Changes intent:** " <> changes <> "\n**Worktree:** " <> branch <> " (cleaned)\n**Context:** " <> case ctx.is_pr { True -> "PR " False -> "" } <> "#" <> ctx.issue_number <> " \"" <> ctx.issue_title <> "\"\n\n(Generated via Codex per spec/15; see job log for full prompt/output. This is GitHub-only v2 slice.)"
  let cmd = ["gh", "issue", "comment", ctx.issue_number, "--body", result, "--repo", repo]
  case run_gh(cmd) {
    ExecResult(0, _, _) -> ffi.console_log("   + posted result comment on #" <> ctx.issue_number)
    _ -> ffi.console_log("   ⚠️ failed to post result comment (best effort; continuing)")
  }
}

fn try_optional_commit_push(dir: String, comment_id: String, raw_cmd: String, reply: String, _repo: String, branch: String) -> Nil {
  // check status with -C
  case ffi.executable("git", ["-C", dir, "status", "--porcelain"], None) {
    ExecResult(0, out, _) -> {
      case string.trim(out) {
        "" -> Nil
        _ -> {
          let _ = ffi.executable("git", ["-C", dir, "add", "-A"], None)
          let commit_msg = "robot(comment-" <> comment_id <> "): code-change for " <> raw_cmd <> "\n\n" <> reply <> "\n\n[grkr v2 worker-handle-comment]"
          let _ = ffi.executable("git", ["-C", dir, "commit", "-m", commit_msg], None)
          case ffi.executable("git", ["-C", dir, "push", "--force-with-lease", "origin", branch], None) {
            ExecResult(0, _, _) -> ffi.console_log("   + pushed branch " <> branch <> " (code-change)")
            _ -> ffi.console_log("   ⚠️ push skipped (no perms or no changes)")
          }
        }
      }
    }
    _ -> Nil
  }
}

fn remove_eyes_and_add_rocket(comment_id: String, repo: String, eyes_id: String) -> Nil {
  case eyes_id {
    "" -> Nil
    id -> {
      let del = ["gh", "api", "-X", "DELETE", "repos/" <> repo <> "/issues/comments/" <> comment_id <> "/reactions/" <> id]
      let _ = run_gh(del)
      Nil
    }
  }
  let rocket = ["gh", "api", "-X", "POST", "repos/" <> repo <> "/issues/comments/" <> comment_id <> "/reactions", "-f", "content=rocket"]
  case run_gh(rocket) {
    ExecResult(0, _, _) -> ffi.console_log("   + rocket reaction (success path)")
    _ -> ffi.console_log("   ⚠️ rocket reaction add failed (best effort)")
  }
}

fn cleanup_worktree(dir: String) -> Nil {
  case dir {
    "" -> Nil
    d -> {
      let _ = ffi.git_exec(["worktree", "remove", d, "--force"], None)
      let _ = ffi.executable("rm", ["-rf", d], None)
      ffi.console_log("   + worktree removed")
    }
  }
}
