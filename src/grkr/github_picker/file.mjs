import { readFileSync as nodeReadFileSync } from "fs";
import { Ok, Error } from "../../gleam.mjs";

export function readFileSync(path) {
  try {
    return new Ok(nodeReadFileSync(path, "utf-8"));
  } catch (err) {
    return new Error(String(err.message));
  }
}
