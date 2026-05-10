import { toList } from "../../gleam.mjs";

export function argv() {
  return toList(process.argv.slice(2));
}

export function env_get(key) {
  return process.env[key] || "";
}
