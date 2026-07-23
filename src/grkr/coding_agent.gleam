//// Shared coding-agent selection + classify/resolve argv assembly.
//// Slice 1: comment-classify; slice 2: resolve_pr ConflictResolve.
//// Env/argv parity: bin/lib/issue_shared_coding_agent.sh + docs/design-gleam-coding-agent-swap.md

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// --- Types ---

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

// --- FFI ---

@external(javascript, "./coding_agent_ffi.mjs", "split_args")
fn ffi_split_args(s: String) -> List(String)

@external(javascript, "./coding_agent_ffi.mjs", "default_grok_bin")
fn ffi_default_grok_bin() -> String

@external(javascript, "./coding_agent_ffi.mjs", "ensure_xai_api_key")
fn ffi_ensure_xai_api_key() -> Nil

@external(javascript, "./workflow/worktree_ffi.mjs", "get_env")
fn default_get_env(name: String) -> String

// --- Agent name ---

/// Production: read process env via workflow get_env.
pub fn agent_name(step: Step) -> Result(Agent, String) {
  agent_name_from(default_get_env, step)
}

/// Testable: inject env lookup. Precedence per step:
/// GRKR_AGENT_<STEP> → GRKR_CODING_AGENT_<STEP> (legacy) → GRKR_CODING_AGENT → CODING_AGENT → codex
pub fn agent_name_from(
  get_env: fn(String) -> String,
  step: Step,
) -> Result(Agent, String) {
  let raw = resolve_raw_name(get_env, step)
  case raw {
    "codex" -> Ok(Codex)
    "grok" -> Ok(Grok)
    other -> Error(other)
  }
}

fn resolve_raw_name(get_env: fn(String) -> String, step: Step) -> String {
  let step_raw = case step {
    Comment ->
      first_nonempty([
        get_env("GRKR_AGENT_COMMENT"),
        get_env("GRKR_CODING_AGENT_COMMENT"),
      ])
    Resolve ->
      first_nonempty([
        get_env("GRKR_AGENT_RESOLVE"),
        get_env("GRKR_CODING_AGENT_RESOLVE"),
      ])
  }
  let chosen = case step_raw {
    "" ->
      first_nonempty([get_env("GRKR_CODING_AGENT"), get_env("CODING_AGENT")])
    s -> s
  }
  case normalize_name(chosen) {
    "" -> "codex"
    n -> n
  }
}

fn first_nonempty(vals: List(String)) -> String {
  case vals {
    [] -> ""
    [h, ..t] ->
      case string.trim(h) {
        "" -> first_nonempty(t)
        s -> s
      }
  }
}

fn normalize_name(s: String) -> String {
  s
  |> string.lowercase
  |> string.trim
  |> string.replace(" ", "")
  |> string.replace("\t", "")
  |> string.replace("\n", "")
  |> string.replace("\r", "")
}

// --- Classify invocation builders (pure given deps) ---

/// Build classify argv for a known agent. Grok requires prompt_file path already written.
pub fn classify_invocation(
  agent: Agent,
  prompt: String,
  workdir: String,
  get_env: fn(String) -> String,
  has_timeout: Bool,
  prompt_file: Option(String),
) -> Invocation {
  case agent {
    Codex -> classify_codex(prompt, get_env, has_timeout)
    Grok ->
      case prompt_file {
        Some(path) -> classify_grok(path, workdir, get_env, has_timeout)
        None ->
          // Should not happen if caller wrote temp; fail-shaped empty cmd.
          Invocation(bin: "false", args: [], stdin: None)
      }
  }
}

fn classify_codex(
  prompt: String,
  get_env: fn(String) -> String,
  has_timeout: Bool,
) -> Invocation {
  let bin = case string.trim(get_env("CODEX_BIN")) {
    "" -> "codex"
    b -> b
  }
  let extra =
    list.append(
      ffi_split_args(get_env("CODEX_ARGS")),
      ffi_split_args(get_env("CODEX_EXTRA_ARGS")),
    )
  let base_args =
    list.append(["exec", "--sandbox", "workspace-write"], extra)
  case has_timeout {
    True ->
      Invocation(
        bin: "timeout",
        args: list.append(["120", bin], base_args),
        stdin: Some(prompt),
      )
    False -> Invocation(bin: bin, args: base_args, stdin: Some(prompt))
  }
}

fn classify_grok(
  prompt_file: String,
  workdir: String,
  get_env: fn(String) -> String,
  has_timeout: Bool,
) -> Invocation {
  let bin = case string.trim(get_env("GROK_BIN")) {
    "" -> ffi_default_grok_bin()
    b -> b
  }
  let model = case string.trim(get_env("GROK_MODEL")) {
    "" -> "grok-4.5"
    m -> m
  }
  let max_turns = case string.trim(get_env("GROK_MAX_TURNS")) {
    "" -> "60"
    t -> t
  }
  let grok_args = ffi_split_args(get_env("GROK_ARGS"))
  let base_args =
    list.append(
      [
        "--prompt-file",
        prompt_file,
        "--cwd",
        workdir,
        "-m",
        model,
        "--yolo",
        "--permission-mode",
        "bypassPermissions",
        "--max-turns",
        max_turns,
        "--output-format",
        "plain",
        "--no-memory",
      ],
      grok_args,
    )
  case has_timeout {
    True ->
      Invocation(
        bin: "timeout",
        args: list.append(["120", bin], base_args),
        stdin: None,
      )
    False -> Invocation(bin: bin, args: base_args, stdin: None)
  }
}

// --- Run (inject exec + fs for testability) ---

pub type ExecFn =
  fn(String, List(String), Option(String)) -> ExecOutcome

/// Run coding agent for step/mode. Unknown agent → ExecFailed (caller maps to refuse).
pub fn run(
  step: Step,
  mode: RunMode,
  prompt: String,
  workdir: String,
  get_env: fn(String) -> String,
  exec: ExecFn,
  fs: FsDeps,
) -> ExecOutcome {
  case agent_name_from(get_env, step) {
    Error(name) ->
      ExecFailed(
        exit_code: 2,
        stdout: "",
        stderr: "Unknown coding agent '"
          <> name
          <> "' (supported: codex, grok).",
      )
    Ok(agent) ->
      case mode {
        Classify -> run_classify(agent, prompt, workdir, get_env, exec, fs)
        ConflictResolve ->
          run_conflict_resolve(agent, prompt, workdir, get_env, exec, fs)
      }
  }
}

/// Production convenience: workflow ffi env/exec/temp helpers.
pub fn run_with_defaults(
  step: Step,
  mode: RunMode,
  prompt: String,
  workdir: String,
  exec: ExecFn,
  fs: FsDeps,
) -> ExecOutcome {
  run(step, mode, prompt, workdir, default_get_env, exec, fs)
}

fn run_classify(
  agent: Agent,
  prompt: String,
  workdir: String,
  get_env: fn(String) -> String,
  exec: ExecFn,
  fs: FsDeps,
) -> ExecOutcome {
  let has_timeout = case exec("which", ["timeout"], None) {
    ExecOk(_) -> True
    ExecFailed(0, _, _) -> True
    _ -> False
  }

  case agent {
    Codex -> {
      let inv = classify_codex(prompt, get_env, has_timeout)
      exec(inv.bin, inv.args, inv.stdin)
    }
    Grok -> {
      let _ = ffi_ensure_xai_api_key()
      let path = fs.temp_path("grkr-agent-prompt.")
      case fs.write_text(path, prompt) {
        Error(e) ->
          ExecFailed(
            exit_code: 1,
            stdout: "",
            stderr: "Failed to write prompt file: " <> e,
          )
        Ok(_) -> {
          let inv = classify_grok(path, workdir, get_env, has_timeout)
          let outcome = exec(inv.bin, inv.args, inv.stdin)
          let _ = fs.unlink(path)
          outcome
        }
      }
    }
  }
}

fn run_conflict_resolve(
  agent: Agent,
  prompt: String,
  workdir: String,
  get_env: fn(String) -> String,
  exec: ExecFn,
  fs: FsDeps,
) -> ExecOutcome {
  // resolve_pr: preserve Codex exec --full-auto + prompt-as-argv + empty stdin.
  case agent {
    Codex -> {
      let bin = case string.trim(get_env("CODEX_BIN")) {
        "" -> "codex"
        b -> b
      }
      let extra =
        list.append(
          ffi_split_args(get_env("CODEX_ARGS")),
          ffi_split_args(get_env("CODEX_EXTRA_ARGS")),
        )
      let args =
        list.append(list.append(["exec", "--full-auto"], extra), [prompt])
      exec(bin, args, Some(""))
    }
    Grok -> {
      let _ = ffi_ensure_xai_api_key()
      let path = fs.temp_path("grkr-agent-prompt.")
      case fs.write_text(path, prompt) {
        Error(e) ->
          ExecFailed(
            exit_code: 1,
            stdout: "",
            stderr: "Failed to write prompt file: " <> e,
          )
        Ok(_) -> {
          let inv = classify_grok(path, workdir, get_env, False)
          let outcome = exec(inv.bin, inv.args, inv.stdin)
          let _ = fs.unlink(path)
          outcome
        }
      }
    }
  }
}

/// Synthetic refuse body for comment classify fail path (stable substring).
pub fn classify_fail_reply(raw_cmd: String) -> String {
  "CLASS: refuse\nREPLY: Coding agent invocation failed or timed out for command: "
  <> raw_cmd
  <> ". Treating as non-actionable.\nCHANGES: N/A"
}

/// Map ExecOutcome to classify stdout (success or synthetic refuse).
pub fn classify_output(outcome: ExecOutcome, raw_cmd: String) -> String {
  case outcome {
    ExecOk(stdout) -> stdout
    ExecFailed(_, stdout, stderr) ->
      stdout <> "\n" <> stderr <> "\n" <> classify_fail_reply(raw_cmd)
  }
}

/// Format agent for logs (optional).
pub fn agent_label(agent: Agent) -> String {
  case agent {
    Codex -> "codex"
    Grok -> "grok"
  }
}

/// Debug helper: join argv like a shell would show.
pub fn format_cmd(bin: String, args: List(String)) -> String {
  string.join(list.append([bin], args), " ")
}

pub fn outcome_exit_code(outcome: ExecOutcome) -> Int {
  case outcome {
    ExecOk(_) -> 0
    ExecFailed(code, _, _) -> code
  }
}

pub fn int_env(get_env: fn(String) -> String, name: String, default: Int) -> Int {
  case int.parse(string.trim(get_env(name))) {
    Ok(n) -> n
    Error(_) -> default
  }
}
