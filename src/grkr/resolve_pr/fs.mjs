import { writeFileSync, unlinkSync, existsSync } from "fs";

export function write_file(path, content) {
  try {
    writeFileSync(path, content, { encoding: "utf-8" });
    return ["Ok", undefined];
  } catch (error) {
    return ["Error", error.message];
  }
}

/** Unique temp path under TMPDIR with prefix (mirror workflow/task_log_ffi). */
export function temp_path(prefix) {
  const tmpdir = process.env.TMPDIR || process.env.TMP || "/tmp";
  const rand =
    Date.now().toString(36) + Math.random().toString(36).substring(2, 12);
  return tmpdir + "/" + prefix + rand;
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
