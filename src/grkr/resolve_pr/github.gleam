import gleam/int
import grkr/resolve_pr/types

type ExecResult {
  ExecResult(exit_code: Int, stdout: String, stderr: String)
}

const gh_bin = "gh"

pub fn fetch_pr(pr_number: Int) -> Result(types.PullRequest, String) {
  let cmd = [
    gh_bin,
    "pr",
    "view",
    int.to_string(pr_number),
    "--json",
    "number,title,author,headRefName,headRefOid,baseRefName,mergeable,mergeStateStatus,isCrossRepository",
  ]

  case execute_command(cmd, "") {
    Ok(output) -> {
      case parse_pr_response(output) {
        Ok(pr) -> Ok(pr)
        Error(err) -> Error("Failed to parse PR response: " <> err)
      }
    }
    Error(err) -> Error("Failed to fetch PR: " <> err)
  }
}

pub fn list_open_prs() -> Result(List(types.PullRequest), String) {
  let cmd = [
    gh_bin,
    "pr",
    "list",
    "--state",
    "open",
    "--json",
    "number,title,author,headRefName,headRefOid,baseRefName,mergeable,mergeStateStatus,isCrossRepository",
  ]

  case execute_command(cmd, "") {
    Ok(output) -> {
      case parse_pr_list_response(output) {
        Ok(prs) -> Ok(prs)
        Error(err) -> Error("Failed to parse PR list: " <> err)
      }
    }
    Error(err) -> Error("Failed to list PRs: " <> err)
  }
}

pub fn post_pr_comment(pr_number: Int, comment: String) -> Result(Nil, String) {
  let cmd = [
    gh_bin,
    "pr",
    "comment",
    int.to_string(pr_number),
    "--body",
    comment,
  ]

  case execute_command(cmd, "") {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error("Failed to post comment: " <> err)
  }
}

pub fn get_pr_head_branch(pr_number: Int) -> Result(String, String) {
  case fetch_pr(pr_number) {
    Ok(pr) -> Ok(pr.head_ref)
    Error(err) -> Error(err)
  }
}

pub fn is_pr_conflicting(pr: types.PullRequest) -> Bool {
  pr.conflicted
}

fn parse_pr_response(output: String) -> Result(types.PullRequest, String) {
  parse_pr_json(output)
}

fn parse_pr_list_response(
  output: String,
) -> Result(List(types.PullRequest), String) {
  parse_pr_list_json(output)
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

@external(javascript, "../resolve_pr/github_ffi.mjs", "parse_pr_json")
fn parse_pr_json(output: String) -> Result(types.PullRequest, String)

@external(javascript, "../resolve_pr/github_ffi.mjs", "parse_pr_list_json")
fn parse_pr_list_json(output: String) -> Result(List(types.PullRequest), String)

@external(javascript, "../resolve_pr/exec.mjs", "executable")
fn javascript_executable(
  command: String,
  args: List(String),
  input: String,
) -> ExecResult
