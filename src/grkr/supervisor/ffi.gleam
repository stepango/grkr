/// FFI re-exports and externals for supervisor (env, exec, fs, process, json, cli)
/// Keep per-module for this slice; consolidate later if desired.

import gleam/dict.{type Dict}
import gleam/option.{type Option}

/// Opaque JSON value for manual decoding (no gleam/json dep)
pub type JsonValue

// --- JSON (from json_ffi.mjs) ---

@external(javascript, "../supervisor/json_ffi.mjs", "parse")
pub fn parse(json_string: String) -> Result(JsonValue, String)

@external(javascript, "../supervisor/json_ffi.mjs", "getField")
pub fn get_field(obj: JsonValue, field: String) -> JsonValue

@external(javascript, "../supervisor/json_ffi.mjs", "getKeys")
pub fn get_keys(obj: JsonValue) -> Result(List(String), String)

@external(javascript, "../supervisor/json_ffi.mjs", "decodeString")
pub fn decode_string(val: JsonValue) -> Result(String, String)

@external(javascript, "../supervisor/json_ffi.mjs", "decodeInt")
pub fn decode_int(val: JsonValue) -> Result(Int, String)

@external(javascript, "../supervisor/json_ffi.mjs", "decodeBool")
pub fn decode_bool(val: JsonValue) -> Result(Bool, String)

@external(javascript, "../supervisor/json_ffi.mjs", "decodeArray")
pub fn decode_array(val: JsonValue) -> Result(List(JsonValue), String)

@external(javascript, "../supervisor/json_ffi.mjs", "decodeObject")
pub fn decode_object(val: JsonValue) -> Result(JsonValue, String)

@external(javascript, "../supervisor/json_ffi.mjs", "isNull")
pub fn is_null(val: JsonValue) -> Bool

@external(javascript, "../supervisor/json_ffi.mjs", "getFieldPath")
pub fn get_field_path(obj: JsonValue, path: List(String)) -> JsonValue

// --- ENV (env.mjs) ---

@external(javascript, "../supervisor/env.mjs", "get_env")
pub fn get_env(name: String) -> String

@external(javascript, "../supervisor/env.mjs", "get_env_with_default")
pub fn get_env_with_default(name: String, default: String) -> String

@external(javascript, "../supervisor/env.mjs", "has_env")
pub fn has_env(name: String) -> Bool

// --- EXEC (exec.mjs) for doctor, gh, git, worker capture ---

pub type ExecResult {
  ExecResult(exit_code: Int, stdout: String, stderr: String)
}

@external(javascript, "../supervisor/exec.mjs", "executable")
pub fn executable(command: String, args: List(String), input: Option(String)) -> ExecResult

// --- FS (fs.mjs) for layout, locks, atomic json, logs ---

@external(javascript, "../supervisor/fs.mjs", "mkdir_p")
pub fn mkdir_p(path: String) -> Bool

@external(javascript, "../supervisor/fs.mjs", "acquire_lock")
pub fn acquire_lock(lock_path: String) -> Result(Nil, Nil)  // Ok(Nil) or Error(Nil) for busy

@external(javascript, "../supervisor/fs.mjs", "release_lock")
pub fn release_lock(lock_path: String) -> Bool

@external(javascript, "../supervisor/fs.mjs", "atomic_write_json")
pub fn atomic_write_json(path: String, content: String) -> Result(Nil, String)

@external(javascript, "../supervisor/fs.mjs", "append_log")
pub fn append_log(path: String, line: String) -> Bool

@external(javascript, "../supervisor/fs.mjs", "read_text")
pub fn read_text(path: String) -> Result(String, String)

@external(javascript, "../supervisor/fs.mjs", "write_text")
pub fn write_text(path: String, content: String) -> Result(Nil, String)

@external(javascript, "../supervisor/fs.mjs", "exists")
pub fn exists(path: String) -> Bool

@external(javascript, "../supervisor/fs.mjs", "list_files")
pub fn list_files(dir: String) -> Result(List(String), String)

@external(javascript, "../supervisor/fs.mjs", "unlink_file")
pub fn unlink_file(path: String) -> Bool

@external(javascript, "../supervisor/fs.mjs", "try_lock_and_release")
pub fn try_lock_and_release(lock_path: String) -> Bool

// --- PROCESS (process.mjs) for bg spawn, pid checks, sleep ---

@external(javascript, "../supervisor/process.mjs", "spawn_detached")
pub fn spawn_detached(cmd: String, args: List(String), opts: Dict(String, String)) -> Int  // pid or 0

@external(javascript, "../supervisor/process.mjs", "is_alive")
pub fn is_alive(pid: Int) -> Bool

@external(javascript, "../supervisor/process.mjs", "kill")
pub fn kill(pid: Int, signal: String) -> Bool

@external(javascript, "../supervisor/process.mjs", "sleep_seconds")
pub fn sleep_seconds(secs: Int) -> Nil

@external(javascript, "../supervisor/process.mjs", "utc_timestamp")
pub fn utc_timestamp() -> String

@external(javascript, "../supervisor/process.mjs", "unix_seconds")
pub fn unix_seconds() -> Int

// --- CLI / ARGV (cli_ffi.mjs) ---

@external(javascript, "../supervisor/cli_ffi.mjs", "argv")
pub fn argv() -> List(String)

// --- EXIT (from process global) ---

@external(javascript, "process", "exit")
pub fn exit(code: Int) -> Nil

@external(javascript, "../supervisor/fs.mjs", "stat_mtime")
pub fn stat_mtime(path: String) -> Result(Int, String)

@external(javascript, "../supervisor/fs.mjs", "remove_dir_recursive")
pub fn remove_dir_recursive(path: String) -> Bool
