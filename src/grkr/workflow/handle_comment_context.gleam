//// handle_comment_context.gleam
//// GH context fetch, JSON parsing, run_gh for handle_comment (LOC hygiene split).
//// Moved verbatim from monolithic handle_comment.gleam (zero behavior change).

import gleam/list
import gleam/option
import gleam/string

import grkr/workflow/ffi.{type ExecResult, type JsonValue, ExecResult}
import grkr/workflow/handle_comment_types.{type CommentContext, CommentContext}

pub fn fetch_context(comment_id: String, repo: String, _main_branch: String) -> Result(CommentContext, String) {
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

pub fn run_gh(args: List(String)) -> ExecResult {
  // args include "gh" as head; split for executable
  case args {
    [bin, ..rest] -> ffi.executable(bin, rest, option.None)
    _ -> ExecResult(1, "", "bad gh cmd")
  }
}
