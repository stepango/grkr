import { toList } from "../../gleam.mjs";
import { readFileSync as nodeReadFileSync, writeFileSync as nodeWriteFileSync } from "fs";
import { spawnSync } from "child_process";
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

// Support for GRKR_LINEAR_APPLY_CMD hermetic stub in tests (and any alt apply binary).
// Always soft-fail (never throws to caller); returns the stdout the cmd emitted (marker line).
// Mirrors the short-circuit in bin/lib/linear_mutate.sh .
export function runApplyOverride(cmd, dumpPath) {
  try {
    const res = spawnSync(cmd, [dumpPath], {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    });
    const out = (res && res.stdout) ? String(res.stdout) : "";
    return new Ok(out.trim());
  } catch (err) {
    // soft: return any partial stdout or empty
    const out = (err && err.stdout) ? String(err.stdout) : "";
    return new Ok(out.trim());
  }
}
