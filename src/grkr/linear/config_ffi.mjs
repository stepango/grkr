import { Ok, Error } from "../../gleam.mjs";
import { readFileSync } from "fs";
import { homedir } from "os";

export function get_env_var(name) {
  return process.env[name] || "";
}

export function read_file(path) {
  try {
    const resolved = path.startsWith("~/") ? `${homedir()}/${path.slice(2)}` : path;
    const content = readFileSync(resolved, "utf-8");
    return new Ok(content);
  } catch (error) {
    return new Error("Failed to read file: " + path + " - " + error.message);
  }
}
