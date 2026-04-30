import { closeSync, mkdirSync, openSync } from "fs";
import { spawnSync } from "child_process";
import { Ok, Error } from "../../gleam.mjs";

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

const lockFds = new Map();

export function acquire_lock(lockPath) {
  try {
    const fd = openSync(lockPath, "a");
    const result = spawnSync("flock", ["-n", "3"], {
      stdio: ["ignore", "ignore", "ignore", fd],
    });

    if (result.status !== 0) {
      closeSync(fd);
      return new Error(undefined);
    }

    lockFds.set(lockPath, fd);
    return new Ok(undefined);
  } catch (_error) {
    return new Error(undefined);
  }
}

export function release_lock(lockPath) {
  const fd = lockFds.get(lockPath);
  if (fd === undefined) {
    return false;
  }

  try {
    closeSync(fd);
    lockFds.delete(lockPath);
    return true;
  } catch (_error) {
    return false;
  }
}

export function exit_process(code) {
  process.exit(code);
}
