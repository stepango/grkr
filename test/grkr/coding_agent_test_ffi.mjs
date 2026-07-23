// Mutable capture for coding_agent_test (fake exec / fs). No real binaries.

import { toList } from "../gleam.mjs";

let writes = [];
let unlinks = [];
let calls = [];

function toJsArray(list) {
  if (!list) return [];
  if (typeof list.toArray === "function") return list.toArray();
  if (Array.isArray(list)) return list;
  return [];
}

export function reset() {
  writes = [];
  unlinks = [];
  calls = [];
}

export function record_write(path, body) {
  writes.push([path, body]);
}

export function record_unlink(path) {
  unlinks.push(path);
}

export function record_call(bin, args, stdin) {
  const arr = toJsArray(args);
  calls.push([
    bin,
    arr,
    stdin === undefined || stdin === null ? "" : String(stdin),
  ]);
}

export function get_writes() {
  return toList(writes.map(([p, b]) => [p, b]));
}

export function get_unlinks() {
  return toList(unlinks.slice());
}

export function get_calls() {
  // Return List(#(String, List(String), String))
  return toList(calls.map(([bin, args, stdin]) => [bin, toList(args), stdin]));
}
