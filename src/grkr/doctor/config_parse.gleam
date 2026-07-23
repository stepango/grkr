import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Normalize GitHub remote URLs to owner/repo (parity with bin/doctor.sh).
pub fn normalize_repo_slug(url: String) -> Result(String, Nil) {
  let trimmed = string.trim(url)
  case string.starts_with(trimmed, "git@github.com:") {
    True -> {
      let rest = string.drop_start(trimmed, 15)
      Ok(strip_git_suffix(rest))
    }
    False ->
      case string.starts_with(trimmed, "ssh://git@github.com/") {
        True -> {
          let rest = string.drop_start(trimmed, 22)
          Ok(strip_git_suffix(rest))
        }
        False ->
          case string.starts_with(trimmed, "https://github.com/") {
            True -> {
              let rest = string.drop_start(trimmed, 19)
              Ok(strip_git_suffix(rest))
            }
            False -> Error(Nil)
          }
      }
  }
}

fn strip_git_suffix(slug: String) -> String {
  case string.ends_with(slug, ".git") {
    True -> string.drop_end(slug, 4)
    False -> slug
  }
}

/// Parse KEY="value" or KEY=value lines from config.sh (shell parity).
pub fn parse_config_assignments(content: String) -> List(#(String, String)) {
  content
  |> string.split("\n")
  |> list.filter_map(parse_config_line)
}

fn parse_config_line(line: String) -> Result(#(String, String), Nil) {
  let trimmed = string.trim(line)
  case trimmed {
    "" -> Error(Nil)
    _ ->
      case string.starts_with(trimmed, "#") {
        True -> Error(Nil)
        False -> parse_assignment(trimmed)
      }
  }
}

fn parse_assignment(line: String) -> Result(#(String, String), Nil) {
  case string.split(line, "=") {
    [key, ..rest] -> {
      let value = string.join(rest, "=")
      let k = string.uppercase(string.trim(key))
      let v = unwrap_quoted(string.trim(value))
      case v {
        "" -> Error(Nil)
        _ -> Ok(#(k, v))
      }
    }
    _ -> Error(Nil)
  }
}

fn unwrap_quoted(value: String) -> String {
  case string.starts_with(value, "\"") && string.ends_with(value, "\"") {
    True -> string.slice(value, 1, string.length(value) - 2)
    False -> value
  }
}

pub fn config_get(
  assignments: List(#(String, String)),
  key: String,
) -> Option(String) {
  let upper = string.uppercase(key)
  case list.find_map(assignments, fn(pair) {
    let #(k, v) = pair
    case k == upper {
      True -> Ok(v)
      False -> Error(Nil)
    }
  }) {
    Ok(v) -> Some(v)
    Error(_) -> None
  }
}

pub fn required_config_keys() -> List(String) {
  [
    "REPO", "PROJECT_OWNER", "PROJECT_NUMBER", "STATUS_FIELD_NAME", "TODO_VALUE",
    "BACKLOG_VALUE", "PRIORITY_FIELD_NAME",
  ]
}

pub fn missing_required_keys(
  assignments: List(#(String, String)),
) -> List(String) {
  required_config_keys()
  |> list.filter(fn(key) {
    case config_get(assignments, key) {
      None -> True
      Some("") -> True
      Some(_) -> False
    }
  })
}

pub fn default_config_template(
  remote_slug: String,
  project_owner: String,
  project_number: String,
) -> String {
  "REPO=\""
    <> remote_slug
    <> "\"\nMAIN_BRANCH=\"main\"\nPROJECT_OWNER=\""
    <> project_owner
    <> "\"\nPROJECT_NUMBER=\""
    <> project_number
    <> "\"\nSTATUS_FIELD_NAME=\"Status\"\nTODO_VALUE=\"Todo\"\nIN_PROGRESS_VALUE=\"In Progress\"\nDONE_VALUE=\"Done\"\nBACKLOG_VALUE=\"Backlog\"\nPRIORITY_FIELD_NAME=\"Priority\"\nTEST_COMMAND=\"npm test\"\nBUILD_COMMAND=\"\"\nLOOP_INTERVAL_SECS=\"20\"\n\n# Coding agent backend: codex (default) or grok. Issue decision/implement use this.\nGRKR_CODING_AGENT=\"codex\"\n# Per-step overrides (optional):\n# GRKR_AGENT_DECISION=\"grok\"\n# GRKR_AGENT_IMPLEMENT=\"codex\"\n# GRKR_AGENT_REMEDIATE=\"grok\"\n# GRKR_AGENT_COMMENT=\"codex\"   # Gleam @:robot: comment-classify\n# GRKR_AGENT_RESOLVE=\"grok\"    # Gleam resolve_pr ConflictResolve\n# Gleam comment-classify + resolve_pr honor the overrides above, else fall back to GRKR_CODING_AGENT.\n# CODEX_BIN=\"codex\"\n# CODEX_MODEL=\"gpt-5-codex\"\n# CODEX_ARGS=\"-c model=$CODEX_MODEL\"\n# GROK_BIN=\"\"\n# GROK_MODEL=\"grok-4.5\"\n# GROK_MAX_TURNS=\"60\"\n# GROK_ARGS=\"\"\n"
}