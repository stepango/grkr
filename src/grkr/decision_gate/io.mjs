import { readFileSync } from "fs";
import { toList } from "../../gleam.mjs";

export function read_file(path) {
  return readFileSync(path, { encoding: "utf-8" });
}

export function argv() {
  return toList(process.argv.slice(2));
}

export function exit(code) {
  process.exit(code);
}
