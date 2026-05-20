import gleam/list

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
