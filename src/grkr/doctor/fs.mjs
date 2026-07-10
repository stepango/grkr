import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmdirSync,
  writeFileSync,
} from "fs";
import { dirname, join } from "path";
import { Ok, Error } from "../../gleam.mjs";

export function read_text(path) {
  try {
    return new Ok(readFileSync(path, "utf-8"));
  } catch (e) {
    return new Error(String(e.message || e));
  }
}

export function write_text(path, content) {
  try {
    const dir = dirname(path);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    writeFileSync(path, content, "utf-8");
    return new Ok(undefined);
  } catch (e) {
    return new Error(String(e.message || e));
  }
}

export function mkdir_p(path) {
  try {
    mkdirSync(path, { recursive: true });
    return true;
  } catch (_e) {
    return false;
  }
}

export function exists(path) {
  try {
    return existsSync(path);
  } catch (_e) {
    return false;
  }
}

export function probe_writable_dir(parent) {
  try {
    if (!mkdir_p(parent)) {
      return false;
    }
    const probe = mkdtempSync(join(parent, ".doctor."));
    rmdirSync(probe);
    return true;
  } catch (_e) {
    return false;
  }
}