import { toList } from "../../gleam.mjs";
import { readFileSync as nodeReadFileSync, writeFileSync as nodeWriteFileSync } from "fs";
import { Ok, Error } from "../../gleam.mjs";

export function argv() {
  return toList(process.argv.slice(2));
}

export function env_get(key) {
  return process.env[key] || "";
}

export function readFileSync(path) {
  try {
    return new Ok(nodeReadFileSync(path, "utf-8"));
  } catch (err) {
    return new Error(String(err && err.message || "read failed"));
  }
}

export function writeFileSync(path, content) {
  try {
    nodeWriteFileSync(path, content, "utf-8");
    return new Ok("ok");
  } catch (err) {
    return new Error(String(err && err.message || "write failed"));
  }
}
