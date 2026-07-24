//// validate_agent.gleam
//// Doctor coding-agent probes (LOC hygiene split, t_74a7a161).
//// Zero intentional behavior change.

import gleam/option.{None, Some}
import gleam/string
import grkr/doctor/config_parse
import grkr/doctor/validate_config as config
import grkr/doctor/validate_tools as tools

pub fn validate_codex() -> Bool {
  validate_named_tool("codex", "codex is required but not installed.")
}

pub fn validate_grok() -> Bool {
  case tools.tool_on_path("grok") {
    True -> validate_named_tool("grok", "grok is required but not installed.")
    False ->
      case tools.path_exists(home_dir() <> "/.grok/bin/grok") {
        True ->
          case tools.executable(home_dir() <> "/.grok/bin/grok", ["--help"], "") {
            tools.ExecResult(0, _, _) -> True
            _ -> {
              tools.fail("grok is installed at ~/.grok/bin/grok but not runnable.")
              False
            }
          }
        False -> {
          tools.fail(
            "grok is required (GRKR_CODING_AGENT=grok) but not installed. Install Grok Build CLI or set GROK_BIN.",
          )
          False
        }
      }
  }
}

/// Selected coding agent from env, then config.sh. Default: codex.
pub fn coding_agent_name() -> String {
  case string.lowercase(string.trim(tools.get_env("GRKR_CODING_AGENT"))) {
    "" ->
      case string.lowercase(string.trim(tools.get_env("CODING_AGENT"))) {
        "" -> coding_agent_from_config()
        other -> other
      }
    agent -> agent
  }
}

fn coding_agent_from_config() -> String {
  let path = config.config_file_path()
  case tools.path_exists(path) {
    False -> "codex"
    True ->
      case tools.read_text(path) {
        Error(_) -> "codex"
        Ok(content) -> {
          let assignments = config_parse.parse_config_assignments(content)
          case config_parse.config_get(assignments, "GRKR_CODING_AGENT") {
            Some(v) -> string.lowercase(string.trim(v))
            None ->
              case config_parse.config_get(assignments, "CODING_AGENT") {
                Some(v) -> string.lowercase(string.trim(v))
                None -> "codex"
              }
          }
        }
      }
  }
}

fn home_dir() -> String {
  case tools.get_env("HOME") {
    "" -> "."
    h -> h
  }
}

fn validate_named_tool(tool: String, missing_msg: String) -> Bool {
  case tools.tool_on_path(tool) {
    False -> {
      tools.fail(missing_msg)
      False
    }
    True ->
      case tools.executable(tool, ["--help"], "") {
        tools.ExecResult(0, _, _) -> True
        _ -> {
          tools.fail(tool <> " is installed but not runnable.")
          False
        }
      }
  }
}

/// Validate only the configured coding agent (codex default, or grok).
pub fn validate_coding_agent() -> Bool {
  case coding_agent_name() {
    "codex" -> validate_codex()
    "grok" -> validate_grok()
    other -> {
      tools.fail(
        "Unknown GRKR_CODING_AGENT="
          <> other
          <> " (supported: codex, grok).",
      )
      False
    }
  }
}
