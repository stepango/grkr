import { Ok, Error, toList } from "../../gleam.mjs";

/**
 * JSON parsing FFI for the issue provider
 */

/**
 * Parse a JSON string into a JavaScript value
 */
export function parse(jsonString) {
  try {
    return new Ok(JSON.parse(jsonString));
  } catch (e) {
    return new Error(String(e.message));
  }
}

/**
 * Get a field from a JavaScript object
 */
export function getField(obj, field) {
  if (obj === null || obj === undefined) {
    return null;
  }
  return obj[field];
}

/**
 * Decode a string field
 */
export function decodeString(obj) {
  if (typeof obj === "string") {
    return new Ok(obj);
  }
  return new Error("Expected string");
}

/**
 * Check if a value is null
 */
export function isNull(val) {
  return val === null || val === undefined;
}

/**
 * Decode an array field
 */
export function decodeArray(obj) {
  if (Array.isArray(obj)) {
    return new Ok(toList(obj));
  }
  return new Error("Expected array");
}