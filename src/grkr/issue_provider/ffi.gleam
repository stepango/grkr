/// External JSON value type
pub type JsonValue

/// Parse a JSON string into a JsonValue
@external(javascript, "../issue_provider/json_ffi.mjs", "parse")
pub fn parse(json_string: String) -> Result(JsonValue, String)

/// Get a field from a JSON object
@external(javascript, "../issue_provider/json_ffi.mjs", "getField")
pub fn get_field(obj: JsonValue, field: String) -> JsonValue

/// Decode a JsonValue as a string
@external(javascript, "../issue_provider/json_ffi.mjs", "decodeString")
pub fn decode_string(val: JsonValue) -> Result(String, String)

/// Check if a JsonValue is null
@external(javascript, "../issue_provider/json_ffi.mjs", "isNull")
pub fn is_null(val: JsonValue) -> Bool

/// Decode a JsonValue as an array
@external(javascript, "../issue_provider/json_ffi.mjs", "decodeArray")
pub fn decode_array(val: JsonValue) -> Result(List(JsonValue), String)