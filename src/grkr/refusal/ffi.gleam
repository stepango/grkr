/// Opaque JSON value from FFI
pub type JsonValue

/// Parse JSON string to JsonValue or error
@external(javascript, "../refusal/json_ffi.mjs", "parse")
pub fn parse(json_string: String) -> Result(JsonValue, String)

/// Get nested field path, returns null/undefined on miss (as JsonValue)
@external(javascript, "../refusal/json_ffi.mjs", "getFieldPath")
pub fn get_field_path(obj: JsonValue, path: List(String)) -> JsonValue

/// Get string at nested path, "" on miss
@external(javascript, "../refusal/json_ffi.mjs", "getFieldPathString")
pub fn get_field_path_string(obj: JsonValue, path: List(String)) -> String

/// Get string field, "" on miss
@external(javascript, "../refusal/json_ffi.mjs", "getFieldString")
pub fn get_field_string(obj: JsonValue, key: String) -> String

/// Get raw field
@external(javascript, "../refusal/json_ffi.mjs", "getField")
pub fn get_field(obj: JsonValue, field: String) -> JsonValue

/// Decode as list of JsonValue
@external(javascript, "../refusal/json_ffi.mjs", "decodeArray")
pub fn decode_array(val: JsonValue) -> Result(List(JsonValue), String)

// --- ENV (env.mjs) ---

@external(javascript, "../refusal/env.mjs", "get_env")
pub fn get_env(name: String) -> String

@external(javascript, "../refusal/env.mjs", "get_env_with_default")
pub fn get_env_with_default(name: String, default: String) -> String

@external(javascript, "../refusal/env.mjs", "has_env")
pub fn has_env(name: String) -> Bool

/// Exec result from child_process
pub type ExecResult {
  ExecResult(
    exit_code: Int,
    stdout: String,
    stderr: String,
  )
}

/// Execute shell command with args (no stdin)
@external(javascript, "../refusal/exec.mjs", "execute_command")
pub fn execute_command(command: String, args: List(String)) -> ExecResult

/// Write a file (for refusal.md checkpoint etc). Returns Result for error surfacing.
@external(javascript, "../refusal/fs.mjs", "write_file")
pub fn write_file(path: String, content: String) -> Result(Nil, String)

/// Update progress.json to refused state (status, decision, reason_class, comment_id, skip test).
/// Preserves existing fields in the json. Returns Result for consistency.
@external(javascript, "../refusal/fs.mjs", "update_progress_for_refusal")
pub fn update_progress_for_refusal(progress_file: String, reason_class: String, comment_id: String) -> Result(Nil, String)

/// Check if a file exists (for idempotency checks on refusal.md).
@external(javascript, "../refusal/fs.mjs", "exists_file")
pub fn exists_file(path: String) -> Bool

/// Read file text or return "" on error/missing (for context/meta reads in linear path).
@external(javascript, "../refusal/fs.mjs", "read_text_or_empty")
pub fn read_text_or_empty(path: String) -> String
