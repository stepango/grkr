import { toList } from "../../gleam.mjs";

export function argv() {
  return toList(process.argv.slice(2));
}
