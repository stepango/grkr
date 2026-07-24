//// Unit tests for grkr/coding_agent: agent_name precedence + classify/resolve
//// argv via injected env/exec (no real coding-agent binary).

import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import gleeunit
import gleeunit/should

import grkr/coding_agent
import grkr/coding_agent_types.{
  Classify, Codex, Comment, ConflictResolve, ExecFailed, ExecOk, FsDeps, Grok,
  Invocation, Resolve,
}

pub fn main() {
  gleeunit.main()
}

// --- env helpers ---

fn env_from(pairs: List(#(String, String))) -> fn(String) -> String {
  let m = dict.from_list(pairs)
  fn(key) {
    case dict.get(m, key) {
      Ok(v) -> v
      Error(_) -> ""
    }
  }
}

// --- capture ffi ---

@external(javascript, "./coding_agent_test_ffi.mjs", "reset")
fn cap_reset() -> Nil

@external(javascript, "./coding_agent_test_ffi.mjs", "record_write")
fn cap_record_write(path: String, body: String) -> Nil

@external(javascript, "./coding_agent_test_ffi.mjs", "record_unlink")
fn cap_record_unlink(path: String) -> Nil

@external(javascript, "./coding_agent_test_ffi.mjs", "record_call")
fn cap_record_call(bin: String, args: List(String), stdin: String) -> Nil

@external(javascript, "./coding_agent_test_ffi.mjs", "get_writes")
fn cap_writes() -> List(#(String, String))

@external(javascript, "./coding_agent_test_ffi.mjs", "get_unlinks")
fn cap_unlinks() -> List(String)

@external(javascript, "./coding_agent_test_ffi.mjs", "get_calls")
fn cap_calls() -> List(#(String, List(String), String))

fn fake_exec_no_timeout(
  bin: String,
  args: List(String),
  input: Option(String),
) -> coding_agent.ExecOutcome {
  let stdin_s = case input {
    Some(s) -> s
    None -> ""
  }
  case bin, args {
    "which", ["timeout"] -> ExecFailed(1, "", "")
    _, _ -> {
      cap_record_call(bin, args, stdin_s)
      case bin {
        "grok" -> ExecOk("GROK-OK")
        _ ->
          case list.contains(args, "grok") {
            True -> ExecOk("GROK-OK")
            False -> ExecOk("CODEX-OK")
          }
      }
    }
  }
}

fn fake_fs() -> coding_agent.FsDeps {
  FsDeps(
    temp_path: fn(prefix) { "/tmp/" <> prefix <> "test" },
    write_text: fn(path, body) {
      cap_record_write(path, body)
      Ok(Nil)
    },
    unlink: fn(path) {
      cap_record_unlink(path)
      True
    },
  )
}

// --- agent_name ---

pub fn agent_name_default_codex_test() {
  coding_agent.agent_name_from(env_from([]), Comment)
  |> should.equal(Ok(Codex))
}

pub fn agent_name_grkr_coding_agent_test() {
  coding_agent.agent_name_from(
    env_from([#("GRKR_CODING_AGENT", "grok")]),
    Comment,
  )
  |> should.equal(Ok(Grok))
}

pub fn agent_name_coding_agent_alias_test() {
  coding_agent.agent_name_from(env_from([#("CODING_AGENT", "Grok")]), Comment)
  |> should.equal(Ok(Grok))
}

pub fn agent_name_grkr_takes_precedence_over_alias_test() {
  coding_agent.agent_name_from(
    env_from([
      #("GRKR_CODING_AGENT", "codex"),
      #("CODING_AGENT", "grok"),
    ]),
    Comment,
  )
  |> should.equal(Ok(Codex))
}

pub fn agent_name_comment_step_override_test() {
  coding_agent.agent_name_from(
    env_from([
      #("GRKR_CODING_AGENT", "codex"),
      #("GRKR_AGENT_COMMENT", "grok"),
    ]),
    Comment,
  )
  |> should.equal(Ok(Grok))
}

pub fn agent_name_comment_legacy_alias_test() {
  coding_agent.agent_name_from(
    env_from([
      #("GRKR_CODING_AGENT", "codex"),
      #("GRKR_CODING_AGENT_COMMENT", "grok"),
    ]),
    Comment,
  )
  |> should.equal(Ok(Grok))
}

pub fn agent_name_comment_override_beats_legacy_test() {
  coding_agent.agent_name_from(
    env_from([
      #("GRKR_AGENT_COMMENT", "codex"),
      #("GRKR_CODING_AGENT_COMMENT", "grok"),
    ]),
    Comment,
  )
  |> should.equal(Ok(Codex))
}

pub fn agent_name_trims_and_lowercases_test() {
  coding_agent.agent_name_from(
    env_from([#("GRKR_CODING_AGENT", "  Grok  ")]),
    Comment,
  )
  |> should.equal(Ok(Grok))
}

pub fn agent_name_unknown_test() {
  coding_agent.agent_name_from(
    env_from([#("GRKR_CODING_AGENT", "claude")]),
    Comment,
  )
  |> should.equal(Error("claude"))
}

pub fn agent_name_resolve_step_override_test() {
  coding_agent.agent_name_from(
    env_from([
      #("GRKR_CODING_AGENT", "codex"),
      #("GRKR_AGENT_RESOLVE", "grok"),
    ]),
    Resolve,
  )
  |> should.equal(Ok(Grok))
}

pub fn agent_name_comment_override_ignored_for_resolve_test() {
  coding_agent.agent_name_from(
    env_from([
      #("GRKR_AGENT_COMMENT", "grok"),
      #("GRKR_CODING_AGENT", "codex"),
    ]),
    Resolve,
  )
  |> should.equal(Ok(Codex))
}

// --- classify argv (pure builders) ---

pub fn classify_codex_default_no_timeout_test() {
  let inv =
    coding_agent.classify_invocation(
      Codex,
      "prompt-body",
      "/tmp/wt",
      env_from([]),
      False,
      None,
    )
  inv
  |> should.equal(Invocation(
    bin: "codex",
    args: ["exec", "--sandbox", "workspace-write"],
    stdin: Some("prompt-body"),
  ))
}

pub fn classify_codex_with_timeout_test() {
  let inv =
    coding_agent.classify_invocation(
      Codex,
      "p",
      "/wt",
      env_from([]),
      True,
      None,
    )
  inv.bin |> should.equal("timeout")
  inv.args
  |> should.equal(["120", "codex", "exec", "--sandbox", "workspace-write"])
  inv.stdin |> should.equal(Some("p"))
}

pub fn classify_codex_bin_and_extra_args_test() {
  let inv =
    coding_agent.classify_invocation(
      Codex,
      "p",
      "/wt",
      env_from([
        #("CODEX_BIN", "my-codex"),
        #("CODEX_ARGS", "--foo bar"),
        #("CODEX_EXTRA_ARGS", "--skip-git-repo-check"),
      ]),
      False,
      None,
    )
  inv.bin |> should.equal("my-codex")
  inv.args
  |> should.equal([
    "exec",
    "--sandbox",
    "workspace-write",
    "--foo",
    "bar",
    "--skip-git-repo-check",
  ])
  // no --full-auto on comment path
  list.any(inv.args, fn(a) { a == "--full-auto" })
  |> should.equal(False)
}

pub fn classify_grok_argv_test() {
  let inv =
    coding_agent.classify_invocation(
      Grok,
      "ignored-prompt-on-stdin",
      "/work/tree",
      env_from([
        #("GROK_BIN", "/opt/grok"),
        #("GROK_MODEL", "grok-build"),
        #("GROK_MAX_TURNS", "60"),
      ]),
      False,
      Some("/tmp/grkr-agent-prompt.xyz"),
    )
  inv.bin |> should.equal("/opt/grok")
  inv.stdin |> should.equal(None)
  inv.args
  |> should.equal([
    "--prompt-file",
    "/tmp/grkr-agent-prompt.xyz",
    "--cwd",
    "/work/tree",
    "-m",
    "grok-build",
    "--yolo",
    "--permission-mode",
    "bypassPermissions",
    "--max-turns",
    "60",
    "--output-format",
    "plain",
    "--no-memory",
  ])
}

pub fn classify_grok_default_model_test() {
  // Empty GROK_MODEL → product default grok-4.5
  let inv =
    coding_agent.classify_invocation(
      Grok,
      "ignored-prompt-on-stdin",
      "/work/tree",
      env_from([#("GROK_BIN", "/opt/grok")]),
      False,
      Some("/tmp/grkr-agent-prompt.xyz"),
    )
  inv.bin |> should.equal("/opt/grok")
  inv.stdin |> should.equal(None)
  inv.args
  |> should.equal([
    "--prompt-file",
    "/tmp/grkr-agent-prompt.xyz",
    "--cwd",
    "/work/tree",
    "-m",
    "grok-4.5",
    "--yolo",
    "--permission-mode",
    "bypassPermissions",
    "--max-turns",
    "60",
    "--output-format",
    "plain",
    "--no-memory",
  ])
}

pub fn classify_grok_with_timeout_and_args_test() {
  let inv =
    coding_agent.classify_invocation(
      Grok,
      "p",
      "/wd",
      env_from([
        #("GROK_BIN", "grok"),
        #("GROK_ARGS", "--check"),
      ]),
      True,
      Some("/tmp/pf"),
    )
  inv.bin |> should.equal("timeout")
  list.contains(inv.args, "120") |> should.equal(True)
  list.contains(inv.args, "grok") |> should.equal(True)
  list.contains(inv.args, "--prompt-file") |> should.equal(True)
  list.contains(inv.args, "grok-4.5") |> should.equal(True)
  list.contains(inv.args, "--check") |> should.equal(True)
  inv.stdin |> should.equal(None)
}

// --- run with fake exec ---

pub fn run_codex_classify_fake_exec_test() {
  cap_reset()
  let get_env = env_from([])
  let outcome =
    coding_agent.run(
      Comment,
      Classify,
      "hello-prompt",
      "/wt-dir",
      get_env,
      fake_exec_no_timeout,
      fake_fs(),
    )
  case outcome {
    ExecOk(s) -> s |> should.equal("CODEX-OK")
    _ -> should.fail()
  }
  let calls = cap_calls()
  list.length(calls) |> should.equal(1)
  let assert [#(bin, args, stdin)] = calls
  bin |> should.equal("codex")
  args |> should.equal(["exec", "--sandbox", "workspace-write"])
  stdin |> should.equal("hello-prompt")
}

pub fn run_grok_classify_writes_prompt_file_test() {
  cap_reset()
  let get_env =
    env_from([#("GRKR_CODING_AGENT", "grok"), #("GROK_BIN", "grok")])
  let outcome =
    coding_agent.run(
      Comment,
      Classify,
      "prompt-text",
      "/cwd",
      get_env,
      fake_exec_no_timeout,
      fake_fs(),
    )
  case outcome {
    ExecOk(s) -> s |> should.equal("GROK-OK")
    _ -> should.fail()
  }
  let writes = cap_writes()
  list.length(writes) |> should.equal(1)
  let assert [#(path, body)] = writes
  body |> should.equal("prompt-text")
  string.contains(path, "grkr-agent-prompt.") |> should.equal(True)
  list.contains(cap_unlinks(), path) |> should.equal(True)

  let calls = cap_calls()
  list.length(calls) |> should.equal(1)
  let assert [#(bin, args, stdin)] = calls
  bin |> should.equal("grok")
  list.contains(args, "--prompt-file") |> should.equal(True)
  list.contains(args, path) |> should.equal(True)
  list.contains(args, "--cwd") |> should.equal(True)
  list.contains(args, "/cwd") |> should.equal(True)
  stdin |> should.equal("")
}

pub fn run_unknown_agent_fails_test() {
  cap_reset()
  let get_env = env_from([#("GRKR_CODING_AGENT", "nope")])
  let outcome =
    coding_agent.run(
      Comment,
      Classify,
      "p",
      "/w",
      get_env,
      fake_exec_no_timeout,
      fake_fs(),
    )
  case outcome {
    ExecFailed(2, _, err) ->
      string.contains(err, "Unknown coding agent") |> should.equal(True)
    _ -> should.fail()
  }
  list.length(cap_calls()) |> should.equal(0)
}

pub fn classify_fail_reply_stable_substring_test() {
  let reply = coding_agent.classify_fail_reply("do stuff")
  string.contains(reply, "invocation failed or timed out")
  |> should.equal(True)
  string.contains(reply, "CLASS: refuse") |> should.equal(True)
  string.contains(reply, "Coding agent") |> should.equal(True)
  string.contains(reply, "do stuff") |> should.equal(True)
}

pub fn classify_output_maps_failure_test() {
  let out =
    coding_agent.classify_output(ExecFailed(1, "out", "err"), "raw-cmd")
  string.contains(out, "invocation failed or timed out")
  |> should.equal(True)
  string.contains(out, "CLASS: refuse") |> should.equal(True)
}

// --- ConflictResolve (slice 2 resolve_pr path) ---

pub fn run_codex_conflict_resolve_default_argv_test() {
  cap_reset()
  let prompt = "resolve-this-conflict-prompt"
  let outcome =
    coding_agent.run(
      Resolve,
      ConflictResolve,
      prompt,
      "/wt-resolve",
      env_from([]),
      fake_exec_no_timeout,
      fake_fs(),
    )
  case outcome {
    ExecOk(s) -> s |> should.equal("CODEX-OK")
    _ -> should.fail()
  }
  let calls = cap_calls()
  list.length(calls) |> should.equal(1)
  let assert [#(bin, args, stdin)] = calls
  bin |> should.equal("codex")
  // Codex resolve: exec --full-auto + prompt-as-argv + empty stdin (no timeout/sandbox/--cd)
  list.length(args) |> should.equal(3)
  list.take(args, 2) |> should.equal(["exec", "--full-auto"])
  case list.last(args) {
    Ok(last) -> last |> should.equal(prompt)
    Error(_) -> should.fail()
  }
  list.any(args, fn(a) { a == "--sandbox" }) |> should.equal(False)
  list.any(args, fn(a) { a == "workspace-write" }) |> should.equal(False)
  list.any(args, fn(a) { a == "120" }) |> should.equal(False)
  stdin |> should.equal("")
  // no prompt file writes on Codex path
  list.length(cap_writes()) |> should.equal(0)
}

pub fn run_codex_conflict_resolve_bin_and_args_test() {
  cap_reset()
  let prompt = "p-body"
  let outcome =
    coding_agent.run(
      Resolve,
      ConflictResolve,
      prompt,
      "/wt",
      env_from([
        #("CODEX_BIN", "my-codex"),
        #("CODEX_ARGS", "--foo bar"),
        #("CODEX_EXTRA_ARGS", "--skip-git-repo-check"),
      ]),
      fake_exec_no_timeout,
      fake_fs(),
    )
  case outcome {
    ExecOk(_) -> Nil
    _ -> should.fail()
  }
  let assert [#(bin, args, stdin)] = cap_calls()
  bin |> should.equal("my-codex")
  args
  |> should.equal([
    "exec",
    "--full-auto",
    "--foo",
    "bar",
    "--skip-git-repo-check",
    prompt,
  ])
  stdin |> should.equal("")
}

pub fn run_grok_conflict_resolve_prompt_file_test() {
  cap_reset()
  let prompt = "conflict-prompt-text"
  let outcome =
    coding_agent.run(
      Resolve,
      ConflictResolve,
      prompt,
      "/work/resolve-wt",
      env_from([
        #("GRKR_AGENT_RESOLVE", "grok"),
        #("GROK_BIN", "grok"),
      ]),
      fake_exec_no_timeout,
      fake_fs(),
    )
  case outcome {
    ExecOk(s) -> s |> should.equal("GROK-OK")
    _ -> should.fail()
  }
  let writes = cap_writes()
  list.length(writes) |> should.equal(1)
  let assert [#(path, body)] = writes
  body |> should.equal(prompt)
  string.contains(path, "grkr-agent-prompt.") |> should.equal(True)
  list.contains(cap_unlinks(), path) |> should.equal(True)

  let calls = cap_calls()
  list.length(calls) |> should.equal(1)
  let assert [#(bin, args, stdin)] = calls
  bin |> should.equal("grok")
  list.contains(args, "--prompt-file") |> should.equal(True)
  list.contains(args, path) |> should.equal(True)
  list.contains(args, "--cwd") |> should.equal(True)
  list.contains(args, "/work/resolve-wt") |> should.equal(True)
  // no timeout wrapper on ConflictResolve Grok path
  list.contains(args, "120") |> should.equal(False)
  stdin |> should.equal("")
}

pub fn run_conflict_resolve_honors_grkr_coding_agent_resolve_test() {
  cap_reset()
  let outcome =
    coding_agent.run(
      Resolve,
      ConflictResolve,
      "p",
      "/w",
      env_from([
        #("GRKR_CODING_AGENT", "codex"),
        #("GRKR_CODING_AGENT_RESOLVE", "grok"),
        #("GROK_BIN", "grok"),
      ]),
      fake_exec_no_timeout,
      fake_fs(),
    )
  case outcome {
    ExecOk(s) -> s |> should.equal("GROK-OK")
    _ -> should.fail()
  }
  let assert [#(bin, _, _)] = cap_calls()
  bin |> should.equal("grok")
}

pub fn run_conflict_resolve_unknown_agent_fails_test() {
  cap_reset()
  let outcome =
    coding_agent.run(
      Resolve,
      ConflictResolve,
      "p",
      "/w",
      env_from([#("GRKR_AGENT_RESOLVE", "claude")]),
      fake_exec_no_timeout,
      fake_fs(),
    )
  case outcome {
    ExecFailed(2, _, err) ->
      string.contains(err, "Unknown coding agent") |> should.equal(True)
    _ -> should.fail()
  }
  list.length(cap_calls()) |> should.equal(0)
}
