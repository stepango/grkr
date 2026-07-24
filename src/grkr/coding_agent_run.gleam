//// coding_agent_run.gleam
//// Run + output helpers (LOC hygiene split, t_e7ea2b4b).
//// Zero behavior change; moved from monolithic coding_agent.gleam.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

import grkr/coding_agent_classify
import grkr/coding_agent_select
import grkr/coding_agent_types.{
  type Agent, type ExecFn, type ExecOutcome, type FsDeps, type RunMode,
  type Step, Classify, Codex, ConflictResolve, ExecFailed, ExecOk, Grok,
}

// --- FFI ---

@external(javascript, "./coding_agent_ffi.mjs", "ensure_xai_api_key")
fn ffi_ensure_xai_api_key() -> Nil

@external(javascript, "./coding_agent_ffi.mjs", "split_args")
fn ffi_split_args(s: String) -> List(String)

// --- Run (inject exec + fs for testability) ---

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
  case coding_agent_select.agent_name_from(get_env, step) {
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
  run(step, mode, prompt, workdir, coding_agent_select.default_get_env, exec, fs)
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
      let inv = coding_agent_classify.classify_codex(prompt, get_env, has_timeout)
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
          let inv =
            coding_agent_classify.classify_grok(path, workdir, get_env, has_timeout)
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
          let inv =
            coding_agent_classify.classify_grok(path, workdir, get_env, False)
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
