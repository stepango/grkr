//// coding_agent_types.gleam
//// Shared public types for coding_agent (LOC hygiene split, t_e7ea2b4b).
//// Zero behavior change; moved from monolithic coding_agent.gleam.
//// Constructors live here; facade re-exports type aliases for annotations.

import gleam/option.{type Option}

pub type Step {
  Comment
  Resolve
}

pub type Agent {
  Codex
  Grok
}

pub type RunMode {
  /// Comment classify: optional timeout 120, sandbox workspace-write,
  /// prompt on stdin for Codex; Grok uses --prompt-file.
  Classify
  /// PR resolve: --full-auto, prompt-as-argv for Codex; Grok --prompt-file.
  ConflictResolve
}

pub type ExecOutcome {
  ExecOk(stdout: String)
  ExecFailed(exit_code: Int, stdout: String, stderr: String)
}

/// Built command ready for exec (tests assert on this).
pub type Invocation {
  Invocation(bin: String, args: List(String), stdin: Option(String))
}

pub type FsDeps {
  FsDeps(
    temp_path: fn(String) -> String,
    write_text: fn(String, String) -> Result(Nil, String),
    unlink: fn(String) -> Bool,
  )
}

pub type ExecFn =
  fn(String, List(String), Option(String)) -> ExecOutcome
