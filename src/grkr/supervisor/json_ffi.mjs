import { Ok, Error, toList } from "../../gleam.mjs";

/**
 * JSON FFI for supervisor (active_jobs.json, config fixtures, etc.)
 * Consistent with github_picker/json_ffi.mjs and refusal patterns.
 * Uses new Ok/Error for Result interop.
 */

export function parse(jsonString) {
  try {
    return new Ok(JSON.parse(jsonString));
  } catch (e) {
    return new Error(String(e.message || e));
  }
}

export function getField(obj, key) {
  if (obj && typeof obj === "object" && key in obj) {
    const v = obj[key];
    if (v === null || v === undefined) return null;
    if (typeof v === "string" || typeof v === "number" || typeof v === "boolean") return v;
    if (Array.isArray(v)) return toList(v);
    if (typeof v === "object") return v;
    return v;
  }
  return null;
}

export function getKeys(obj) {
  if (obj === null || obj === undefined || typeof obj !== "object" || Array.isArray(obj)) {
    return new Ok(toList([]));
  }
  return new Ok(toList(Object.keys(obj)));
}

export function decodeString(val) {
  if (typeof val === "string") return new Ok(val);
  return new Error("Expected string");
}

export function decodeInt(val) {
  if (typeof val === "number" && Number.isInteger(val)) return new Ok(val);
  if (typeof val === "string") {
    const n = parseInt(val, 10);
    if (!isNaN(n)) return new Ok(n);
  }
  return new Error("Expected int");
}

export function decodeBool(val) {
  if (typeof val === "boolean") return new Ok(val);
  return new Error("Expected bool");
}

export function decodeArray(val) {
  if (Array.isArray(val)) return new Ok(toList(val));
  return new Error("Expected array");
}

export function decodeObject(val) {
  if (val && typeof val === "object" && !Array.isArray(val)) return new Ok(val);
  return new Error("Expected object");
}

export function isNull(val) {
  return val === null || val === undefined;
}

// Convenience: get string or default
export function getString(obj, key, defaultVal) {
  const v = getField(obj, key);
  const res = decodeString(v);
  if (res[0] === "Ok" || (res && res.constructor && res.constructor.name === "Ok")) {
    // handle both array and tagged? but since new Ok returns object, check
    return res[1] !== undefined ? res[1] : (res.value !== undefined ? res.value : defaultVal);
  }
  return defaultVal;
}

// Path helper e.g. getFieldPath(json, ["a", "b", "c"])
export function getFieldPath(obj, path) {
  let cur = obj;
  for (const k of path) {
    cur = getField(cur, k);
    if (cur === null || cur === undefined) return null;
  }
  return cur;
}
