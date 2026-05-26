import { mkdirSync, existsSync, readFileSync, writeFileSync, readdirSync, unlinkSync, rmSync } from "fs";
import { Ok, Error, toList } from "../../gleam.mjs";

/**
 * FFI for workflow/task_log.gleam (sharding, persist, emit, manifest for codex outputs >1000 lines)
 * Duplicates minimal fs helpers (per migration patterns: dupe accepted pre-consolidation).
 * Matches bash behavior exactly for parity with grkr-issue-workflow.sh + bin/grkr.
 */

export function get_env(name) {
  return process.env[name] || "";
}

export function mkdir_p(path) {
  try {
    mkdirSync(path, { recursive: true });
    return true;
  } catch (_error) {
    return false;
  }
}

export function exists(path) {
  try {
    return existsSync(path);
  } catch (_) {
    return false;
  }
}

export function read_text(path) {
  try {
    return new Ok(readFileSync(path, "utf-8"));
  } catch (e) {
    return new Error(String(e.message || e));
  }
}

export function write_text(path, content) {
  try {
    const dir = path.substring(0, Math.max(0, path.lastIndexOf("/")));
    if (dir) mkdir_p(dir);
    writeFileSync(path, content, "utf-8");
    return new Ok(undefined);
  } catch (e) {
    return new Error(String(e.message || e));
  }
}

export function list_files(dir) {
  try {
    if (!existsSync(dir)) {
      return new Ok(toList([]));
    }
    const files = readdirSync(dir);
    return new Ok(toList(files));
  } catch (e) {
    return new Error(String(e.message || e));
  }
}

export function unlink_file(path) {
  try {
    if (existsSync(path)) {
      unlinkSync(path);
    }
    return true;
  } catch (_) {
    return false;
  }
}

export function remove_recursive(path) {
  try {
    if (existsSync(path)) {
      rmSync(path, { recursive: true, force: true });
    }
    return true;
  } catch (_) {
    return false;
  }
}

export function temp_path(prefix) {
  const tmpdir = process.env.TMPDIR || process.env.TMP || "/tmp";
  const rand = Date.now().toString(36) + Math.random().toString(36).substring(2, 12);
  return tmpdir + "/" + prefix + rand;
}

/**
 * Raw stdout write for exact emit_task_log_stream (no trailing \n from console.log).
 * Critical for sharded log concat parity in bin/grkr PR body extract + tests.
 */
export function stdout_write(s) {
  process.stdout.write(s);
  return true;
}
