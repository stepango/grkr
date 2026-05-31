/// FFI for workflow/worktree (env, fs, git with context support, cli)
/// GitHub-only v2 issue worktree mgmt.
/// Extended for handle_comment: general exec + json decode (for gh api responses)

import gleam/option.{type Option}

pub type ExecResult {
  ExecResult(exit_code: Int, stdout: String, stderr: String)
}

/// ENV
@external(javascript, "./worktree_ffi.mjs", "get_env")
pub fn get_env(name: String) -> String

/// FS
@external(javascript, "./worktree_ffi.mjs", "mkdir_p")
pub fn mkdir_p(path: String) -> Bool

@external(javascript, "./worktree_ffi.mjs", "path_exists")
pub fn path_exists(path: String) -> Bool

/// GIT host context (for prepare, cleanup, base ref checks etc)
@external(javascript, "./worktree_ffi.mjs", "git_exec")
pub fn git_exec(args: List(String), input: Option(String)) -> ExecResult

/// GIT in issue worktree context (respects CURRENT_ISSUE_WORKTREE env for cd equiv)
@external(javascript, "./worktree_ffi.mjs", "git_exec_in_context")
pub fn git_exec_in_context(args: List(String), input: Option(String)) -> ExecResult

/// CLI argv
@external(javascript, "./cli_ffi.mjs", "argv")
pub fn argv() -> List(String)

@external(javascript, "console", "log")
pub fn console_log(s: String) -> Nil

@external(javascript, "console", "error")
pub fn console_error(s: String) -> Nil

@external(javascript, "process", "exit")
pub fn exit(code: Int) -> Nil

/// TASK LOG (sharding/persist/emit/manifest for codex impl outputs > MAX_FILE_LINES under .grkr/tasks/*/implementation.log)
/// FFI wired to dedicated task_log_ffi.mjs (dupe of minimal fs per migration patterns)
/// Used by split modules: task_log_core/persist/cli (t_491dd327)
@external(javascript, "./task_log_ffi.mjs", "get_env")
pub fn tl_get_env(name: String) -> String

@external(javascript, "./task_log_ffi.mjs", "mkdir_p")
pub fn tl_mkdir_p(path: String) -> Bool

@external(javascript, "./task_log_ffi.mjs", "exists")
pub fn tl_exists(path: String) -> Bool

@external(javascript, "./task_log_ffi.mjs", "read_text")
pub fn tl_read_text(path: String) -> Result(String, String)

@external(javascript, "./task_log_ffi.mjs", "write_text")
pub fn tl_write_text(path: String, content: String) -> Result(Nil, String)

@external(javascript, "./task_log_ffi.mjs", "list_files")
pub fn tl_list_files(dir: String) -> Result(List(String), String)

@external(javascript, "./task_log_ffi.mjs", "unlink_file")
pub fn tl_unlink_file(path: String) -> Bool

@external(javascript, "./task_log_ffi.mjs", "remove_recursive")
pub fn tl_remove_recursive(path: String) -> Bool

@external(javascript, "./task_log_ffi.mjs", "temp_path")
pub fn tl_temp_path(prefix: String) -> String

/// Raw write to stdout (no auto \n) for exact content emit of sharded/non-sharded logs.
/// Used by task_log CLI "emit" subcommand to preserve exact bytes (cat parity) for bin/grkr + sh tests.
@external(javascript, "./task_log_ffi.mjs", "stdout_write")
pub fn tl_stdout_write(s: String) -> Bool

// --- JSON (from json_ffi.mjs, copied for workflow/handle_comment gh responses; no gleam/json dep) ---
/// Opaque JSON value for manual decoding
pub type JsonValue

@external(javascript, "./json_ffi.mjs", "parse")
pub fn parse(json_string: String) -> Result(JsonValue, String)

@external(javascript, "./json_ffi.mjs", "getField")
pub fn get_field(obj: JsonValue, field: String) -> JsonValue

@external(javascript, "./json_ffi.mjs", "getKeys")
pub fn get_keys(obj: JsonValue) -> Result(List(String), String)

@external(javascript, "./json_ffi.mjs", "decodeString")
pub fn decode_string(val: JsonValue) -> Result(String, String)

@external(javascript, "./json_ffi.mjs", "decodeInt")
pub fn decode_int(val: JsonValue) -> Result(Int, String)

@external(javascript, "./json_ffi.mjs", "decodeBool")
pub fn decode_bool(val: JsonValue) -> Result(Bool, String)

@external(javascript, "./json_ffi.mjs", "decodeArray")
pub fn decode_array(val: JsonValue) -> Result(List(JsonValue), String)

@external(javascript, "./json_ffi.mjs", "decodeObject")
pub fn decode_object(val: JsonValue) -> Result(JsonValue, String)

@external(javascript, "./json_ffi.mjs", "isNull")
pub fn is_null(val: JsonValue) -> Bool

@external(javascript, "./json_ffi.mjs", "getFieldPath")
pub fn get_field_path(obj: JsonValue, path: List(String)) -> JsonValue

// --- General exec for gh api, codex, reactions, git etc (handle_comment + future) ---
@external(javascript, "./worktree_ffi.mjs", "executable")
pub fn executable(command: String, args: List(String), input: Option(String)) -> ExecResult
