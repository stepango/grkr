/// External JSON value type (opaque)
pub type JsonValue

/// Parse a JSON string into a JsonValue
@external(javascript, "../github_picker/json_ffi.mjs", "parse")
pub fn parse(json_string: String) -> Result(JsonValue, String)

/// Get a field from a JSON object
@external(javascript, "../github_picker/json_ffi.mjs", "getField")
pub fn get_field(obj: JsonValue, field: String) -> JsonValue

/// Get all keys of a JSON object (for flexible field discovery)
@external(javascript, "../github_picker/json_ffi.mjs", "getKeys")
pub fn get_keys(obj: JsonValue) -> Result(List(String), String)

/// Decode a JsonValue as a string
@external(javascript, "../github_picker/json_ffi.mjs", "decodeString")
pub fn decode_string(val: JsonValue) -> Result(String, String)

/// Decode a JsonValue as an int
@external(javascript, "../github_picker/json_ffi.mjs", "decodeInt")
pub fn decode_int(val: JsonValue) -> Result(Int, String)

/// Check if a JsonValue is null
@external(javascript, "../github_picker/json_ffi.mjs", "isNull")
pub fn is_null(val: JsonValue) -> Bool

/// Decode a JsonValue as an array
@external(javascript, "../github_picker/json_ffi.mjs", "decodeArray")
pub fn decode_array(val: JsonValue) -> Result(List(JsonValue), String)
