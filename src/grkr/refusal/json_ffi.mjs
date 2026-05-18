import { Ok, Error, toList } from "../../gleam.mjs";

/**
 * JSON parsing FFI for the refusal module
 * Includes path helpers and basic decoders.
 */

export function parse(jsonString) {
  try {
    return new Ok(JSON.parse(jsonString));
  } catch (e) {
    return new Error(String(e.message));
  }
}

export function getField(obj, field) {
  if (obj === null || obj === undefined) {
    return null;
  }
  return obj[field];
}

export function getKeys(obj) {
  if (obj === null || obj === undefined || typeof obj !== "object") {
    return new Ok(toList([]));
  }
  return new Ok(toList(Object.keys(obj)));
}

export function decodeString(obj) {
  if (typeof obj === "string") {
    return new Ok(obj);
  }
  return new Error("Expected string");
}

export function decodeInt(obj) {
  if (Number.isInteger(obj)) {
    return new Ok(obj);
  }
  return new Error("Expected int");
}

export function isNull(val) {
  return val === null || val === undefined;
}

export function decodeArray(obj) {
  if (Array.isArray(obj)) {
    return new Ok(toList(obj));
  }
  return new Error("Expected array");
}

// Path helper
export function getFieldPath(obj, path) {
  let cur = obj;
  for (const k of path) {
    cur = getField(cur, k);
    if (cur === null || cur === undefined) return null;
  }
  return cur;
}

export function getString(obj, key, defaultVal) {
  const v = getField(obj, key);
  const res = decodeString(v);
  if (res[0] === "Ok" || (res && res.constructor && res.constructor.name === "Ok")) {
    return res[1] !== undefined ? res[1] : (res.value !== undefined ? res.value : defaultVal);
  }
  return defaultVal;
}
