//// linear_apply.gleam
//// Cluster D extracted from progress/main.gleam for LOC hygiene (t_8c7cd0a0).
//// Linear apply path (highest cohesion): guarded apply from dump path/stdin, gate, sidecar, token, POST, error handling.
/// cli_apply_* + core apply fns + helpers + FFI.
/// Co-located FFI decls with apply. Public cli surface preserved via main facade.
/// Exact semantics: GRKR_LINEAR_MUTATE literal "1", GRKR_LINEAR_APPLY_CMD stub, sidecars, markers, no behavior change.

import gleam/string
import grkr/issue_provider/client as issue_client
import grkr/issue_provider/types
import grkr/progress/linear_mutation

/// Apply entry for CLI: reads dump from path, applies if gate allows, writes sidecar next to it.
/// Always returns Ok(marker line) for soft exit 0; caller prints it.
pub fn cli_apply_linear_mutation_from_path(
  dump_path: String,
  env_get: fn(String) -> String,
) -> Result(String, String) {
  case read_dump_file(dump_path) {
    Error(e) -> Error("cannot-read-dump:" <> e)
    Ok(content) -> apply_linear_mutation_dump(dump_path, content, env_get)
  }
}

/// Stdin variant (for piping dumps in tests or manual).
pub fn cli_apply_linear_mutation_from_stdin(
  _env_get: fn(String) -> String,
) -> Result(String, String) {
  // For stdin mode in this slice, we expect callers to use file path.
  // FFI stdin read can be added later; return guidance.
  Error("linear-apply-mutation stdin: provide explicit dump file path for now")
}

/// Core apply logic. Respects GRKR_LINEAR_MUTATE literal "1".
/// Writes sidecar <dump>.linear-apply-result.txt on attempt or skip-with-reason.
/// GRKR_LINEAR_APPLY_CMD (if set) short-circuits to the provided stub/cmd (hermetic tests);
/// mirrors bin/lib/linear_mutate.sh behavior. Stub controls output/sidecars.
fn apply_linear_mutation_dump(
  dump_path: String,
  content: String,
  env_get: fn(String) -> String,
) -> Result(String, String) {
  let apply_cmd = env_get("GRKR_LINEAR_APPLY_CMD")
  case string.trim(apply_cmd) {
    "" -> apply_with_gate(dump_path, content, env_get)
    cmd -> {
      case run_apply_override(cmd, dump_path) {
        Ok(out) -> {
          case out {
            "" -> Ok("LINEAR_MUTATE=dry-run key=" <> extract_key_or_unknown(content))
            m -> Ok(m)
          }
        }
        Error(_) -> Ok("LINEAR_MUTATE=dry-run key=" <> extract_key_or_unknown(content))
      }
    }
  }
}

fn apply_with_gate(
  dump_path: String,
  content: String,
  env_get: fn(String) -> String,
) -> Result(String, String) {
  let sidecar_path = dump_path <> ".linear-apply-result.txt"

  // 1. Gate
  case linear_mutation.should_apply_live(env_get) {
    False -> {
      let key = extract_key_or_unknown(content)
      let marker = "LINEAR_MUTATE=dry-run key=" <> key
      Ok(marker)
    }
    True -> {
      // 2. Check prior sidecar for idempotent skip
      case read_dump_file(sidecar_path) {
        Ok(prior) ->
          case linear_mutation.sidecar_indicates_already_done(prior) {
            True -> {
              let key = extract_key_or_unknown(content)
              let marker = "LINEAR_MUTATE=skipped-already key=" <> key
              Ok(marker)
            }
            False -> do_apply_or_skip(content, sidecar_path, env_get)
          }
        Error(_) -> do_apply_or_skip(content, sidecar_path, env_get)
      }
    }
  }
}

fn do_apply_or_skip(
  content: String,
  sidecar_path: String,
  _env_get: fn(String) -> String,
) -> Result(String, String) {
  // name-only check
  case linear_mutation.parse_mutation_dump(content) {
    Error(_name_only) -> {
      // name_only contains "name-only:..." or TARGET
      let target =
        content
        |> string.split("\n")
        |> list_first
        |> string.replace("TARGET_STATE=", "")
        |> string.trim
      let marker = "LINEAR_MUTATE=skipped-no-state-id target=" <> target
      let _ = write_sidecar(sidecar_path, linear_mutation.format_apply_sidecar("name-only", "skipped-no-state-id", "target=" <> target))
      Ok(marker)
    }
    Ok(#(query, vars_json, key)) -> {
      // 3. Token?  (soft skip: do not write sidecar so a later token run retries cleanly)
      case issue_client.resolve_access_token() {
        Error(_) -> {
          let marker = "LINEAR_MUTATE=skipped-no-token key=" <> key
          // Intentionally no sidecar write: skipped-no-token is soft/resume-safe.
          Ok(marker)
        }
        Ok(token) -> {
          // 4. Perform the POST via variables path
          case issue_client.run_graphql_with_variables(token, query, vars_json) {
            Ok(resp) -> {
              let res = linear_mutation.mutation_result_from_response(resp)
              let #(status, detail) = linear_mutation.classify_apply_outcome(res, True, False)
              let side = linear_mutation.format_apply_sidecar(key, status, detail)
              let _ = write_sidecar(sidecar_path, side)
              let marker = case status {
                "applied" -> "LINEAR_MUTATE=applied key=" <> key <> " " <> detail
                _ -> "LINEAR_MUTATE=" <> status <> " key=" <> key <> " " <> detail
              }
              Ok(marker)
            }
            Error(e) -> {
              let err_str = provider_error_message(e)
              let red = redact_apply_error(err_str)
              let side = linear_mutation.format_apply_sidecar(key, "failed", "error=" <> red)
              let _ = write_sidecar(sidecar_path, side)
              let marker = "LINEAR_MUTATE=failed key=" <> key <> " error=" <> red
              Ok(marker)
            }
          }
        }
      }
    }
  }
}

fn extract_key_or_unknown(content: String) -> String {
  let lines = string.split(string.trim(content), "\n")
  case lines {
    [_, _, k] -> k
    _ -> "unknown"
  }
}

fn list_first(l: List(String)) -> String {
  case l {
    [h, ..] -> h
    _ -> ""
  }
}

fn redact_apply_error(e: String) -> String {
  // Reuse client redact if possible, but simple here; token already redacted by client layer
  e
  |> string.replace("\n", " ")
  |> string.slice(0, 200)
}

fn provider_error_message(e: types.ProviderError) -> String {
  case e {
    types.QueryError(msg) -> msg
    types.ParseError(msg) -> msg
    types.ConfigError(_) -> "config error"
    types.NoMatchingIssue -> "no matching issue"
  }
}

// FFI declarations (implemented in cli_ffi.mjs)
// Use same external module specifier as original for path stability.
@external(javascript, "../progress/cli_ffi.mjs", "readFileSync")
fn read_dump_file(path: String) -> Result(String, String)

@external(javascript, "../progress/cli_ffi.mjs", "writeFileSync")
fn write_sidecar(path: String, content: String) -> Result(String, String)

@external(javascript, "../progress/cli_ffi.mjs", "runApplyOverride")
fn run_apply_override(cmd: String, dump_path: String) -> Result(String, String)
