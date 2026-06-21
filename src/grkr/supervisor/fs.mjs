import { closeSync, mkdirSync, openSync, writeFileSync, readFileSync, renameSync, appendFileSync, existsSync, readdirSync, unlinkSync, statSync, rmSync } from "fs";
import { spawnSync } from "child_process";
import { Ok, Error, toList } from "../../gleam.mjs";

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
    // ensure dir exists
    const dir = lockPath.substring(0, lockPath.lastIndexOf("/"));
    if (dir) mkdir_p(dir);
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

export function atomic_write_json(final_path, content_string) {
  try {
    const tmp = final_path + ".tmp." + Date.now() + "." + Math.random().toString(36).slice(2);
    writeFileSync(tmp, content_string, "utf-8");
    renameSync(tmp, final_path);
    return new Ok(undefined);
  } catch (e) {
    return new Error(String(e.message || e));
  }
}

export function append_log(path, line) {
  try {
    const dir = path.substring(0, path.lastIndexOf("/"));
    if (dir) mkdir_p(dir);
    appendFileSync(path, line + "\n", "utf-8");
    return true;
  } catch (_e) {
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
    const dir = path.substring(0, path.lastIndexOf("/"));
    if (dir) mkdir_p(dir);
    writeFileSync(path, content, "utf-8");
    return new Ok(undefined);
  } catch (e) {
    return new Error(String(e.message || e));
  }
}

export function exists(path) {
  try {
    return existsSync(path);
  } catch (_) {
    return false;
  }
}

export function list_files(dir) {
  try {
    if (!existsSync(dir)) {
      return new Ok(toList([]));
    }
    const rawFiles = readdirSync(dir);
    const files = rawFiles.filter((f) => f != null && typeof f === "string");
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

export function try_lock_and_release(lockPath) {
  try {
    const dir = lockPath.substring(0, lockPath.lastIndexOf("/"));
    if (dir) mkdir_p(dir);
    const fd = openSync(lockPath, "a");
    const result = spawnSync("flock", ["-n", "3"], {
      stdio: ["ignore", "ignore", "ignore", fd],
    });

    if (result.status !== 0) {
      closeSync(fd);
      return false;
    }
    closeSync(fd);
    return true;
  } catch (_error) {
    return false;
  }
}


export function stat_mtime(path) {
  try {
    const stats = statSync(path);
    return new Ok(Math.floor(stats.mtime.getTime() / 1000));
  } catch (e) {
    return new Error(String(e.message || e));
  }
}

export function remove_dir_recursive(path) {
  try {
    if (existsSync(path)) {
      rmSync(path, { recursive: true, force: true });
    }
    return true;
  } catch (_) {
    return false;
  }
}
