import { Ok, Error, toList } from "../../gleam.mjs";

/**
 * JSON parsing FFI for the GitHub picker (provider)
 * Extended with getKeys for enumerating object fields.
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

export function decodeBool(obj) {
  if (typeof obj === "boolean") {
    return new Ok(obj);
  }
  return new Error("Expected bool");
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

/**
 * Build the normalized {items: [...]} JSON string from a list of nodes.
 * Used by client.gleam to return accumulated pages in the shape expected by decoder/field.
 */
export function buildItemsResponse(nodes) {
  const arr = nodes && typeof nodes.toArray === "function"
    ? nodes.toArray()
    : (Array.isArray(nodes) ? nodes : []);
  return JSON.stringify({ items: arr });
}
