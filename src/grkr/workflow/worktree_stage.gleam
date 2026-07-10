import gleam/list
import gleam/option
import gleam/string

import grkr/workflow/ffi

/// collect paths (diff + cached + untracked, filter !.grkr/, dedup) - uses context git
pub fn collect_relevant_issue_paths() -> List(String) {
  let diff = git_context_lines(["diff", "--name-only", "--relative"])
  let cached = git_context_lines(["diff", "--cached", "--name-only", "--relative"])
  let others = git_context_lines(["ls-files", "--others", "--exclude-standard"])
  let all_lines = list.flatten([diff, cached, others])
  all_lines
  |> list.filter(fn(p) {
    let t = string.trim(p)
    t != "" && !string.starts_with(t, ".grkr/")
  })
  |> dedup
}

fn git_context_lines(args: List(String)) -> List(String) {
  let res = ffi.git_exec_in_context(args, option.None)
  case res.exit_code {
    0 ->
      res.stdout
      |> string.trim()
      |> string.split("\n")
    _ -> []
  }
}

fn dedup(items: List(String)) -> List(String) {
  list.fold(items, [], fn(acc, item) {
    case list.contains(acc, item) {
      True -> acc
      False -> list.append(acc, [item])
    }
  })
}

/// stage only relevant files in context (reset + add -A per path)
/// If no CURRENT_ISSUE_WORKTREE, falls back to git add -A (host)
pub fn stage_relevant_issue_files() -> Nil {
  case ffi.get_env("CURRENT_ISSUE_WORKTREE") {
    "" -> {
      let _ = ffi.git_exec(["add", "-A"], option.None)
      Nil
    }
    _ -> {
      let _ = ffi.git_exec_in_context(["reset"], option.None)
      let paths = collect_relevant_issue_paths()
      list.each(paths, fn(p) {
        let _ = ffi.git_exec_in_context(["add", "-A", "--", p], option.None)
        Nil
      })
      Nil
    }
  }
}
