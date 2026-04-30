import { closeSync, mkdirSync, openSync } from "fs";
import { spawnSync } from "child_process";

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
    const result = spawnSync("flock", ["-n", String(fd)], {
      stdio: ["ignore", "ignore", "ignore"],
    });

    if (result.status !== 0) {
      closeSync(fd);
      return ["Error", undefined];
    }

    lockFds.set(lockPath, fd);
    return ["Ok", undefined];
  } catch (_error) {
    return ["Error", undefined];
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
